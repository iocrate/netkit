
import netkit/aio/posix/pollers
import netkit/aio/posix/executors
import netkit/aio/posix/runtime

type
  Pod* = object 
    fd: cint
    id: Natural
    executor: ptr Executor

  PollableId[T] = object
    id: Natural
    value: T

proc `=destroy`*(pod: var Pod) =
  if pod.executor != nil:
    if getCurrentExecutor() == pod.executor:
      getCurrentExecutor()[].unregisterHandle(pod.id)
    else:
      let fiber = new(Fiber[PollableId[void]]) 
      fiber.run = proc (fiber: ref FiberBase) =
        getCurrentExecutor()[].unregisterHandle((ref Fiber[PollableId[void]])(fiber).value.id)
      fiber.value.id = pod.id
      pod.executor[].execMpsc(fiber)

proc `=`*(dest: var Pod, source: Pod) {.error.}
 
proc initPod*(fd: cint): Pod = 
  result.fd = fd
  result.executor = getCurrentExecutor()
  result.id = getCurrentExecutor()[].registerHandle(fd)

proc registerReadable*(pod: Pod, pollable: ref PollableBase) =
  if getCurrentExecutor() == pod.executor:
    getCurrentExecutor()[].registerReadable(pod.id, pollable)
  else:
    var fiber = new(Fiber[PollableId[ref PollableBase]]) 
    fiber.run = proc (fiber: ref FiberBase) =
      let fiberAlias = (ref Fiber[PollableId[ref PollableBase]])(fiber)
      getCurrentExecutor()[].registerReadable(fiberAlias.value.id, fiberAlias.value.value)
    fiber.value.id = pod.id
    #
    # fiber.value.value = pollable # crashs! Why?
    #
    #   SIGSEGV: Illegal storage access. (Attempt to read from nil?)
    #
    fiber.value.value = (ref PollableBase)(pollable)
    pod.executor[].execMpsc(fiber)

proc unregisterReadable*(pod: Pod) =
  if getCurrentExecutor() == pod.executor:
    getCurrentExecutor()[].unregisterReadable(pod.id)
  else:
    var fiber = new(Fiber[PollableId[void]]) 
    fiber.run = proc (fiber: ref FiberBase) =
      getCurrentExecutor()[].unregisterReadable((ref Fiber[PollableId[void]])(fiber).value.id)
    fiber.value.id = pod.id
    pod.executor[].execMpsc(fiber)

proc registerWritable*(pod: Pod, pollable: ref PollableBase) =
  if getCurrentExecutor() == pod.executor:
    getCurrentExecutor()[].registerWritable(pod.id, pollable)
  else:
    var fiber = new(Fiber[PollableId[ref PollableBase]]) 
    fiber.run = proc (fiber: ref FiberBase) =
      let fiberAlias = (ref Fiber[PollableId[ref PollableBase]])(fiber)
      getCurrentExecutor()[].registerWritable(fiberAlias.value.id, fiberAlias.value.value)
    fiber.value.id = pod.id
    fiber.value.value = (ref PollableBase)(pollable)
    pod.executor[].execMpsc(fiber)

proc unregisterWritable*(pod: Pod) =
  if getCurrentExecutor() == pod.executor:
    getCurrentExecutor()[].unregisterWritable(pod.id)
  else:
    var fiber = new(Fiber[PollableId[void]]) 
    fiber.run = proc (fiber: ref FiberBase) =
      getCurrentExecutor()[].unregisterWritable((ref Fiber[PollableId[void]])(fiber).value.id)
    fiber.value.id = pod.id
    pod.executor[].execMpsc(fiber)

when isMainModule:
  import std/os
  import std/posix

  type
    Reader = object
      pod: Pod

    Writer = object
      pod: Pod
      value: Natural
  
  var channel: array[2, cint]
  discard pipe(channel)

  proc pollReadable(p: ref PollableBase): bool =
    result = true
    var buffer = newString(9)
    if (ref Pollable[Reader])(p).value.pod.fd.read(buffer.cstring, buffer.len) < 0:
      raiseOSError(osLastError())
    assert buffer == "hello 100"
    shutdownExecutorScheduler()

  proc runReadFiber(fiber: ref FiberBase) =
    var readable = new(Pollable[Reader])
    readable.poll = pollReadable
    readable.value.pod = initPod(channel[0])
    readable.value.pod.registerReadable(readable)

  proc newReadFiber(): ref Fiber[void] =
    new(result)
    result.run = runReadFiber

  proc pollWritable(p: ref PollableBase): bool =
    result = true
    var buffer = "hello " & $((ref Pollable[Writer])(p).value.value)
    if (ref Pollable[Writer])(p).value.pod.fd.write(buffer.cstring, buffer.len) < 0:
      raiseOSError(osLastError())

  proc runWriteFiber(fiber: ref FiberBase) =
    var writable = new(Pollable[Writer])
    writable.poll = pollWritable
    writable.value.pod = initPod(channel[1])
    writable.value.pod.registerWritable(writable)
    writable.value.value = (ref Fiber[Natural])(fiber).value

  proc newWriteFiber(value: int): ref Fiber[Natural] =
    new(result)
    result.run = runWriteFiber
    result.value = value

  proc test() =
    var group = sliceExecutorGroup(20)
    group.spawn(newReadFiber())
    group.spawn(newWriteFiber(100))
    runExecutorScheduler()

  test()