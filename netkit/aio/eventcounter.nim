
import std/os
import std/posix
import netkit/sigcounter

type
  EventCounter* = SigCounter[cint]

proc eventfd*(initval: cuint, flags: cint): cint {.
  importc: "eventfd", 
  header: "<sys/eventfd.h>"
.}

proc signalEventCounter*(c: var SigCounterBase) = 
  var buf = 1'u64
  while EventCounter(c).value.write(buf.addr, sizeof(buf)) < 0:
    let errorCode = osLastError()
    if errorCode.int32 == EINTR:
      discard
    elif errorCode.int32 == EWOULDBLOCK or errorCode.int32 == EAGAIN:
      raise newException(IOError, "signal fd should not be non-blocking")
    else:
      raiseOSError(errorCode) 

proc waitEventCounter*(c: var SigCounterBase): uint64 = 
  var buf = 0'u64
  while EventCounter(c).value.read(buf.addr, sizeof(buf)) < 0:
    let errorCode = osLastError()
    if errorCode.int32 == EINTR:
      discard
    elif errorCode.int32 == EWOULDBLOCK or errorCode.int32 == EAGAIN:
      raise newException(IOError, "signal fd should not be non-blocking")
    else:
      raiseOSError(osLastError()) 
  result = buf 

proc initEventCounter*(fd: cint): EventCounter =
  result.value = fd
  result.signalImpl = signalEventCounter
  result.waitImpl = waitEventCounter