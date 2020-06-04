import netkit/posix/linux/selector
import netkit/posix/linux/socket
import netkit/future
import posix
import os
import nativesockets

import netkit/misc
import netkit/collections/vec

# file -> loop -> thread -> looppool

type
  EventLoopGroup = object # TODO
    loops: SharedVec[EventLoop]

  EventLoop = object
    id: int
    group: ptr EventLoopGroup # TODO
    thread: Thread[ptr EventLoop] # TODO Context
    selector: Selector

proc createEventLoopGroup(n: Natural): ptr EventLoopGroup =
  result = cast[ptr EventLoopGroup](allocShared0(sizeof(EventLoopGroup)))
  result.loops = createSharedVec[EventLoop](n)
  for i in 0..<n:
    let loop = result.loops[i].addr
    loop.id = i
    loop.group = result
    loop.selector = initSelector() # TODO: 考虑参数

proc close(g: ptr EventLoopGroup) = 
  `=destroy`(g.loops)
  deallocShared(g)

proc loopRunable(loop: ptr EventLoop) {.thread.} =
  echo "Thread: ", loop.id
  var events = newSeq[Event](128)
  while true:
    let count = loop.selector.select(events, -1)
    for i in 0..<count:
      let event = events[i].addr
      echo "..."

proc run(g: ptr EventLoopGroup) = 
  for i in 0..<g.loops.len:
    let loop = g.loops[i].addr
    createThread(loop.thread, loopRunable, loop)
    
  for i in 0..<g.loops.len:
    let loop = g.loops[i].addr
    joinThread(loop.thread)

when isMainModule:
  let g = createEventLoopGroup(4)
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

