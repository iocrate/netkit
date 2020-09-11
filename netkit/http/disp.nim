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
  let (client, address) = fd.SocketHandle.accept()
  if client == osInvalidSocket:
    let lastError = osLastError()
    raiseOSError(lastError)
  setBlocking(client, false)
  selector.registerHandle(client, {Event.Read}, Data(
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
  ))

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
  var selector = newSelector[Data]()

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

  selector.registerHandle(fd, {Event.Read}, Data(kind: Server))

  selector.registerHandle(asyncdispatch.getGlobalDispatcher().getIoHandler().getFd(), {Event.Read},
                          Data(kind: Dispatcher))

  # Set up timer to get current date/time.
  # discard updateDate(0.AsyncFD)
  # asyncdispatch.addTimer(1000, false, updateDate)

  var events: array[64, ReadyKey]
  while true:
    let count = selector.selectInto(-1, events)
    for i in 0..<count:
      let fd = events[i].fd
      var data: ptr Data = selector.getData(fd).addr
      # Handle error events first.
      if Event.Error in events[i].events:
        if isDisconnectionError({SocketFlag.SafeDisconn}, events[i].errorCode):
          selector.unregister(fd)
          fd.SocketHandle.close()
          continue
        raiseOSError(events[i].errorCode)

      case data.kind
      of Server:
        if Event.Read in events[i].events:
          handleAccept()
        else:
          assert false, "Only Read events are expected for the server"
      of Client:
        if Event.Read in events[i].events:
          block read:
            if data.conn.parser.state != HttpParseState.Body:
              var succ = false
              if data.conn.buffer.len > 0:
                succ = data.conn.parser.parseHttpHeader(data.conn.buffer, data.conn.currentRequest.header)
              while not succ:
                let region = data.conn.buffer.next()
                let ret = recv(fd.SocketHandle, region[0], region[1], 0.cint)
                if ret == 0:
                  selector.unregister(fd)
                  fd.SocketHandle.close()
                  break read
                if ret == -1:
                  let lastError = osLastError()
                  if lastError.int32 in {EWOULDBLOCK, EAGAIN}:
                    break read
                  if isDisconnectionError({SocketFlag.SafeDisconn}, lastError):
                    selector.unregister(fd)
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
                  selector.unregister(fd)
                  fd.SocketHandle.close()
                  break read
                if ret == -1:
                  let lastError = osLastError()
                  if lastError.int32 in {EWOULDBLOCK, EAGAIN}:
                    break read
                  if isDisconnectionError({SocketFlag.SafeDisconn}, lastError):
                    selector.unregister(fd)
                    fd.SocketHandle.close()
                    break read
                  raiseOSError(lastError)
                discard data.conn.buffer.pack(ret)
             
            selector.updateHandle(fd.SocketHandle, {Event.Write})

        elif Event.Write in events[i].events:
          block write:
            let s = "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nHello World"
            let ret = send(fd.SocketHandle, s.cstring, s.len, 0)
            if ret == -1:
              let lastError = osLastError()
              if lastError.int32 in {EWOULDBLOCK, EAGAIN}:
                break
              if isDisconnectionError({SocketFlag.SafeDisconn}, lastError):
                selector.unregister(fd)
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
            selector.updateHandle(fd.SocketHandle, {Event.Read})
        else:
          assert false
      of Dispatcher:
        assert events[i].events == {Event.Read}
        asyncdispatch.poll(0)

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

var
  thr: array[0..4, Thread[void]]

proc threadFunc() {.thread.} =
  var server = newAsyncHttpServer()
  server.serve(Port(8080))

for i in 0..3:
  createThread(thr[i], threadFunc)
joinThreads(thr)
