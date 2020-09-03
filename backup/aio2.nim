#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import std/selectors
import std/nativesockets

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
  FDEvent* {.pure.} = enum
    Read, Write, Error

  SelectFD* = distinct int
  SelectTimer* = distinct int
  SelectEvent* = selectors.SelectEvent

  SelectFDCb* = proc (disp: AioDispatcher, fd: SelectFD, events: set[FDEvent]) {.closure, gcsafe.}
  SelectTimerCb* = proc (disp: AioDispatcher, timer: SelectTimer) {.closure, gcsafe.}
  SelectEventCb* = proc (disp: AioDispatcher, event: SelectEvent) {.closure, gcsafe.}
  
  AioKind {.pure.} = enum
    SelectFD, SelectTimer, SelectEvent

  AioData* = object
    case kind: AioKind
    of AioKind.SelectFD:
      fdCb: SelectFDCb
    of AioKind.SelectTimer:
      timerCb: SelectTimerCb
    of AioKind.SelectEvent:
      eventCb: SelectEventCb
      eventPtr: SelectEvent
  
  AioDispatcher* = ref object of RootRef
    # timers*: HeapQueue[tuple[finishAt: MonoTime, fut: Future[void]]]
    # callbacks*: Deque[proc () {.gcsafe.}]
    selector: Selector[AioData]

## TODO: 参考 std/asyncdispatch 提供 windows IOCP API
## TODO：添加 timer， event，兼容 [poll, select]
## TODO：添加 pending 处理，参考 asyncdispatch
## 
## timers - pendings - io 

proc registerHandle*(disp: AioDispatcher, fd: SelectFD, cb: SelectFDCb) = 
  ## 为调度器注册一个描述符 ``fd`` 。当该描述符接收到感兴趣的事件时，运行回调函数 ``data`` 。这个函数仅仅
  ## 注册描述符，并不为描述符绑定感兴趣的事件。 TODO：“事件” 这个词需要推敲一下，看看网络上有没有合适的词语替代。
  disp.selector.registerHandle(fd.int, {}, AioData(kind: AioKind.SelectFD, fdCb: cb))

proc unregisterHandle*(disp: AioDispatcher, fd: SelectFD) = 
  ## 从调度器删除一个已经注册的描述符 ``fd`` 。
  disp.selector.unregister(fd.int)

proc advertiseHandle*(disp: AioDispatcher, fd: SelectFD, events: set[FDEvent]) = 
  ## 告诉调度器，描述符 ``fd`` 对事件 ``events`` 感兴趣。接下来，只通知 ``events`` 有关的事件。
  var evs: set[Event] = {}
  if FDEvent.Read in events: evs.incl(Event.Read)
  if FDEvent.Write in events: evs.incl(Event.Write)
  if FDEvent.Error in events: evs.incl(Event.Error)
  disp.selector.updateHandle(fd.int, evs)

proc registerTimer*(disp: AioDispatcher, timeout: int, oneshot: bool, cb: SelectTimerCb): SelectTimer {.discardable.} = 
  ## 为调度器注册一个描述符 ``fd`` 。当该描述符接收到感兴趣的事件时，运行回调函数 ``data`` 。这个函数仅仅
  ## 注册描述符，并不为描述符绑定感兴趣的事件。 TODO：“事件” 这个词需要推敲一下，看看网络上有没有合适的词语替代。
  result = disp.selector.registerTimer(timeout, oneshot, AioData(kind: AioKind.SelectTimer, timerCb: cb)).SelectTimer

proc unregisterTimer*(disp: AioDispatcher, timer: SelectTimer) = 
  ## 从调度器删除一个已经注册的描述符 ``fd`` 。
  disp.selector.unregister(timer.int)

proc registerEvent*(disp: AioDispatcher, event: SelectEvent, cb: SelectEventCb) = 
  ## 为调度器注册一个描述符 ``fd`` 。当该描述符接收到感兴趣的事件时，运行回调函数 ``data`` 。这个函数仅仅
  ## 注册描述符，并不为描述符绑定感兴趣的事件。 TODO：“事件” 这个词需要推敲一下，看看网络上有没有合适的词语替代。
  disp.selector.registerEvent(event, AioData(kind: AioKind.SelectEvent, eventCb: cb, eventPtr: event))

proc unregisterEvent*(disp: AioDispatcher, event: SelectEvent) = 
  ## 从调度器删除一个已经注册的描述符 ``fd`` 。
  disp.selector.unregister(event)

proc newAioDispatcher*(): AioDispatcher = 
  new(result)
  result.selector = newSelector[AioData]()

  proc cb(disp: AioDispatcher, fd: SelectFD, events: set[FDEvent]) =
    assert events == {FDEvent.Read}
    asyncdispatch.poll(0)
  result.registerHandle(asyncdispatch.getGlobalDispatcher().getIoHandler().getFd().SelectFD, cb)
  result.advertiseHandle(asyncdispatch.getGlobalDispatcher().getIoHandler().getFd().SelectFD, {FDEvent.Read})

proc poll*(disp: AioDispatcher, timeout = 500) =
  ## 
  var keys: array[64, ReadyKey]
  var count = disp.selector.selectInto(timeout, keys)
  for i in 0..<count:
    let fd = keys[i].fd
    let events = keys[i].events
    var data: ptr AioData = addr disp.selector.getData(fd)
    case data.kind
    of AioKind.SelectFD:
      var evs: set[FDEvent] = {}
      if Event.Read in events: evs.incl(FDEvent.Read)
      if Event.Write in events: evs.incl(FDEvent.Write)
      if Event.Error in events: evs.incl(FDEvent.Error)
      data.fdCb(disp, fd.SelectFD, evs)
    of AioKind.SelectTimer:
      data.timerCb(disp, fd.SelectTimer)
    of AioKind.SelectEvent:
      data.eventCb(disp, data.eventPtr)

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
  var disp = newAioDispatcher()

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

  proc cbServer(disp: AioDispatcher, fd: SelectFD, events: set[FDEvent]) = 
    if FDEvent.Read in events:
      let (client, address) = fd.SocketHandle.accept()
      if client == osInvalidSocket:
        let lastError = osLastError()
        raiseOSError(lastError)
      setBlocking(client, false)

      proc cbClient(disp: AioDispatcher, fd: SelectFD, events: set[FDEvent]) = 
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
        if FDEvent.Read in events:
          block read:
            if data.conn.parser.state != HttpParseState.Body:
              var succ = false
              if data.conn.buffer.len > 0:
                succ = data.conn.parser.parseHttpHeader(data.conn.buffer, data.conn.currentRequest.header)
              while not succ:
                let region = data.conn.buffer.next()
                let ret = recv(fd.SocketHandle, region[0], region[1], 0.cint)
                if ret == 0:
                  disp.unregisterHandle(fd)
                  fd.SocketHandle.close()
                  break read
                if ret == -1:
                  let lastError = osLastError()
                  if lastError.int32 in {EWOULDBLOCK, EAGAIN}:
                    break read
                  if isDisconnectionError({SocketFlag.SafeDisconn}, lastError):
                    disp.unregisterHandle(fd)
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
                  disp.unregisterHandle(fd)
                  fd.SocketHandle.close()
                  break read
                if ret == -1:
                  let lastError = osLastError()
                  if lastError.int32 in {EWOULDBLOCK, EAGAIN}:
                    break read
                  if isDisconnectionError({SocketFlag.SafeDisconn}, lastError):
                    disp.unregisterHandle(fd)
                    fd.SocketHandle.close()
                    break read
                  raiseOSError(lastError)
                discard data.conn.buffer.pack(ret)
              
            disp.advertiseHandle(fd, {FDEvent.Write})

        elif FDEvent.Write in events:
          block write:
            let s = "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nHello World"
            let ret = send(fd.SocketHandle, s.cstring, s.len, 0)
            if ret == -1:
              let lastError = osLastError()
              if lastError.int32 in {EWOULDBLOCK, EAGAIN}:
                break
              if isDisconnectionError({SocketFlag.SafeDisconn}, lastError):
                disp.unregisterHandle(fd)
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
            disp.advertiseHandle(fd, {FDEvent.Read})
        else:
          assert false
      
      ## 注册客户端 read - recv()
      disp.registerHandle(client.SelectFD, cbClient)
      disp.advertiseHandle(client.SelectFD, {FDEvent.Read})
    else:
      assert false, "Only Read events are expected for the server"

  ## 注册服务器 read - accept()
  disp.registerHandle(fd.SelectFD, cbServer)
  disp.advertiseHandle(fd.SelectFD, {FDEvent.Read})

  while true:
    disp.poll()


# var disp = newAioDispatcher()

# proc timeoutCb(disp: AioDispatcher, timer: SelectTimer) =
#   echo  "timeout"

# disp.registerTimer(10, false, timeoutCb)

# disp.poll()
# disp.poll()
# disp.poll()
# disp.poll()
# disp.poll()
# disp.poll()

var server = newAsyncHttpServer()

server.serve(Port(8080))
