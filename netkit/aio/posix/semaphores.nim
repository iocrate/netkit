
import std/os
import std/posix
import netkit/objects
import netkit/aio/posix/pollers

type
  PollableSemaphore* = object
    reader: cint
    writer: cint
    rbuf: uint
    wbuf: uint
    destructorState: DestructorState

proc `=destroy`*(x: var PollableSemaphore) =
  if x.destructorState == DestructorState.READY:
    if x.reader.close() < 0:
      raiseOSError(osLastError())
    if x.writer.close() < 0:
      raiseOSError(osLastError())
    x.destructorState = DestructorState.COMPLETED

proc `=`*(dest: var PollableSemaphore, source: PollableSemaphore) {.error.} 

proc initPollableSemaphore*(x: var PollableSemaphore) =
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

proc signal*(s: var PollableSemaphore) = 
  s.wbuf = 1'u
  while s.writer.write(s.wbuf.addr, sizeof(uint)) < 0:
    let errorCode = osLastError()
    if errorCode.int32 == EINTR:
      discard
    elif errorCode.int32 == EWOULDBLOCK or errorCode.int32 == EAGAIN:
      raise newException(IOError, "signal writer should not be non-blocking")
    else:
      raiseOSError(errorCode) 

proc wait*(s: var PollableSemaphore): uint = 
  s.rbuf = 0'u
  while true:
    let ret = s.reader.read(s.rbuf.addr, sizeof(uint)) 
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
      result = result + s.rbuf
      s.rbuf = 0'u

proc register*(poller: var Poller, s: PollableSemaphore): Natural =
  result = poller.registerHandle(s.reader)

