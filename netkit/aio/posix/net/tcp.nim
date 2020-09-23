
import std/os
import std/posix
import std/nativesockets
import netkit/aio/futures
import netkit/aio/posix/runtime

type
  TcpListener* = distinct IoHandle
  TcpConnector* = distinct IoHandle

  AcceptStream* = ref object
    handle: TcpListener
    registry: IoRegistry

  TcpStream* = ref object
    handle: TcpConnector
    registry: IoRegistry

proc createTcpHandle(domain: Domain, sockType: SockType, protocol: Protocol): IoHandle =
  let socket = nativesockets.createNativeSocket(domain, sockType, protocol)
  if socket == osInvalidSocket:
    raiseOSError(osLastError())
  socket.setBlocking(false)
  socket.setSockOptInt(SOL_SOCKET, SO_REUSEADDR, 1)
  when defined(macosx) and not defined(nimdoc):
    socket.setSockOptInt(SOL_SOCKET, SO_NOSIGPIPE, 1)
  result = IoHandle(socket)

proc `==`*(a: TcpListener, b: TcpListener): bool {.borrow.}

proc bindAddr(listener: TcpListener, domain: Domain, port: Port, address: string) =
  var aiList: ptr AddrInfo
  if address == "":
    var realaddr: string
    case domain
    of Domain.AF_INET6: realaddr = "::"
    of Domain.AF_INET: realaddr = "0.0.0.0"
    else:
      raise newException(ValueError, "Unknown socket address family and no address specified")
    aiList = getAddrInfo(realaddr, port, domain)
  else:
    aiList = getAddrInfo(address, port, domain)
  if nativesockets.bindAddr(SocketHandle(listener), aiList.ai_addr, aiList.ai_addrlen.SockLen) < 0:
    aiList.freeAddrInfo()
    raiseOSError(osLastError())
  else:
    aiList.freeAddrInfo()

proc listen(listener: TcpListener, backlog: cint) =
  if nativesockets.listen(SocketHandle(listener), backlog) < 0: 
    raiseOSError(osLastError())

proc bindTCP*(
  domain = Domain.AF_INET, 
  port = Port(0), 
  address = "", 
  backlog = SOMAXCONN
): TcpListener =
  # TODO: consider defining Domain, Port, and SOMAXCONN separately?
  result = TcpListener(createTcpHandle(domain, SockType.SOCK_STREAM, Protocol.IPPROTO_TCP))
  result.bindAddr(domain, port, address)
  result.listen(backlog)
  
proc close*(listener: TcpListener) {.inline.} = 
  ## Closes this listener to release the underlying resources.
  #
  # TODO: consider the following scenarios:
  #
  # - Socket: {tcp, udp} posix.close(cint); windows.closeSocket(Handle) 
  # - Pipe: ? 
  # - FIFO: ? 
  #
  # How to deal with them gracefully?
  close(SocketHandle(listener))

proc getLocalAddr*(listener: TcpListener, domain: Domain): (string, Port) {.inline.} = 
  ## Returns a tuple of the local address and port of this listener.
  SocketHandle(listener).getLocalAddr(domain)

const IP_TTL = when defined(linux): 2
               elif defined(macosx) or defined(freebsd) or defined(netbsd) or defined(openbsd) or defined(dragonfly): 4
               else: {.error: "Platform not supported!".}

proc getTTL*(listener: TcpListener): Natural {.inline.} = 
  # Gets the value of the ``IP_TTL`` option for this listener.
  SocketHandle(listener).getSockOptInt(posix.IPPROTO_IP, IP_TTL)

proc setTTL*(listener: TcpListener, ttl: Natural) {.inline.} = 
  ## Sets the value for the ``IP_TTL`` option on this listener.
  ## This value sets the time-to-live field that is used in every packet sent from this listener.
  SocketHandle(listener).setSockOptInt(posix.IPPROTO_IP, IP_TTL, ttl)

proc newAcceptStream*(listener: TcpListener): AcceptStream = 
  ## Creates a new stream which will be bound to the specified listener.
  new(result)
  result.handle = listener
  result.registry = initIoRegistry(IoHandle(listener))

proc close*(stream: AcceptStream) = 
  ## Closes this stream to release the underlying resources.
  `=destroy`(stream.registry)

proc accept*(stream: AcceptStream): Future[TcpConnector] =
  var retFuture = newFuture[TcpConnector]()
  result = retFuture
  stream.registry.registerReadable proc (): bool =
    result = true
    var sockAddress: Sockaddr_storage
    var addrLen = SockLen(sizeof(sockAddress))
    var client =
      when declared(accept4):
        accept4(SocketHandle(stream.handle), cast[ptr SockAddr](sockAddress.addr), addrLen.addr, 
                SOCK_CLOEXEC #[if inheritable: 0 else: SOCK_CLOEXEC]#)
      else:
        accept(SocketHandle(stream.handle), cast[ptr SockAddr](sockAddress.addr), addrLen.addr)
    if client == osInvalidSocket:
      let lastError = osLastError()
      assert int32(lastError) != EWOULDBLOCK and int32(lastError) != EAGAIN
      if int32(lastError) == EINTR:
        return false
      else:
        retFuture.fail(newException(OSError, osErrorMsg(lastError)))
        # if flags.isDisconnectionError(lastError):
        #   return false
        # else:
        #   retFuture.fail(newException(OSError, osErrorMsg(lastError)))
    else:
      when declared(setInheritable) and not declared(accept4):
        if not setInheritable(client, inheritable):
          # Set failure first because close() itself can fail,
          # # altering osLastError().
          client.close()
          retFuture.fail(newException(OSError, osErrorMsg(lastError)))
          return
      client.setBlocking(false)
      retFuture.complete(TcpConnector(client))
      # try:
      #   let address = getAddrString(cast[ptr SockAddr](sockAddress.addr))
      #   client.setBlocking(false)
      #   retFuture.complete(TcpConnector(client))
      # except:
      #   # getAddrString may raise
      #   client.close()
      #   retFuture.fail(getCurrentException())

proc `==`*(a: TcpConnector, b: TcpConnector): bool {.borrow.}

proc connectTCP*(
  domain = Domain.AF_INET, 
  port = Port(0), 
  address = ""
): TcpConnector = 
  discard

proc close*(connector: TcpConnector) {.inline.} = 
  ## Closes this connector to release the underlying resources.
  close(SocketHandle(connector))

proc getLocalAddr*(connector: TcpConnector, domain: Domain): (string, Port) {.inline.} = 
  ## Returns a tuple of address and port of the local half of this TCP connection.
  SocketHandle(connector).getLocalAddr(domain)

proc getPeerAddr*(connector: TcpConnector, domain: Domain): (string, Port) {.inline.} = 
  ## Returns a connector and port of the remote peer of this TCP connection.
  SocketHandle(connector).getPeerAddr(domain)

proc getTTL*(connector: TcpConnector): Natural {.inline.} = 
  # Gets the value of the ``IP_TTL`` option for this connector.
  SocketHandle(connector).getSockOptInt(posix.IPPROTO_IP, IP_TTL)

proc setTTL*(connector: TcpConnector, ttl: Natural) {.inline.} = 
  ## Sets the value for the ``IP_TTL`` option on this connector.
  ## This value sets the time-to-live field that is used in every packet sent from this connector.
  SocketHandle(connector).setSockOptInt(posix.IPPROTO_IP, IP_TTL, ttl)

proc isNoDelay*(connector: TcpConnector): bool {.inline.} = 
  ## Checkes whether this connector enables the Nagle's algorithm. Nagle's algorithm delays data before 
  ## it is sent via the network. It attempts to optimize throughput at the expense of latency.
  SocketHandle(connector).getSockOptInt(posix.IPPROTO_TCP, TCP_NODELAY) > 0

proc setNoDelay*(connector: TcpConnector, nodelay: bool) {.inline.} = 
  ## Sets the value for the ``TCP_NODELAY`` option on this connector to enable/disable the Nagle's algorithm.
  SocketHandle(connector).setSockOptInt(posix.IPPROTO_TCP, TCP_NODELAY, if nodelay: 1 else: 0)

proc isKeepAlive*(connector: TcpConnector): bool {.inline.} = 
  ## Checkes whether this connector enables keepalive. 
  SocketHandle(connector).getSockOptInt(posix.SOL_SOCKET, SO_KEEPALIVE) > 0

proc setKeepAlive*(connector: TcpConnector, keepalive: bool) {.inline.} = 
  ## Sets the value for the ``SO_KEEPALIVE`` option on this connector.
  SocketHandle(connector).setSockOptInt(posix.SOL_SOCKET, SO_KEEPALIVE, if keepalive: 1 else: 0)

proc newTcpStream*(connector: TcpConnector): TcpStream = 
  ## Creates a new stream which will be bound to the specified connector.
  new(result)
  result.handle = connector
  result.registry = initIoRegistry(IoHandle(connector))

proc close*(stream: TcpStream) = 
  ## Closes this stream to release the underlying resources.
  `=destroy`(stream.registry)

proc send*(stream: TcpStream, buffer: string): Future[void] =
  var retFuture = newFuture[void]()
  result = retFuture
  stream.registry.registerReadable proc (): bool =
    result = true
    let res = send(SocketHandle(stream.handle), buffer.cstring, buffer.len, 0
                  #[{SocketFlag.SafeDisconn}.toOSFlags()]#)
    if res < 0:
      let lastError = osLastError()
      if int32(lastError) == EINTR or int32(lastError) == EWOULDBLOCK or int32(lastError) == EAGAIN:
        result = false # We still want this callback to be called.
      else:
        retFuture.fail(newException(OSError, osErrorMsg(lastError)))
        # if flags.isDisconnectionError(lastError):
        #   retFuture.complete("")
        # else:
        #   retFuture.fail(newException(OSError, osErrorMsg(lastError)))
    elif res == 0:
      # Disconnected TODO
      retFuture.complete()
    else:
      retFuture.complete()

proc recv*(stream: TcpStream): Future[string] =
  var retFuture = newFuture[string]()
  result = retFuture
  stream.registry.registerReadable proc (): bool =
    result = true
    var buffer = newString(1024)
    let res = recv(SocketHandle(stream.handle), buffer[0].addr, cint(1024), 0
                  #[{SocketFlag.SafeDisconn}.toOSFlags()]#)
    if res < 0:
      let lastError = osLastError()
      if int32(lastError) == EINTR or int32(lastError) == EWOULDBLOCK or int32(lastError) == EAGAIN:
        result = false # We still want this callback to be called.
      else:
        retFuture.fail(newException(OSError, osErrorMsg(lastError)))
        # if flags.isDisconnectionError(lastError):
        #   retFuture.complete("")
        # else:
        #   retFuture.fail(newException(OSError, osErrorMsg(lastError)))
    elif res == 0:
      # Disconnected TODO
      retFuture.complete(buffer)
    else:
      retFuture.complete(buffer)

when isMainmodule:
  import netkit/aio/posix/runtime

  proc test() =
    var listener = bindTCP(port = Port(10003))
    var acception = newAcceptStream(listener)

    var acceptFuture = acception.accept()
    acceptFuture.callback = proc () =
      var connector = acceptFuture.read()
      
      var connection = newTcpStream(connector)
      var recvFuture = connection.recv()
      recvFuture.callback = proc () = 
        var data = recvFuture.read()
        echo data

        connection.close()
        connector.close()

        acception.close()
        listener.close()

        shutdownExecutorScheduler()

    runExecutorScheduler()

  test()
  