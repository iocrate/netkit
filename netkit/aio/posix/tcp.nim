
import std/os
import std/posix
import std/nativesockets
import netkit/aio/futures
import netkit/aio/posix/pods
import netkit/aio/handles

type
  AcceptStream* = ref object
    handle: IoHandle
    pod: Pod

  TcpStream* = ref object
    handle: IoHandle
    pod: Pod

proc createTcpSocket(
  domain: Domain, 
  sockType: SockType,
  protocol: Protocol
): IoHandle {.raises: [OSError].} =
  let socket = nativesockets.createNativeSocket(domain, sockType, protocol)
  if socket == osInvalidSocket:
    raiseOSError(osLastError())
  socket.setBlocking(false)
  socket.setSockOptInt(SOL_SOCKET, SO_REUSEADDR, 1)
  when defined(macosx) and not defined(nimdoc):
    socket.setSockOptInt(SOL_SOCKET, SO_NOSIGPIPE, 1)
  result = IoHandle(socket)

proc listen(socket: IoHandle, backlog = SOMAXCONN) {.raises: [OSError].} =
  if nativesockets.listen(SocketHandle(socket), backlog) < 0: 
    raiseOSError(osLastError())

proc bindAddr(socket: IoHandle, domain: Domain, port: Port, address: string) {.raises: [OSError, ValueError].} =
  var aiList: ptr AddrInfo
  if address == "":
    var realaddr: string
    case domain
    of Domain.AF_INET6: realaddr = "::"
    of Domain.AF_INET: realaddr = "0.0.0.0"
    else:
      raise newException(ValueError, "Unknown socket address family and no address specified to bindAddr")
    aiList = getAddrInfo(realaddr, port, domain)
  else:
    aiList = getAddrInfo(address, port, domain)
  if nativesockets.bindAddr(SocketHandle(socket), aiList.ai_addr, aiList.ai_addrlen.SockLen) < 0:
    aiList.freeAddrInfo()
    raiseOSError(osLastError())
  else:
    aiList.freeAddrInfo()

proc bindTcp*(
  domain = Domain.AF_INET, 
  port = Port(0), 
  address = "", 
  backlog = SOMAXCONN
): IoHandle {.raises: [OSError, ValueError].} =
  result = createTcpSocket(domain, SockType.SOCK_STREAM, Protocol.IPPROTO_TCP)
  result.bindAddr(domain, port, address)
  result.listen()
  
proc close*(socket: IoHandle) = 
  close(SocketHandle(socket))

proc newTcpStream*(socket: IoHandle): TcpStream = 
  new(result)
  result.handle = socket
  result.pod = initPod(socket.cint)

proc close*(stream: AcceptStream) = 
  `=destroy`(stream.pod)

proc accept*(stream: AcceptStream): Future[tuple[address: string, client: IoHandle]] =
  var retFuture = newFuture[tuple[address: string, client: IoHandle]]()
  result = retFuture
  stream.pod.registerReadable proc (): bool =
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
      try:
        let address = getAddrString(cast[ptr SockAddr](sockAddress.addr))
        client.setBlocking(false)
        retFuture.complete((address, IoHandle(client)))
      except:
        # getAddrString may raise
        client.close()
        retFuture.fail(getCurrentException())

proc newAcceptStream*(socket: IoHandle): AcceptStream = 
  new(result)
  result.handle = socket
  result.pod = initPod(socket.cint)

proc close*(stream: TcpStream) = 
  `=destroy`(stream.pod)

proc send*(stream: TcpStream, buffer: string): Future[void] =
  var retFuture = newFuture[void]()
  result = retFuture
  stream.pod.registerReadable proc (): bool =
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
  stream.pod.registerReadable proc (): bool =
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
    var serverHandle = bindTcp(port = Port(10003))
    var acceptStream = newAcceptStream(serverHandle)

    var acceptFuture = acceptStream.accept()
    acceptFuture.callback = proc () =
      var (clientAddr, clientHandle) = acceptFuture.read()
      
      var clientStream = newTcpStream(clientHandle)
      var recvFuture = clientStream.recv()
      recvFuture.callback = proc () = 
        var data = recvFuture.read()
        echo data

        clientStream.close()
        clientHandle.close()

        acceptStream.close()
        serverHandle.close()

        shutdownExecutorScheduler()

    runExecutorScheduler()

  test()
  