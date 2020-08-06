
#[ 
  
  基于 epoll w 的线程池，类似一个流水线工厂。每一个流水线都是隔离的，线性地运转着。主流水线可以通过一条总线
  给其他流水线推送箱子。各流水线在每次循环的时候，查看自己的仓库是否有箱子需要运走。箱子装着需要处理的任务和相关
  的数据。
  
  我觉得是这样：

  只有主线程能够 spawn 任务给其他线程，在其他线程内部 spawn 任务给另一个线程，这是很无聊的事情，对吧？

      MainThread.spawn((contextMain) {
        AnotherThread.spawn((contextAnother) {
        })  
      })

  这对性能并没有任何帮助，不是吗？spawn 的本质就是为了将任务分散地分布在各个线程，由主线程来做这个任务就足够了。

  那么，怎么能保证 spawn 的 API 调用足够灵活而又逻辑按着这个想法进行呢？我认为是这样：

  1. spawn() 调用时，检查当前线程，如果当前线程是主线程，则从线程池 select 一个工作线程，将任务交给这个线程；
      如果当前线程不是主线程，则将任务交给当前线程。

  这样就能保证 spawn() 的完美运行。Good job!

  还有一个需要解决的小任务！什么任务？

  我们可能希望能 (异步地) 等待 (同步) 任务执行，当任务完成后，发起线程能准确知道该任务完成，然后可以执行某些特定操作。

      someWait MainThread.spawn((contextMain) {
        someWait AnotherThread.spawn((contextAnother) {
        })  

        doSomething()
      })

      doSomething()

  开始实施！

  先完成第 1 步，即基于 epoll pool 的线程池和 spawn 任务。

  
]#

import std/cpuinfo
import std/os
import std/posix

import netkit/collections/mpsc
import netkit/collections/share/vecs
import netkit/posix/linux/selector
import netkit/aio/ident

proc eventfd*(initval: cuint, flags: cint): cint {.
  importc: "eventfd", 
  header: "<sys/eventfd.h>"
.}

type
  TaskCounter = object of SigCounter
    fd: cint

proc signalTaskCounter(c: ptr SigCounter) = 
  var buf = 1'u64
  if cast[ptr TaskCounter](c).fd.write(buf.addr, sizeof(buf)) < 0:
    raiseOSError(osLastError()) # TODO: 考虑 errorno == Enter, EAGAIN, EWOULDBLOCK

proc waitTaskCounter(c: ptr SigCounter): Natural = 
  var buf = 0'u64
  if cast[ptr TaskCounter](c).fd.read(buf.addr, sizeof(buf)) < 0:
    raiseOSError(osLastError())
  result = buf # TODO: u64 -> int 考虑溢出；考虑 errorno == Enter, EAGAIN, EWOULDBLOCK

type
  Task = object of RootObj
    context: pointer
    run: proc (ctx: pointer) {.nimcall, gcsafe.}
    feedback: proc () {.nimcall, gcsafe.}

proc createTask(
  context: pointer,
  run: proc (ctx: pointer) {.nimcall, gcsafe.},
  # feedback: proc () {.nimcall, gcsafe.}
): ptr Task =
  result = cast[ptr Task](allocShared0(sizeof(Task)))
  result.context = context
  result.run = run

proc destroy(t: ptr Task) =
  deallocShared(t)

type
  Worker = object
    id: int
    taskEventFd: cint
    taskCounter: TaskCounter
    taskQueue: MpscQueue[ptr Task]
    selector: Selector
    interests: SharedVec[InterestData] # 散列 handle -> data
    identManager: IdentityManager

  InterestData = object
    interest: Interest
    readReady: bool

const
  MaxThreadPoolSize* {.intdefine.} = 256 ## Maximum size of the thread pool. 256 threads
                                         ## should be good enough for anybody ;-)
  MaxDistinguishedThread* {.intdefine.} = 32 ## Maximum number of "distinguished" threads.

var
  workers: array[MaxThreadPoolSize, Thread[ptr Worker]]
  workersData: array[MaxThreadPoolSize, Worker]
  currentPoolSize: int
  currentThreadId {.threadvar.}: int 
  recursiveThreadId: int

when defined(nimPinToCpu):
  var gCpus: Natural

proc spawn(
  context: pointer,
  run: proc (ctx: pointer) {.nimcall, gcsafe.}
) {.compilerProc.} =
  assert currentPoolSize > 1
  recursiveThreadId = recursiveThreadId mod (currentPoolSize - 1) + 1
  workersData[recursiveThreadId].taskQueue.add(createTask(context, run))

proc run(w: ptr Worker) {.thread.} =
  echo "Start Thread: ", w.id
  currentThreadId = w.id

  # interest 表注册 ([文件描述符 -> ident] - 感兴趣的数据 (缓存))
  # selector 注册 (文件描述符 - ident, 感兴趣的事件)
  var identEventFd = w.identManager.acquire()
  var interest = initInterest()
  interest.registerReadable()
  w.selector.register(w.taskEventFd, UserData(u64: identEventFd.uint64), interest)
  var data = InterestData(
    interest: interest
  )
  w.interests[identEventFd.int] = data

  # TODO: 考虑 events 的容量；使用 Vec -> newSeq；Event kind
  # 考虑使用 thread local heap?
  var events = newSeq[Event](128)
  while true:
    # TODO: 考虑 select 超时
    let count = w.selector.select(events, -1)
    for i in 0..<count:
      let event = events[i].addr
      if event[].data.u64 == identEventFd.uint64:
        # read eventfd 应该不会出现错误 (否则，是一个 fatal error or program error)
        # read eventfd 应该只有 readable
        if event[].isReadable:
          w.taskQueue.sync()
          while w.taskQueue.len > 0:
            var task = w.taskQueue.take()
            task.run(task.context)
            task.destroy()
        else:
          raise newException(Defect, "bug， 不应该遇到这个错误")
      else:
        discard

proc startWorkerThread(i: int) {.noinline.} =
  workersData[i].id = i

  workersData[i].taskEventFd = eventfd(0, 0)
  if workersData[i].taskEventFd < 0:
    raiseOSError(osLastError())
  workersData[i].taskCounter = TaskCounter(
    fd: workersData[i].taskEventFd,
    signalImpl: signalTaskCounter,
    waitImpl: waitTaskCounter
  )
  workersData[i].taskQueue = initMpscQueue[ptr Task](workersData[i].taskCounter.addr, 4096)

  workersData[i].selector = initSelector()
  workersData[i].interests.init(4096)
  workersData[i].identManager.init()

  createThread(workers[i], run, workersData[i].addr)
  when defined(nimPinToCpu):
    if gCpus > 0: 
      pinToCpu(workers[i], i mod gCpus)

type
  MyContext = object
    val: int

proc createMyContext(val: int): ptr MyContext =
  result = cast[ptr MyContext](allocShared0(sizeof(Task)))
  result.val = val

proc destroy(context: ptr MyContext) =
  deallocShared(context)

var num = 0

proc runMyContext(ctx: pointer) =
  echo "Worker id: ", currentThreadId, " val: ", cast[ptr MyContext](ctx).val
  num.inc()
  echo num
  cast[ptr MyContext](ctx).destroy()

proc setup() =
  let cpus = countProcessors()
  when defined(nimPinToCpu):
    gCpus = cpus
  currentPoolSize = min(cpus, MaxThreadPoolSize)
  
  # 启动流水线
  for i in 0..<currentPoolSize: 
    startWorkerThread(i)
  
  # 测试
  for i in 0..<1000:
    spawn(createMyContext(i), runMyContext)
  
  # 等待流水线完成工作 (虽然流水线直到某个特定信号前不会停止)
  joinThreads(workers)

setup()
