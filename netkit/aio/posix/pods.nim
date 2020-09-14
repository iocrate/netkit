
import netkit/aio/posix/pollers
import netkit/aio/posix/executors
import netkit/aio/posix/runtime

type
  Pod* = ref object 
    fd: cint
    id: Natural
    executor: ptr Executor

  PodFiber[T] = object of FiberBase
    pod: ref Pod
    value: T

proc newPod*(fd: cint): ref Pod = 
  new(result)
  result.fd = fd
  result.executor = getCurrentExecutor()
  result.id = getCurrentExecutor()[].registerHandle(fd)

proc close*(pod: ref Pod) =
  if getCurrentExecutor() == pod.executor:
    getCurrentExecutor()[].unregisterHandle(pod.id)
  else:
    var fiber = new(PodFiber[void]) 
    fiber.run = proc (fiber: ref FiberBase) =
      getCurrentExecutor()[].unregisterHandle((ref PodFiber[void])(fiber).pod.id)
    fiber.pod = pod
    pod.executor[].execMpsc(fiber)
 
proc cancelReadable*(pod: ref Pod) =
  if getCurrentExecutor() == pod.executor:
    getCurrentExecutor()[].unregisterReadable(pod.id)
  else:
    var fiber = new(PodFiber[void]) 
    fiber.run = proc (fiber: ref FiberBase) =
      getCurrentExecutor()[].unregisterReadable((ref PodFiber[void])(fiber).pod.id)
    fiber.pod = pod
    pod.executor[].execMpsc(fiber)

proc cancelWritable*(pod: ref Pod) =
  if getCurrentExecutor() == pod.executor:
    getCurrentExecutor()[].unregisterWritable(pod.id)
  else:
    var fiber = new(PodFiber[void]) 
    fiber.run = proc (fiber: ref FiberBase) =
      getCurrentExecutor()[].unregisterWritable((ref PodFiber[void])(fiber).pod.id)
    fiber.pod = pod
    pod.executor[].execMpsc(fiber)

proc updateRead*(pod: ref Pod, pollable: ref PollableBase) =
  if getCurrentExecutor() == pod.executor:
    getCurrentExecutor()[].updateRead(pod.id, pollable)
  else:
    var fiber = new(PodFiber[ref PollableBase]) 
    fiber.run = proc (fiber: ref FiberBase) =
      let fiberAlias = (ref PodFiber[ref PollableBase])(fiber)
      getCurrentExecutor()[].updateRead(fiberAlias.pod.id, fiberAlias.value)
    fiber.pod = pod
    fiber.value = pollable
    pod.executor[].execMpsc(fiber)

proc updateWrite*(pod: ref Pod, pollable: ref PollableBase) =
  if getCurrentExecutor() == pod.executor:
    getCurrentExecutor()[].updateWrite(pod.id, pollable)
  else:
    var fiber = new(PodFiber[ref PollableBase]) 
    fiber.run = proc (fiber: ref FiberBase) =
      let fiberAlias = (ref PodFiber[ref PollableBase])(fiber)
      getCurrentExecutor()[].updateWrite(fiberAlias.pod.id, fiberAlias.value)
    fiber.pod = pod
    fiber.value = pollable
    pod.executor[].execMpsc(fiber)

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