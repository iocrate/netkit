
import std/os
import std/posix
import std/nativesockets
import netkit/aio/futures
import netkit/aio/posix/pollers
import netkit/aio/posix/pods

type
  Socket = distinct int

  SocketStream = object
    fd: int
    pod: Pod

  SocketStreamFuture[T] = object
    stream: ref SocketStream
    future: ref Future[T]

proc createANativeSocket*(
  domain: Domain, 
  sockType: SockType,
  protocol: Protocol,
  inheritable = defined(nimInheritHandles)
): Socket =
  let handle = nativesockets.createNativeSocket(domain, sockType, protocol, inheritable)
  if handle == osInvalidSocket:
    return osInvalidSocket.Socket
  handle.setBlocking(false)
  when defined(macosx) and not defined(nimdoc):
    handle.setSockOptInt(SOL_SOCKET, SO_NOSIGPIPE, 1)
  result = handle.Socket

proc accept(stream: ref SocketStream, inheritable = defined(nimInheritHandles)): ref Future[Socket] =
  var retFuture = newFuture[Socket]()
  result = retFuture
  stream.pod.registerReadable proc (): bool =
    result = true
    var sockAddress: Sockaddr_storage
    var addrLen = sizeof(sockAddress).SockLen
    var client =
      when declared(accept4):
        accept4(stream.fd.SocketHandle, cast[ptr SockAddr](addr(sockAddress)),
                addr(addrLen), SOCK_CLOEXEC #[if inheritable: 0 else: SOCK_CLOEXEC]#)
      else:
        accept(stream.fd.SocketHandle, cast[ptr SockAddr](addr(sockAddress)),
               addr(addrLen))
    when declared(setInheritable) and not declared(accept4):
      if client != osInvalidSocket and not setInheritable(client, inheritable):
        # Set failure first because close() itself can fail,
        # # altering osLastError().
        retFuture.fail(newException(OSError, osErrorMsg(lastError)))
        client.close()
        return false

    if client == osInvalidSocket:
      let lastError = osLastError()
      assert lastError.int32 != EWOULDBLOCK and lastError.int32 != EAGAIN
      if lastError.int32 == EINTR:
        return false
      else:
        retFuture.fail(newException(OSError, osErrorMsg(lastError)))
        # if flags.isDisconnectionError(lastError):
        #   return false
        # else:
        #   retFuture.fail(newException(OSError, osErrorMsg(lastError)))
    else:
      try:
        let address = getAddrString(cast[ptr SockAddr](addr sockAddress))
        # register(client.AsyncFD)
        retFuture.complete(Socket(client))
      except:
        # getAddrString may raise
        client.close()
        retFuture.fail(getCurrentException())

proc recv(stream: ref SocketStream): ref Future[string] =
  var retFuture = newFuture[string]()
  result = retFuture
  stream.pod.registerReadable proc (): bool =
    result = true
    var buffer = newString(1024)
    let res = recv(stream.fd.SocketHandle, addr buffer[0], 1024.cint, 0
                  #[{SocketFlag.SafeDisconn}.toOSFlags()]#)
    if res < 0:
      let lastError = osLastError()
      if lastError.int32 != EINTR and lastError.int32 != EWOULDBLOCK and
          lastError.int32 != EAGAIN:
        retFuture.fail(newException(OSError, osErrorMsg(lastError)))
        # if flags.isDisconnectionError(lastError):
        #   retFuture.complete("")
        # else:
        #   retFuture.fail(newException(OSError, osErrorMsg(lastError)))
      else:
        result = false # We still want this callback to be called.
    elif res == 0:
      # Disconnected TODO
      retFuture.complete(buffer)
    else:
      retFuture.complete(buffer)
    stream.fd.SocketHandle.close()

proc listen*(socket: ref SocketStream, backlog = SOMAXCONN) {.tags: [ReadIOEffect].} =
  if nativesockets.listen(socket.fd.SocketHandle, backlog) < 0'i32: 
    raiseOSError(osLastError())

proc bindAddr*(socket: ref SocketStream, port = Port(0), address = "") {.tags: [ReadIOEffect].} =
  var realaddr = address
  # if realaddr == "":
  #   case socket.domain
  #   of AF_INET6: realaddr = "::"
  #   of AF_INET: realaddr = "0.0.0.0"
  #   else:
  #     raise newException(ValueError,
  #       "Unknown socket address family and no address specified to bindAddr")
  realaddr = "0.0.0.0"
  var aiList = getAddrInfo(realaddr, port, Domain.AF_INET#[socket.domain]#)
  if nativesockets.bindAddr(socket.fd.SocketHandle, aiList.ai_addr, aiList.ai_addrlen.SockLen) < 0'i32:
    freeaddrinfo(aiList)
    raiseOSError(osLastError())
  freeaddrinfo(aiList)
  
when isMainmodule:
  import netkit/aio/posix/runtime

  var s = createANativeSocket(Domain.AF_INET, SockType.SOCK_STREAM, Protocol.IPPROTO_TCP)

  var stream = new(SocketStream)
  stream.fd = s.cint
  stream.pod = initPod(stream.fd.cint) # windows is int

  stream.fd.SocketHandle.setSockOptInt(SOL_SOCKET.cint, SO_REUSEADDR.cint, 1.cint)
  stream.bindAddr(Port(10003))
  stream.listen()

  var future = stream.accept()
  future.callback = proc (future: ref FutureBase) = 
    var future = (ref Future[Socket])(future)
    var client = future.read()
    var clientStream = new(SocketStream)
    clientStream.fd = client.cint
    clientStream.pod = initPod(clientStream.fd.cint)

    var recvFuture = clientStream.recv()
    recvFuture.callback = proc (future: ref FutureBase) = 
      var data = (ref Future[string])(future).read()
      echo data

  runExecutorScheduler()