
import std/cpuinfo
import netkit/options
import netkit/sync/locks
import netkit/errors
import netkit/aio/posix/executors

const
  MaxExecutorCount* {.intdefine.} = 256            ## Maximum size of the event loop gScheduler. 
  InitialPollerSize* {.intdefine.} = 4096
  InitialSpscSize* {.intdefine.} = 4096
  InitialMpscSize* {.intdefine.} = 4096
  ExecutorTimeout* {.intdefine.} = 500

type
  ExecutorId* = Natural

  ExecutorRole* {.pure.} = enum
    PRIMARY, SECONDARY

  ExecutorGroup* = object
    id: ExecutorGroupId
    start: Natural
    cap: Natural
    recursiveExecutorId: Natural
    recursiveExecutorLock: SpinLock

  ExecutorGroupId* = Natural

  ExecutorScheduler* = object
    threads: array[MaxExecutorCount, Thread[Natural]] 
    executors: array[MaxExecutorCount, Executor]    
    executorGroups: array[MaxExecutorCount, Option[ExecutorGroup]] 
    cpus: Natural
    cap: Natural
    mask: Natural
    recursiveExecutorId: Natural
    recursiveExecutorLock: SpinLock
    recursiveExecutorGroupId: Natural
    recursiveExecutorGroupLock: SpinLock
    stateLock: SpinLock
    state: ExecutorSchedulerState

  ExecutorSchedulerState* {.pure.} = enum
    CREATED, RUNNING, SHUTDOWN, STOPPED, CLOSED

var
  gScheduler: ExecutorScheduler
  currentExecutor {.threadvar.}: ptr Executor 
  currentExecutorId {.threadvar.}: ExecutorId 

proc getCurrentExecutor*(): ptr Executor {.inline.} =
  currentExecutor

proc isPrimaryExecutor*(): bool {.inline.} =
  currentExecutorId == 0

proc isSecondaryExecutor*(): bool {.inline.} =
  currentExecutorId > 0

proc initExecutorScheduler(s: var ExecutorScheduler) =
  s.cpus = countProcessors()
  s.cap = min(s.cpus, MaxExecutorCount)
  s.mask = s.cap - 1
  s.recursiveExecutorId = 1
  s.recursiveExecutorLock.initSpinLock()
  s.recursiveExecutorGroupId = 0
  s.recursiveExecutorGroupLock.initSpinLock()
  s.stateLock.initSpinLock()
  s.state = ExecutorSchedulerState.CREATED
  for i in 0..<s.cap:
    s.executors[i].initExecutor(InitialPollerSize)
  currentExecutor = s.executors[0].addr

proc sliceExecutorGroup*(cap: Natural): ExecutorGroupId =
  result = 0
  
  withLock gScheduler.recursiveExecutorGroupLock:
    result = gScheduler.recursiveExecutorGroupId
    gScheduler.recursiveExecutorGroupId = gScheduler.recursiveExecutorGroupId + 1
    if gScheduler.recursiveExecutorGroupId >= MaxExecutorCount:
      raise newException(RangeDefect, "too many ExecutorGroup slices")
  
  gScheduler.executorGroups[result].has = true

  let group = gScheduler.executorGroups[result].value.addr
  group.cap = min(gScheduler.mask, cap)
  if group.cap > 0:
    group.recursiveExecutorLock.initSpinLock()
    withLock gScheduler.recursiveExecutorLock:
      group.start = gScheduler.recursiveExecutorId - 1
      gScheduler.recursiveExecutorId = (group.start + group.cap) mod gScheduler.mask + 1

proc spawn*(id: ExecutorGroupId, fiber: FiberProc) =
  if not gScheduler.executorGroups[id].has:
    raise newException(IndexDefect, "ExecutorGroup not found")
  let group = gScheduler.executorGroups[id].value.addr
  if group.cap > 0:
    var idInGroup = 0
    withLock group.recursiveExecutorLock:
      idInGroup = group.recursiveExecutorId
      group.recursiveExecutorId = (group.recursiveExecutorId + 1) mod group.cap
    let executorId = (group.start + idInGroup) mod gScheduler.mask + 1
    if isSecondaryExecutor():
      gScheduler.executors[executorId].execMpsc(fiber)
    else:
      gScheduler.executors[executorId].execSpsc(fiber)
  else:
    gScheduler.executors[0].execSpsc(fiber)

proc runExecutor(id: Natural) {.thread.} =
  currentExecutorId = id
  currentExecutor = gScheduler.executors[id].addr
  runBlocking(currentExecutor[], ExecutorTimeout)

proc runExecutorScheduler*() =
  withLock gScheduler.stateLock:
    case gScheduler.state
    of ExecutorSchedulerState.CREATED:
      gScheduler.state = ExecutorSchedulerState.RUNNING
    of ExecutorSchedulerState.SHUTDOWN:
      raise newException(IllegalStateError, "ExecutorScheduler still shutdowning")
    of ExecutorSchedulerState.STOPPED:
      gScheduler.state = ExecutorSchedulerState.RUNNING
    of ExecutorSchedulerState.RUNNING:
      raise newException(IllegalStateError, "ExecutorScheduler already running")
    of ExecutorSchedulerState.CLOSED:
      raise newException(IllegalStateError, "ExecutorScheduler already closed")
  
  for i in 1..<gScheduler.cap:
    createThread(gScheduler.threads[i], runExecutor, i)
    when defined(PinToCpu):
      assert gScheduler.cpus > 0
      pinToCpu(gScheduler.threads[i], i mod gScheduler.cpus)
  runExecutor(0) 

  for i in 1..<gScheduler.cap:
    joinThread(gScheduler.threads[i])
  gScheduler.state = ExecutorSchedulerState.STOPPED

proc shutdownExecutorScheduler*() =
  withLock gScheduler.stateLock:
    case gScheduler.state
    of ExecutorSchedulerState.CREATED:
      gScheduler.state = ExecutorSchedulerState.SHUTDOWN
    of ExecutorSchedulerState.SHUTDOWN:
      raise newException(IllegalStateError, "ExecutorScheduler still shutdowning")
    of ExecutorSchedulerState.STOPPED:
      raise newException(IllegalStateError, "ExecutorScheduler already stopped")
    of ExecutorSchedulerState.RUNNING:
      gScheduler.state = ExecutorSchedulerState.SHUTDOWN
    of ExecutorSchedulerState.CLOSED:
      raise newException(IllegalStateError, "ExecutorScheduler already closed")

    for i in 1..<gScheduler.cap:
      gScheduler.executors[i].shutdown()
    gScheduler.executors[0].shutdown()

gScheduler.initExecutorScheduler()

when isMainModule:
  var num = 0

  proc test() =
    var group = sliceExecutorGroup(20)
    for i in 0..<1000:
      group.spawn proc () =
        atomicInc(num)
        if num == 1000:
          shutdownExecutorScheduler()
    runExecutorScheduler()
    assert num == 1000
    echo num

  test()
  