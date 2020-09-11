
import netkit/aio/posix/pollers
import netkit/aio/posix/executors
import netkit/aio/posix/runtime

type
  Pod* = ref object 
    fd: cint
    interestId: Natural
    executor: ptr Executor

  PodFiber[T] = object of FiberBase
    pod: ref Pod
    value: T

proc newPod*(fd: cint): ref Pod = 
  new(result)
  result.fd = fd
  result.executor = getCurrentExecutor()
  result.interestId = getCurrentExecutor()[].registerHandle(fd)

proc close*(pod: ref Pod) =
  if getCurrentExecutor() == pod.executor:
    getCurrentExecutor()[].unregisterHandle(pod.interestId)
  else:
    var fiber = new(PodFiber[void]) 
    fiber.run = proc (fiber: ref FiberBase) =
      getCurrentExecutor()[].unregisterHandle((ref PodFiber[void])(fiber).pod.interestId)
    fiber.pod = pod
    pod.executor[].execMpsc(fiber)
 
proc cancelReadable*(pod: ref Pod) =
  if getCurrentExecutor() == pod.executor:
    getCurrentExecutor()[].unregisterReadable(pod.interestId)
  else:
    var fiber = new(PodFiber[void]) 
    fiber.run = proc (fiber: ref FiberBase) =
      getCurrentExecutor()[].unregisterReadable((ref PodFiber[void])(fiber).pod.interestId)
    fiber.pod = pod
    pod.executor[].execMpsc(fiber)

proc cancelWritable*(pod: ref Pod) =
  if getCurrentExecutor() == pod.executor:
    getCurrentExecutor()[].unregisterWritable(pod.interestId)
  else:
    var fiber = new(PodFiber[void]) 
    fiber.run = proc (fiber: ref FiberBase) =
      getCurrentExecutor()[].unregisterWritable((ref PodFiber[void])(fiber).pod.interestId)
    fiber.pod = pod
    pod.executor[].execMpsc(fiber)

proc updateRead*(pod: ref Pod, pollable: ref PollableBase) =
  if getCurrentExecutor() == pod.executor:
    getCurrentExecutor()[].updateRead(pod.interestId, pollable)
  else:
    var fiber = new(PodFiber[ref PollableBase]) 
    fiber.run = proc (fiber: ref FiberBase) =
      let fiberAlias = (ref PodFiber[ref PollableBase])(fiber)
      getCurrentExecutor()[].updateRead(fiberAlias.pod.interestId, fiberAlias.value)
    fiber.pod = pod
    fiber.value = pollable
    pod.executor[].execMpsc(fiber)

proc updateWrite*(pod: ref Pod, pollable: ref PollableBase) =
  if getCurrentExecutor() == pod.executor:
    getCurrentExecutor()[].updateWrite(pod.interestId, pollable)
  else:
    var fiber = new(PodFiber[ref PollableBase]) 
    fiber.run = proc (fiber: ref FiberBase) =
      let fiberAlias = (ref PodFiber[ref PollableBase])(fiber)
      getCurrentExecutor()[].updateWrite(fiberAlias.pod.interestId, fiberAlias.value)
    fiber.pod = pod
    fiber.value = pollable
    pod.executor[].execMpsc(fiber)

