
import std/os
import std/posix
import netkit/collections/mpsc

proc eventfd*(initval: cuint, flags: cint): cint {.
  importc: "eventfd", 
  header: "<sys/eventfd.h>"
.}

type
  TaskCounter* = object of SigCounter
    fd: cint

proc signalTaskCounter*(c: ptr SigCounter) = 
  var buf = 1'u64
  while cast[ptr TaskCounter](c).fd.write(buf.addr, sizeof(buf)) < 0:
    let lastError = osLastError().int32
    if lastError == EINTR:
      discard
    elif lastError == EWOULDBLOCK or lastError == EAGAIN:
      raise newException(IOError, "signal fd should not be non-blocking")
    else:
      raiseOSError(osLastError()) 

proc waitTaskCounter*(c: ptr SigCounter): Natural = 
  var buf = 0'u64
  while cast[ptr TaskCounter](c).fd.read(buf.addr, sizeof(buf)) < 0:
    let lastError = osLastError().int32
    if lastError == EINTR:
      discard
    elif lastError == EWOULDBLOCK or lastError == EAGAIN:
      raise newException(IOError, "signal fd should not be non-blocking")
    else:
      raiseOSError(osLastError()) 
  result = buf # TODO: u64 -> int 考虑溢出；

proc initTaskCounter*(fd: cint): TaskCounter =
  result.fd = fd
  result.signalImpl = signalTaskCounter
  result.waitImpl = waitTaskCounter