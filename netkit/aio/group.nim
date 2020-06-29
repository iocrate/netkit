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
import netkit/collections/vec

type
  EventLoopGroup* = object 
    loops: SharedVec[EventLoop]

  # TODO: 考虑全局变量；考虑主线程的 Loop (其线程不需要设置)；考虑获取当前 Loop 的状态
  EventLoop* = object
    id: Natural
    group: ptr EventLoopGroup 
    thread: Thread[ptr EventLoop] 
    delegator: array[2, cint] # TODO: 使用 PipeChannel 
    selector: Selector
    interests: SharedVec[InterestData] # TODO: 考虑散列 [] 增长缩小，handle -> data

  InterestData = object
    interest: Interest
    readHead: pointer # TODO: ptr Task 
    readTail: pointer # TODO: ptr Task 
    writeHead: pointer # TODO: ptr Task
    writeTail: pointer # TODO: ptr Task

  Delegate = object
    code: DelegateCode
    task: pointer # TODO: ptr Task
  
  DelegateCode {.pure, size: sizeof(uint8).} = enum
    Request, Response

proc `=destroy`*(x: var EventLoop) {.raises: [OSError].} = 
  if x.id > 0:
    if x.delegator[0].close() < 0:
      raiseOSError(osLastError())
    if x.delegator[1].close() < 0:
      raiseOSError(osLastError())
    x.selector.close()
    `=destroy`(x.interests)

proc createEventLoop(g: ptr EventLoopGroup, id: Natural): EventLoop {.raises: [OSError].} = 
  # TODO: 考虑 ptr EventLoopGroup 为全局变量
  result.id = id
  result.group = g
  result.selector = initSelector() 
  result.interests = createSharedVec[InterestData](1024) # TODO: 使用 ptr；考虑散列 [] 增长缩小，handle -> data
  if pipe(result.delegator) < 0:
    raiseOSError(osLastError())

proc sendDelegate*(loop: ptr EventLoop, task: pointer) {.raises: [OSError].} = 
  # TODO: 考虑提供 ref 或者 object API
  var dlg = cast[ptr Delegate](allocShared0(sizeof(Delegate)))
  dlg.code = DelegateCode.Request
  dlg.task = task
  var buffer: uint64 = cast[ByteAddress](dlg).uint64
  if loop.delegator[1].write(buffer.addr, sizeof(uint64)) < 0: # TODO: 考虑 errorno enter,eagain,ewouldblock,...
    raiseOSError(osLastError())

proc deliverDelegate*(loop: ptr EventLoop, task: pointer) {.raises: [OSError].} = 
  # TODO: 考虑提供 ref 或者 object API
  var dlg = cast[ptr Delegate](allocShared0(sizeof(Delegate)))
  dlg.code = DelegateCode.Response
  dlg.task = task
  var buffer: uint64 = cast[ByteAddress](dlg).uint64
  if loop.delegator[1].write(buffer.addr, sizeof(uint64)) < 0: # TODO: 考虑 errorno enter,eagain,ewouldblock,...
    raiseOSError(osLastError())

proc recvDelegate*(loop: ptr EventLoop): ptr Delegate {.raises: [OSError].} = 
  # TODO: 考虑提供 ref 或者 object API
  var buffer: uint64
  if loop.delegator[0].read(buffer.addr, sizeof(uint64)) < 0: # TODO: 考虑 errorno enter,eagain,ewouldblock,...
    raiseOSError(osLastError())
  cast[ptr Delegate](buffer)

proc createEventLoopGroup(n: Natural): ptr EventLoopGroup =
  result = cast[ptr EventLoopGroup](allocShared0(sizeof(EventLoopGroup)))
  result.loops = createSharedVec[EventLoop](n)
  for i in 0..<n:
    result.loops[i] = createEventLoop(result, i)

proc close(g: ptr EventLoopGroup) = 
  `=destroy`(g.loops)
  deallocShared(g)

# import deques

# type
#   IdGenerator = object
#     data: seq[pointer]
#     curr: int
#     reclaimed: Deque[int]

# proc getId(ig: var IdGenerator): int =
#   if ig.reclaimed.len > 0:
#     return ig.reclaimed.popFirst()
#   result = ig.curr
#   ig.curr.inc()

# proc close(ig: var IdGenerator, id: int) =
#   ig.reclaimed.addLast(id)
#   ig.data[id] = nil

# var ig = IdGenerator(reclaimed: initDeque[int]())

# for i in 0..10:
#   echo ig.getId()

# ig.close(6)
# ig.close(3)
# ig.close(1)

# echo ig.getId()
# echo ig.getId()
# echo ig.getId()
# echo ig.getId()
# echo ig.getId()
# echo ig.getId()

import deques

var a: Deque[int]

a.addLast 100
echo a[0]
 