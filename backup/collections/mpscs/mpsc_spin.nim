

import std/math
import netkit/locks

type
  SigCounter* = object of RootObj
    signalImpl*: proc (c: ptr SigCounter) {.nimcall, gcsafe.}
    waitImpl*: proc (c: ptr SigCounter): Natural {.nimcall, gcsafe.}

proc signal*(c: ptr SigCounter) {.inline.} =
  c.signalImpl(c) 

proc wait*(c: ptr SigCounter): Natural {.inline.} =
  c.waitImpl(c) 

type
  MpscQueue*[T] = object 
    writeLock: SpinLock
    data: ptr UncheckedArray[T]
    head: Natural
    tail: Natural 
    cap: Natural
    len: Natural
    mask: Natural
    counter: ptr SigCounter

proc `=destroy`*[T](x: var MpscQueue[T]) = 
  if x.data != nil:
    for i in 0..<x.len: 
      `=destroy`(x.data[i])
    deallocShared(x.data)
    x.data = nil
    x.counter = nil

proc `=sink`*[T](dest: var MpscQueue[T], source: MpscQueue[T]) = 
  `=destroy`(dest)
  dest.data = source.data
  dest.head = source.head
  dest.tail = source.tail
  dest.cap = source.cap
  dest.len = source.len
  dest.mask = source.mask
  dest.counter = source.counter

proc `=`*[T](dest: var MpscQueue[T], source: MpscQueue[T]) =
  if dest.data != source.data: 
    `=destroy`(dest)
    dest.head = source.head
    dest.tail = source.tail
    dest.cap = source.cap
    dest.len = source.len
    dest.mask = source.mask
    dest.counter = source.counter
    if source.data != nil:
      dest.data = cast[ptr UncheckedArray[T]](allocShared0(sizeof(T) * source.cap))
      copyMem(dest.data, source.data, sizeof(T) * source.len)

proc initMpscQueue*[T](counter: ptr SigCounter, cap: Natural = 1024*1024): MpscQueue[T] =
  assert isPowerOfTwo(cap)
  result.writeLock = initSpinLock()
  result.data = cast[ptr UncheckedArray[T]](allocShared0(sizeof(T) * cap))
  result.head = 0
  result.tail = 0
  result.cap = cap
  result.mask = cap - 1
  result.len = 0
  result.counter = counter

proc tryAdd*[T](x: var MpscQueue[T], item: sink T): bool = 
  result = true
  withLock x.writeLock:
    let next = (x.tail + 1) and x.mask
    if unlikely(next == x.head):
      return false
    x.data[x.tail] = item
    x.tail = next
  fence()
  x.counter.signal()

proc add*[T](x: var MpscQueue[T], item: sink T) = 
  withLock x.writeLock:
    let next = (x.tail + 1) and x.mask
    while unlikely(next == x.head):
      cpuRelax()
    x.data[x.tail] = item
    x.tail = next
  fence()
  x.counter.signal()

proc len*[T](x: var MpscQueue[T]): Natural {.inline.} = 
  x.len
  
proc sync*[T](x: var MpscQueue[T]) {.inline.} = 
  x.len.inc(x.counter.wait())
  
proc take*[T](x: var MpscQueue[T]): T = 
  result = move(x.data[x.head])
  x.head = (x.head + 1) and x.mask
  x.len.dec()

when isMainModule and defined(linux):
  import std/os
  import std/posix

  proc eventfd*(initval: cuint, flags: cint): cint {.
    importc: "eventfd", 
    header: "<sys/eventfd.h>"
  .}

  type 
    MySigCounter = object of SigCounter
      efd: cint

  proc signalMySigCounter(c: ptr SigCounter) = 
    var buf = 1'u64
    if cast[ptr MySigCounter](c).efd.write(buf.addr, sizeof(buf)) < 0:
      raiseOSError(osLastError())
  
  proc waitMySigCounter(c: ptr SigCounter): Natural = 
    var buf = 0'u64
    if cast[ptr MySigCounter](c).efd.read(buf.addr, sizeof(buf)) < 0:
      raiseOSError(osLastError())
    result = buf # TODO: u64 -> int 考虑溢出

  proc createMySigCounter(): ptr MySigCounter = 
    let p = cast[ptr MySigCounter](allocShared0(sizeof(MySigCounter)))
    p.signalImpl = signalMySigCounter
    p.waitImpl = waitMySigCounter
    p.efd = eventfd(0, 0)
    if p.efd < 0:
      raiseOSError(osLastError())
    result = p

  proc destroy(c: ptr MySigCounter) =
    if cast[ptr MySigCounter](c).efd.close() < 0:
      raiseOSError(osLastError())
    deallocShared(c)

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
  var sigCounter = createMySigCounter()
  var mq = initMpscQueue[ptr Task](sigCounter, 4)

  proc producerFunc() {.thread.} =
    for i in 1..1000000:
      mq.add(createTask(i)) 

  proc consumerFunc() {.thread.} =
    while counter < 4000000:
      mq.sync()
      while mq.len > 0:
        counter.inc()
        var task = mq.take()
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
    sigCounter.destroy()
    doAssert sum == ((1 + 1000000) * (1000000 div 2)) * 4 # (1 + n) * n / 2

  test()




  