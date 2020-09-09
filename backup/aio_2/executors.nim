
when not compileOption("threads"):
  {.error: "ExecutorScheduler requires --threads:on option.".}

import std/cpuinfo
import std/os
import netkit/options
import netkit/locks
import netkit/collections/spsc
import netkit/collections/mpsc
import netkit/collections/simplelists
import netkit/aio/fibercounter
import netkit/aio/pollers
import netkit/aio/error

const
  MaxExecutorCount* {.intdefine.} = 256            ## Maximum size of the event loop gScheduler. 
  InitialPollerSize* {.intdefine.} = 4096
  InitialSpscSize* {.intdefine.} = 4096
  InitialMpscSize* {.intdefine.} = 4096
  ExecutorTimeout* {.intdefine.} = 500

type
  FiberBase* = object of RootObj
    run*: FiberProc

  Fiber*[T] = object of FiberBase
    value*: T

  FiberProc* = proc (fiber: ref FiberBase) {.nimcall, gcsafe.}

  Pod* = object 
    fd: cint
    interestId: Natural
    executorId: Natural

  PodFiber[T] = object of FiberBase
    pod: Pod
    value: T

  Executor* = object
    id: Natural
    poller: Poller
    spscCounter: Pod
    spscQueue: SpscQueue[ref FiberBase, cint]
    mpscCounter: Pod
    mpscQueue: MpscQueue[ref FiberBase, cint]

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
  currentExecutorId {.threadvar.}: int 

proc initPod*(pod: var Pod, fd: cint) = 
  pod.fd = fd
  pod.executorId = currentExecutorId
  pod.interestId = currentExecutor.poller.register(fd)

proc close*(pod: var Pod) =
  if currentExecutorId == pod.executorId:
    currentExecutor.poller.unregister(pod.interestId)
  else:
    var fiber = new(PodFiber[void]) 
    fiber.run = proc (fiber: ref FiberBase) =
      currentExecutor.poller.unregister((ref PodFiber[void])(fiber).pod.interestId)
    fiber.pod = pod
    gScheduler.executors[pod.executorId].mpscQueue.add(fiber)
 
proc cancelReadable*(pod: var Pod) =
  if currentExecutorId == pod.executorId:
    currentExecutor.poller.unregisterReadable(pod.interestId)
  else:
    var fiber = new(PodFiber[void]) 
    fiber.run = proc (fiber: ref FiberBase) =
      currentExecutor.poller.unregisterReadable((ref PodFiber[void])(fiber).pod.interestId)
    fiber.pod = pod
    gScheduler.executors[pod.executorId].mpscQueue.add(fiber)

proc cancelWritable*(pod: var Pod) =
  if currentExecutorId == pod.executorId:
    currentExecutor.poller.unregisterWritable(pod.interestId)
  else:
    var fiber = new(PodFiber[void]) 
    fiber.run = proc (fiber: ref FiberBase) =
      currentExecutor.poller.unregisterWritable((ref PodFiber[void])(fiber).pod.interestId)
    fiber.pod = pod
    gScheduler.executors[pod.executorId].mpscQueue.add(fiber)

proc updateRead*(pod: var Pod, pollable: ref PollableBase) =
  if currentExecutorId == pod.executorId:
    currentExecutor.poller.updateRead(pod.interestId, pollable)
  else:
    var fiber = new(PodFiber[ref PollableBase]) 
    fiber.run = proc (fiber: ref FiberBase) =
      let fiberAlias = (ref PodFiber[ref PollableBase])(fiber)
      currentExecutor.poller.updateRead(fiberAlias.pod.interestId, fiberAlias.value)
    fiber.pod = pod
    fiber.value = pollable
    gScheduler.executors[pod.executorId].mpscQueue.add(fiber)

proc updateWrite*(pod: var Pod, pollable: ref PollableBase) =
  if currentExecutorId == pod.executorId:
    currentExecutor.poller.updateWrite(pod.interestId, pollable)
  else:
    var fiber = new(PodFiber[ref PollableBase]) 
    fiber.run = proc (fiber: ref FiberBase) =
      let fiberAlias = (ref PodFiber[ref PollableBase])(fiber)
      currentExecutor.poller.updateWrite(fiberAlias.pod.interestId, fiberAlias.value)
    fiber.pod = pod
    fiber.value = pollable
    gScheduler.executors[pod.executorId].mpscQueue.add(fiber)

proc pollSpscFibers(pollable: ref PollableBase): bool =
  result = false
  currentExecutor.spscQueue.sync()
  while currentExecutor.spscQueue.len > 0:
    let runnable = currentExecutor.spscQueue.take()
    runnable.run(runnable)

proc pollMpscFibers(pollable: ref PollableBase): bool =
  result = false
  result = false
  currentExecutor.mpscQueue.sync()
  while currentExecutor.mpscQueue.len > 0:
    let runnable = currentExecutor.mpscQueue.take()
    runnable.run(runnable)

proc initExecutor(ex: var Executor, id: Natural) {.raises: [OSError, ValueError].} =
  ex.id = id
  initPoller(ex.poller, InitialPollerSize)

  ex.spscCounter.fd = eventfd(0, 0)
  if ex.spscCounter.fd < 0:
    raiseOSError(osLastError())
  ex.spscQueue = initSpscQueue[ref FiberBase, cint](initFiberCounter(ex.spscCounter.fd), InitialSpscSize)

  ex.spscCounter.executorId = id
  ex.spscCounter.interestId = ex.poller.register(ex.spscCounter.fd)
  let spscPollable = new(PollableBase)
  spscPollable.initSimpleNode()
  spscPollable.poll = pollSpscFibers
  ex.poller.updateRead(ex.spscCounter.interestId, spscPollable)

  ex.mpscCounter.fd = eventfd(0, 0)
  if ex.mpscCounter.fd < 0:
    raiseOSError(osLastError())
  ex.mpscQueue = initMpscQueue[ref FiberBase, cint](initFiberCounter(ex.mpscCounter.fd), InitialMpscSize)

  ex.mpscCounter.executorId = id
  ex.mpscCounter.interestId = ex.poller.register(ex.mpscCounter.fd)
  let mpscPollable = new(PollableBase)
  mpscPollable.initSimpleNode()
  mpscPollable.poll = pollMpscFibers
  ex.poller.updateRead(ex.mpscCounter.interestId, mpscPollable)

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
    s.executors[i].initExecutor(i)

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

proc spawn*(id: ExecutorGroupId, ex: ref FiberBase) =
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
      gScheduler.executors[executorId].mpscQueue.add(ex)
    else:
      gScheduler.executors[executorId].spscQueue.add(ex)
  else:
    gScheduler.executors[0].spscQueue.add(ex)

proc runExecutor(id: Natural) {.thread.} =
  currentExecutorId = id
  currentExecutor = gScheduler.executors[id].addr
  currentExecutor.poller.runBlocking(ExecutorTimeout)

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
      gScheduler.executors[i].poller.shutdown()
    gScheduler.executors[0].poller.shutdown()

initExecutorScheduler(gScheduler)

when isMainModule:
  type
    TestData = object 
      value: int

  var num = 0

  proc runTestFiber(fiber: ref FiberBase) =
    atomicInc(num)
    if num == 1000:
      shutdownExecutorScheduler()

  proc newTestFiber(value: int): ref Fiber[TestData] =
    new(result)
    result.value.value = value
    result.run = runTestFiber

  proc testFiberScheduling() =
    var group = sliceExecutorGroup(20)
    for i in 0..<1000:
      group.spawn(newTestFiber(i))
    runExecutorScheduler()
    assert num == 1000

  testFiberScheduling()

  import std/posix

  type
    ReadData = object 
      pod: Pod

    ReadContext = object 

    WriteData = object 
      pod: Pod
      value: int

    WriteContext = object
      value: int
  
  var data = 100
  var channel: array[2, cint]
  discard pipe(channel)

  proc pollReadable(p: ref PollableBase): bool =
    result = true
    var buffer = newString(9)
    if (ref Pollable[WriteData])(p).value.pod.fd.read(buffer.cstring, buffer.len) < 0:
      raiseOSError(osLastError())
    assert buffer == "hello 100"
    (ref Pollable[ReadData])(p).value.pod.close()
    shutdownExecutorScheduler()

  proc runReadFiber(fiber: ref FiberBase) =
    var pod: Pod
    initPod(pod, channel[0])
    var pollable = new(Pollable[ReadData])
    pollable.initSimpleNode()
    pollable.poll = pollReadable
    pollable.value.pod = pod
    pod.updateRead(pollable)

  proc newReadFiber(): ref Fiber[ReadContext] =
    new(result)
    result.run = runReadFiber

  proc pollWritable(p: ref PollableBase): bool =
    result = true
    var buffer = "hello " & $((ref Pollable[WriteData])(p).value.value)
    if (ref Pollable[WriteData])(p).value.pod.fd.write(buffer.cstring, buffer.len) < 0:
      raiseOSError(osLastError())
    (ref Pollable[WriteData])(p).value.pod.close()

  proc runWriteFiber(fiber: ref FiberBase) =
    var pod: Pod
    initPod(pod, channel[1])
    var pollable = new(Pollable[WriteData])
    pollable.initSimpleNode()
    pollable.poll = pollWritable
    pollable.value.pod = pod
    pollable.value.value = (ref Fiber[WriteContext])(fiber).value.value
    pod.updateWrite(pollable)

  proc newWriteFiber(value: int): ref Fiber[WriteContext] =
    new(result)
    result.value.value = value
    result.run = runWriteFiber

  proc testPolling() =
    var group = sliceExecutorGroup(20)
    group.spawn(newReadFiber())
    group.spawn(newWriteFiber(data))
    runExecutorScheduler()

  testPolling()