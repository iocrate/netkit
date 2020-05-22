import posix

const
  SOCK_NONBLOCK* = 0x800
  SOCK_CLOEXEC* = 0x80000

proc accept4*(a1: SocketHandle, a2: ptr SockAddr, a3: ptr SockLen, a4: cint): SocketHandle {.
  importc: "accept4", 
  header: "<sys/socket.h>", 
  sideEffect
.}
