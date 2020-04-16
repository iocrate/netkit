#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import asyncdispatch
import nativesockets
import os
import netkit/http/connection
import netkit/http/reader
import netkit/http/writer

type
  AsyncHttpServer* = ref object
    socket: AsyncFD
    domain: Domain
    onRequest: RequestHandler

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
  new(result)

proc `onRequest=`*(server: AsyncHttpServer, handler: RequestHandler) = 
  server.onRequest = handler
   
proc serve*(
  server: AsyncHttpServer, 
  port: Port,
  address: string = "",
  domain = AF_INET
) {.async.} = 
  ## Starts the process of listening for incoming HTTP connections on the
  ## specified ``address`` and ``port``.
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
  fd.AsyncFD.register()
  server.socket = fd.AsyncFD
  server.domain = domain
  
  while true:
    let (clientAddress, clientSocket) = await server.socket.acceptAddr()
    clientSocket.SocketHandle.setBlocking(false)
    let conn = newHttpConnection(clientSocket, clientAddress)

    proc handleNextRequest() {.async.} = 
      var req: ServerRequest
      var res: ServerResponse

      proc onReadEnd() = 
        if res.ended and not conn.closed:
          asyncCheck handleNextRequest()

      proc onWriteEnd() = 
        if req.ended and not conn.closed:
          asyncCheck handleNextRequest()

      req = newServerRequest(conn, onReadEnd)
      res = newServerResponse(conn, onWriteEnd)
      
      try:
        # TODO: 考虑内存泄露
        await conn.readHttpHeader(req.header.addr)
      except:
        # TODO: 考虑错误处理
        conn.close()
    