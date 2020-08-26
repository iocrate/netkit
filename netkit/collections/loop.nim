
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
  {.error: "EventLoopPool requires --threads:on option.".}

import std/cpuinfo
import std/os
# import std/locks

import netkit/collections/taskcounter
import netkit/collections/task
import netkit/collections/action
import netkit/aio/ident

const
  MaxEventLoopPoolSize* {.intdefine.} = 256 ## Maximum size of the event loop pool. 
  InitialTaskRegistrySize* {.intdefine.} = 4096
  InitialActionRegistrySize* {.intdefine.} = 4096
  EventLoopTimeout* {.intdefine.} = 500

type
  EventLoop* = object
    id: Natural
    taskCounterFd: cint
    taskRegistry: TaskRegistry
    actionRegistry: ActionRegistry

  EventLoopPool* = object
    threads: array[MaxEventLoopPoolSize, Thread[Natural]]
    eventLoops: array[MaxEventLoopPoolSize, EventLoop]
    capacity: Natural
    recursiveEventLoopId: Natural
    cpus: Natural
    state: EventLoopPoolState

  EventLoopPoolState* {.pure.} = enum
    IDLE, RUNNING, SHUTDOWN

proc initEventLoop(id: int): EventLoop {.raises: [OSError].} =
  result.id = id
  result.taskCounterFd = eventfd(0, 0)
  if result.taskCounterFd < 0:
    raiseOSError(osLastError())
  result.taskRegistry = initTaskRegistry(result.taskCounterFd, InitialTaskRegistrySize)
  result.actionRegistry = initActionRegistry(InitialActionRegistrySize)

proc initEventLoopPool(): EventLoopPool =
  result.cpus = countProcessors()
  result.capacity = min(result.cpus, MaxEventLoopPoolSize)
  # initLock(workersLock)
  for i in 0..<result.capacity:
    result.eventLoops[i] = initEventLoop(i)
  result.state = EventLoopPoolState.IDLE

var
  pool: EventLoopPool = initEventLoopPool()
  currentEventLoopId {.threadvar.}: int 
  currentEventLoop {.threadvar.}: ptr EventLoop 

proc register*(fd: cint): Identity {.inline.} =
  currentEventLoop.actionRegistry.register(fd)

proc unregister*(ident: Identity) {.inline.} =
  currentEventLoop.actionRegistry.unregister(ident)

proc unregisterReadable*(ident: Identity) {.inline.} =
  currentEventLoop.actionRegistry.unregisterReadable(ident)

proc unregisterWritable*(ident: Identity) {.inline.} =
  currentEventLoop.actionRegistry.unregisterWritable(ident)

proc updateRead*(ident: Identity, c: ref ActionBase) {.inline.} =
  currentEventLoop.actionRegistry.updateRead(ident, c)

proc updateWrite*(ident: Identity, c: ref ActionBase) {.inline.} =
  currentEventLoop.actionRegistry.updateWrite(ident, c)

proc poll(timeout: cint) {.inline.} =
  currentEventLoop.actionRegistry.poll(timeout)

proc spawn*(task: ptr TaskBase) =
  if currentEventLoopId == 0 and pool.capacity > 1:
    pool.recursiveEventLoopId = pool.recursiveEventLoopId mod (pool.capacity - 1) + 1
    pool.eventLoops[pool.recursiveEventLoopId].taskRegistry.add(task)
  else:
    task.run(task) # TODO: callsoon

proc runCounterAction(r: ref ActionBase): bool =
  result = false
  currentEventLoop.taskRegistry.run()

proc runEventLoop(id: Natural) {.thread.} =
  currentEventLoopId = id
  currentEventLoop = pool.eventLoops[id].addr
  let counterIdent = register(currentEventLoop.taskCounterFd)
  let counterAction = new(ActionBase)
  counterAction.run = runCounterAction
  updateRead(counterIdent, counterAction)
  poll(EventLoopTimeout)

proc runEventLoopPool*() =
  for i in 1..<pool.capacity:
    createThread(pool.threads[i], runEventLoop, i)
    when defined(PinToCpu):
      assert pool.cpus > 0
      pinToCpu(pool.threads[i], i mod pool.cpus)
  runEventLoop(0) 
  for i in 1..<pool.capacity:
    joinThread(pool.threads[i])

when isMainModule:
  import std/posix
  # type
  #   MyTask = object of TaskBase
  #     val: int

  # proc destroy(r: ptr MyTask) =
  #   deallocShared(r)

  # var num = 0

  # proc runMyTask(r: ptr TaskBase) =
  #   # num.inc()
  #   atomicInc(num)
  #   echo "Worker id: ", currentEventLoopId, " val: ", cast[ptr MyTask](r).val
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

  proc runReadAction(r: ref ActionBase): bool =
    var buffer = newString(1024)
    if channel[0].read(buffer.cstring, buffer.len) < 0:
      raiseOSError(osLastError())
    echo buffer
    result = true

  proc runReadTask(r: ptr TaskBase) =
    echo "Worker read id: ", currentEventLoopId, " val: ", cast[ptr Task[ReadContext]](r).value.val
    var ident = register(channel[0])
    var callable = new(ActionBase)
    callable.run = runReadAction
    updateRead(ident, callable)
    deallocShared(cast[ptr Task[ReadContext]](r))

  proc createReadTask(val: int): ptr Task[ReadContext] =
    result = cast[ptr Task[ReadContext]](allocShared0(sizeof(Task[ReadContext])))
    result.value.val = val
    result.run = runReadTask

  proc runWriteAction(r: ref ActionBase): bool =
    var buffer = "hello " & $((ref Action[WriteData])(r).value.val)
    if channel[1].write(buffer.cstring, buffer.len) < 0:
      raiseOSError(osLastError())
    result = true

  proc runWriteTask(r: ptr TaskBase) =
    echo "Worker write id: ", currentEventLoopId, " val: ", cast[ptr Task[WriteContext]](r).value.val
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

  runEventLoopPool()
