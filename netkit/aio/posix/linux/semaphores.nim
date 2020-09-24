
import std/os
import std/posix
import netkit/objects
import netkit/aio/posix/pollers
import netkit/platforms/posix/linux/eventfd

type
  PollableSemaphore* = object
    duplexer*: cint
    rbuf: uint
    wbuf: uint
    destructorState: DestructorState

proc `=destroy`*(x: var PollableSemaphore) =
  if x.destructorState == DestructorState.READY:
    if x.duplexer.close() < 0:
      raiseOSError(osLastError())
    x.destructorState = DestructorState.COMPLETED

proc `=`*(dest: var PollableSemaphore, source: PollableSemaphore) {.error.}

proc initPollableSemaphore*(x: var PollableSemaphore) =
  x.duplexer = eventfd(0, 0)
  if x.duplexer < 0:
    raiseOSError(osLastError())
  x.destructorState = DestructorState.READY

proc signal*(s: var PollableSemaphore) = 
  s.wbuf = 1'u
  while s.duplexer.write(s.wbuf.addr, sizeof(uint)) < 0:
    let errorCode = osLastError()
    if errorCode.int32 == EINTR:
      discard
    elif errorCode.int32 == EWOULDBLOCK or errorCode.int32 == EAGAIN:
      raise newException(IOError, "signal duplexer should not be non-blocking")
    else:
      raiseOSError(errorCode) 

proc wait*(s: var PollableSemaphore): uint = 
  s.rbuf = 0'u
  while s.duplexer.read(s.rbuf.addr, sizeof(uint)) < 0:
    let errorCode = osLastError()
    if errorCode.int32 == EINTR:
      discard
    elif errorCode.int32 == EWOULDBLOCK or errorCode.int32 == EAGAIN:
      raise newException(IOError, "signal duplexer should not be non-blocking")
    else:
      raiseOSError(osLastError()) 
  result = s.rbuf 
  assert result > 0

proc register*(poller: var Poller, s: PollableSemaphore): Natural =
  result = poller.registerHandle(s.duplexer)

