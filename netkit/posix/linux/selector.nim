from std/posix import EINTR, EINPROGRESS, close, write, read
import std/os
import netkit/posix/linux/epoll
import netkit/posix/linux/socket

type
  Selector* = object # TODO: 考虑多线程，考虑多 epollfd
    epollFD: cint

  Event* = object # 兼容 
    value: EpollEvent 

  Intent* = object # 兼容 
    value: uint32

proc initIntent*(): Intent = 
  result.value = EPOLLET.uint32 # TODO: 考虑 EPOLLET 的利弊

proc registerReadable*(intent: var Intent) {.inline.} = 
  intent.value = intent.value or EPOLLIN or EPOLLRDHUP

proc unregisterReadable*(intent: var Intent) {.inline.} = 
  # TODO: 考虑常量标记为　uint32 类型
  intent.value = intent.value and not EPOLLIN.uint32 and not EPOLLRDHUP.uint32

proc registerWritable*(intent: var Intent) {.inline.} = 
  intent.value = intent.value or EPOLLOUT

proc unregisterWritable*(intent: var Intent) {.inline.} = 
  # TODO: 考虑常量标记为　uint32 类型
  intent.value = intent.value and not EPOLLOUT.uint32 

proc registerAio*(intent: var Intent) {.inline.} = 
  discard

proc unregisterAio*(intent: var Intent) {.inline.} = 
  discard

proc registerLio*(intent: var Intent) {.inline.} = 
  discard

proc unregisterLio*(intent: var Intent) {.inline.} = 
  discard

proc unregister*(intent: var Intent) {.inline.} = 
  intent.value = EPOLLET.uint32

proc token*(event: Event): cint {.inline.} =
  event.value.data.fd

proc isReadable*(event: Event): bool {.inline.} =
  (event.value.events and EPOLLIN) != 0 or (event.value.events and EPOLLPRI) != 0

proc isWritable*(event: Event): bool {.inline.} =
  (event.value.events and EPOLLOUT) != 0 

proc isError*(event: Event): bool {.inline.} =
  (event.value.events and EPOLLERR) != 0 

proc isReadClosed*(event: Event): bool {.inline.} =
  # - 对端没有监听端口（服务器）或者通过该端口与本端通信（重启）
  # - 对端已经发送过 FIN 信号表示断开连接 - 自 2.6.17 版本支持
  (event.value.events and EPOLLHUP) != 0 or ((event.value.events and EPOLLIN) != 0 and (event.value.events and EPOLLRDHUP) != 0)

proc isWriteClosed*(event: Event): bool {.inline.} =
  # - 对端没有监听端口（服务器）或者通过该端口与本端通信（重启）
  # - 出现错误
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



import nativesockets

proc createSocket(): cint = 
  let fd = createNativeSocket(Domain.AF_INET, SOCK_STREAM, IPPROTO_TCP)
  if fd == osInvalidSocket:
    raiseOSError(osLastError())
  fd.setSockOptInt(SOL_SOCKET, SO_REUSEADDR, 1)
  fd.setSockOptInt(SOL_SOCKET, SO_REUSEPORT, 1)
  when defined(macosx):
    fd.setSockOptInt(SOL_SOCKET, SO_NOSIGPIPE, 1)
  fd.setBlocking(false)
  return fd.cint

proc bindAddr(fd: cint, port: Port, address = "", domain = AF_INET) {.raises: [OSError, ValueError].} =
  ## Binds ``address``:``port`` to the socket.
  ##
  ## If ``address`` is "" then ``ADDR_ANY`` will be bound.
  var aiList: ptr AddrInfo
  if address == "":
    var realaddr: string
    case domain
    of AF_INET6: realaddr = "::"
    of AF_INET: realaddr = "0.0.0.0"
    else:
      raise newException(ValueError, "Unknown socket address family and no address specified to bindAddr")
    aiList = getAddrInfo(realaddr, port, domain)
  else:
    aiList = getAddrInfo(address, port, domain)
  if nativesockets.bindAddr(fd.SocketHandle, aiList.ai_addr, aiList.ai_addrlen.SockLen) < 0'i32:
    aiList.freeAddrInfo()
    raiseOSError(osLastError())
  else:
    aiList.freeAddrInfo()

proc listen(fd: cint, backlog = SOMAXCONN) {.raises: [OSError].} =
  ## Marks ``fd`` as accepting connections. ``Backlog`` specifies the maximum length of the
  ## queue of pending connections.
  ##
  ## Raises an OSError error upon failure.
  if nativesockets.listen(fd.SocketHandle, backlog) < 0'i32:
    raiseOSError(osLastError())

proc connect*(fd: cint, address: string, port = Port(0), domain = AF_INET) {.raises: [OSError].} =
  var aiList = getAddrInfo(address, port, domain)
  # try all possibilities:
  var success = false
  var lastError: OSErrorCode
  var it = aiList
  while it != nil:
    if connect(fd.SocketHandle, it.ai_addr, it.ai_addrlen.SockLen) == 0'i32:
      success = true
      break
    else: 
      lastError = osLastError()
    it = it.ai_next
  freeAddrInfo(aiList)
  if not success: 
    raiseOSError(lastError)

var a: uint8 = 0x1
var b: uint8 = 0x2
var c: uint8 = 0x4
var d: uint8 = 0x8

var v = a or b or c
echo v

echo (v and a) != 0
echo (v and b) != 0
echo (v and c) != 0

v = v and not a and not b
echo v
echo (v and a) != 0
echo (v and b) != 0
echo (v and c) != 0


# when isMainModule:
#   proc threadWriteFunc(clientSocket: cint) {.thread.} =
#     var data = "" 
#     for i in 1..1024*1024*2:
#       data.add("bar")

#     clientSocket.SocketHandle.setBlocking(true)
#     echo ">>> <Client> Client write blocking ... {fd=", repr clientSocket, "} ", "{total=", data.len, "}" 
#     let ret = clientSocket.write(data.cstring, data.len)
#     if ret < 0:
#       raiseOSError(osLastError())
#     echo ">>> <Client> Client write finished, {fd=", repr clientSocket, "} ", "{sent=", ret, "} {total=", data.len, "}" 
      
#   var serverSocket = createSocket()
#   serverSocket.bindAddr(Port(8080))
#   serverSocket.listen()
#   echo ">>> [Server] Server listening ... {fd=", serverSocket, "}"

#   var selector = newSelector()

#   block:
#     var serverIntent = initIntent()
#     serverIntent.registerReadable()
#     selector.register(serverSocket, serverIntent)

#   var clientSockets = newSeq[cint](3)
#   block:
#     for i in 0..0:
#       clientSockets[i] = createSocket()
#       var aiList = getAddrInfo("127.0.0.1", Port(8080), Domain.AF_INET)
#       let ret = connect(clientSockets[i] .SocketHandle, aiList.ai_addr, aiList.ai_addrlen.SockLen)
#       freeAddrInfo(aiList)
#       if ret < 0:
#         let lastError = osLastError()
#         if lastError.int32 in {EINTR, EWOULDBLOCK, EAGAIN}:
#           discard
#         elif osLastError().cint == EINPROGRESS:
#           discard
#         else:
#           raiseOSError(lastError)
#           # if flags.isDisconnectionError(lastError):
#           #   retFuture.complete("")
#           # else:
#           #   retFuture.fail(newException(OSError, osErrorMsg(lastError)))
#       echo ">>> <Client> Client connecting ... {fd=", clientSockets[i], "}"

#   var events = newSeq[Event](128)
#   while true:
#     let count = selector.select(events, -1)
#     echo "--- Got IO ---------"
#     assert count > 0
#     for i in 0..<count:
#       let event = events[i].addr
#       # TODO: token 存储更有意义的数值，比如某些 enum 或者标识符，能识别不同类型不同目的的描述符
#       if event[].token == serverSocket:
#         assert event[].isReadable

#         var sockAddress: Sockaddr_storage
#         var addrLen = sizeof(sockAddress).SockLen
#         let clientSocket = accept4(
#           event[].token.SocketHandle, 
#           cast[ptr SockAddr](addr(sockAddress)), 
#           addr(addrLen), 
#           SOCK_NONBLOCK or SOCK_CLOEXEC
#         )
#         if clientSocket.cint < 0:
#           let lastError = osLastError()
#           if lastError.int32 in {EINTR, EWOULDBLOCK, EAGAIN}:
#             discard
#           else:
#             raiseOSError(lastError)
#         assert clientSocket.cint > 0
#         echo ">>> [Server] [Readable] Server accepted, {fd=", repr clientSocket, "}"

#         block:
#           # TODO: 考虑 EPOLLET 利弊
#           # EPOLLET 模式，此处必须更新事件，否则不再触发该事件
#           var serverIntent = initIntent()
#           serverIntent.registerReadable()
#           selector.update(serverSocket.cint, serverIntent)

#         block:
#           # TODO: 考虑 Intent 如何支持删除可读事件保持其他事件、删除可写事件保持其他事件
#           var clientIntent = initIntent()
#           clientIntent.registerReadable()
#           clientIntent.registerWritable()
#           selector.register(clientSocket.cint, clientIntent)

#         # block:
#         #   var data = "" 
#         #   for i in 1..1024*1024*2:
#         #     data.add("foo")
          
#         #   let ret = clientSocket.cint.write(data.cstring, data.len)
#         #   if ret < 0:
#         #     let lastError = osLastError()
#         #     if lastError.int32 in {EINTR, EWOULDBLOCK, EAGAIN}:
#         #       discard
#         #     else:
#         #       raiseOSError(lastError)
#         #   # TODO: 我发现写可以立刻执行，而不需要等待；应该是先拷贝到内核缓冲区，当满了之后才会有延迟
#         #   #       这样的话需要考虑一些策略
#         #   echo ">>> [Server] Client write nonblocking ... {fd=", repr clientSocket, "} ", "{sent=", ret, "} {total=", data.len, "}"
        
#         block:
#           # 模拟客户端写入大块数据
#           var thr: Thread[cint]
#           createThread(thr, threadWriteFunc, clientSockets[0])
#       else:
#         if event[].isReadable:
#           echo ">>> [Server] [Readable] Client reading ... {fd=", (event[].token), "}"
#           var buff = newString(1024) 
#           let ret = event[].token.cint.read(buff.cstring, 1024)
#           if ret < 0:
#             let lastError = osLastError()
#             if lastError.int32 in {EINTR, EWOULDBLOCK, EAGAIN}:
#               discard
#             else:
#               raiseOSError(lastError)
#           echo ">>> [Server] [Readable] Client readed, {fd=", (event[].token), "}", "{readed=", ret, "}"
          
#           block:
#             # TODO: 考虑 EPOLLET 利弊
#             # EPOLLET 模式，此处必须更新事件，否则不再触发该事件
#             var clientIntent = initIntent()
#             clientIntent.registerReadable()
#             clientIntent.registerWritable()
#             selector.update(event[].token.cint, clientIntent)
          
#         if event[].isWritable:
#           echo ">>> [Server] [Writable] Client writing ... {fd=", (event[].token), "}"





