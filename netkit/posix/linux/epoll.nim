const
  EPOLLIN* = 0x00000001
  EPOLLPRI* = 0x00000002
  EPOLLOUT* = 0x00000004
  EPOLLERR* = 0x00000008
  EPOLLHUP* = 0x00000010
  EPOLLRDNORM* = 0x00000040
  EPOLLRDBAND* = 0x00000080
  EPOLLWRNORM* = 0x00000100
  EPOLLWRBAND* = 0x00000200
  EPOLLMSG* = 0x00000400
  EPOLLRDHUP* = 0x00002000
  EPOLLEXCLUSIVE* = 0x10000000
  EPOLLWAKEUP* = 0x20000000
  EPOLLONESHOT* = 0x40000000
  EPOLLET* = 0x80000000

const
  EPOLL_CTL_ADD* = 1  
  EPOLL_CTL_DEL* = 2  
  EPOLL_CTL_MOD* = 3  

const
  EPOLL_CLOEXEC* = 0x80000

type
  EpollData* {.importc: "union epoll_data", header: "<sys/epoll.h>", union, final.} = object 
    data* {.importc: "ptr".}: pointer
    fd* {.importc: "fd".}: cint
    u32* {.importc: "u32".}: uint32
    u64* {.importc: "u64".}: uint64

  EpollEvent* {.importc: "struct epoll_event", header: "<sys/epoll.h>", pure, final.} = object
    events*: uint32 
    data*: EpollData 

  SignalSet* {.importc: "sigset_t", header: "<sys/signal.h>", pure, final.} = object

proc epoll_create*(size: cint): cint {.
  importc: "epoll_create",
  header: "<sys/epoll.h>"
.}

proc epoll_create1*(flags: cint): cint {.
  importc: "epoll_create1",
  header: "<sys/epoll.h>"
.}

proc epoll_ctl*(epfd: cint, op: cint, fd: cint, event: ptr EpollEvent): cint {.
  importc: "epoll_ctl",
  header: "<sys/epoll.h>"
.}

proc epoll_wait*(epfd: cint, events: ptr EpollEvent, maxevents: cint, timeout: cint): cint {.
  importc: "epoll_wait",
  header: "<sys/epoll.h>"
.}

proc epoll_pwait*(epfd: cint, events: ptr EpollEvent, maxevents: cint, timeout: cint, sigmask: ptr SignalSet): cint {.
  importc: "epoll_pwait",
  header: "<sys/epoll.h>"
.}
