
import std/cpuinfo
import netkit/options
import netkit/locks
import netkit/aio/error
import netkit/aio/executor

const
  MaxExecutorCount* {.intdefine.} = 256            ## Maximum size of the event loop gScheduler. 
  InitialPollerSize* {.intdefine.} = 4096
  InitialSpscSize* {.intdefine.} = 4096
  InitialMpscSize* {.intdefine.} = 4096
  ExecutorTimeout* {.intdefine.} = 500

type
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
  currentExecutor* {.threadvar.}: ptr Executor 
  currentExecutorId {.threadvar.}: int 

proc initExecutorScheduler(s: var ExecutorScheduler) =
  s.cpus = countProcessors()
  s.cap = min(s.cpus, MaxExecutorCount)
  s.mask = s.cap - 1
  s.recursiveExecutorId = 1
  s.recursiveExecutorLock = initSpinLock()
  s.recursiveExecutorGroupId = 0
  s.recursiveExecutorGroupLock = initSpinLock()
  s.stateLock = initSpinLock()
  s.state = ExecutorSchedulerState.CREATED
  for i in 0..<s.cap:
    s.executors[i].initExecutor(InitialPollerSize)

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
    group.recursiveExecutorLock = initSpinLock()
    withLock gScheduler.recursiveExecutorLock:
      group.start = gScheduler.recursiveExecutorId - 1
      gScheduler.recursiveExecutorId = (group.start + group.cap) mod gScheduler.mask + 1

proc spawn*(id: ExecutorGroupId, fiber: ref FiberBase) =
  if not gScheduler.executorGroups[id].has:
    raise newException(IndexDefect, "ExecutorGroup not found")
  let group = gScheduler.executorGroups[id].value.addr
  if group.cap > 0:
    var idInGroup = 0
    withLock group.recursiveExecutorLock:
      idInGroup = group.recursiveExecutorId
      group.recursiveExecutorId = (group.recursiveExecutorId + 1) mod group.cap
    let executorId = (group.start + idInGroup) mod gScheduler.mask + 1
    if currentExecutorId > 0:
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

# proc shutdownExecutor(ex: ptr Executor, pollable: ref PollableBase): bool =
#   result = true
#   for id in ex.poller.interests():
#     ex.poller.unregister(id)
#   ex.poller.shutdown()

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

initExecutorScheduler(gScheduler)

# when isMainModule:
#   type
#     TestData = object 
#       value: int

#   var num = 0

#   proc runTestFiber(fiber: ref FiberBase) =
#     atomicInc(num)
#     if num == 1000:
#       shutdownExecutorScheduler()

#   proc newTestFiber(value: int): ref Fiber[TestData] =
#     new(result)
#     result.value.value = value
#     result.run = runTestFiber

#   proc testFiberScheduling() =
#     var group = sliceExecutorGroup(20)
#     for i in 0..<1000:
#       group.spawn(newTestFiber(i))
#     runExecutorScheduler()
#     assert num == 1000

#   testFiberScheduling()

#   import std/posix

#   type
#     ReadData = object 
#       pod: Pod

#     ReadContext = object 

#     WriteData = object 
#       pod: Pod
#       value: int

#     WriteContext = object
#       value: int
  
#   var data = 100
#   var channel: array[2, cint]
#   discard pipe(channel)

#   proc pollReadable(p: ref PollableBase): bool =
#     result = true
#     var buffer = newString(9)
#     if (ref Pollable[WriteData])(p).value.pod.fd.read(buffer.cstring, buffer.len) < 0:
#       raiseOSError(osLastError())
#     assert buffer == "hello 100"
#     (ref Pollable[ReadData])(p).value.pod.close()
#     shutdownExecutorScheduler()

#   proc runReadFiber(fiber: ref FiberBase) =
#     var pod: Pod
#     initPod(pod, channel[0])
#     var pollable = new(Pollable[ReadData])
#     pollable.initSimpleNode()
#     pollable.poll = pollReadable
#     pollable.value.pod = pod
#     pod.updateRead(pollable)

#   proc newReadFiber(): ref Fiber[ReadContext] =
#     new(result)
#     result.run = runReadFiber

#   proc pollWritable(p: ref PollableBase): bool =
#     result = true
#     var buffer = "hello " & $((ref Pollable[WriteData])(p).value.value)
#     if (ref Pollable[WriteData])(p).value.pod.fd.write(buffer.cstring, buffer.len) < 0:
#       raiseOSError(osLastError())
#     (ref Pollable[WriteData])(p).value.pod.close()

#   proc runWriteFiber(fiber: ref FiberBase) =
#     var pod: Pod
#     initPod(pod, channel[1])
#     var pollable = new(Pollable[WriteData])
#     pollable.initSimpleNode()
#     pollable.poll = pollWritable
#     pollable.value.pod = pod
#     pollable.value.value = (ref Fiber[WriteContext])(fiber).value.value
#     pod.updateWrite(pollable)

#   proc newWriteFiber(value: int): ref Fiber[WriteContext] =
#     new(result)
#     result.value.value = value
#     result.run = runWriteFiber

#   proc testPolling() =
#     var group = sliceExecutorGroup(20)
#     group.spawn(newReadFiber())
#     group.spawn(newWriteFiber(data))
#     runExecutorScheduler()

#   testPolling()