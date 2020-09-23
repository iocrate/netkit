
import netkit/aio/posix/pollers
import netkit/aio/posix/executors
import netkit/aio/posix/runtime/schedulers
import netkit/aio/posix/runtime/handles

type
  IoRegistry* = object 
    owner: ptr Executor
    id: Natural
    handle: IoHandle

proc `=destroy`*(r: var IoRegistry) =
  if r.owner != nil:
    if getCurrentExecutor() == r.owner:
      getCurrentExecutor()[].unregisterHandle(r.id)
    else:
      let id = r.id
      let exec = if isPrimaryExecutor(): execSpsc else: execMpsc
      r.owner[].exec proc () =
        getCurrentExecutor()[].unregisterHandle(id)

proc `=`*(dest: var IoRegistry, source: IoRegistry) {.error.}
 
proc initIoRegistry*(handle: IoHandle): IoRegistry = 
  result.owner = getCurrentExecutor()
  result.id = result.owner[].registerHandle(handle.cint)
  result.handle = handle

proc registerReadable*(r: IoRegistry, p: Pollable) =
  if getCurrentExecutor() == r.owner:
    getCurrentExecutor()[].registerReadable(r.id, p)
  else:
    let id = r.id
    let exec = if isPrimaryExecutor(): execSpsc else: execMpsc
    r.owner[].exec proc () =
      getCurrentExecutor()[].registerReadable(id, p)

proc unregisterReadable*(r: IoRegistry) =
  if getCurrentExecutor() == r.owner:
    getCurrentExecutor()[].unregisterReadable(r.id)
  else:
    let id = r.id
    let exec = if isPrimaryExecutor(): execSpsc else: execMpsc
    r.owner[].exec proc () =
      getCurrentExecutor()[].unregisterReadable(id)

proc registerWritable*(r: IoRegistry, p: Pollable) =
  if getCurrentExecutor() == r.owner:
    getCurrentExecutor()[].registerWritable(r.id, p)
  else:
    let id = r.id
    let exec = if isPrimaryExecutor(): execSpsc else: execMpsc
    r.owner[].exec proc () =
      getCurrentExecutor()[].registerWritable(id, p)

proc unregisterWritable*(r: IoRegistry) =
  if getCurrentExecutor() == r.owner:
    getCurrentExecutor()[].unregisterWritable(r.id)
  else:
    let id = r.id
    let exec = if isPrimaryExecutor(): execSpsc else: execMpsc
    r.owner[].exec proc () =
      getCurrentExecutor()[].unregisterWritable(id)

when isMainModule:
  import std/os
  import std/posix

  type
    IoStream = ref object
      registry: IoRegistry

  proc test() =
    let group = sliceExecutorGroup(20)

    var channel: array[2, cint]
    if pipe(channel) < 0:
      raiseOSError(osLastError())
    let reader = IoHandle(channel[0])
    let writer = IoHandle(channel[1])

    group.spawn proc () =
      let stream = new(IoStream)
      stream.registry = initIoRegistry(reader)
      stream.registry.registerReadable proc (): bool =
        result = true
        let buffer = newString(9)
        if cint(stream.registry.handle).read(buffer.cstring, buffer.len) < 0:
          raiseOSError(osLastError())
        assert buffer == "hello 100"
        shutdownExecutorScheduler()

    group.spawn proc () =
      let stream = new(IoStream)
      stream.registry = initIoRegistry(writer)
      stream.registry.registerWritable proc (): bool =
        result = true
        let buffer = "hello " & $(100)
        if cint(stream.registry.handle).write(buffer.cstring, buffer.len) < 0:
          raiseOSError(osLastError())

    runExecutorScheduler()

    if close(reader.cint) < 0:
      raiseOSError(osLastError())
    if close(writer.cint) < 0:
      raiseOSError(osLastError())

  test()
