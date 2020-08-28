
when not compileOption("threads"):
  {.error: "EventLoopPool requires --threads:on option.".}

import std/cpuinfo
import std/os
import std/locks

import netkit/collections/taskcounter
import netkit/collections/task
import netkit/collections/action
import netkit/aio/ident

const
  MaxEventLoopPoolSize* {.intdefine.} = 256 ## Maximum size of the event loop pool. 
  InitialTaskRegistrySpscSize* {.intdefine.} = 4096
  InitialTaskRegistryMpscSize* {.intdefine.} = 4096
  InitialActionRegistrySize* {.intdefine.} = 4096
  EventLoopTimeout* {.intdefine.} = 500

type
  EventLoop* = object
    id: Natural
    taskCounterSpscFd: cint
    taskCounterMpscFd: cint
    taskRegistry: TaskRegistry
    actionRegistry: ActionRegistry

  EventLoopGroup* = object
    start: Natural
    cap: Natural
    recursiveEventLoopId: Natural
    lock: Lock
    state: EventLoopGroupState

  EventLoopGroupId* = int

  EventLoopGroupState* {.pure.} = enum
    IDLE, RUNNING, SHUTDOWN

  EventLoopPool* = object
    threads: array[MaxEventLoopPoolSize, Thread[Natural]] # TODO: ptr UncheckedArray
    eventLoops: array[MaxEventLoopPoolSize, EventLoop]    # TODO: ptr UncheckedArray
    eventLoopGroups: array[MaxEventLoopPoolSize, EventLoopGroup]   # TODO: ptr UncheckedArray
    capacity: Natural
    recursiveEventLoopGroupId: EventLoopGroupId
    recursiveEventLoopIndex: Natural
    cpus: Natural
    lock: Lock

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
  result.capacity = min(result.cpus, MaxEventLoopPoolSize)
  initLock(result.lock)
  for i in 0..<result.capacity:
    result.eventLoops[i] = initEventLoop(i)

var
  pool: EventLoopPool = initEventLoopPool()
  currentEventLoopId {.threadvar.}: Natural 
  currentEventLoop {.threadvar.}: ptr EventLoop 

proc initEventLoopGroup*(cap: Natural): EventLoopGroupId =
  withLock pool.lock:
    result = pool.recursiveEventLoopGroupId
    pool.recursiveEventLoopGroupId.inc()
    pool.eventLoopGroups[result].start = pool.recursiveEventLoopIndex
    pool.eventLoopGroups[result].cap = cap mod pool.capacity
    pool.recursiveEventLoopIndex = (pool.recursiveEventLoopIndex + cap) mod pool.capacity  
  pool.eventLoopGroups[result].lock.initLock()          

proc register*(fd: cint): Identity {.inline.} =
  currentEventLoop.actionRegistry.register(fd)

proc unregister*(ident: Identity) {.inline.} =
  currentEventLoop.actionRegistry.unregister(ident)

proc unregisterReadable*(ident: Identity) {.inline.} =
  currentEventLoop.actionRegistry.unregisterReadable(ident)
  
proc spawn*(groupId: EventLoopGroupId, task: ptr TaskBase) =
  let group = pool.eventLoopGroups[groupId].addr
  var eventLoopId: Natural
  withLock group.lock:
    eventLoopId = (group.start + group.recursiveEventLoopId) mod pool.capacity
    group.recursiveEventLoopId = (group.recursiveEventLoopId + 1) mod group.cap
  if currentEventLoopId == 0:
    pool.eventLoops[eventLoopId].taskRegistry.addSpsc(task)
  else:
    pool.eventLoops[eventLoopId].taskRegistry.addMpsc(task)

proc runSpscCounterAction(r: ref ActionBase): bool =
  result = false
  currentEventLoop.taskRegistry.runSpsc()

proc runMpscCounterAction(r: ref ActionBase): bool =
  result = false
  currentEventLoop.taskRegistry.runMpsc()

proc runEventLoop(id: Natural) {.thread.} =
  currentEventLoopId = id
  currentEventLoop = pool.eventLoops[id].addr
  let spscCounterIdent = register(currentEventLoop.taskSpscCounterFd)
  let spscCounterAction = new(ActionBase)
  spscCounterAction.run = runSpscCounterAction
  updateRead(spscCounterIdent, spscCounterAction)
  let mpscCounterIdent = register(currentEventLoop.taskMpscCounterFd)
  let mpscCounterAction = new(ActionBase)
  mpscCounterAction.run = runMpscCounterAction
  updateRead(mpscCounterIdent, mpscCounterAction)
  poll(EventLoopTimeout)