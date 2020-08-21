
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

      someWait MainThread.spawn((context) {
        someWait AnotherThread.spawn((context) {
        }, contextAnother)  

        doSomething()
      }, contextMain)

      doSomething()

  开始实施！

      MainThread.spawn((context) {
        AnotherThread.spawn((context) {
        }, contextAnother)  

        doSomething()

        AnotherThread.post((context) {
        }, contextAnother)
      }, contextMain)

      doSomething()

  先完成第 1 步，即基于 epoll pool 的线程池和 spawn 任务。

  TODO:

  紧接着要做两件事：用 spsc 代替 mpsc，只允许主线程分发任务，其他线程分发任务时，任务
                 总是由本线程完成；制定 ActionBase(context, fn) 和 
                 TaskBase(runner: ActionBase, callbacker: ActionBase)，无论是线程之间
                 还是 epoll loop 内部都使用这个对象处理任务。  
      
  # PromiseKind* {.pure.} = enum
  #   RUNNABLE, CALLABLE

  # Promise* = object
  #   context: pointer
  #   clean: proc (context: pointer) {.nimcall, gcsafe.}
  #   case kind: PromiseKind
  #   of PromiseKind.RUNNABLE:
  #     run: proc (context: pointer) {.nimcall, gcsafe.}
  #   of PromiseKind.CALLABLE:
  #     result: pointer
  #     call: proc (context: pointer): pointer {.nimcall, gcsafe.}
  #     then: proc (result: pointer) {.nimcall, gcsafe.}

]#

when not compileOption("threads"):
  {.error: "Threadpool requires --threads:on option.".}

import std/cpuinfo
import std/os
import std/posix

import netkit/collections/spsc
import netkit/collections/share/vecs
import netkit/collections/taskcounter
import netkit/collections/simplequeue
import netkit/posix/linux/selector
import netkit/aio/ident

type
  TaskBase* = object of RootObj
    run*: TaskProc

  Task*[T] = object of TaskBase
    value*: T

  TaskProc* = proc (r: ptr TaskBase) {.nimcall, gcsafe.}

  Future* = object
    publish: proc ()
    subscribe: proc ()
    finished: bool
    # error*: ref Exception
    # value: T   

  ActionBase* = object of RootObj
    future: ref Future
    run: ActionProc

  Action*[T] = object of ActionBase
    value*: T

  ActionProc* = proc (c: ref ActionBase) {.nimcall, gcsafe.}

  Worker = object
    id: int
    taskEventFd: cint
    taskCounter: TaskCounter
    taskQueue: SpscQueue[ptr TaskBase]
    ioSelector: Selector
    ioInterests: SharedVec[InterestData] # 散列 handle -> data
    ioIdentManager: IdentityManager

  InterestData = object
    fd: cint
    interest: Interest
    readQueue: SimpleQueue[ref ActionBase]
    writeQueue: SimpleQueue[ref ActionBase]
    readReady: bool
    has: bool

const
  MaxThreadPoolSize* {.intdefine.} = 256 ## Maximum size of the thread pool. 256 threads
                                         ## should be good enough for anybody ;-)

var
  workers: array[MaxThreadPoolSize, Thread[ptr Worker]]
  workersData: array[MaxThreadPoolSize, Worker]
  currentThreadPoolSize: int
  currentThreadId {.threadvar.}: int 
  recursiveThreadId: int

when defined(PinToCpu):
  gCpus: Natural

proc spawn*(r: ptr TaskBase) =
  assert currentThreadPoolSize > 1
  if currentThreadId == 0:
    r.run(r)
  else:
    recursiveThreadId = recursiveThreadId mod (currentThreadPoolSize - 1) + 1
    workersData[recursiveThreadId].taskQueue.add(r)

proc registerTaskCounter(fd: cint): Identity =
  let w = workersData[currentThreadId].addr
  result = w.ioIdentManager.acquire()
  assert w.ioInterests.len > result.int
  var interest = initInterest()
  interest.registerReadable()
  let data = w.ioInterests[result.int].addr
  data.fd = fd
  data.interest = interest
  data.has = true
  w.ioSelector.register(fd, UserData(u64: result.uint64), interest)

proc run*(w: ptr Worker) {.thread.} =
  currentThreadId = w.id

  template handleTaskEvent() =
    w.taskQueue.sync()
    while w.taskQueue.len > 0:
      let task = w.taskQueue.take()
      task.run(task)

  template handleIOEvent(node: ref SimpleNode[ref ActionBase]) =
    node.val.run(node.val)

  let taskCounterIdent = registerTaskCounter(w.taskEventFd)
  var events = newSeq[Event](128) # TODO: 考虑 events 的容量；使用 Vec -> newSeq；Event kind # 考虑使用 thread local heap?
  while true:
    let count = w.ioSelector.select(events, -1) # TODO: 考虑 select 超时；考虑 count <= 0
    for i in 0..<count:
      let event = events[i]
      if event.data.u64 == taskCounterIdent.uint64:
        if event.isReadable: # read eventfd 应该不会出现错误 (否则，是一个 fatal error or program error)
          handleTaskEvent()
        else:
          raise newException(Defect, "bug， 不应该遇到这个错误")
      else:
        let data = w.ioInterests[event.data.u64].addr
        if event.isReadable or event.isError:
          echo "isReadable or isError...", data.readQueue.len, " [", currentThreadId, "]"
          for node in data.readQueue.nodesByPop():
            handleIOEvent(node)
        if event.isWritable or event.isError:
          echo "isWritable or isError...", data.writeQueue.len, " [", currentThreadId, "]"
          for node in data.writeQueue.nodesByPop():
            handleIOEvent(node)

proc register*(fd: cint): Identity =
  let w = workersData[currentThreadId].addr
  let interest = initInterest()
  result = w.ioIdentManager.acquire()
  if w.ioInterests.len <= result.int:
    w.ioInterests.resize(w.ioInterests.len * 2)
  let data = w.ioInterests[result.int].addr
  data.fd = fd
  data.interest = interest
  data.readQueue = initSimpleQueue[ref ActionBase]()
  data.writeQueue = initSimpleQueue[ref ActionBase]()
  data.readReady = false
  data.has = true
  w.ioSelector.register(fd, UserData(u64: result.uint64), interest)

proc unregister*(ident: Identity) =
  let w = workersData[currentThreadId].addr
  let data = w.ioInterests[ident.int].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  reset(w.ioInterests[ident.int]) 
  w.ioSelector.unregister(data.fd)
  w.ioIdentManager.release(ident)

proc unregisterReadable*(ident: Identity) =
  let w = workersData[currentThreadId].addr
  let data = w.ioInterests[ident.int].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  if data.interest.isReadable():
    data.interest.unregisterReadable()
    w.ioSelector.update(data.fd, UserData(u64: ident.uint64), data.interest)

proc unregisterWritable*(ident: Identity) =
  let w = workersData[currentThreadId].addr
  let data = w.ioInterests[ident.int].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  if data.interest.isWritable():
    data.interest.unregisterWritable()
    w.ioSelector.update(data.fd, UserData(u64: ident.uint64), data.interest)

proc updateRead*(ident: Identity, c: ref ActionBase) =
  let w = workersData[currentThreadId].addr
  let data = w.ioInterests[ident.int].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  data.readQueue.addLast(newSimpleNode[ref ActionBase](c))
  if not data.interest.isReadable():
    data.interest.registerReadable()
    w.ioSelector.update(data.fd, UserData(u64: ident.uint64), data.interest)

proc updateWrite*(ident: Identity, c: ref ActionBase) =
  let w = workersData[currentThreadId].addr
  let data = w.ioInterests[ident.int].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  data.writeQueue.addLast(newSimpleNode[ref ActionBase](c))
  if not data.interest.isWritable():
    data.interest.registerWritable()
    w.ioSelector.update(data.fd, UserData(u64: ident.uint64), data.interest)

proc runLoop*() =
  # 启动流水线
  for i in 1..<currentThreadPoolSize:
    createThread(workers[i], run, workersData[i].addr)
    when defined(PinToCpu):
      assert gCpus > 0
      pinToCpu(workers[i], i mod gCpus)
  run(workersData[0].addr)
  for i in 1..<currentThreadPoolSize:
    joinThread(workers[i]) 

proc setup() =
  let cpus = countProcessors()
  when defined(PinToCpu):
    gCpus = cpus
  currentThreadPoolSize = min(cpus, MaxThreadPoolSize)
  
  for i in 0..<currentThreadPoolSize:
    let w = workersData[i].addr
    w.id = i
    w.taskEventFd = eventfd(0, 0)
    if w.taskEventFd < 0:
      raiseOSError(osLastError())
    w.taskCounter = initTaskCounter(w.taskEventFd)
    w.taskQueue = initSpscQueue[ptr TaskBase](w.taskCounter.addr, 4096)
    w.ioSelector = initSelector()
    w.ioInterests.init(4096)
    w.ioIdentManager.init()

setup()

when isMainModule:
  # type
  #   MyTask = object of TaskBase
  #     val: int

  # proc destroy(r: ptr MyTask) =
  #   deallocShared(r)

  # var num = 0

  # proc runMyTask(r: ptr TaskBase) =
  #   # num.inc()
  #   atomicInc(num)
  #   echo "Worker id: ", currentThreadId, " val: ", cast[ptr MyTask](r).val
  #   echo num
  #   cast[ptr MyTask](r).destroy()

  # proc createMyTask(val: int): ptr MyTask =
  #   result = cast[ptr MyTask](allocShared0(sizeof(MyTask)))
  #   result.val = val
  #   result.run = runMyTask

  type
    ReadContext = object 
      val: int

    WriteContext = object
      val: int

    WriteData = object 
      val: int

  var channel: array[2, cint]
  discard pipe(channel)

  proc runReadAction(r: ref ActionBase) =
    var buffer = newString(1024)
    if channel[0].read(buffer.cstring, buffer.len) < 0:
      raiseOSError(osLastError())
    echo buffer

  proc runReadTask(r: ptr TaskBase) =
    echo "Worker id: ", currentThreadId, " val: ", cast[ptr Task[ReadContext]](r).value.val
    var ident = register(channel[0])
    var callable = new(ActionBase)
    callable.run = runReadAction
    updateRead(ident, callable)
    deallocShared(cast[ptr Task[ReadContext]](r))

  proc createReadTask(val: int): ptr Task[ReadContext] =
    result = cast[ptr Task[ReadContext]](allocShared0(sizeof(Task[ReadContext])))
    result.value.val = val
    result.run = runReadTask

  proc runWriteAction(r: ref ActionBase) =
    var buffer = "hello " & $((ref Action[WriteData])(r).value.val)
    if channel[1].write(buffer.cstring, buffer.len) < 0:
      raiseOSError(osLastError())

  proc runWriteTask(r: ptr TaskBase) =
    echo "Worker id: ", currentThreadId, " val: ", cast[ptr Task[WriteContext]](r).value.val
    var ident = register(channel[1])
    var callable = new(Action[WriteData])
    callable.run = runWriteAction
    callable.value.val = cast[ptr Task[WriteContext]](r).value.val
    updateWrite(ident, callable)
    deallocShared(cast[ptr Task[WriteContext]](r))

  proc createWriteTask(val: int): ptr Task[WriteContext] =
    result = cast[ptr Task[WriteContext]](allocShared0(sizeof(Task[WriteContext])))
    result.value.val = val
    result.run = runWriteTask

  # 测试
  # for i in 0..<1000:
  #   spawn(createMyTask(i))
  spawn(createReadTask(1))
  spawn(createWriteTask(2))

  runLoop()