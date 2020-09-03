import std/os
import std/posix
import std/nativesockets

type
  MpscQueue* = object 
    pipe: array[2, cint]

proc initMpscQueue*(): MpscQueue =
  if pipe(result.pipe) < 0:
    raiseOSError(osLastError())
  result.pipe[0].SocketHandle.setBlocking(false)

proc add*(x: var MpscQueue, item: pointer) = 
  var buf: ByteAddress = cast[ByteAddress](item)
  if x.pipe[1].write(buf.addr, sizeof(ByteAddress)) < 0:
    raiseOSError(osLastError())

proc take*(x: var MpscQueue): pointer = 
  var buf: ByteAddress 
  if x.pipe[0].read(buf.addr, sizeof(ByteAddress)) < 0:
    let lastError = osLastError() # TODO: EINTR
    if lastError.int32 == EWOULDBLOCK or lastError.int32 == EAGAIN:
      return nil
    else:
      raiseOSError(osLastError())
  return cast[pointer](buf)

when isMainModule and defined(linux):
  type 
    Task = object
      val: int
      val1: int
      val2: int
      val3: int
      val4: int
      val5: int
      val6: int

  proc createTask(val: int): ptr Task =
    result = cast[ptr Task](allocShared0(sizeof(Task)))
    result.val = val

  proc destroy(t: ptr Task) =
    deallocShared(t)

  var counter = 0
  var sum = 0
  var mq = initMpscQueue()

  proc producerFunc() {.thread.} =
    for i in 1..1000000:
      mq.add(createTask(i)) 

  proc consumerFunc() {.thread.} =
    while counter < 4000000:
      var task = cast[ptr Task](mq.take())
      while task == nil: 
        task = cast[ptr Task](mq.take())
      counter.inc()
      sum.inc(task.val)
      task.destroy()

  proc test() = 
    var producers: array[4, Thread[void]]
    var comsumer: Thread[void]
    for i in 0..<4:
      createThread(producers[i], producerFunc)
    createThread(comsumer, consumerFunc)
    joinThreads(producers)
    joinThreads(comsumer)
    doAssert sum == ((1 + 1000000) * (1000000 div 2)) * 4 # (1 + n) * n / 2

  test()