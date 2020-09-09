
import netkit/aio/pollers
import netkit/aio/executor
import netkit/aio/runtime

type
  Pod* = object 
    fd: cint
    interestId: Natural
    executor: ptr Executor

  PodFiber[T] = object of FiberBase
    pod: Pod
    value: T

proc initPod*(pod: var Pod, fd: cint) = 
  pod.fd = fd
  pod.executor = currentExecutor
  pod.interestId = currentExecutor[].registerHandle(fd)

proc close*(pod: var Pod) =
  if currentExecutor == pod.executor:
    currentExecutor[].unregisterHandle(pod.interestId)
  else:
    var fiber = new(PodFiber[void]) 
    fiber.run = proc (fiber: ref FiberBase) =
      currentExecutor[].unregisterHandle((ref PodFiber[void])(fiber).pod.interestId)
    fiber.pod = pod
    pod.executor[].execMpsc(fiber)
 
proc cancelReadable*(pod: var Pod) =
  if currentExecutor == pod.executor:
    currentExecutor[].unregisterReadable(pod.interestId)
  else:
    var fiber = new(PodFiber[void]) 
    fiber.run = proc (fiber: ref FiberBase) =
      currentExecutor[].unregisterReadable((ref PodFiber[void])(fiber).pod.interestId)
    fiber.pod = pod
    pod.executor[].execMpsc(fiber)

proc cancelWritable*(pod: var Pod) =
  if currentExecutor == pod.executor:
    currentExecutor[].unregisterWritable(pod.interestId)
  else:
    var fiber = new(PodFiber[void]) 
    fiber.run = proc (fiber: ref FiberBase) =
      currentExecutor[].unregisterWritable((ref PodFiber[void])(fiber).pod.interestId)
    fiber.pod = pod
    pod.executor[].execMpsc(fiber)

proc updateRead*(pod: var Pod, pollable: ref PollableBase) =
  if currentExecutor == pod.executor:
    currentExecutor[].updateRead(pod.interestId, pollable)
  else:
    var fiber = new(PodFiber[ref PollableBase]) 
    fiber.run = proc (fiber: ref FiberBase) =
      let fiberAlias = (ref PodFiber[ref PollableBase])(fiber)
      currentExecutor[].updateRead(fiberAlias.pod.interestId, fiberAlias.value)
    fiber.pod = pod
    fiber.value = pollable
    pod.executor[].execMpsc(fiber)

proc updateWrite*(pod: var Pod, pollable: ref PollableBase) =
  if currentExecutor == pod.executor:
    currentExecutor[].updateWrite(pod.interestId, pollable)
  else:
    var fiber = new(PodFiber[ref PollableBase]) 
    fiber.run = proc (fiber: ref FiberBase) =
      let fiberAlias = (ref PodFiber[ref PollableBase])(fiber)
      currentExecutor[].updateWrite(fiberAlias.pod.interestId, fiberAlias.value)
    fiber.pod = pod
    fiber.value = pollable
    pod.executor[].execMpsc(fiber)
