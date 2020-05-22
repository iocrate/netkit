import std/posix
import std/os
import netkit/posix/linux/epoll

type
  Selector* = object # TODO: 考虑多线程，考虑多 epollfd
    epollFD: cint

  Event* = object # 兼容 
    value: EpollEvent 

  Intent* = object # 兼容 
    value: uint32

proc initIntent*(): Intent = 
  discard

proc registerReadable*(intent: var Intent) {.inline.} = 
  intent.value = intent.value or EPOLLIN or EPOLLRDHUP

proc registerWritable*(intent: var Intent) {.inline.} = 
  intent.value = intent.value or EPOLLOUT

proc registerAio*(intent: var Intent) {.inline.} = 
  discard

proc registerLio*(intent: var Intent) {.inline.} = 
  discard

proc unregister*(intent: var Intent) {.inline.} = 
  intent.value = 0

proc token*(event: Event): cint {.inline.} =
  event.value.data.fd

proc isReadable*(event: Event): bool {.inline.} =
  (event.value.events and EPOLLIN) != 0 or (event.value.events and EPOLLPRI) != 0

proc isWritable*(event: Event): bool {.inline.} =
  (event.value.events and EPOLLOUT) != 0 

proc isError*(event: Event): bool {.inline.} =
  (event.value.events and EPOLLERR) != 0 

proc isReadClosed*(event: Event): bool {.inline.} =
  (event.value.events and EPOLLHUP) != 0 or ((event.value.events and EPOLLIN) != 0 and (event.value.events and EPOLLRDHUP) != 0)

proc isWriteClosed*(event: Event): bool {.inline.} =
  (event.value.events and EPOLLHUP) != 0 or ((event.value.events and EPOLLOUT) != 0 and (event.value.events and EPOLLERR) != 0)

proc isPriority*(event: Event): bool {.inline.} =
  (event.value.events and EPOLLPRI) != 0 

proc isAio*(event: Event): bool {.inline.} = 
  ## Not supported in the kernel, only in libc.  
  false

proc isLio*(event: Event): bool {.inline.} =
  ## Not supported.
  false

proc newSelector*(): Selector {.raises: [OSError].} = 
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

proc register*(s: var Selector, fd: cint, intent: Intent) {.raises: [OSError].} =
  var event = EpollEvent(events: intent.value, data: EpollData(fd: fd))
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

proc update*(s: var Selector, fd: cint, intent: Intent) {.raises: [OSError].} =
  var event = EpollEvent(events: intent.value, data: EpollData(fd: fd))
  if epoll_ctl(s.epollFD, EPOLL_CTL_MOD, fd, event.addr) != 0:
    raiseOSError(osLastError())

