import std/nativesockets
import std/os
import std/net
import std/tables
import std/deques
from std/posix import write
import netkit/posix/linux/socket
import netkit/posix/linux/selector
import netkit/future

proc eventfd(count: cuint, flags: cint): cint
     {.cdecl, importc: "eventfd", header: "<sys/eventfd.h>".}

type
  ReadyData* = object
    fd: SocketHandle
    readReady: bool
    readList: Deque[proc ()]
    writeReady: bool
    writeList: Deque[proc ()]

  TcpListener* = object
    inner: SocketHandle

  TcpStream* = object
    inner: SocketHandle

  ReadyManager* = object
    map: Table[cint, ReadyData]

proc createSocket(): SocketHandle = 
  let socket = createNativeSocket(Domain.AF_INET, SOCK_STREAM, IPPROTO_TCP)
  if socket == osInvalidSocket:
    raiseOSError(osLastError())
  socket.setSockOptInt(SOL_SOCKET, SO_REUSEADDR, 1)
  socket.setSockOptInt(SOL_SOCKET, SO_REUSEPORT, 1)
  when defined(macosx):
    socket.setSockOptInt(SOL_SOCKET, SO_NOSIGPIPE, 1)
  socket.setBlocking(false)
  return socket

proc bindAddr(socket: SocketHandle, port: Port, address = "", domain = AF_INET) {.raises: [OSError, ValueError].} =
  ## Binds ``address``:``port`` to the socket.
  ##
  ## If ``address`` is "" then ``ADDR_ANY`` will be bound.
  var aiList: ptr AddrInfo
  if address == "":
    var realaddr: string
    case domain
    of AF_INET6: realaddr = "::"
    of AF_INET: realaddr = "0.0.0.0"
    else:
      raise newException(ValueError, "Unknown socket address family and no address specified to bindAddr")
    aiList = getAddrInfo(realaddr, port, domain)
  else:
    aiList = getAddrInfo(address, port, domain)
  if nativesockets.bindAddr(socket, aiList.ai_addr, aiList.ai_addrlen.SockLen) < 0'i32:
    aiList.freeAddrInfo()
    raiseOSError(osLastError())
  else:
    aiList.freeAddrInfo()

proc listen(socket: SocketHandle, backlog = SOMAXCONN) {.raises: [OSError].} =
  ## Marks ``fd`` as accepting connections. ``Backlog`` specifies the maximum length of the
  ## queue of pending connections.
  ##
  ## Raises an OSError error upon failure.
  if nativesockets.listen(socket, backlog) < 0'i32:
    raiseOSError(osLastError())

proc bindAddr*(port: Port, address = "", domain = AF_INET): TcpListener =
  result.inner = createSocket()
  result.inner.bindAddr(port, address, domain)
  result.inner.listen()

proc accept*(l: TcpListener): TcpStream =
  var sockAddress: Sockaddr_storage
  var addrLen = sizeof(sockAddress).SockLen
  result.inner = l.inner.accept4(
    cast[ptr SockAddr](addr(sockAddress)), 
    addr(addrLen), 
    SOCK_NONBLOCK or SOCK_CLOEXEC
  ) # TODO: 错误


proc connect(socket: SocketHandle, port = Port(0), address: string, domain = AF_INET) {.raises: [OSError].} =
  var aiList = getAddrInfo(address, port, domain)
  # try all possibilities:
  var success = false
  var lastError: OSErrorCode
  var it = aiList
  while it != nil:
    if connect(socket, it.ai_addr, it.ai_addrlen.SockLen) == 0'i32:
      success = true
      break
    else: 
      lastError = osLastError()
    it = it.ai_next
  freeAddrInfo(aiList)
  if not success: 
    raiseOSError(lastError)

proc connect(port = Port(0), address: string, domain = AF_INET): TcpStream =
  result.inner = createSocket()
  result.inner.connect(port, address, domain)

proc read(s: TcpStream, size: int): int =
  var buffer = newString(size)
  result = recv(s.inner, buffer.cstring, size, 0.cint)
  if result == -1:
    let lastError = osLastError()
    if lastError.int32 in {EWOULDBLOCK, EAGAIN}:
      return -100
    if isDisconnectionError({SocketFlag.SafeDisconn}, lastError):
      return -200
    raiseOSError(lastError)

var slt = newSelector()
var listener = bindAddr(Port(8080))

var rmanager = ReadyManager()
rmanager.map = initTable[cint, ReadyData]()

# 注册
rmanager.map[listener.inner.cint] = ReadyData(
  fd: listener.inner,
  readReady: false,
  writeReady: false
)

proc accept2*(): Future[TcpStream] =
  var promise = newPromise[TcpStream]()
  result = promise.future

  proc cb() = 
    var sockAddress: Sockaddr_storage
    var addrLen = sizeof(sockAddress).SockLen
    var client = listener.inner.accept4(
      cast[ptr SockAddr](addr(sockAddress)), 
      addr(addrLen), 
      SOCK_NONBLOCK or SOCK_CLOEXEC
    ) # TODO: 错误
    promise.setValue(TcpStream(inner: client))

  rmanager.map[listener.inner.cint].readList.addLast(cb)

proc loop() =
  block:
    var serverIntent = initIntent()
    serverIntent.registerReadable()
    slt.register(listener.inner.cint, serverIntent)

  var events = newSeq[Event](128)
  while true:
    let count = slt.select(events, -1)
    for i in 0..<count:
      let event = events[i].addr

      if event[].isError:
        let data = rmanager.map[event[].token].addr
        while data.readList.len > 0:
          data.readList.popFirst()()
        while data.writeList.len > 0:
          data.writeList.popFirst()()
      else:
        if event[].isReadable:
          let data = rmanager.map[event[].token].addr
          if data.readList.len > 0:
            data.readList.popFirst()()
            
        if event[].isWritable:
          let data = rmanager.map[event[].token].addr
          if data.writeList.len > 0:
            data.writeList.popFirst()()
      

proc test() =
  iterator handler(): FutureBase {.closure.} =
    var acceptFuture = accept2()
    yield acceptFuture
    if acceptFuture.failed:
      raise acceptFuture.getError
    echo acceptFuture.finished
    echo acceptFuture.getValue

  var iter = handler
  
  proc cb() =
    let future = iter()
    if not iter.finished:
      future.callback = proc () =
        echo "...gc:", future.finished
        assert future.finished
        # if future.failed:
        #   raise future.getError()
        cb()

  cb()

test()
loop()