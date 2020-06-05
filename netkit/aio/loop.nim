import netkit/posix/linux/selector
import netkit/posix/linux/socket
import netkit/future
import std/posix
import std/os
import std/nativesockets

import netkit/misc
import netkit/collections/vec

# file -> loop -> thread -> looppool


# Now 
#
#   2020-06-05 09:31 - 创建一个小的异步操作原型: 执行一次异步函数的演示，以形成基本模型。
#   2020-06-05 10:46 - 创建一个小的套接字读操作原型。
#   TODO - 创建一个小的异步操作原型: 执行一次异步文件读的演示，以形成基本模型。

type
  EventLoopGroup* = object 
    loops: SharedVec[EventLoop]

  # TODO: 考虑全局变量；考虑主线程的 Loop (其线程不需要设置)；考虑获取当前 Loop 的状态
  EventLoop* = object
    id: Natural
    group: ptr EventLoopGroup 
    thread: Thread[ptr EventLoop] 
    selector: Selector
    pipe: array[2, cint] # TODO: 使用 PipeChannel 

    dataPool: seq[ptr EventData] # TODO: 使用 ptr；考虑散列 [] 增长缩小，handle -> data

  EventData = object
    interest: Interest
    readHead: ptr Task 
    readTail: ptr Task 
    writeHead: ptr Task 
    writeTail: ptr Task 

  Task = object of RootObj
    code: TaskCode
    next: ptr Task

  TaskCode {.pure, size: sizeof(uint8).} = enum # TODO: size 优化，与 Promise 一致
    Read, Write, ReadV, WriteV, Recv, Send, RecvV, SendV, RecvFrom, SendTo, Accept

  AcceptTask = object of Task
    channel: SocketChannel # TODO: 改成 ptr

  Channel* = object
    handle: cint
    loop: ptr EventLoop

  SocketChannel* = object
    handle: SocketHandle
    loop: ptr EventLoop

  CallableContext* = object # TODO: 考虑参数版本，param: pointer - 只能是堆内存指针
    cb: proc () {.thread.}

proc createSocket(): SocketHandle = 
  # TODO: 考虑前缀歧义 (posix nativesockets)
  let socket = createNativeSocket(Domain.AF_INET, nativesockets.SOCK_STREAM, nativesockets.IPPROTO_TCP)
  if socket == osInvalidSocket:
    raiseOSError(osLastError())
  socket.setSockOptInt(SOL_SOCKET, SO_REUSEADDR, 1)
  socket.setSockOptInt(SOL_SOCKET, SO_REUSEPORT, 1)
  when defined(macosx):
    socket.setSockOptInt(SOL_SOCKET, SO_NOSIGPIPE, 1)
  socket.setBlocking(false)
  return socket

proc bindAddr(socket: SocketHandle, port: Port, address = "", domain = Domain.AF_INET) {.raises: [OSError, ValueError].} =
  ## Binds ``address``:``port`` to the socket.
  ##
  ## If ``address`` is "" then ``ADDR_ANY`` will be bound.
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

proc connect(socket: SocketHandle, port = Port(0), address: string, domain = Domain.AF_INET) {.raises: [OSError].} =
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

proc accept(s: SocketChannel) = 
  # TODO: 考虑 s.loop 尚未分配
  var data: ptr EventData
  if s.loop.dataPool[s.handle.cint] == nil:
    data = cast[ptr EventData](allocShared0(sizeof(EventData)))
    data.interest = initInterest()
    data.interest.registerReadable()
    s.loop.dataPool[s.handle.cint] = data
    s.loop.selector.register(s.handle.cint, UserData(data: data), data.interest)
  
  let task = cast[ptr AcceptTask](allocShared0(sizeof(AcceptTask)))
  task.code = TaskCode.Accept
  task.channel = s

  if data.readHead == nil:
    data.readHead = task
    data.readTail = task
  else:
    data.readTail.next = task
    data.readTail = task

proc exec(g: ptr EventLoopGroup, cb: proc () {.thread.}) = 
  # TODO: 优化 buffer，考虑 Task Context 共享堆内存
  # TODO: 考虑 enter 循环发送；eagain,ewouldblock 延迟发送
  # TODO：考虑 cb 和 Context，Waker
  # TODO: 考虑调度一个线程 Loop，和当前线程不在一个线程 （有多个线程时）
  let ctx = cast[ptr CallableContext](allocShared0(sizeof(CallableContext)))
  ctx.cb = cb
  # POSIX.1 says that write(2)s of less than PIPE_BUF bytes must be atomic.
  # POSIX.1 requires PIPE_BUF to be at least 512 bytes.  (On Linux, PIPE_BUF is 4096 bytes.)
  var buffer: uint64 = cast[ByteAddress](ctx).uint64
  if g.loops[1].pipe[1].write(buffer.addr, sizeof(uint64)) < 0: # TODO: 考虑 errorno enter,eagain,ewouldblock,...
    raiseOSError(osLastError())

proc `=destroy`*(x: var EventLoop) = 
  if x.id > 0:
    if x.pipe[0].close() < 0:
      raiseOSError(osLastError())
    if x.pipe[1].close() < 0:
      raiseOSError(osLastError())
    x.selector.close()

proc createEventLoopGroup(n: Natural): ptr EventLoopGroup =
  result = cast[ptr EventLoopGroup](allocShared0(sizeof(EventLoopGroup)))
  result.loops = createSharedVec[EventLoop](n)
  for i in 0..<n:
    let loop = result.loops[i].addr
    loop.id = i
    loop.group = result
    loop.selector = initSelector() # TODO: 考虑参数
    loop.dataPool = newSeq[ptr EventData](1024) # TODO: 使用 ptr；考虑散列 [] 增长缩小，handle -> data

    # TODO: 重构
    if pipe(loop.pipe) < 0:
      raiseOSError(osLastError())

proc close(g: ptr EventLoopGroup) = 
  `=destroy`(g.loops)
  deallocShared(g)

proc runable(loop: ptr EventLoop) {.thread.} =
  echo "Loop: ", loop.id

  var interest = initInterest()
  interest.registerReadable()
  # TODO: 考虑 UserData 和 kind
  loop.selector.register(loop.pipe[0], UserData(u64: 1), interest)

  var interest2 = initInterest()
  interest.registerWritable()
  # TODO: 考虑 UserData 和 kind
  loop.selector.register(loop.pipe[1], UserData(u64: 2), interest2)

  # TODO: 考虑 events 的容量；使用 Vec -> newSeq；Event kind
  var events = newSeq[Event](128)
  while true:
    let count = loop.selector.select(events, -1)
    for i in 0..<count:
      let event = events[i].addr
      if event[].isError:
        discard
      if event[].isReadClosed:
        discard
      if event[].isReadable:
        if event[].data.u64 == 1:
          echo "[Loop ", loop.id, "] loop.pipe isReadable"
          # POSIX.1 says that write(2)s of less than PIPE_BUF bytes must be atomic.
          # POSIX.1 requires PIPE_BUF to be at least 512 bytes.  (On Linux, PIPE_BUF is 4096 bytes.)
          #var buffer = cast[ptr CallableContext](allocShared0(sizeof(CallableContext)))
          var buffer: uint64
          if loop.pipe[0].read(buffer.addr, sizeof(uint64)) < 0: # TODO: 考虑 errorno enter,eagain,ewouldblock,...
            raiseOSError(osLastError())
          var ctx = cast[ptr CallableContext](buffer)
          ctx.cb()
          deallocShared(ctx)
          echo "-------------------------"
        elif event[].data.u64 == 2:
          discard
        else:
          var data = cast[ptr EventData](event[].data.data)
          var task = data.readHead
          echo "code:", $task.code
          case task.code
          of TaskCode.Accept:
            var task = cast[ptr AcceptTask](task)
            echo "[Loop ", loop.id, "] loop.accept isReadable"
            var sockAddress: Sockaddr_storage
            var addrLen = sizeof(sockAddress).SockLen
            var client = socket.accept4(
              task.channel.handle.SocketHandle,
              cast[ptr SockAddr](addr(sockAddress)), 
              addr(addrLen), 
              SOCK_NONBLOCK or socket.SOCK_CLOEXEC
            ) # TODO: 错误
            # promise.setValue(TcpStream(inner: client))
            echo repr client
            echo "-------------------------"
          else:
            discard
      if event[].isWriteClosed:
        discard
      if event[].isWritable:
        discard

proc run(g: ptr EventLoopGroup) = 
  # TODO: 考虑主线程 loop 直接 runable(loop)
  # TODO: 考虑 close 后 joinThread

  for i in 1..<g.loops.len:
    let loop = g.loops[i].addr
    createThread(loop.thread, runable, loop)

  g.loops[0].addr.runable()
    
  for i in 1..<g.loops.len:
    let loop = g.loops[i].addr
    joinThread(loop.thread)

when isMainModule:
  let g = createEventLoopGroup(4)

  g.exec(proc () = echo "hello")

  var socketChannel: SocketChannel
  
  block InitSocketChannel:
    socketChannel.handle = createNativeSocket()
    socketChannel.handle.bindAddr(Port(8080))
    socketChannel.handle.listen()

    socketChannel.loop = g.loops[2].addr # TODO: .loop() .loop(loopInstance) 
  
  socketChannel.accept()

  g.run()

proc exec*(loop: EventLoop) = 
  ## 使用事件循环 ``loop`` 执行一个异步任务。
  ## 
  ## 线程 A - 发送事件 (write efd1) -> loop
  ## loop - 接收事件 (epoll_wait read efd1) -> 执行任务
  ## loop - 发送事件 (write efd2) -> 线程 A
  ## 线程 A - 接收事件 (epoll_wait read efd2) -> 获取结果
  ## 
  ## 线程 A - loop 线程 [efd1, efd2]
  ## -> 线程 A 能够访问 loop 线程的 epoll fd
  ## -> 线程 A 通过 loop 线程的 epoll fd 注册 (epoll_ctl) efd1
  ## -> 
  ## -> loop 线程能够访问线程 A 的 epoll fd
  ## -> loop 线程通过线程 A 的 epoll fd 注册 (epoll_ctl) efd2
  discard

# { # loopA
#   efd1 = createefd()

#   loopX.selector.register(efd1)  
#   efd1.write(1)

#   this.loop.selector.select() {
#     efd2.eventdata {
#       ...
#       efd2.read()
#       efd2.close()
#     }
#   }
# }

# { # loopX
#   this.loop.selector.select() {
#     efd1.eventdata {
#       ...
#       efd1.read()
#       efd1.close()
#       efd2 = createefd()
#       resLoop.selector.register(efd2) 
#       efd2.write(1)
#     }
#   }
# }

