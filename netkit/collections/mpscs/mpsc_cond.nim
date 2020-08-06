import std/math
import std/locks 

type
  MpscQueue*[T] = object 
    writeLock: Lock
    writeCond: Cond
    data: ptr UncheckedArray[T]
    head: Natural
    tail: Natural 
    cap: Natural
    len: Natural
    mask: Natural

proc initMpscQueue*[T](cap: Natural = 4): MpscQueue[T] =
  assert isPowerOfTwo(cap)
  result.data = cast[ptr UncheckedArray[T]](allocShared0(sizeof(T) * cap))
  result.head = 0
  result.tail = 0
  result.cap = cap
  result.mask = cap - 1
  result.len = 0
  initLock(result.writeLock)
  initCond(result.writeCond)

proc add*[T](x: var MpscQueue[T], item: sink T) = 
  acquire(x.writeLock)

  while x.len == x.cap: # 满了，释放锁，等待条件信号
    wait(x.writeCond, x.writeLock)

  let next = (x.tail + 1) and x.mask
  x.data[x.tail] = item
  x.tail = next
  x.len.inc()

  signal(x.writeCond)   # 发出条件信号，如果消费正在睡眠则被唤醒
  release(x.writeLock)

proc take*[T](x: var MpscQueue[T]): T = 
  acquire(x.writeLock)
  
  while x.len == 0:     # 空的，释放锁，等待条件信号
    wait(x.writeCond, x.writeLock)
    assert x.len > 0
    
  result = move(x.data[x.head])
  x.head = (x.head + 1) and x.mask
  x.len.dec()

  if x.len == x.mask:   # 刚才是满的 -> 发出条件信号，如果生产者正在睡眠则被唤醒
    signal(x.writeCond)

  release(x.writeLock)

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
  var mq = initMpscQueue[ptr Task](32768)

  proc producerFunc() {.thread.} =
    for i in 1..1000000:
      mq.add(createTask(i)) 

  proc consumerFunc() {.thread.} =
    while counter < 4000000:
      var task = mq.take()
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