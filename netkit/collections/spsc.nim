

import std/math
import netkit/collections/sigcounter

type
  SpscQueue*[T] = object 
    data: ptr UncheckedArray[T]
    head: Natural
    tail: Natural 
    cap: Natural
    len: Natural
    mask: Natural
    counter: ptr SigCounter

proc `=destroy`*[T](x: var SpscQueue[T]) = 
  if x.data != nil:
    for i in 0..<x.len: 
      `=destroy`(x.data[i])
    deallocShared(x.data)
    x.data = nil
    x.counter = nil

proc `=sink`*[T](dest: var SpscQueue[T], source: SpscQueue[T]) = 
  `=destroy`(dest)
  dest.data = source.data
  dest.head = source.head
  dest.tail = source.tail
  dest.cap = source.cap
  dest.len = source.len
  dest.mask = source.mask
  dest.counter = source.counter

proc `=`*[T](dest: var SpscQueue[T], source: SpscQueue[T]) =
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

proc initSpscQueue*[T](counter: ptr SigCounter, cap: Natural = 1024*1024): SpscQueue[T] =
  assert isPowerOfTwo(cap)
  result.data = cast[ptr UncheckedArray[T]](allocShared0(sizeof(T) * cap))
  result.head = 0
  result.tail = 0
  result.cap = cap
  result.mask = cap - 1
  result.len = 0
  result.counter = counter

proc tryAdd*[T](x: var SpscQueue[T], item: sink T): bool = 
  result = true
  let next = (x.tail + 1) and x.mask
  if unlikely(next == x.head):
    return false
  x.data[x.tail] = item
  x.tail = next
  fence()
  x.counter.signal()

proc add*[T](x: var SpscQueue[T], item: sink T) = 
  let next = (x.tail + 1) and x.mask
  while unlikely(next == x.head):
    cpuRelax()
  x.data[x.tail] = item
  x.tail = next
  fence()
  x.counter.signal()

proc len*[T](x: var SpscQueue[T]): Natural {.inline.} = 
  x.len
  
proc sync*[T](x: var SpscQueue[T]) {.inline.} = 
  x.len.inc(Natural(x.counter.wait()))
  
proc take*[T](x: var SpscQueue[T]): T = 
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
  
  proc waitMySigCounter(c: ptr SigCounter): uint64 = 
    var buf = 0'u64
    if cast[ptr MySigCounter](c).efd.read(buf.addr, sizeof(buf)) < 0:
      raiseOSError(osLastError())
    result = buf 

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
  var mq = initSpscQueue[ptr Task](sigCounter, 4)

  proc producerFunc() {.thread.} =
    for i in 1..10000:
      mq.add(createTask(i)) 

  proc consumerFunc() {.thread.} =
    while counter < 10000:
      mq.sync()
      while mq.len > 0:
        counter.inc()
        var task = mq.take()
        sum.inc(task.val)
        task.destroy()

  proc test() = 
    var producer: Thread[void]
    var comsumer: Thread[void]
    createThread(producer, producerFunc)
    createThread(comsumer, consumerFunc)
    joinThread(producer)
    joinThread(comsumer)
    sigCounter.destroy()
    doAssert sum == ((1 + 10000) * (10000 div 2)) * 1 # (1 + n) * n / 2

  test()




  