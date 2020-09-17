
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

proc accept(stream: ref SocketStream, inheritable = defined(nimInheritHandles)): ref Future[string] =
  var future = newFuture[string]()
  result = future
  var readable = new(Pollable[SocketStreamFuture[string]])
  readable.poll = proc (p: ref PollableBase): bool =
    result = true
    var pollable = (ref Pollable[SocketStreamFuture[string]])(p)
    var stream = pollable.value.stream
    var future = pollable.value.future
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
        future.fail(newOSError(osLastError()))
        client.close()
        return false

    if client == osInvalidSocket:
      let lastError = osLastError()
      assert lastError.int32 != EWOULDBLOCK and lastError.int32 != EAGAIN
      if lastError.int32 == EINTR:
        return false
      else:
        future.fail(newException(OSError, osErrorMsg(lastError)))
        # if flags.isDisconnectionError(lastError):
        #   return false
        # else:
        #   retFuture.fail(newException(OSError, osErrorMsg(lastError)))
    else:
      try:
        let address = getAddrString(cast[ptr SockAddr](addr sockAddress))
        # register(client.AsyncFD)
        future.complete(address)
      except:
        # getAddrString may raise
        client.close()
        future.fail(getCurrentException())
      client.close()
  readable.value.stream = stream
  readable.value.future = future
  readable.value.stream.pod.registerReadable(readable) 

proc recv(stream: ref SocketStream) =
  var readable = new(Pollable[ref SocketStream])
  readable.poll = proc (p: ref PollableBase): bool =
    result = true
    var stream = (ref Pollable[ref SocketStream])(p).value
    var buffer = newString(1024)
    let res = recv(stream.fd.SocketHandle, addr buffer[0], 1024.cint, 0
                  #[{SocketFlag.SafeDisconn}.toOSFlags()]#)
    if res < 0:
      let lastError = osLastError()
      if lastError.int32 != EINTR and lastError.int32 != EWOULDBLOCK and
          lastError.int32 != EAGAIN:
        discard
        # if flags.isDisconnectionError(lastError):
        #   retFuture.complete("")
        # else:
        #   retFuture.fail(newException(OSError, osErrorMsg(lastError)))
      else:
        discard 
        # result = false # We still want this callback to be called.
    elif res == 0:
      # Disconnected
      discard
    else:
      discard
  readable.value = stream
  readable.value.pod.registerReadable(readable) 

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
    var future = (ref Future[string])(future)
    echo future.read()

  runExecutorScheduler()