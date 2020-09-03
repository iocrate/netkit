
when not compileOption("threads"):
  {.error: "EventLoopExecutor requires --threads:on option.".}

import std/cpuinfo
import std/os

import netkit/collections/taskcounter
import netkit/collections/task
import netkit/collections/action
import netkit/collections/error
import netkit/collections/options
import netkit/locks

const
  MaxEventLoopCount* {.intdefine.} = 256            ## Maximum size of the event loop gExecutor. 
  InitialSpscRegistrySize* {.intdefine.} = 4096
  InitialMpscRegistrySize* {.intdefine.} = 4096
  InitialReactorSize* {.intdefine.} = 4096
  EventLoopTimeout* {.intdefine.} = 500

type
  EventLoop* = object
    id: int
    reactor: Reactor
    taskCounterSpscFd: cint
    taskCounterMpscFd: cint
    taskRegistry: TaskRegistry

  EventLoopGroup* = object
    id: EventLoopGroupId
    start: Natural
    cap: Natural
    recursiveEventLoopId: Natural
    recursiveEventLoopLock: SpinLock

  EventLoopGroupId* = int

  EventLoopExecutor* = object
    threads: array[MaxEventLoopCount, Thread[Natural]] 
    eventLoops: array[MaxEventLoopCount, EventLoop]    
    eventLoopGroups: array[MaxEventLoopCount, Option[EventLoopGroup]] # TODO: ptr UncheckedArray[EventLoopGroup]
    cpus: Natural
    cap: Natural
    mask: Natural
    recursiveEventLoopId: Natural
    recursiveEventLoopLock: SpinLock
    recursiveEventLoopGroupId: Natural
    recursiveEventLoopGroupLock: SpinLock
    stateLock: SpinLock
    state: EventLoopExecutorState

  EventLoopExecutorState* {.pure.} = enum
    CREATING, RUNNING, SHUTDOWN, CLOSED

proc initEventLoop(loop: var EventLoop, id: Natural) {.raises: [OSError].} =
  loop.id = id
  loop.reactor.open(InitialReactorSize)
  loop.taskCounterSpscFd = eventfd(0, 0)
  if loop.taskCounterSpscFd < 0:
    raiseOSError(osLastError())
  loop.taskCounterMpscFd = eventfd(0, 0)
  if loop.taskCounterMpscFd < 0:
    raiseOSError(osLastError())
  loop.taskRegistry = initTaskRegistry(loop.taskCounterSpscFd, InitialSpscRegistrySize, 
                                       loop.taskCounterMpscFd, InitialMpscRegistrySize)

proc initEventLoopExecutor(): EventLoopExecutor =
  result.cpus = countProcessors()
  result.cap = min(result.cpus, MaxEventLoopCount)
  result.mask = result.cap - 1
  result.recursiveEventLoopId = 1
  result.recursiveEventLoopLock = initSpinLock()
  result.recursiveEventLoopGroupId = 0
  result.recursiveEventLoopGroupLock = initSpinLock()
  result.stateLock = initSpinLock()
  result.state = EventLoopExecutorState.CREATING
  for i in 0..<result.cap:
    result.eventLoops[i].initEventLoop(i)

var
  gExecutor: EventLoopExecutor = initEventLoopExecutor()
  currentEventLoopId {.threadvar.}: int 
  currentEventLoop {.threadvar.}: ptr EventLoop 

proc sliceEventLoopGroup*(cap: Natural): EventLoopGroupId =
  result = 0
  
  withLock gExecutor.recursiveEventLoopGroupLock:
    result = gExecutor.recursiveEventLoopGroupId
    gExecutor.recursiveEventLoopGroupId = gExecutor.recursiveEventLoopGroupId + 1
    if gExecutor.recursiveEventLoopGroupId >= MaxEventLoopCount:
      raise newException(RangeDefect, "too many EventLoopGroup slices")
  
  gExecutor.eventLoopGroups[result].has = true

  let group = gExecutor.eventLoopGroups[result].value.addr
  group.cap = min(gExecutor.mask, cap)
  if group.cap > 0:
    group.recursiveEventLoopLock = initSpinLock()
    withLock gExecutor.recursiveEventLoopLock:
      group.start = gExecutor.recursiveEventLoopId - 1
      gExecutor.recursiveEventLoopId = (group.start + group.cap) mod gExecutor.mask + 1

proc spawn*(id: EventLoopGroupId, task: ref TaskBase) =
  if not gExecutor.eventLoopGroups[id].has:
    raise newException(IndexDefect, "EventLoopGroup not found")
  let group = gExecutor.eventLoopGroups[id].value.addr
  if group.cap > 0:
    var idInGroup = 0
    withLock group.recursiveEventLoopLock:
      idInGroup = group.recursiveEventLoopId
      group.recursiveEventLoopId = (group.recursiveEventLoopId + 1) mod group.cap
    let eventLoopId = (group.start + idInGroup) mod gExecutor.mask + 1
    if currentEventLoopId > 0:
      gExecutor.eventLoops[eventLoopId].taskRegistry.addMpsc(task)
    else:
      gExecutor.eventLoops[eventLoopId].taskRegistry.addSpsc(task)
  else:
    gExecutor.eventLoops[0].taskRegistry.addSpsc(task)

proc runSpscCounterAction(r: ref ActionBase): bool =
  result = false
  currentEventLoop.taskRegistry.runSpsc()

proc runMpscCounterAction(r: ref ActionBase): bool =
  result = false
  currentEventLoop.taskRegistry.runMpsc()

proc runEventLoop(id: Natural) {.thread.} =
  currentEventLoopId = id
  currentEventLoop = gExecutor.eventLoops[id].addr
  let spscCounterIdent = currentEventLoop.reactor.register(currentEventLoop.taskCounterSpscFd)
  let spscCounterAction = new(ActionBase)
  spscCounterAction.run = runSpscCounterAction
  currentEventLoop.reactor.updateRead(spscCounterIdent, spscCounterAction)
  let mpscCounterIdent = currentEventLoop.reactor.register(currentEventLoop.taskCounterMpscFd)
  let mpscCounterAction = new(ActionBase)
  mpscCounterAction.run = runMpscCounterAction
  currentEventLoop.reactor.updateRead(mpscCounterIdent, mpscCounterAction)
  currentEventLoop.reactor.runBlocking(EventLoopTimeout)

proc runEventLoopExceutor*() =
  withLock gExecutor.stateLock:
    # TODO: 考虑 restart
    if gExecutor.state == EventLoopExecutorState.SHUTDOWN:
      raise newException(IllegalStateError, "EventLoopExecutor still shutdown")
    if gExecutor.state == EventLoopExecutorState.RUNNING:
      raise newException(IllegalStateError, "EventLoopExecutor already running")

    gExecutor.state = EventLoopExecutorState.RUNNING
  
  for i in 1..<gExecutor.cap:
    createThread(gExecutor.threads[i], runEventLoop, i)
    when defined(PinToCpu):
      assert gExecutor.cpus > 0
      pinToCpu(gExecutor.threads[i], i mod gExecutor.cpus)
  runEventLoop(0) 

  for i in 1..<gExecutor.cap:
    joinThread(gExecutor.threads[i])
  gExecutor.state = EventLoopExecutorState.CLOSED

proc shutdownEventLoopExceutor*() =
  withLock gExecutor.stateLock:
    # TODO: 考虑 restart
    if gExecutor.state == EventLoopExecutorState.SHUTDOWN:
      raise newException(IllegalStateError, "EventLoopExecutor already shutdown")
    # TODO: 考虑 restart
    if gExecutor.state == EventLoopExecutorState.CLOSED:
      raise newException(IllegalStateError, "EventLoopExecutor already closed")

    gExecutor.state = EventLoopExecutorState.SHUTDOWN

    for i in 1..<gExecutor.cap:
      # TODO: 考虑 fd shutdown 时的 hook 函数
      gExecutor.eventLoops[i].reactor.shutdown()
    gExecutor.eventLoops[0].reactor.shutdown()

type
  Channel = object
    fd: cint
    reactiveId: Natural
    eventLoopId: int

  ActionTask[T] = object of TaskBase
    chan: ref Channel
    value: T

proc register*(chan: ref Channel) =
  if chan.eventLoopId == currentEventLoopId:
    chan.reactiveId = currentEventLoop.reactor.register(chan.fd)
  else:
    var task = new(Task[ref Channel]) 
    task.run = proc (task: ref TaskBase) =
      let chan = (ref Task[ref Channel])(task).value
      chan.reactiveId = currentEventLoop.reactor.register(chan.fd)
    task.value = chan
    gExecutor.eventLoops[chan.eventLoopId].taskRegistry.addMpsc(task)

proc unregister*(chan: ref Channel) =
  if chan.eventLoopId == currentEventLoopId:
    currentEventLoop.reactor.unregister(chan.reactiveId)
  else:
    var task = new(Task[ref Channel]) 
    task.run = proc (task: ref TaskBase) =
      currentEventLoop.reactor.unregister((ref Task[ref Channel])(task).value.reactiveId)
    task.value = chan
    gExecutor.eventLoops[chan.eventLoopId].taskRegistry.addMpsc(task)
    
proc unregisterReadable*(chan: ref Channel) =
  if chan.eventLoopId == currentEventLoopId:
    currentEventLoop.reactor.unregisterReadable(chan.reactiveId)
  else:
    var task = new(Task[ref Channel]) 
    task.run = proc (task: ref TaskBase) =
      currentEventLoop.reactor.unregisterReadable((ref Task[ref Channel])(task).value.reactiveId)
    task.value = chan
    gExecutor.eventLoops[chan.eventLoopId].taskRegistry.addMpsc(task)

proc unregisterWritable*(chan: ref Channel) =
  if chan.eventLoopId == currentEventLoopId:
    currentEventLoop.reactor.unregisterWritable(chan.reactiveId)
  else:
    var task = new(Task[ref Channel]) 
    task.run = proc (task: ref TaskBase) =
      currentEventLoop.reactor.unregisterWritable((ref Task[ref Channel])(task).value.reactiveId)
    task.value = chan
    gExecutor.eventLoops[chan.eventLoopId].taskRegistry.addMpsc(task)

proc updateRead*(chan: ref Channel, action: ref ActionBase) =
  if chan.eventLoopId == currentEventLoopId:
    currentEventLoop.reactor.updateRead(chan.reactiveId, action)
  else:
    var task = new(ActionTask[ref ActionBase]) 
    task.run = proc (task: ref TaskBase) =
      let t = (ref ActionTask[ref ActionBase])(task)
      currentEventLoop.reactor.updateRead(t.chan.reactiveId, t.value)
    task.chan = chan
    task.value = action
    gExecutor.eventLoops[chan.eventLoopId].taskRegistry.addMpsc(task)

proc updateWrite*(chan: ref Channel, action: ref ActionBase) =
  if chan.eventLoopId == currentEventLoopId:
    currentEventLoop.reactor.updateWrite(chan.reactiveId, action)
  else:
    var task = new(ActionTask[ref ActionBase]) 
    task.run = proc (task: ref TaskBase) =
      let t = (ref ActionTask[ref ActionBase])(task)
      currentEventLoop.reactor.updateWrite(t.chan.reactiveId, t.value)
    task.chan = chan
    task.value = action
    gExecutor.eventLoops[chan.eventLoopId].taskRegistry.addMpsc(task)


