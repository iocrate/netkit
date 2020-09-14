
import std/os
import std/posix
import netkit/objects
import netkit/sync/semaphores
import netkit/aio/posix/pollers

type
  PollableCounter* = object
    reader: cint
    writer: cint
    rbuf: uint
    wbuf: uint
    destructorState: DestructorState

  PollableSemaphore* = Semaphore[PollableCounter]

proc `=destroy`*(x: var PollableCounter)  {.raises: [OSError].} =
  if x.destructorState == DestructorState.READY:
    if x.reader.close() < 0:
      raiseOSError(osLastError())
    if x.writer.close() < 0:
      raiseOSError(osLastError())
    x.destructorState = DestructorState.COMPLETED

proc `=`*(dest: var PollableCounter, source: PollableCounter) {.error.} 

proc initPollableCounter*(x: var PollableCounter) {.raises: [OSError].} =
  var duplexer: array[2, cint]
  let retPipe = pipe(duplexer)
  if retPipe < 0:
    raiseOSError(osLastError())
  x.reader = duplexer[0]
  x.writer = duplexer[1]
  let retFcntl = fcntl(x.reader, F_SETFL, O_NONBLOCK)
  if retFcntl < 0:
    raiseOSError(osLastError())
  x.destructorState = DestructorState.READY

proc signal(s: var PollableSemaphore) = 
  s.value.wbuf = 1'u
  while s.value.writer.write(s.value.wbuf.addr, sizeof(uint)) < 0:
    let errorCode = osLastError()
    if errorCode.int32 == EINTR:
      discard
    elif errorCode.int32 == EWOULDBLOCK or errorCode.int32 == EAGAIN:
      raise newException(IOError, "signal writer should not be non-blocking")
    else:
      raiseOSError(errorCode) 

proc wait(s: var PollableSemaphore): uint = 
  s.value.rbuf = 0'u
  while true:
    let ret = s.value.reader.read(s.value.rbuf.addr, sizeof(uint)) 
    if ret < 0:
      let errorCode = osLastError()
      if errorCode.int32 == EINTR:
        discard
      elif errorCode.int32 == EWOULDBLOCK or errorCode.int32 == EAGAIN:
        return 
      else:
        raiseOSError(osLastError()) 
    elif ret == 0:
      assert false
    else:
      result = result + s.value.rbuf
      s.value.rbuf = 0'u

proc initPollableSemaphore*(s: var PollableSemaphore) {.raises: [OSError].} =
  s.value.initPollableCounter()
  s.signalImpl = signal
  s.waitImpl = wait

proc register*(poller: var Poller, s: PollableSemaphore): Natural {.raises: [OSError].} =
  result = poller.registerHandle(s.value.reader)

