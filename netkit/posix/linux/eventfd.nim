import std/posix
import std/os

const
  EFD_CLOEXEC* = 0x80000
  EFD_NONBLOCK* = 0x800
  EFD_SEMAPHORE* = 0x1

type
  EventFD = object
    fd: cint
    buffer: uint64

proc eventfd*(initval: cuint, flags: cint): cint {.
  importc: "eventfd", 
  header: "<sys/eventfd.h>"
.}

proc initEventFD*(fd: cint): EventFD = 
  result.fd = fd
  result.buffer = 0

proc read*(efd: var EventFD): int = 
  read(efd.fd, efd.buffer.addr, sizeof(uint64))


var fd1 = eventfd(0, 0)
var fd2 = eventfd(0, 0)

var buffer1: uint64 = 6
var buffer1a: uint64 = 0
echo "write 1: ", fd1.write(buffer1.addr, sizeof(uint64)
), " ", buffer1
echo "write 1: ", fd1.write(buffer1.addr, sizeof(uint64)
)
echo "write 1: ", fd1.write(buffer1.addr, sizeof(uint64)
)
echo "write 1: ", fd1.write(buffer1.addr, sizeof(uint64)
)
echo "write 1: ", fd1.write(buffer1.addr, sizeof(uint64)
)
echo "read 1: ", fd1.read(buffer1a.addr, sizeof(uint64)
), " ", buffer1a, " ", buffer1*5