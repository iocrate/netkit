
when not compileOption("threads"):
  {.error: "EventLoopPool requires --threads:on option.".}

import std/cpuinfo
import std/os

import netkit/collections/taskcounter
import netkit/collections/task
import netkit/collections/action
import netkit/locks
import netkit/aio/ident

const
  MaxEventLoopPoolSize* {.intdefine.} = 256 ## Maximum size of the event loop pool. 
  InitialTaskRegistrySpscSize* {.intdefine.} = 4096
  InitialTaskRegistryMpscSize* {.intdefine.} = 4096
  InitialActionRegistrySize* {.intdefine.} = 4096
  EventLoopTimeout* {.intdefine.} = 500

type
  EventLoop* = object
    id: int
    taskCounterSpscFd: cint
    taskCounterMpscFd: cint
    taskRegistry: TaskRegistry
    actionRegistry: ActionRegistry

  # TODO
  # EventLoopGroup* = object
  #   id: EventLoopGroupId
  #   start: Natural
  #   cap: Natural
  #   recursiveEventLoopId: Natural
  #   lock: Lock
  # # TODO
  # EventLoopGroupId* = int

  EventLoopPool* = object
    threads: array[MaxEventLoopPoolSize, Thread[Natural]] # TODO: ptr UncheckedArray
    eventLoops: array[MaxEventLoopPoolSize, EventLoop]    # TODO: ptr UncheckedArray
    cpus: Natural
    cap: Natural
    recursiveEventLoopId: Natural
    recursiveEventLoopIdLock: SpinLock
    state: EventLoopPoolState

  EventLoopPoolState* {.pure.} = enum
    CREATING, RUNNING, SHUTDOWN

proc initEventLoop(id: Natural): EventLoop {.raises: [OSError].} =
  result.id = id
  result.taskCounterSpscFd = eventfd(0, 0)
  if result.taskCounterSpscFd < 0:
    raiseOSError(osLastError())
  result.taskCounterMpscFd = eventfd(0, 0)
  if result.taskCounterMpscFd < 0:
    raiseOSError(osLastError())
  result.taskRegistry = initTaskRegistry(result.taskCounterSpscFd, InitialTaskRegistrySpscSize, 
                                         result.taskCounterMpscFd, InitialTaskRegistryMpscSize)
  result.actionRegistry = initActionRegistry(InitialActionRegistrySize)

proc initEventLoopPool(): EventLoopPool =
  result.cpus = countProcessors()
  result.cap = min(result.cpus, MaxEventLoopPoolSize)
  result.recursiveEventLoopIdLock = initSpinLock()
  for i in 0..<result.cap:
    result.eventLoops[i] = initEventLoop(i)
  result.state = EventLoopPoolState.CREATING

var
  pool: EventLoopPool = initEventLoopPool()
  currentEventLoopId {.threadvar.}: int 
  currentEventLoop {.threadvar.}: ptr EventLoop 

type
  Channel = object
    fd: cint
    ident: Identity
    eventLoopId: int

proc spawn*(task: ptr TaskBase) =
  if pool.cap > 1:
    var id: int
    withLock pool.recursiveEventLoopIdLock:
      pool.recursiveEventLoopId = pool.recursiveEventLoopId mod (pool.cap - 1) + 1
      id = pool.recursiveEventLoopId
    if currentEventLoopId == 0:
      pool.eventLoops[id].taskRegistry.addSpsc(task)
    else:
      pool.eventLoops[id].taskRegistry.addMpsc(task)
  else:
    pool.eventLoops[0].taskRegistry.addSpsc(task)

type
  RegisterContext = object 
    val: int

proc register*(chan: ref Channel) =
  if chan.eventLoopId == currentEventLoopId:
    chan.ident = currentEventLoop.actionRegistry.register(chan.fd)
  else:
    var task = cast[ptr Task[ref Channel]](allocShared0(sizeof(Task[ref Channel])))
    task.run = proc (r: ptr TaskBase) =
      (ptr Task[ref Channel])(r).value.ident = currentEventLoop.actionRegistry.register((ptr Task[ref Channel])(r).value.fd)
      deallocShared(r)
    task.value = chan
    pool.eventLoops[chan.eventLoopId].taskRegistry.addMpsc(task)

proc unregister*(chan: ref Channel) =
  if chan.eventLoopId == currentEventLoopId:
    currentEventLoop.actionRegistry.unregister(chan.ident)
  else:
    var task = cast[ptr Task[ref Channel]](allocShared0(sizeof(Task[ref Channel])))
    task.run = proc (r: ptr TaskBase) =
      currentEventLoop.actionRegistry.unregister((ptr Task[ref Channel])(r).value.ident)
      deallocShared(r)
    task.value = chan
    pool.eventLoops[chan.eventLoopId].taskRegistry.addMpsc(task)

