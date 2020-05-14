#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import std/selectors
import std/nativesockets, os, net, asyncdispatch, deques

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
  Data = object
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

type
  AsyncFD* = distinct int
  AsyncData* = proc (fd: AsyncFD, events: set[Event]): bool {.closure.}

  AsyncDispatcher* = ref object of RootRef
    # timers*: HeapQueue[tuple[finishAt: MonoTime, fut: Future[void]]]
    # callbacks*: Deque[proc () {.gcsafe.}]
    selector: Selector[AsyncData]

## TODO: 参考 std/asyncdispatch 提供 windows IOCP API

proc register*(disp: AsyncDispatcher, fd: AsyncFD, data: AsyncData) = 
  ## 为调度器注册一个描述符 ``fd`` 。当该描述符接收到感兴趣的事件时，运行回调函数 ``data`` 。这个函数仅仅
  ## 注册描述符，并不为描述符绑定感兴趣的事件。 TODO：“事件” 这个词需要推敲一下，看看网络上有没有合适的词语替代。
  disp.selector.registerHandle(fd.SocketHandle, {}, data)

proc unregister*(disp: AsyncDispatcher, fd: AsyncFD) = 
  ## 从调度器删除一个已经注册的描述符 ``fd`` 。
  disp.selector.unregister(fd.SocketHandle)

proc advertise*(disp: AsyncDispatcher, fd: AsyncFD, events: set[Event]) = 
  ## 告诉调度器，描述符 ``fd`` 对事件 ``events`` 感兴趣。接下来，只通知 ``events`` 有关的事件。
  disp.selector.updateHandle(fd.SocketHandle, events)

proc newAsyncDispatcher*(): AsyncDispatcher = 
  new(result)
  result.selector = newSelector[AsyncData]()

  proc cb(fd: AsyncFD, events: set[Event]): bool =
    assert events == {Event.Read}
    asyncdispatch.poll(0)
  result.register(asyncdispatch.getGlobalDispatcher().getIoHandler().getFd().AsyncFD, cb)
  result.advertise(asyncdispatch.getGlobalDispatcher().getIoHandler().getFd().AsyncFD, {Event.Read})

proc poll*(disp: AsyncDispatcher) =
  ## 
  var keys: array[64, ReadyKey]
  var count = disp.selector.selectInto(-1, keys)
  for i in 0..<count:
    let fd = keys[i].fd.AsyncFD
    let events = keys[i].events
    let cb: AsyncData = disp.selector.getData(fd.SocketHandle)
    discard cb(fd, events)

  if unlikely(asyncdispatch.getGlobalDispatcher().callbacks.len() > 0):
    asyncdispatch.poll(0)

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
  var disp = newAsyncDispatcher()

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

  proc cbServer(fd: AsyncFD, events: set[Event]): bool = 
    if Event.Read in events:
      let (client, address) = fd.SocketHandle.accept()
      if client == osInvalidSocket:
        let lastError = osLastError()
        raiseOSError(lastError)
      setBlocking(client, false)

      proc cbClient(fd: AsyncFD, events: set[Event]): bool = 
        discard
        var data = Data(
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
        if Event.Read in events:
          block read:
            if data.conn.parser.state != HttpParseState.Body:
              var succ = false
              if data.conn.buffer.len > 0:
                succ = data.conn.parser.parseHttpHeader(data.conn.buffer, data.conn.currentRequest.header)
              while not succ:
                let region = data.conn.buffer.next()
                let ret = recv(fd.SocketHandle, region[0], region[1], 0.cint)
                if ret == 0:
                  disp.unregister(fd)
                  fd.SocketHandle.close()
                  break read
                if ret == -1:
                  let lastError = osLastError()
                  if lastError.int32 in {EWOULDBLOCK, EAGAIN}:
                    break read
                  if isDisconnectionError({SocketFlag.SafeDisconn}, lastError):
                    disp.unregister(fd)
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
                  disp.unregister(fd)
                  fd.SocketHandle.close()
                  break read
                if ret == -1:
                  let lastError = osLastError()
                  if lastError.int32 in {EWOULDBLOCK, EAGAIN}:
                    break read
                  if isDisconnectionError({SocketFlag.SafeDisconn}, lastError):
                    disp.unregister(fd)
                    fd.SocketHandle.close()
                    break read
                  raiseOSError(lastError)
                discard data.conn.buffer.pack(ret)
              
            disp.advertise(fd, {Event.Write})

        elif Event.Write in events:
          block write:
            let s = "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nHello World"
            let ret = send(fd.SocketHandle, s.cstring, s.len, 0)
            if ret == -1:
              let lastError = osLastError()
              if lastError.int32 in {EWOULDBLOCK, EAGAIN}:
                break
              if isDisconnectionError({SocketFlag.SafeDisconn}, lastError):
                disp.unregister(fd)
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
            disp.advertise(fd, {Event.Read})
        else:
          assert false
      
      ## 注册客户端 read - recv()
      disp.register(client.AsyncFD, cbClient)
      disp.advertise(client.AsyncFD, {Event.Read})
    else:
      assert false, "Only Read events are expected for the server"

  ## 注册服务器 read - accept()
  disp.register(fd.AsyncFD, cbServer)
  disp.advertise(fd.AsyncFD, {Event.Read})

  while true:
    disp.poll()


# import net

# var socket1 = newSocket(buffered=false)
# var socket2 = newSocket(buffered=false)

# socket1.bindAddr(Port(8080))
# socket1.listen()
# socket1.getFd().setSockOptInt(SOL_SOCKET, SO_REUSEADDR, 1)
# socket1.getFd().setSockOptInt(SOL_SOCKET, SO_REUSEPORT, 1)
# socket1.getFd().setBlocking(false)

# socket2.getFd().setBlocking(false)
# # socket2.bindAddr(Port(8081))
# # socket2.listen()

# var disp = newAsyncDispatcher()

# proc cb1(fd: AsyncFD, events: set[Event]): bool =
#   var client: Socket
#   socket1.accept(client)
#   echo "cb1:", events, " ", repr client.getPeerAddr()
#   # sleep(10)
#   # disp.advertise(socket1.getFd().AsyncFD, {Event.Read})

# proc cb2(fd: AsyncFD, events: set[Event]): bool =
#   echo "cb2:", repr events

# disp.register(socket1.getFd().AsyncFD, cb1)
# disp.register(socket2.getFd().AsyncFD, cb2)

# ## Tip：有意思，我发现 socket 没有进行 bind listen，于是使用 epoll 监听 socket 时立马触发 EPOLLRDHUP {Error} 事件
# ## 并且，由于 std/ioselectors 实现 updateHandle 时采用的水平触发，导致该事件在每次 selectInto 时都会触发。
# ## 如果 std/ioselectors.updateHandle 修改为 var epv = EpollEvent(events: EPOLLRDHUP or EPOLLET) 则只触发一次
# ## 考虑：标准库的 asynchttpserver 有没有可能因为此导致效率问题？
# disp.advertise(socket1.getFd().AsyncFD, {Event.Read})
# disp.advertise(socket2.getFd().AsyncFD, {Event.Write})

# import posix
# try:
#   socket2.connect("127.0.0.1", Port(8080))
# except:
#   assert osLastError().cint == EINPROGRESS ## TODO: 发现 nonblocking connect 非常复杂，特别是 windows 版本，有必要封装一个函数

# disp.poll()
# # disp.poll()
# # disp.poll()

var server = newAsyncHttpServer()

server.serve(Port(8080))
