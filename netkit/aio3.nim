import netkit/posix/linux/selector
import netkit/posix/linux/socket
import netkit/future
import posix
import os
import nativesockets

type
  Value = ref object
    a: int

proc childFunc(value: Value) {.thread.} = 
  echo "Child: (before) ", value.a
  value.a = value.a + 1
  echo "Child: (after) ", value.a

proc test() = 
  var child: Thread[Value]
  var value = new(Value)
  
  createThread(child, childFunc, value)
  joinThread(child)

  echo "Main: ", value.a


test()

type
  Reactor = object
    selector: Selector
    #operations: seq[AsyncData] # 优化 seq -> ringbuffer

  Request = ref object of RootObj
    code: RequestCode
    next: Request

  RequestCode {.pure, size: sizeof(uint8).} = enum # TODO: size 优化，与 Promise 一致
    Read, Write, ReadV, WriteV, Recv, Send, RecvV, SendV, RecvFrom, SendTo, Accept
    
  EventData = object
    interest: Interest
    readList: Request 
    writeList: Request 

#   RecvPromise = ref object of Promise[int]
#     fd: cint
#     buf: pointer
#     size: cint
#     pos: cint

#   SendPromise = ref object of Promise[int]
#     fd: cint
#     buf: pointer
#     size: cint

# proc register(reactor: var Reactor, fd: cint) = 
#   let interest = initInterest()
#   reactor.selector.register(fd, UserData(), interest)
#   reactor.operations[fd] = AsyncData(interest: interest)

# proc recv(reactor: var Reactor, fd: cint, buf: pointer, size: int): Future[int] = 
#   var promise = RecvPromise(
#     fd: fd,
#     buf: buf,
#     size: size.cint,
#     pos: 0
#   )
#   promise.init(AioPromiseCode.Recv)
#   reactor.operations[fd].interest.registerReadable()
#   reactor.selector.update(fd, UserData(fd: fd), reactor.operations[fd].interest)
#   reactor.operations[fd].readList.add(promise)
#   promise.future

# proc poll(reactor: var Reactor, promise: RecvPromise, fd: cint): bool = 
#   var recvPromise = cast[RecvPromise](promise)
#   while true:
#     let res = recv(
#       SocketHandle(fd), 
#       recvPromise.buf, 
#       recvPromise.size - recvPromise.pos, 
#       0'i32
#     ) # TODO: flags
#     if res < 0:
#       let lastError = osLastError()
#       if lastError.int32 == EINTR:
#         discard
#       elif lastError.int32 == EAGAIN or lastError.int32 == EWOULDBLOCK:
#         return false # no next
#       else:
#         # TODO: 考虑 flags.isDisconnectionError(lastError)
#         # if flags.isDisconnectionError(lastError):
#         #   retFuture.complete(0)
#         reactor.operations[fd].readList[0] = nil # TODO: ringbuffer
#         recvPromise.setError(newException(OSError, lastError.osErrorMsg()))
#         return true # next (error, or others)
#     elif res == 0:
#       reactor.operations[fd].readList[0] = nil # TODO: ringbuffer
#       recvPromise.setValue(recvPromise.pos)
#       return true # next (0, or others)
#     else:
#       recvPromise.pos = recvPromise.pos + res.cint
#       if recvPromise.pos < recvPromise.size:
#         if true:
#           return false # EAGAIN
#         else:
#           recvPromise.setValue(recvPromise.pos)
#           return false # no next
#       else: # ==
#         reactor.operations[fd].readList[0] = nil # TODO: ringbuffer
#         recvPromise.setValue(recvPromise.pos)
#         return true # next

#       # TODO: 是否考虑 import recv？posix.recv 定义不是十分准确，
#       #       应该返回 cint, recv？posix.recv 却返回 int

# proc send(reactor: var Reactor, fd: cint, buf: pointer, size: int): Future[int] = 
#   var promise = SendPromise(
#     fd: fd,
#     buf: buf,
#     size: size.cint
#   )
#   promise.init(AioPromiseCode.Send)
#   reactor.operations[fd].interest.registerWritable()
#   reactor.selector.update(fd,  UserData(fd: fd), reactor.operations[fd].interest)
#   reactor.operations[fd].writeList.add(promise)
#   promise.future

# proc loop(reactor: var Reactor) =
#   echo "[Server] loop ..."
#   var events: array[128, Event]
#   while true:
#     let count = reactor.selector.select(events, -1)
#     # echo "[Server] selected ..."
#     for i in 0..<count:
#       let event = events[i].addr
#       var data = event[].data
#       # TODO: 考虑其他事件
#       if event[].isReadable():
#         # TODO: 考虑操作未完全完成，只完成了一部分
#         for promise in reactor.operations[data.fd].readList:
#           case promise.code
#           of AioPromiseCode.Recv:
#             var recvPromise = cast[RecvPromise](promise)
#             while true:
#               let res = recv(
#                 data.fd.SocketHandle, 
#                 recvPromise.buf, 
#                 recvPromise.size - recvPromise.pos, 
#                 0'i32
#               ) # TODO: flags
#               if res < 0:
#                 let lastError = osLastError()
#                 if lastError.int32 == EINTR:
#                   continue
#                 if lastError.int32 == EAGAIN or lastError.int32 == EWOULDBLOCK:
#                   break # no next
#                 # TODO: 考虑 flags.isDisconnectionError(lastError)
#                 # if flags.isDisconnectionError(lastError):
#                 #   retFuture.complete(0)
#                 # else:
#                 #   retFuture.fail(newException(OSError, osErrorMsg(lastError)))
#                 recvPromise.setError(newException(OSError, lastError.osErrorMsg()))
#                 break # next (error, or others)
#               elif res == 0:
#                 recvPromise.setValue(recvPromise.pos)
#                 break # next (0, or others)
#               else:
#                 recvPromise.pos = recvPromise.pos + res.cint
#                 if recvPromise.pos < recvPromise.size:
#                   if true:
#                     continue
#                   else:
#                     recvPromise.setValue(recvPromise.pos)
#                     break # no next
#                 else: # ==
#                   recvPromise.setValue(recvPromise.pos)
#                   break # next

#                 # if true and recvPromise.pos < recvPromise.size: # flag Until
#                 #   continue
#                 # recvPromise.setValue(recvPromise.pos)
#                 # break # next 

#                 # TODO: 是否考虑 import recv？posix.recv 定义不是十分准确，
#                 #       应该返回 cint, recv？posix.recv 却返回 int
#           else:
#             discard
#       if event[].isWritable():
#         for promise in reactor.operations[data.fd].readList:
#           case promise.code
#           of AioPromiseCode.Send:
#             var sendPromise = cast[SendPromise](promise)
#             let res = send(
#               data.fd.SocketHandle, 
#               sendPromise.buf, 
#               sendPromise.size, 
#               MSG_NOSIGNAL
#             )
#             if res < 0:
#               discard
#               # let lastError = osLastError()
#               # if lastError.int32 != EINTR and
#               #   lastError.int32 != EWOULDBLOCK and
#               #   lastError.int32 != EAGAIN:
#               #   if flags.isDisconnectionError(lastError):
#               #     retFuture.complete()
#               #   else:
#               #     retFuture.fail(newOSError(lastError))
#               # else:
#               #   result = false # We still want this callback to be called.
#             else:
#               sendPromise.setValue(res)
#               # written.inc(res)
#               # if res != netSize:
#               #   result = false # We still have data to send.
#               # else:
#               #   retFuture.complete()
#           else:
#             discard

# proc createSocket(): SocketHandle = 
#   # TODO: 改用 posix socket ? 需要考虑 windows 兼容
#   let socket = createNativeSocket(Domain.AF_INET, nativesockets.SOCK_STREAM, nativesockets.IPPROTO_TCP)
#   if socket == osInvalidSocket:
#     raiseOSError(osLastError())
#   socket.setSockOptInt(SOL_SOCKET, SO_REUSEADDR, 1)
#   socket.setSockOptInt(SOL_SOCKET, SO_REUSEPORT, 1)
#   when defined(macosx):
#     socket.setSockOptInt(SOL_SOCKET, SO_NOSIGPIPE, 1)
#   socket.setBlocking(false)
#   return socket

# proc bindAddr(socket: SocketHandle, port: Port, address = "", domain = Domain.AF_INET) {.raises: [OSError, ValueError].} =
#   ## Binds ``address``:``port`` to the socket.
#   ##
#   ## If ``address`` is "" then ``ADDR_ANY`` will be bound.
#   var aiList: ptr AddrInfo
#   if address == "":
#     var realaddr: string
#     case domain
#     of Domain.AF_INET6: realaddr = "::"
#     of Domain.AF_INET: realaddr = "0.0.0.0"
#     else:
#       raise newException(ValueError, "Unknown socket address family and no address specified to bindAddr")
#     aiList = getAddrInfo(realaddr, port, domain)
#   else:
#     aiList = getAddrInfo(address, port, domain)
#   if nativesockets.bindAddr(socket, aiList.ai_addr, aiList.ai_addrlen.SockLen) < 0'i32:
#     aiList.freeAddrInfo()
#     raiseOSError(osLastError())
#   else:
#     aiList.freeAddrInfo()

# proc listen(socket: SocketHandle, backlog = SOMAXCONN) {.raises: [OSError].} =
#   ## Marks ``fd`` as accepting connections. ``Backlog`` specifies the maximum length of the
#   ## queue of pending connections.
#   ##
#   ## Raises an OSError error upon failure.
#   if nativesockets.listen(socket, backlog) < 0'i32:
#     raiseOSError(osLastError())

# proc accept*(socket: SocketHandle): SocketHandle {.raises: [OSError].} =
#   var sockAddress: Sockaddr_storage
#   var addrLen = sizeof(sockAddress).SockLen
#   var client = accept4(
#     socket,
#     cast[ptr SockAddr](addr(sockAddress)), 
#     addr(addrLen), 
#     SOCK_NONBLOCK or SOCK_CLOEXEC
#   ) # TODO: 错误
#   if client.cint < 0'i32:
#     raiseOSError(osLastError())
#   client

# proc connect(socket: SocketHandle, port = Port(0), address = "127.0.0.1", domain = Domain.AF_INET) {.raises: [OSError].} =
#   var aiList = getAddrInfo(address, port, domain)
#   # try all possibilities:
#   var success = false
#   var lastError: OSErrorCode
#   var it = aiList
#   while it != nil:
#     if connect(socket, it.ai_addr, it.ai_addrlen.SockLen) == 0'i32:
#       success = true
#       break
#     else: 
#       lastError = osLastError()
#     it = it.ai_next
#   freeAddrInfo(aiList)
#   if not success: 
#     raiseOSError(lastError)

# proc threadFunc() {.thread.} =
#   sleep(1)
#   var client = createSocket()
#   client.setBlocking(true)
#   echo "[Client] connecting ..."
#   client.connect(Port(8080))
#   var data = "hello world"
#   echo "[Client] sending ..."
#   var res = client.send(data.cstring, 11, 0'i32)
#   if res < 0:
#     raiseOSError(osLastError())
#   echo "[Client] sended ", res

#   sleep(3000)

#   var data2 = "hello world"
#   echo "[Client] sending ..."
#   var res2 = client.send(data2.cstring, 11, 0'i32)
#   if res2 < 0:
#     raiseOSError(osLastError())
#   echo "[Client] sended ", res2



# var reactor: Reactor = Reactor()

# proc main() =
#   reactor.selector = initSelector()
#   reactor.operations = newSeq[AsyncData](1024)

#   var server = createSocket()
#   server.setBlocking(true)

#   server.bindAddr(Port(8080))
#   server.listen()
  
#   var thr: Thread[void]
#   createThread(thr, threadFunc)

#   echo "[Server] accepting ..."
#   var client = server.accept()
#   client.setBlocking(false)
  
#   reactor.register(client.cint)

#   echo "[Server] recving ..."
#   var buf = newString(16)
#   var readFuture = reactor.recv(client.cint, buf.cstring, 16)

#   readFuture.callback = proc () = 
#     echo "[Server] readFuture finished: ", readFuture.finished
#     echo "                    value: ", readFuture.getValue()
  
#   reactor.loop()
#   joinThread(thr)

# main()

# type
#   myseq*[T] = object
#     len, cap: int
#     value: T
#     # data: ptr UncheckedArray[T]

#   OptObj = object
#     myseq: myseq[int]

# proc `=destroy`*[T](x: var myseq[T]) =
#   echo "=destroy myseq"

# proc `=destroy`*(x: var OptObj) =
#   echo "=destroy OptObj"
#   `=destroy`(x.myseq)

# proc run() =
#   var opt: OptObj = OptObj()
#   echo repr opt

# run()

# type
#   Foo[T] = object
#     value: T

# proc `=destroy`*[T](x: var Foo[T]) =
#   echo "=destroy Foo"

# type
#   Bar = object
#     baz: Foo[int]

# proc main() =
#   var foo: Foo[int] = Foo[int]()
#   echo repr foo

# main()

