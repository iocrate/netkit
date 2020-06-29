#[
  
                ========= 
                LoopGroup
                =========
                    ↑
                    |    [EventDataTable] 发起者
         Thread ←→ Loop ←-------------------------------------------+ 
                    ↑                                               |
                    | 执行者                                         |
                    |                                    ========================
                  Channel ←-----------------------------           Task [Promise]
                    ↑                                               ↑
      +-------------+-------------+---------+              +------+-----+-----+
      |             |             |         |              |      |     |     |
  SocketChannel  PipeChannel  FileChannel   ...          Accept  Recv  Send  ...
                                                         ========================

  Call:

    Loop::Local

      >> create Task
      >> register or update

    Loop::Remote

      >> create Task
      >> write Notify::Request 

  Loop:

    Event::Local[Channel]: (event.data.fd == 2 ...)

      >> cast [Task] -> Task
         case Task.code

      >> check Task.loop == Local.loop
         -> run Waker::Local  (Promise)
         -> run Waker::Remote (Task.loop.write Notify::Response)

    Event::Remote[Pipe]:   (event.data.fd == 0 | 1)

      >> cast [Notify] -> Notify
         case Notify.code
         -> run Notify::Request  (Task)
         -> run Notify::Response (Promise)
]#

# Now 
#
#   2020-06-05 09:31 - 创建一个小的异步操作原型: 执行一次异步函数的演示，以形成基本模型。
#   2020-06-05 10:46 - 创建一个小的套接字读操作原型。
#   TODO - 创建一个小的异步操作原型: 执行一次异步文件读的演示，以形成基本模型。

import netkit/posix/linux/selector
import netkit/posix/linux/socket
import std/posix
import std/os

import netkit/misc
import netkit/collections/share/vecs
import netkit/aio/ident
import netkit/aio/task

type
  # TODO: 考虑全局变量；考虑主线程的 Loop (其线程不需要设置)；考虑获取当前 Loop 的状态
  EventLoop* = object
    ## 循环包括两个操作：
    ## - 任务 (1) 添加任务 （2）执行任务（3）反馈任务
    ## - 委派/委托 -> 任务 （1）发送委派（2）接收委派（3）交付委派
    id*: int # TODO 使用 EventLoopId = distinct int
    thread: Thread[int] 
    pipe: array[2, cint] # TODO: 使用 PipeChannel 
    selector: Selector
    interests: SharedVec[InterestData] # 散列 handle -> data
    identManager: IdentityManager

  EventLoopId* = distinct int

  InterestData = object
    interest: Interest
    readReady: bool
    readHead: ptr Task 
    readTail: ptr Task  
    writeReady: bool
    writeHead: ptr Task 
    writeTail: ptr Task 

  Delegate = object
    code: DelegateCode
    task: ptr Task 
  
  DelegateCode {.pure, size: sizeof(uint8).} = enum
    Request, Response

proc `=destroy`*(x: var EventLoop) {.raises: [OSError].} = 
  if int(x.id) > 0:
    if x.pipe[0].close() < 0:
      raiseOSError(osLastError())
    if x.pipe[1].close() < 0:
      raiseOSError(osLastError())
    x.selector.close()
    `=destroy`(x.interests)
    `=destroy`(x.identManager)
    # joinThread(x.thread) TODO: 考虑线程清理

proc init(x: var EventLoop, id: Natural) {.raises: [OSError].} = 
  `=destroy`(x)
  x.id = int(id)
  x.selector = initSelector() 
  x.interests.init(1024) # TODO: 使用 ptr；考虑散列 [] 增长缩小，handle -> data
  if pipe(x.pipe) < 0:
    raiseOSError(osLastError())

type
  EventLoopManager* = object 
    loops: SharedVec[EventLoop]
    cursor: int

const
  EventLoopCores* {.intDefine.} = 0

proc `=destroy`(x: var EventLoopManager) = 
  `=destroy`(x.loops)

proc init(x: var EventLoopManager) =
  `=destroy`(x)
  x.loops.init(8) # TODO
  for i in 0..<8:
    x.loops[i].init(i)

var gManager: EventLoopManager

proc getEventLoop*(id: int): lent EventLoop =
  gManager.loops[int(id)]

proc round*(): int = 
  result = int(gManager.cursor) 
  gManager.cursor = (gManager.cursor + 1) mod gManager.loops.len

var eventLoopId* {.threadvar.}: int

proc current*(): int = 
  result = eventLoopId

# proc runable(loop: int) {.thread.} =
#   eventLoopId = loop
#   echo "int: ", int(current())

#   var events = newSeq[Event](128)
#   while true:
#     let count = gManager.loops[int(loop)].selector.select(events, -1)
#     for i in 0..<count:
#       discard

proc runable(loopId: int) {.thread.} =
  eventLoopId = loopId
  echo "EventLoop Id: ", int(current())
  var loop = gManager.loops[eventLoopId]

  var interest = initInterest()
  interest.registerReadable()
  
  loop.selector.register(loop.pipe[0], UserData(fd: loop.pipe[0]), interest)

  var interest2 = initInterest()
  interest.registerWritable()
  loop.selector.register(loop.pipe[1], UserData(fd: loop.pipe[1]), interest2)

  # TODO: 考虑 events 的容量；使用 Vec -> newSeq；Event kind
  var events = newSeq[Event](128)
  while true:
    let count = loop.selector.select(events, -1)
    for i in 0..<count:
      let event = events[i].addr
      if event[].data.fd == loop.pipe[0]:
        if event[].isReadable:
          discard
        if event[].isError:
          raise newException(Defect, "bug， 不应该遇到这个错误")
      elif event[].data.fd == loop.pipe[1]:
        if event[].isWritable:
          discard
        if event[].isError:
          raise newException(Defect, "bug， 不应该遇到这个错误")
      else:
        discard
      if event[].isError:
        if event[].data.fd == loop.pipe[0]:
          discard
        elif event[].data.fd == loop.pipe[1]:
          discard
        else:
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
          if ctx.code == TaskCode.NotifyExec:
            ctx.cb()
            deallocShared(ctx)
            echo "-------------------------"
          else:
            var notify = cast[ptr NotifyTask](buffer)
            case notify.task.code
            of TaskCode.Accept:
              var taskNotify = cast[ptr AcceptTask](notify.task)
              var data: ptr EventData
              if loop.dataPool[taskNotify.channel.handle.cint] == nil:
                data = cast[ptr EventData](allocShared0(sizeof(EventData)))
                data.interest = initInterest()
                data.interest.registerReadable()
                loop.dataPool[taskNotify.channel.handle.cint] = data

                # TODO: 只有本地 loop 才允许直接添加
                loop.selector.register(taskNotify.channel.handle.cint, UserData(data: data), data.interest)
              
              if data.readHead == nil:
                data.readHead = taskNotify
                data.readTail = taskNotify
              else:
                data.readTail.next = taskNotify
                data.readTail = taskNotify
            else:
              discard
        elif event[].data.u64 == 2:
          discard
        else:
          var data = cast[ptr EventData](event[].data.data)
          var task = data.readHead
          while task != nil:
            echo "code:", $task.code
            case task.code
            of TaskCode.Accept:
              var task = cast[ptr AcceptTask](task)
              echo "[Loop ", loop.id, "] loop.accept isReadable"
              var sockAddress: Sockaddr_storage
              var addrLen = sizeof(sockAddress).SockLen
              var client = socket.accept4(
                task.channel.handle,
                cast[ptr SockAddr](addr(sockAddress)), 
                addr(addrLen), 
                SOCK_NONBLOCK or socket.SOCK_CLOEXEC
              ) # TODO: 错误
              
              var clientChannel: SocketChannel
              clientChannel.handle = client
              # clientChannel.loop = loop() TODO

              # TODO: callback task.promise.setValue(TcpStream(inner: client))
              # promise.setValue(TcpStream(inner: client))
              
              # TODO: 判断是否 loop 相同
              #   if task.loop != getCurrentLoop():
              #     write pipe
              # let ctx = cast[ptr CallableContext](allocShared0(sizeof(CallableContext)))
              # ctx.cb = cb
              # var buffer: uint64 = cast[ByteAddress](ctx).uint64
              # if task.loop.pipe[1].write(buffer.addr, sizeof(uint64)) < 0: # TODO: 考虑 errorno enter,eagain,ewouldblock,...
              #   raiseOSError(osLastError())
              # echo repr client
              echo "-------------------------"
            of TaskCode.NotifyRequest:
              var buffer: uint64
              if loop.pipe[0].read(buffer.addr, sizeof(uint64)) < 0: # TODO: 考虑 errorno enter,eagain,ewouldblock,...
                raiseOSError(osLastError())
              var notify = cast[ptr NotifyTask](buffer)
              case notify.task.code
              of TaskCode.Accept:
                var taskNotify = cast[ptr AcceptTask](notify.task)
                var data: ptr EventData
                if loop.dataPool[taskNotify.channel.handle.cint] == nil:
                  data = cast[ptr EventData](allocShared0(sizeof(EventData)))
                  data.interest = initInterest()
                  data.interest.registerReadable()
                  loop.dataPool[taskNotify.channel.handle.cint] = data

                  # TODO: 只有本地 loop 才允许直接添加
                  loop.selector.register(taskNotify.channel.handle.cint, UserData(data: data), data.interest)
                
                if data.readHead == nil:
                  data.readHead = taskNotify
                  data.readTail = taskNotify
                else:
                  data.readTail.next = taskNotify
                  data.readTail = taskNotify
              else:
                discard
            of TaskCode.NotifyResponse:
              discard
            else:
              discard
            task = task.next
      if event[].isWriteClosed:
        discard
      if event[].isWritable:
        discard

proc run() = 
  # TODO: 考虑主线程 loop 直接 runable(loop)
  # TODO: 考虑 close 后 joinThread

  for i in 1..<gManager.loops.len:
    let loop = gManager.loops[i].addr
    createThread(loop.thread, runable, int(i))

  runable(int(0))
    
  for i in 1..<gManager.loops.len:
    let loop = gManager.loops[i].addr
    joinThread(loop.thread)

# TODO: 添加编译选项
gManager.init()
run()

# proc sendDelegate*(loop: ptr EventLoop, task: pointer) {.raises: [OSError].} = 
#   # TODO: 考虑提供 ref 或者 object API
#   var dlg = cast[ptr Delegate](allocShared0(sizeof(Delegate)))
#   dlg.code = DelegateCode.Request
#   dlg.task = task
#   var buffer: uint64 = cast[ByteAddress](dlg).uint64
#   if loop.pipe[1].write(buffer.addr, sizeof(uint64)) < 0: # TODO: 考虑 errorno enter,eagain,ewouldblock,...
#     raiseOSError(osLastError())

# proc deliverDelegate*(loop: ptr EventLoop, task: pointer) {.raises: [OSError].} = 
#   # TODO: 考虑提供 ref 或者 object API
#   var dlg = cast[ptr Delegate](allocShared0(sizeof(Delegate)))
#   dlg.code = DelegateCode.Response
#   dlg.task = task
#   var buffer: uint64 = cast[ByteAddress](dlg).uint64
#   if loop.pipe[1].write(buffer.addr, sizeof(uint64)) < 0: # TODO: 考虑 errorno enter,eagain,ewouldblock,...
#     raiseOSError(osLastError())

# proc recvDelegate*(loop: ptr EventLoop): ptr Delegate {.raises: [OSError].} = 
#   # TODO: 考虑提供 ref 或者 object API
#   var buffer: uint64
#   if loop.pipe[0].read(buffer.addr, sizeof(uint64)) < 0: # TODO: 考虑 errorno enter,eagain,ewouldblock,...
#     raiseOSError(osLastError())
#   cast[ptr Delegate](buffer)

# proc createEventLoopManager(n: Natural): ptr EventLoopManager =
#   result = cast[ptr EventLoopManager](allocShared0(sizeof(EventLoopManager)))
#   result.loops = createSharedVec[EventLoop](n)
#   for i in 0..<n:
#     result.loops[i] = createEventLoop(result, i)

# proc close(g: ptr EventLoopManager) = 
#   `=destroy`(g.loops)
#   deallocShared(g)
