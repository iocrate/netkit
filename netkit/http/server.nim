#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

# 这个文件很混乱，待整理！！！

import asyncdispatch
import nativesockets
import os
import netkit/http/connection

type
  AsyncHttpServer* = ref object
    socket: AsyncFD

proc bindAddr(fd: SocketHandle, port = 0.Port, address = "") {.tags: [ReadIOEffect].} =
  ## Binds ``address``:``port`` to the socket.
  ##
  ## If ``address`` is "" then ADDR_ANY will be bound.
  var realaddr = address
  # TODO: 添加 Domain
  # if realaddr == "":
  #   case socket.domain
  #   of AF_INET6: realaddr = "::"
  #   of AF_INET: realaddr = "0.0.0.0"
  #   else:
  #     raise newException(ValueError,
  #       "Unknown socket address family and no address specified to bindAddr")

  var aiList = getAddrInfo(realaddr, port, Domain.AF_INET)
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
   
proc serve*(
  server: AsyncHttpServer, 
  port: Port = 8001.Port,
  handler: RequestHandler,
  address = "127.0.0.1"
): Future[void] {.async.} = 
  # TODO: Domain 支持 IPv6
  let fd = createNativeSocket(Domain.AF_INET, SOCK_STREAM, IPPROTO_TCP)
  if fd == osInvalidSocket:
    raiseOSError(osLastError())
  fd.setSockOptInt(SOL_SOCKET, SO_REUSEADDR, 1)
  fd.setSockOptInt(SOL_SOCKET, SO_REUSEPORT, 1)
  when defined(macosx) and not defined(nimdoc):
    fd.setSockOptInt(SOL_SOCKET, SO_NOSIGPIPE, 1)
  fd.bindAddr(port, address)
  fd.listen()
  fd.setBlocking(false)
  fd.AsyncFD.register()
  server.socket = fd.AsyncFD
  
  while true:
    let (clientAddress, clientSocket) = await server.socket.acceptAddr()
    clientSocket.SocketHandle.setBlocking(false)
    asyncCheck newHttpConnection(clientSocket, clientAddress, handler).processNextRequest()
    