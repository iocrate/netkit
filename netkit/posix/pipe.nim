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

var PIPE_BUF {.
  importc: "PIPE_BUF", 
  header: "<sys/eventfd.h>"
.}: cint
echo PIPE_BUF
proc pipe*(a: array[0..1, cint]): cint {.importc, header: "<unistd.h>".}

var fdPair: array[0..1, cint]
discard pipe(fdPair)




var buffer1: uint64 = 6
echo "write: ", fdPair[1].write(buffer1.addr, 8)

var buffer2: uint64 = 3
echo "write: ", fdPair[1].write(buffer2.addr, 8)

var buffer: uint64 = 0
echo "read: ", fdPair[0].read(buffer.addr, sizeof(uint64)), " value: ", buffer
echo "read: ", fdPair[0].read(buffer.addr, sizeof(uint64)), " value: ", buffer
echo "read: ", fdPair[0].read(buffer.addr, sizeof(uint64)), " value: ", buffer