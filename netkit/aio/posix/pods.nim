
import netkit/aio/posix/pollers
import netkit/aio/posix/executors
import netkit/aio/posix/runtime

type
  Pod* = object 
    fd: cint
    id: Natural
    executor: ptr Executor

proc `=destroy`*(pod: var Pod) =
  if pod.executor != nil:
    if getCurrentExecutor() == pod.executor:
      getCurrentExecutor()[].unregisterHandle(pod.id)
    else:
      let id = pod.id
      pod.executor[].execMpsc proc () =
        getCurrentExecutor()[].unregisterHandle(id)

proc `=`*(dest: var Pod, source: Pod) {.error.}
 
proc initPod*(fd: cint): Pod = 
  result.fd = fd
  result.executor = getCurrentExecutor()
  result.id = getCurrentExecutor()[].registerHandle(fd)

proc registerReadable*(pod: Pod, p: Pollable) =
  if getCurrentExecutor() == pod.executor:
    getCurrentExecutor()[].registerReadable(pod.id, p)
  else:
    let id = pod.id
    pod.executor[].execMpsc proc () =
      getCurrentExecutor()[].registerReadable(id, p)

proc unregisterReadable*(pod: Pod) =
  if getCurrentExecutor() == pod.executor:
    getCurrentExecutor()[].unregisterReadable(pod.id)
  else:
    let id = pod.id
    pod.executor[].execMpsc proc () =
      getCurrentExecutor()[].unregisterReadable(id)

proc registerWritable*(pod: Pod, p: Pollable) =
  if getCurrentExecutor() == pod.executor:
    getCurrentExecutor()[].registerWritable(pod.id, p)
  else:
    let id = pod.id
    pod.executor[].execMpsc proc () =
      getCurrentExecutor()[].registerWritable(id, p)

proc unregisterWritable*(pod: Pod) =
  if getCurrentExecutor() == pod.executor:
    getCurrentExecutor()[].unregisterWritable(pod.id)
  else:
    let id = pod.id
    pod.executor[].execMpsc proc () =
      getCurrentExecutor()[].unregisterWritable(id)

when isMainModule:
  import std/os
  import std/posix

  type
    Stream = object
      pod: Pod

  var channel: array[2, cint]
  discard pipe(channel)

  proc test() =
    var group = sliceExecutorGroup(20)

    group.spawn proc () =
      var stream = new(Stream)
      stream.pod = initPod(channel[0])
      stream.pod.registerReadable proc (): bool =
        result = true
        var buffer = newString(9)
        if stream.pod.fd.read(buffer.cstring, buffer.len) < 0:
          raiseOSError(osLastError())
        assert buffer == "hello 100"
        shutdownExecutorScheduler()

    group.spawn proc () =
      var stream = new(Stream)
      stream.pod = initPod(channel[1])
      stream.pod.registerWritable proc (): bool =
        result = true
        var buffer = "hello " & $(100)
        if stream.pod.fd.write(buffer.cstring, buffer.len) < 0:
          raiseOSError(osLastError())

    runExecutorScheduler()

  test()
