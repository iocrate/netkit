from std/posix import EINTR, EINPROGRESS, close
import std/os
import netkit/posix/linux/epoll

type
  Selector* = object # TODO: 考虑多线程，考虑多 epollfd
    epollFD: cint

  Event* = object # 兼容 
    value: EpollEvent 

  Interest* = object # 兼容 
    value: uint32

  UserData* {.union.} = object
    fd*: cint
    data*: pointer
    u32*: uint32
    u64*: uint64

proc initInterest*(): Interest = 
  result.value = EPOLLET.uint32 # TODO: 考虑 EPOLLET 的利弊

proc registerReadable*(interest: var Interest) {.inline.} = 
  interest.value = interest.value or EPOLLIN or EPOLLRDHUP

proc registerWritable*(interest: var Interest) {.inline.} = 
  interest.value = interest.value or EPOLLOUT

proc registerAio*(interest: var Interest) {.inline.} = 
  discard

proc registerLio*(interest: var Interest) {.inline.} = 
  discard

proc unregisterReadable*(interest: var Interest) {.inline.} = 
  # TODO: 考虑常量标记为　uint32 类型
  interest.value = interest.value and not EPOLLIN.uint32 and not EPOLLRDHUP.uint32

proc unregisterWritable*(interest: var Interest) {.inline.} = 
  # TODO: 考虑常量标记为　uint32 类型
  interest.value = interest.value and not EPOLLOUT.uint32 

proc unregisterAio*(interest: var Interest) {.inline.} = 
  discard

proc unregisterLio*(interest: var Interest) {.inline.} = 
  discard

proc unregister*(interest: var Interest) {.inline.} = 
  interest.value = EPOLLET.uint32

proc isReadable*(interest: Interest): bool {.inline.} =
  (interest.value and EPOLLIN) != 0 

proc isWritable*(interest: Interest): bool {.inline.} =
  (interest.value and EPOLLOUT) != 0 

proc isAio*(interest: Interest): bool {.inline.} =
  false

proc isLio*(interest: Interest): bool {.inline.} =
  false

proc data*(event: Event): UserData {.inline.} =
  cast[UserData](event.value.data)

proc isReadable*(event: Event): bool {.inline.} =
  (event.value.events and EPOLLIN) != 0 or (event.value.events and EPOLLPRI) != 0

proc isWritable*(event: Event): bool {.inline.} =
  (event.value.events and EPOLLOUT) != 0 

proc isReadClosed*(event: Event): bool {.inline.} =
  # - 对端没有监听端口（服务器）或者通过该端口与本端通信（重启）
  # - 对端已经发送过 FIN 信号表示断开连接 - 自 2.6.17 版本支持
  (event.value.events and EPOLLHUP) != 0 or ((event.value.events and EPOLLIN) != 0 and (event.value.events and EPOLLRDHUP) != 0)

proc isWriteClosed*(event: Event): bool {.inline.} =
  # - 对端没有监听端口（服务器）或者通过该端口与本端通信（重启）
  # - 出现错误
  (event.value.events and EPOLLHUP) != 0 or ((event.value.events and EPOLLOUT) != 0 and (event.value.events and EPOLLERR) != 0)

proc isAio*(event: Event): bool {.inline.} = 
  ## Not supported in the kernel, only in libc.  
  false

proc isLio*(event: Event): bool {.inline.} =
  ## Not supported.
  false

proc isError*(event: Event): bool {.inline.} =
  (event.value.events and EPOLLERR) != 0 

proc initSelector*(): Selector {.raises: [OSError].} = 
  let fd = epoll_create1(EPOLL_CLOEXEC)
  if fd < 0:
    raiseOSError(osLastError())
  result.epollFD = fd

proc close*(s: var Selector) {.raises: [OSError].} = 
  if s.epollFD.close() < 0:
    raiseOSError(osLastError())

proc select*(s: var Selector, events: var openArray[Event], timeout: cint): Natural {.raises: [OSError].} =
  # TODO: timeout: cint 设计一个超时数据结构以提供更好的兼容 ? how about Option<Duration> ?
  result = epoll_wait(s.epollFD, events[0].value.addr, cint(events.len), timeout)
  if result < 0:
    result = 0
    let err = osLastError()
    if cint(err) != EINTR: # TODO: 需不需要循环直到创建成功呢？
      raiseOSError(err)

proc register*(s: var Selector, fd: cint, data: UserData, interest: Interest) {.raises: [OSError].} =
  var event = EpollEvent(events: interest.value, data: cast[EpollData](data))
  if epoll_ctl(s.epollFD, EPOLL_CTL_ADD, fd, event.addr) != 0:
    raiseOSError(osLastError())

proc unregister*(s: var Selector, fd: cint) {.raises: [OSError].} =
  # `Epoll Manpage <http://man7.org/linux/man-pages/man2/epoll_ctl.2.html>`_
  #
  # ..
  #
  #   Applications that need to be portable to kernels before 2.6.9 should specify a non-null pointer in event. 
  # 
  var event = EpollEvent()
  if epoll_ctl(s.epollFD, EPOLL_CTL_DEL, fd, event.addr) != 0:
    raiseOSError(osLastError())

proc update*(s: var Selector, fd: cint, data: UserData, interest: Interest) {.raises: [OSError].} =
  var event = EpollEvent(events: interest.value, data: cast[EpollData](data))
  if epoll_ctl(s.epollFD, EPOLL_CTL_MOD, fd, event.addr) != 0:
    raiseOSError(osLastError())
