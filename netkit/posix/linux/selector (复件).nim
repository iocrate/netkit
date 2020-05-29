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
  result.value = 0 #EPOLLET.uint32 # TODO: 考虑 EPOLLET 的利弊

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



# import nativesockets

# proc createSocket(): cint = 
#   let fd = createNativeSocket(Domain.AF_INET, SOCK_STREAM, IPPROTO_TCP)
#   if fd == osInvalidSocket:
#     raiseOSError(osLastError())
#   fd.setSockOptInt(SOL_SOCKET, SO_REUSEADDR, 1)
#   fd.setSockOptInt(SOL_SOCKET, SO_REUSEPORT, 1)
#   when defined(macosx):
#     fd.setSockOptInt(SOL_SOCKET, SO_NOSIGPIPE, 1)
#   fd.setBlocking(false)
#   return fd.cint

# proc bindAddr(fd: cint, port: Port, address = "", domain = AF_INET) {.raises: [OSError, ValueError].} =
#   ## Binds ``address``:``port`` to the socket.
#   ##
#   ## If ``address`` is "" then ``ADDR_ANY`` will be bound.
#   var aiList: ptr AddrInfo
#   if address == "":
#     var realaddr: string
#     case domain
#     of AF_INET6: realaddr = "::"
#     of AF_INET: realaddr = "0.0.0.0"
#     else:
#       raise newException(ValueError, "Unknown socket address family and no address specified to bindAddr")
#     aiList = getAddrInfo(realaddr, port, domain)
#   else:
#     aiList = getAddrInfo(address, port, domain)
#   if nativesockets.bindAddr(fd.SocketHandle, aiList.ai_addr, aiList.ai_addrlen.SockLen) < 0'i32:
#     aiList.freeAddrInfo()
#     raiseOSError(osLastError())
#   else:
#     aiList.freeAddrInfo()

# proc listen(fd: cint, backlog = SOMAXCONN) {.raises: [OSError].} =
#   ## Marks ``fd`` as accepting connections. ``Backlog`` specifies the maximum length of the
#   ## queue of pending connections.
#   ##
#   ## Raises an OSError error upon failure.
#   if nativesockets.listen(fd.SocketHandle, backlog) < 0'i32:
#     raiseOSError(osLastError())

# proc connect*(fd: cint, address: string, port = Port(0), domain = AF_INET) {.raises: [OSError].} =
#   var aiList = getAddrInfo(address, port, domain)
#   # try all possibilities:
#   var success = false
#   var lastError: OSErrorCode
#   var it = aiList
#   while it != nil:
#     if connect(fd.SocketHandle, it.ai_addr, it.ai_addrlen.SockLen) == 0'i32:
#       success = true
#       break
#     else: 
#       lastError = osLastError()
#     it = it.ai_next
#   freeAddrInfo(aiList)
#   if not success: 
#     raiseOSError(lastError)

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




import tables
import selectors
import nativesockets
import net
import asyncdispatch
import nativesockets
import os
import strutils
import deques
import netkit/http/status
import netkit/http/exception
import netkit/http/connection
import netkit/http/reader
import netkit/http/writer
import netkit/buffer
import netkit/http/parser
import netkit/http/header
import netkit/http/headerfield

when defined(posix):
  from posix import EBADF

type
  HandleKind = enum
    Server, Client, Dispatcher # TODO: Accepter, Reader, Writer, Timer, Pendinger

  Data = object
    kind: HandleKind
    ip: string
    conn: FastConnection

  AsyncHttpServer* = ref object ## Server object.
    socket: SocketHandle
    domain: Domain
    onRequest: RequestHandler
    closed: bool
    readTimeout: Natural

  FastConnection* = ref object ## HTTP connection object.
    buffer: MarkableCircularBuffer
    parser: HttpParser
    socket: SocketHandle
    address: string
    closed: bool
    readTimeout: Natural
    currentRequest: FastRequest

  FastRequest* = ref object of RootObj ## An abstraction of read operations related to HTTP.
    conn: FastConnection
    header*: HttpHeader
    # metadata: HttpMetadata
    onEnd: proc () {.gcsafe, closure.}
    contentLen: Natural
    chunked: bool
    readable: bool

  RequestHandler* = proc (req: ServerRequest, res: ServerResponse): Future[void] {.closure, gcsafe.}

proc bindAddr(fd: SocketHandle, port: Port, address = "", domain = AF_INET) {.tags: [ReadIOEffect].} =
  ## Binds ``address``:``port`` to the socket.
  ##
  ## If ``address`` is "" then ``ADDR_ANY`` will be bound.
  var realaddr = address
  if realaddr == "":
    case domain
    of AF_INET6: realaddr = "::"
    of AF_INET: realaddr = "0.0.0.0"
    else:
      raise newException(ValueError, "Unknown socket address family and no address specified to bindAddr")
  var aiList = getAddrInfo(realaddr, port, domain)
  if bindAddr(fd, aiList.ai_addr, aiList.ai_addrlen.SockLen) < 0'i32:
    aiList.freeAddrInfo()
    raiseOSError(osLastError())
  aiList.freeAddrInfo()

proc listen(fd: SocketHandle, backlog = SOMAXCONN) {.tags: [ReadIOEffect].} =
  ## Marks ``fd`` as accepting connections. ``Backlog`` specifies the maximum length of the
  ## queue of pending connections.
  ##
  ## Raises an OSError error upon failure.
  if nativesockets.listen(fd, backlog) < 0'i32:
    raiseOSError(osLastError())

proc newAsyncHttpServer*(): AsyncHttpServer = 
  ## Creates a new ``AsyncHttpServer`` 。
  new(result)
  result.closed = false

proc `onRequest=`*(server: AsyncHttpServer, handler: RequestHandler) = 
  ## Sets a hook proc for the server. Whenever a new request comes, this hook function is triggered.
  server.onRequest = handler

proc close*(server: AsyncHttpServer) = 
  ## Closes the server to release the underlying resources.
  server.socket.close()
  server.closed = true

proc handleNextRequest(server: AsyncHttpServer, conn: HttpConnection) {.async.} = 
  var req: ServerRequest
  var res: ServerResponse

  proc onReadEnd() = 
    assert not conn.closed
    if res.ended:
      req = nil
      res = nil
      asyncCheck server.handleNextRequest(conn)

  proc onWriteEnd() = 
    assert not conn.closed
    if req.ended:
      req = nil
      res = nil
      asyncCheck server.handleNextRequest(conn)

  req = newServerRequest(conn, onReadEnd)
  
  try:
    await conn.readHttpHeader(req.header.addr)
    req.normalizeSpecificFields()
  except HttpError as e:
    yield conn.write("HTTP/1.1 " & $e.code & "\r\nConnection: close\r\n\r\n")
    conn.close()
    return
  except ValueError:
    yield conn.write("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n")
    conn.close()
    return
  except ReadAbortedError as e:
    if e.timeout:
      yield conn.write("HTTP/1.1 408 Request Timeout\r\nConnection: close\r\n\r\n")
    conn.close()
    return
  except:
    conn.close()
    return
  
  res = newServerResponse(conn, onWriteEnd)
  await server.onRequest(req, res)

template handleAccept() =
  let (client, address) = fd.accept()
  if client == osInvalidSocket:
    let lastError = osLastError()
    raiseOSError(lastError)
  setBlocking(client, false)
  var clientIntent = initIntent()
  clientIntent.registerReadable();
  register(selector, client.cint, clientIntent)

  clients[client.cint] = Data(
    kind: Client, 
    ip: address,
    conn: FastConnection(
      buffer: initMarkableCircularBuffer(),
      parser: initHttpParser(),
      socket: client,
      address: address,
      closed: false,
      readTimeout: 0,
      currentRequest: FastRequest(
        header: HttpHeader(),
        # metadata: HttpMetadata
        contentLen: 0,
        chunked: false,
        readable: true
      )
    )
  )

proc serve*(
  server: AsyncHttpServer, 
  port: Port,
  address: string = "",
  domain = AF_INET,
  readTimeout = 0
) = 
  ## Starts the process of listening for incoming HTTP connections on the
  ## specified ``address`` and ``port``. ``readTimeout`` specifies the timeout
  ## about read operations and keepalive.
  var selector = newSelector()
  var clients = newTable[cint, Data]()

  let fd = createNativeSocket(Domain.AF_INET, SOCK_STREAM, IPPROTO_TCP)
  if fd == osInvalidSocket:
    raiseOSError(osLastError())
  fd.setSockOptInt(SOL_SOCKET, SO_REUSEADDR, 1)
  fd.setSockOptInt(SOL_SOCKET, SO_REUSEPORT, 1)
  when defined(macosx) and not defined(nimdoc):
    fd.setSockOptInt(SOL_SOCKET, SO_NOSIGPIPE, 1)
  fd.bindAddr(port, address, domain)
  fd.listen()
  fd.setBlocking(false)

  var serverIntent = initIntent()
  serverIntent.registerReadable()
  selector.register(fd.cint, serverIntent)
  
  var dispFD = asyncdispatch.getGlobalDispatcher().getIoHandler().getFd()
  var dispIntent = initIntent()
  dispIntent.registerReadable()
  selector.register(dispFD.cint, dispIntent)
  
  # Set up timer to get current date/time.
  # discard updateDate(0.AsyncFD)
  # asyncdispatch.addTimer(1000, false, updateDate)
  
  var selector2 = newSelector()
  var selector3 = newSelector()

  var s1Intent = initIntent()
  s1Intent.registerReadable()
  selector3.register(selector.epollFD, s1Intent) 

  var s2Intent = initIntent()
  s2Intent.registerReadable()
  selector3.register(selector2.epollFD, s2Intent) 

  var eventsSelectors = newSeq[Event](128)
  while true:
    let count = selector3.select(eventsSelectors, -1)
    for i in 0..<count:
      let eventSelectors = eventsSelectors[i].addr
      if eventSelectors[].token != selector.epollFD:
        echo "........................."
      else:

        var events = newSeq[Event](128)
        let count = selector.select(events, -1)
        for i in 0..<count:
          let event = events[i].addr
          
          # let fd = events[i].fd
          # var data: ptr Data = selector.getData(fd).addr
          # # Handle error events first.
          # if Event.Error in events[i].events:
          #   if isDisconnectionError({SocketFlag.SafeDisconn}, events[i].errorCode):
          #     selector.unregister(fd)
          #     fd.SocketHandle.close()
          #     continue
          #   raiseOSError(events[i].errorCode)

          if event[].isError():
            selector.unregister(event[].token)
            event[].token.SocketHandle.close()
            continue
            # if isDisconnectionError({SocketFlag.SafeDisconn}, events[i].errorCode):
            #   selector.unregister(fd)
            #   fd.SocketHandle.close()
            #   continue
            # raiseOSError(events[i].errorCode)

          if event[].token == fd.cint:
            if event[].isReadable():
              handleAccept()
            else:
              assert false, "Only Read events are expected for the server"
          elif event[].token == dispFD:
            asyncdispatch.poll(0)
          else:
            let fd = event[].token
            var data = clients[event[].token].addr
            if event[].isReadable():
              block read:
                if data.conn.parser.state != HttpParseState.Body:
                  var succ = false
                  if data.conn.buffer.len > 0:
                    succ = data.conn.parser.parseHttpHeader(data.conn.buffer, data.conn.currentRequest.header)
                  while not succ:
                    let region = data.conn.buffer.next()
                    let ret = recv(fd.SocketHandle, region[0], region[1], 0.cint)
                    if ret == 0:
                      selector.unregister(fd.cint)
                      fd.SocketHandle.close()
                      break read
                    if ret == -1:
                      let lastError = osLastError()
                      if lastError.int32 in {EWOULDBLOCK, EAGAIN}:
                        break read
                      if isDisconnectionError({SocketFlag.SafeDisconn}, lastError):
                        selector.unregister(fd.cint)
                        fd.SocketHandle.close()
                        break read
                      raiseOSError(lastError)
                    discard data.conn.buffer.pack(ret)
                    succ = data.conn.parser.parseHttpHeader(data.conn.buffer, data.conn.currentRequest.header)
                  if data.conn.currentRequest.header.fields.contains("Content-Length"):
                    if data.conn.currentRequest.header.fields["Content-Length"].len > 1:
                      raise newHttpError(Http400, "Bad content length")
                    var a = data.conn.currentRequest.header.fields["Content-Length"][0]
                    data.conn.currentRequest.contentLen = a.parseInt()
                    if data.conn.currentRequest.contentLen < 0:
                      raise newHttpError(Http400, "Bad content length")
                  if data.conn.currentRequest.contentLen == 0:
                    data.conn.currentRequest.readable = false

                assert data.conn.parser.state == HttpParseState.Body  
                while data.conn.currentRequest.contentLen > 0:
                  if data.conn.buffer.len > 0:
                    data.conn.currentRequest.contentLen = data.conn.currentRequest.contentLen - data.conn.buffer.del(data.conn.currentRequest.contentLen)
                  if data.conn.currentRequest.contentLen > 0:
                    let region = data.conn.buffer.next()
                    let ret = recv(fd.SocketHandle, region[0], region[1], 0.cint)
                    if ret == 0:
                      selector.unregister(fd.cint)
                      fd.SocketHandle.close()
                      break read
                    if ret == -1:
                      let lastError = osLastError()
                      if lastError.int32 in {EWOULDBLOCK, EAGAIN}:
                        break read
                      if isDisconnectionError({SocketFlag.SafeDisconn}, lastError):
                        selector.unregister(fd.cint)
                        fd.SocketHandle.close()
                        break read
                      raiseOSError(lastError)
                    discard data.conn.buffer.pack(ret)

                var intent = initIntent()
                intent.registerWritable() 
                selector.update(fd.cint, intent)

            if event[].isWritable():
              block write:
                let s = "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nHello World"
                let ret = send(fd.SocketHandle, s.cstring, s.len, 0)
                if ret == -1:
                  let lastError = osLastError()
                  if lastError.int32 in {EWOULDBLOCK, EAGAIN}:
                    break
                  if isDisconnectionError({SocketFlag.SafeDisconn}, lastError):
                    selector.unregister(fd.cint)
                    fd.SocketHandle.close()
                    break write
                  raiseOSError(lastError)
                
                data.conn.parser.clear()
                data.conn.currentRequest = FastRequest(
                  header: HttpHeader(),
                  # metadata: HttpMetadata
                  contentLen: 0,
                  chunked: false,
                  readable: true
                )

                var intent = initIntent()
                intent.registerWritable() 
                selector.update(fd.cint, intent)
            

        # Ensure callbacks list doesn't grow forever in asyncdispatch.
        # See https://github.com/nim-lang/Nim/issues/7532.
        # Not processing callbacks can also lead to exceptions being silently
        # lost!
        if unlikely(asyncdispatch.getGlobalDispatcher().callbacks.len() > 0):
          asyncdispatch.poll(0)


      # AsyncFD(fd).register()
      # server.socket = fd
      # server.domain = domain
      
      # while not server.closed:
      #   var peer: tuple[address: string, client: AsyncFD]
      #   try:
      #     peer = await server.socket.acceptAddr()
      #   except:
      #     if server.closed:
      #       when defined(posix):
      #         if osLastError() == OSErrorCode(EBADF):
      #           break
      #       else:
      #         break
      #     raise getCurrentException()
      #   SocketHandle(peer.client).setBlocking(false)
      #   asyncCheck server.handleNextRequest(newHttpConnection(peer.client, peer.address, readTimeout))

# var server = newAsyncHttpServer()

# server.serve(Port(8080))
