#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module implements an HTTP server.

import asyncdispatch
import nativesockets
import os
import netkit/http/exception
import netkit/http/spec
import netkit/http/status
import netkit/http/connection
import netkit/http/reader
import netkit/http/writer

when defined(posix):
  from posix import EBADF

type
  AsyncHttpServer* = ref object ## Server object.
    socket: AsyncFD
    domain: Domain
    onRequest: RequestHandler
    closed: bool
    readTimeout: Natural

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
  server.socket.closeSocket()
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
  except HttpError as ex:
    yield conn.write("HTTP/1.1 " & $ex.code & CRLF)
    conn.close()
    return
  except:
    yield conn.write("HTTP/1.1 " & $Http400 & CRLF)
    conn.close()
    return
  
  res = newServerResponse(conn, onWriteEnd)
  await server.onRequest(req, res)
   
proc serve*(
  server: AsyncHttpServer, 
  port: Port,
  address: string = "",
  domain = AF_INET,
  readTimeout = 0
) {.async.} = 
  ## Starts the process of listening for incoming HTTP connections on the
  ## specified ``address`` and ``port``. ``readTimeout`` specifies the timeout
  ## about read operations and keepalive.
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
  AsyncFD(fd).register()
  server.socket = AsyncFD(fd)
  server.domain = domain
  
  while not server.closed:
    var peer: tuple[address: string, client: AsyncFD]
    try:
      peer = await server.socket.acceptAddr()
    except:
      if server.closed:
        when defined(posix):
          if osLastError() == OSErrorCode(EBADF):
            break
        else:
          break
      raise getCurrentException()
    SocketHandle(peer.client).setBlocking(false)
    asyncCheck server.handleNextRequest(newHttpConnection(peer.client, peer.address, readTimeout))
