
import std/os
import std/posix
import netkit/collections/mpsc

proc eventfd*(initval: cuint, flags: cint): cint {.
  importc: "eventfd", 
  header: "<sys/eventfd.h>"
.}

type
  TaskCounter* = object of SigCounter
    fd*: cint

proc signalTaskCounter*(c: ptr SigCounter) = 
  var buf = 1'u64
  if cast[ptr TaskCounter](c).fd.write(buf.addr, sizeof(buf)) < 0:
    raiseOSError(osLastError()) # TODO: 考虑 errorno == Enter, EAGAIN, EWOULDBLOCK

proc waitTaskCounter*(c: ptr SigCounter): Natural = 
  var buf = 0'u64
  if cast[ptr TaskCounter](c).fd.read(buf.addr, sizeof(buf)) < 0:
    raiseOSError(osLastError())
  result = buf # TODO: u64 -> int 考虑溢出；考虑 errorno == Enter, EAGAIN, EWOULDBLOCK
