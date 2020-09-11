
import std/os
import std/posix
import netkit/objects
import netkit/sync/semaphores
import netkit/aio/posix/pollers
import netkit/platforms/posix/linux/eventfd

type
  PollableCounter* = object
    duplexer: cint
    rbuf: uint
    wbuf: uint
    destructorState: DestructorState

  PollableSemaphore* = Semaphore[PollableCounter]

proc `=destroy`*(x: var PollableCounter)  {.raises: [OSError].} =
  if x.destructorState == DestructorState.READY:
    if x.duplexer.close() < 0:
      raiseOSError(osLastError())
    x.destructorState = DestructorState.COMPLETED

proc `=sink`*(dest: var PollableCounter, source: PollableCounter) {.raises: [OSError].} =
  if dest.duplexer != source.duplexer:
    `=destroy`(dest)
    dest.duplexer = source.duplexer
    dest.destructorState = source.destructorState

proc `=`*(dest: var PollableCounter, source: PollableCounter) {.raises: [OSError].} =
  if dest.duplexer != source.duplexer:
    `=destroy`(dest)
    if source.destructorState == DestructorState.READY:
      dest.duplexer = dup(source.duplexer)
      if dest.duplexer < 0:
        raiseOSError(osLastError())
    else:
      dest.duplexer = source.duplexer
    dest.destructorState = source.destructorState

proc initPollableCounter*(x: var PollableCounter) {.raises: [OSError].} =
  x.duplexer = eventfd(0, 0)
  if x.duplexer < 0:
    raiseOSError(osLastError())
  x.destructorState = DestructorState.READY

proc signal(s: var PollableSemaphore) = 
  s.value.wbuf = 1'u
  while s.value.duplexer.write(s.value.wbuf.addr, sizeof(uint)) < 0:
    let errorCode = osLastError()
    if errorCode.int32 == EINTR:
      discard
    elif errorCode.int32 == EWOULDBLOCK or errorCode.int32 == EAGAIN:
      raise newException(IOError, "signal duplexer should not be non-blocking")
    else:
      raiseOSError(errorCode) 

proc wait(s: var PollableSemaphore): uint = 
  s.value.rbuf = 0'u
  while s.value.duplexer.read(s.value.rbuf.addr, sizeof(uint)) < 0:
    let errorCode = osLastError()
    if errorCode.int32 == EINTR:
      discard
    elif errorCode.int32 == EWOULDBLOCK or errorCode.int32 == EAGAIN:
      raise newException(IOError, "signal duplexer should not be non-blocking")
    else:
      raiseOSError(osLastError()) 
  result = s.value.rbuf 
  assert result > 0

proc initPollableSemaphore*(s: var PollableSemaphore) {.raises: [OSError].} =
  s.value.initPollableCounter()
  s.signalImpl = signal
  s.waitImpl = wait

proc register*(poller: var Poller, s: PollableSemaphore): Natural {.raises: [OSError].} =
  result = poller.registerHandle(s.value.duplexer)

