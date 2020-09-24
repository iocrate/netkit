
#[
  连接池：

  
  var group = sliceExecutorGroup()
  var mysqlPool = newMysqlPool(group) {
    let cpus = getCpus()
    mysqlPool.connections = newSeq[MySqlConnection](cpus)
    for executorId in group.items():
      exec(executorId) proc =
        for i in 0..<10:
          var connection = newMysqlConnection() {
            connection.socket = ...
            connection.registry = initIoRegistry(connection.socket)
          }
          mysqlPool.executors[executorId].add(connection)
  }

  group.spawn proc =
    let conn = mysqlPool.getConnection() {
      return mysqlPool.executors[getCurrentExecutorId()].getConnection()
    }
    conn.query()
    conn.release() {
      mysqlPool.executors[getCurrentExecutorId()].release(conn)
    }
]#


import std/os
import std/posix
import std/nativesockets
import netkit/misc
import netkit/aio/futures
import netkit/net/ip
import netkit/aio/posix/runtime

type
  TcpFlag* {.pure.} = enum
    SafeDisconn
    
  TcpListener* = ref object
    handle: IoHandle
    registry: IoRegistry
    flags: set[TcpFlag]

  TcpConnector* = ref object
    handle: IoHandle
    registry: IoRegistry
    flags: set[TcpFlag]

proc isDisconnectionError(flags: set[TcpFlag], errorCode: OSErrorCode): bool =
  ## Determines whether ``errorCode`` is a disconnection error. Only does this
  ## if flags contains ``SafeDisconn``.
  when defined(windows):
    TcpFlag.SafeDisconn in flags and
      (errorCode.int32 == WSAECONNRESET or
       errorCode.int32 == WSAECONNABORTED or
       errorCode.int32 == WSAENETRESET or
       errorCode.int32 == WSAEDISCON or
       errorCode.int32 == WSAESHUTDOWN or
       errorCode.int32 == ERROR_NETNAME_DELETED)
  else:
    TcpFlag.SafeDisconn in flags and
      (errorCode.int32 == ECONNRESET or
       errorCode.int32 == EPIPE or
       errorCode.int32 == ENETRESET)

proc toDomain(family: IpAddressFamily): Domain {.inline.} =
  result = case family
  of IpAddressFamily.IPv6: Domain.AF_INET6
  of IpAddressFamily.IPv4: Domain.AF_INET

proc createTcpHandle(domain: Domain, sockType: SockType, protocol: Protocol): IoHandle =
  let socket = nativesockets.createNativeSocket(domain, sockType, protocol)
  if socket == osInvalidSocket:
    raiseOSError(osLastError())
  socket.setBlocking(false)
  socket.setSockOptInt(SOL_SOCKET, SO_REUSEADDR, 1)
  # socket.setSockOptInt(SOL_SOCKET, SO_REUSEPORT, 1)
  when defined(macosx) and not defined(nimdoc):
    socket.setSockOptInt(SOL_SOCKET, SO_NOSIGPIPE, 1)
  result = IoHandle(socket)

proc bindAddr(listener: IoHandle, domain: Domain, port: Port, address: string) =
  var addrInfo: ptr AddrInfo
  if address == "":
    var realaddr: string
    case domain
    of Domain.AF_INET6: realaddr = "::"
    of Domain.AF_INET: realaddr = "0.0.0.0"
    else:
      raise newException(ValueError, "Unknown socket address family and no address specified")
    addrInfo = getAddrInfo(realaddr, port, domain, SockType.SOCK_STREAM, Protocol.IPPROTO_TCP)
  else:
    addrInfo = getAddrInfo(address, port, domain, SockType.SOCK_STREAM, Protocol.IPPROTO_TCP)
  if nativesockets.bindAddr(SocketHandle(listener), addrInfo.ai_addr, addrInfo.ai_addrlen.SockLen) < 0:
    addrInfo.freeAddrInfo()
    raiseOSError(osLastError())
  else:
    addrInfo.freeAddrInfo()

proc newTcpListener*(
  port = Port(0), 
  address = "", 
  family = IpAddressFamily.IPv4, 
  backlog = SOMAXCONN, 
  flags = {TcpFlag.SafeDisconn}
): TcpListener =
  # TODO: consider defining Domain, Port, and SOMAXCONN separately?
  new(result)
  let domain = family.toDomain()
  let socket = createTcpHandle(domain, SockType.SOCK_STREAM, Protocol.IPPROTO_TCP)
  socket.bindAddr(domain, port, address)
  if nativesockets.listen(SocketHandle(socket), backlog) < 0: 
    raiseOSError(osLastError())
  result.handle = socket
  result.registry = initIoRegistry(socket)
  result.flags = flags

proc close*(listener: TcpListener) = 
  ## Closes this listener to release the underlying resources.
  #
  # TODO: consider the following scenarios:
  #
  # - Socket: {tcp, udp} posix.close(cint); windows.closeSocket(Handle) 
  # - Pipe: ? 
  # - FIFO: ? 
  #
  # How to deal with them gracefully?
  listener.registry.`=destroy`()
  SocketHandle(listener.handle).close()

proc getLocalAddr*(listener: TcpListener, domain: Domain): (string, Port) {.inline.} = 
  ## Returns a tuple of the local address and port of this listener.
  SocketHandle(listener.handle).getLocalAddr(domain)

const IP_TTL = when defined(linux): 2
               elif defined(macosx) or defined(freebsd) or defined(netbsd) or defined(openbsd) or defined(dragonfly): 4
               else: {.error: "Platform not supported!".}

proc getTTL*(listener: TcpListener): Natural {.inline.} = 
  # Gets the value of the ``IP_TTL`` option for this listener.
  SocketHandle(listener.handle).getSockOptInt(posix.IPPROTO_IP, IP_TTL)

proc setTTL*(listener: TcpListener, ttl: Natural) {.inline.} = 
  ## Sets the value for the ``IP_TTL`` option on this listener.
  ## This value sets the time-to-live field that is used in every packet sent from this listener.
  SocketHandle(listener.handle).setSockOptInt(posix.IPPROTO_IP, IP_TTL, ttl)

proc accept*(listener: TcpListener): Future[IoHandle] =
  var retFuture = newFuture[IoHandle]()
  result = retFuture
  listener.registry.registerReadable proc (): bool =
    result = true
    var sockAddress: Sockaddr_storage
    var addrLen = SockLen(sizeof(sockAddress))
    var client =
      when declared(accept4):
        accept4(SocketHandle(listener.handle), cast[ptr SockAddr](sockAddress.addr), addrLen.addr, 
                SOCK_CLOEXEC)
      else:
        accept(SocketHandle(listener.handle), cast[ptr SockAddr](sockAddress.addr), addrLen.addr)
    if client == osInvalidSocket:
      let lastError = osLastError()
      assert lastError.int32 != EWOULDBLOCK and lastError.int32 != EAGAIN
      if lastError.int32 == EINTR:
        return false
      else:
        if listener.flags.isDisconnectionError(lastError):
          return false
        else:
          retFuture.fail(newException(OSError, osErrorMsg(lastError)))
    else:
      client.setBlocking(false)
      retFuture.complete(IoHandle(client))
      # try:
      #   let address = getAddrString(cast[ptr SockAddr](sockAddress.addr))
      #   client.setBlocking(false)
      #   retFuture.complete(TcpConnector(client))
      # except:
      #   # getAddrString may raise
      #   client.close()
      #   retFuture.fail(getCurrentException())

proc newTcpConnector*(
  port = Port(0), 
  address = "",
  family = IpAddressFamily.IPv4, 
  flags = {TcpFlag.SafeDisconn}
): TcpConnector = 
  new(result)
  let domain = family.toDomain()
  let socket = createTcpHandle(domain, SockType.SOCK_STREAM, Protocol.IPPROTO_TCP)
  socket.bindAddr(domain, port, address)
  result.handle = socket
  result.registry = initIoRegistry(socket)
  result.flags = flags
  
proc newTcpConnector*(
  handle: IoHandle,
  flags = {TcpFlag.SafeDisconn}
): TcpConnector = 
  new(result)
  result.handle = handle
  result.registry = initIoRegistry(handle)
  result.flags = flags
  
proc close*(connector: TcpConnector) {.inline.} = 
  ## Closes this connector to release the underlying resources.
  connector.registry.`=destroy`()
  SocketHandle(connector.handle).close()

proc getLocalAddr*(connector: TcpConnector, domain: Domain): (string, Port) {.inline.} = 
  ## Returns a tuple of address and port of the local half of this TCP connection.
  SocketHandle(connector.handle).getLocalAddr(domain)

proc getPeerAddr*(connector: TcpConnector, domain: Domain): (string, Port) {.inline.} = 
  ## Returns a connector and port of the remote peer of this TCP connection.
  SocketHandle(connector.handle).getPeerAddr(domain)

proc getTTL*(connector: TcpConnector): Natural {.inline.} = 
  # Gets the value of the ``IP_TTL`` option for this connector.
  SocketHandle(connector.handle).getSockOptInt(posix.IPPROTO_IP, IP_TTL)

proc setTTL*(connector: TcpConnector, ttl: Natural) {.inline.} = 
  ## Sets the value for the ``IP_TTL`` option on this connector.
  ## This value sets the time-to-live field that is used in every packet sent from this connector.
  SocketHandle(connector.handle).setSockOptInt(posix.IPPROTO_IP, IP_TTL, ttl)

proc isNoDelay*(connector: TcpConnector): bool {.inline.} = 
  ## Checkes whether this connector enables the Nagle's algorithm. Nagle's algorithm delays data before 
  ## it is sent via the network. It attempts to optimize throughput at the expense of latency.
  SocketHandle(connector.handle).getSockOptInt(posix.IPPROTO_TCP, TCP_NODELAY) > 0

proc setNoDelay*(connector: TcpConnector, nodelay: bool) {.inline.} = 
  ## Sets the value for the ``TCP_NODELAY`` option on this connector to enable/disable the Nagle's algorithm.
  SocketHandle(connector.handle).setSockOptInt(posix.IPPROTO_TCP, TCP_NODELAY, if nodelay: 1 else: 0)

proc isKeepAlive*(connector: TcpConnector): bool {.inline.} = 
  ## Checkes whether this connector enables keepalive. 
  SocketHandle(connector.handle).getSockOptInt(posix.SOL_SOCKET, SO_KEEPALIVE) > 0

proc setKeepAlive*(connector: TcpConnector, keepalive: bool) {.inline.} = 
  ## Sets the value for the ``SO_KEEPALIVE`` option on this connector.
  SocketHandle(connector.handle).setSockOptInt(posix.SOL_SOCKET, SO_KEEPALIVE, if keepalive: 1 else: 0)

# proc connect*(
#   port = Port(0), 
#   address = "",
#   domain = Domain.AF_INET
# ): TcpConnector = 
#   var addrInfo: ptr AddrInfo
#   if address == "":
#     var realaddr: string
#     case domain
#     of Domain.AF_INET6: realaddr = "::"
#     of Domain.AF_INET: realaddr = "0.0.0.0"
#     else:
#       raise newException(ValueError, "Unknown socket address family and no address specified")
#     addrInfo = getAddrInfo(realaddr, port, domain, SockType.SOCK_STREAM, Protocol.IPPROTO_TCP)
#   else:
#     addrInfo = getAddrInfo(address, port, domain, SockType.SOCK_STREAM, Protocol.IPPROTO_TCP)
#   let socket = createTcpHandle(domain, SockType.SOCK_STREAM, Protocol.IPPROTO_TCP)
#   if nativesockets.bindAddr(SocketHandle(socket), addrInfo.ai_addr, addrInfo.ai_addrlen.SockLen) < 0:
#     addrInfo.freeAddrInfo()
#     raiseOSError(osLastError())
#   let ret = connect(SocketHandle(socket), addrInfo.ai_addr, addrInfo.ai_addrlen.SockLen)
#   result = TcpConnector(socket)
  
# proc connect*(connector: TcpConnector, buf: pointer, size: Natural): Future[void] =
#   var retFuture = newFuture[void]()
#   result = retFuture
#   let addrInfo = getAddrInfo(address, port, domain, SockType.SOCK_STREAM, Protocol.IPPROTO_TCP)
#   let ret = connect(SocketHandle(connector.handle),
#                     addrInfo.ai_addr,
#                     addrInfo.ai_addrlen.SockLen)
#   addrInfo.freeAddrInfo()
#   if ret == 0:
#     retFuture.complete()
#   else:
#     let lastError = osLastError()
#     if lastError.int32 == EINTR or lastError.int32 == EINPROGRESS:
#       connector.registry.registerReadable proc (): bool =
#         result = true
#         let ret = SocketHandle(connector.handle).getSockOptInt(SOL_SOCKET, SO_ERROR)
#         if ret == 0:
#           retFuture.complete()
#         elif ret == EINTR:
#           result = false
#         else:
#           retFuture.fail(newException(OSError, osErrorMsg(OSErrorCode(ret))))
#     else:
#       retFuture.fail(newException(OSError, osErrorMsg(lastError)))

proc send*(connector: TcpConnector, buf: pointer, size: Natural): Future[void] =
  var retFuture = newFuture[void]()
  result = retFuture
  var written = 0
  connector.registry.registerReadable proc (): bool =
    result = true
    let netSize = size - written
    let res = recv(SocketHandle(connector.handle), buf.offset(written), netSize, MSG_NOSIGNAL)
    if res < 0:
      let lastError = osLastError()
      if lastError.int32 == EINTR or lastError.int32 == EWOULDBLOCK or lastError.int32 == EAGAIN:
        result = false 
      else:
        if connector.flags.isDisconnectionError(lastError):
          retFuture.complete()
        else:
          retFuture.fail(newException(OSError, osErrorMsg(lastError)))
    else:
      written.inc(res)
      if res != netSize:
        result = false 
      else:
        retFuture.complete()

proc send*(connector: TcpConnector, buffer: string): Future[void] =
  var retFuture = newFuture[void]()
  result = retFuture
  var written = 0
  connector.registry.registerReadable proc (): bool =
    result = true
    let netSize = buffer.len - written
    let res = recv(SocketHandle(connector.handle), buffer[written].unsafeAddr, netSize, MSG_NOSIGNAL)
    if res < 0:
      let lastError = osLastError()
      if lastError.int32 == EINTR or lastError.int32 == EWOULDBLOCK or lastError.int32 == EAGAIN:
        result = false 
      else:
        if connector.flags.isDisconnectionError(lastError):
          retFuture.complete()
        else:
          retFuture.fail(newException(OSError, osErrorMsg(lastError)))
    else:
      written.inc(res)
      if res != netSize:
        result = false 
      else:
        retFuture.complete()

proc recv*(connector: TcpConnector, buf: pointer, size: Natural): Future[Natural] =
  var retFuture = newFuture[Natural]()
  result = retFuture
  connector.registry.registerReadable proc (): bool =
    result = true
    let res = recv(SocketHandle(connector.handle), buf, size, 0)
    if res < 0:
      let lastError = osLastError()
      if lastError.int32 == EINTR or lastError.int32 == EWOULDBLOCK or lastError.int32 == EAGAIN:
        result = false 
      else:
        if connector.flags.isDisconnectionError(lastError):
          retFuture.complete(0)
        else:
          retFuture.fail(newException(OSError, osErrorMsg(lastError)))
    else:
      retFuture.complete(res)

proc recv*(connector: TcpConnector, size: Natural): Future[string] =
  var retFuture = newFuture[string]()
  result = retFuture
  var buf = newString(size)
  connector.registry.registerReadable proc (): bool =
    result = true
    let res = recv(SocketHandle(connector.handle), buf.cstring, size, 0)
    if res < 0:
      let lastError = osLastError()
      if lastError.int32 == EINTR or lastError.int32 == EWOULDBLOCK or lastError.int32 == EAGAIN:
        result = false 
      else:
        if connector.flags.isDisconnectionError(lastError):
          retFuture.complete("")
        else:
          retFuture.fail(newException(OSError, osErrorMsg(lastError)))
    elif res == 0:
      retFuture.complete("")
    else:
      buf.setLen(res)
      retFuture.complete(buf)

proc peek*(connector: TcpConnector, buf: pointer, size: Natural): Future[Natural] =
  var retFuture = newFuture[Natural]()
  result = retFuture
  connector.registry.registerReadable proc (): bool =
    result = true
    let res = recv(SocketHandle(connector.handle), buf, size, MSG_PEEK)
    if res < 0:
      let lastError = osLastError()
      if lastError.int32 == EINTR or lastError.int32 == EWOULDBLOCK or lastError.int32 == EAGAIN:
        result = false 
      else:
        if connector.flags.isDisconnectionError(lastError):
          retFuture.complete(0)
        else:
          retFuture.fail(newException(OSError, osErrorMsg(lastError)))
    else:
      retFuture.complete(res)

proc peek*(connector: TcpConnector, size: Natural): Future[string] =
  var retFuture = newFuture[string]()
  result = retFuture
  var buf = newString(size)
  connector.registry.registerReadable proc (): bool =
    result = true
    let res = recv(SocketHandle(connector.handle), buf.cstring, size, MSG_PEEK)
    if res < 0:
      let lastError = osLastError()
      if lastError.int32 == EINTR or lastError.int32 == EWOULDBLOCK or lastError.int32 == EAGAIN:
        result = false 
      else:
        if connector.flags.isDisconnectionError(lastError):
          retFuture.complete("")
        else:
          retFuture.fail(newException(OSError, osErrorMsg(lastError)))
    elif res == 0:
      retFuture.complete("")
    else:
      buf.setLen(res)
      retFuture.complete(buf)

when isMainmodule:
  import netkit/aio/posix/runtime

  proc test() =
    var listener = newTcpListener(port = Port(10003))

    var acceptFuture = listener.accept()
    acceptFuture.callback = proc () =
      var client = acceptFuture.read()
      
      var connector = newTcpConnector(client)
      var recvFuture = connector.recv(128)
      recvFuture.callback = proc () = 
        var data = recvFuture.read()
        echo data

        connector.close()
        listener.close()

        shutdownExecutorScheduler()

    runExecutorScheduler()

  test()
  
