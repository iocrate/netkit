
const
  EFD_CLOEXEC* = 0x80000
  EFD_NONBLOCK* = 0x800
  EFD_SEMAPHORE* = 0x1

proc eventfd*(initval: cuint, flags: cint): cint {.
  importc: "eventfd", 
  header: "<sys/eventfd.h>"
.}

