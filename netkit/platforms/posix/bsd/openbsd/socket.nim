import posix

const
  SOCK_NONBLOCK* = 0x4000
  SOCK_CLOEXEC*  = 0x8000

proc accept4*(a1: SocketHandle, a2: ptr SockAddr, a3: ptr SockLen, a4: cint): SocketHandle {.
  importc: "accept4", 
  header: "<sys/socket.h>", 
  sideEffect
.}
