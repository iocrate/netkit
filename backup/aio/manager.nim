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

type
  # TODO: 考虑全局变量；考虑主线程的 Loop (其线程不需要设置)；考虑获取当前 Loop 的状态
  EventLoop* = object
    ## 循环包括两个操作：
    ## - 任务 (1) 添加任务 （2）执行任务（3）反馈任务
    ## - 委派/委托 -> 任务 （1）发送委派（2）接收委派（3）交付委派
    id*: EventLoopId # TODO 使用 EventLoopId = distinct int
    thread: Thread[EventLoopId] 
    pipe: array[2, cint] # TODO: 使用 PipeChannel 
    selector: Selector
    interests: SharedVec[InterestData] # 散列 handle -> data

  EventLoopId* = distinct int

  InterestData = object
    interest: Interest
    readHead: pointer # TODO: ptr Task 
    readTail: pointer # TODO: ptr Task 
    writeHead: pointer # TODO: ptr Task
    writeTail: pointer # TODO: ptr Task

  # Delegate = object
  #   code: DelegateCode
  #   task: pointer # TODO: ptr Task
  
  # DelegateCode {.pure, size: sizeof(uint8).} = enum
  #   Request, Response

const 
  InvalidEventLoopId* = EventLoopId(-1)

proc `=destroy`*(x: var EventLoop) {.raises: [OSError].} = 
  if int(x.id) > 0:
    if x.pipe[0].close() < 0:
      raiseOSError(osLastError())
    if x.pipe[1].close() < 0:
      raiseOSError(osLastError())
    x.selector.close()
    `=destroy`(x.interests)
    # joinThread(x.thread) TODO: 考虑线程清理

proc init(x: var EventLoop, id: Natural) {.raises: [OSError].} = 
  `=destroy`(x)
  x.id = EventLoopId(id)
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

proc getEventLoop*(id: EventLoopId): lent EventLoop =
  gManager.loops[int(id)]

proc round*(): EventLoopId = 
  result = EventLoopId(gManager.cursor) 
  gManager.cursor = (gManager.cursor + 1) mod gManager.loops.len

var eventLoopId* {.threadvar.}: EventLoopId

proc current*(): EventLoopId = 
  result = eventLoopId

proc runable(loop: EventLoopId) {.thread.} =
  eventLoopId = loop
  echo "EventLoopId: ", int(current())

  var events = newSeq[Event](128)
  while true:
    let count = gManager.loops[int(loop)].selector.select(events, -1)
    for i in 0..<count:
      discard

proc run() = 
  # TODO: 考虑主线程 loop 直接 runable(loop)
  # TODO: 考虑 close 后 joinThread

  for i in 1..<gManager.loops.len:
    let loop = gManager.loops[i].addr
    createThread(loop.thread, runable, EventLoopId(i))

  runable(EventLoopId(0))
    
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
