

import std/math
import netkit/locks
import netkit/sigcounter

type
  MpscQueue*[D, C] = object 
    writeLock: SpinLock
    data: ptr UncheckedArray[D]
    head: Natural
    tail: Natural 
    cap: Natural
    len: Natural
    mask: Natural
    counter: SigCounter[C]

proc `=destroy`*[D, C](x: var MpscQueue[D, C]) = 
  if x.data != nil:
    for i in 0..<x.len: 
      `=destroy`(x.data[i])
    deallocShared(x.data)
    x.data = nil
    `=destroy`(x.counter)

proc `=sink`*[D, C](dest: var MpscQueue[D, C], source: MpscQueue[D, C]) = 
  `=destroy`(dest)
  dest.data = source.data
  dest.head = source.head
  dest.tail = source.tail
  dest.cap = source.cap
  dest.len = source.len
  dest.mask = source.mask
  dest.counter = source.counter

proc `=`*[D, C](dest: var MpscQueue[D, C], source: MpscQueue[D, C]) =
  if dest.data != source.data: 
    `=destroy`(dest)
    dest.head = source.head
    dest.tail = source.tail
    dest.cap = source.cap
    dest.len = source.len
    dest.mask = source.mask
    dest.counter = source.counter
    if source.data != nil:
      dest.data = cast[ptr UncheckedArray[D]](allocShared0(sizeof(D) * source.cap))
      copyMem(dest.data, source.data, sizeof(D) * source.len)

proc initMpscQueue*[D, C](counter: SigCounter[C], cap: Natural = 4096): MpscQueue[D, C] =
  assert isPowerOfTwo(cap)
  result.writeLock = initSpinLock()
  result.data = cast[ptr UncheckedArray[D]](allocShared0(sizeof(D) * cap))
  result.head = 0
  result.tail = 0
  result.cap = cap
  result.mask = cap - 1
  result.len = 0
  result.counter = counter

proc tryAdd*[D, C](x: var MpscQueue[D, C], item: sink D): bool = 
  result = true
  withLock x.writeLock:
    let next = (x.tail + 1) and x.mask
    if unlikely(next == x.head):
      return false
    x.data[x.tail] = item
    x.tail = next
  fence()
  x.counter.signal()

proc add*[D, C](x: var MpscQueue[D, C], item: sink D) = 
  withLock x.writeLock:
    let next = (x.tail + 1) and x.mask
    while unlikely(next == x.head):
      cpuRelax()
    x.data[x.tail] = item
    x.tail = next
  fence()
  x.counter.signal()

proc len*[D, C](x: var MpscQueue[D, C]): Natural {.inline.} = 
  x.len
  
proc sync*[D, C](x: var MpscQueue[D, C]) {.inline.} = 
  x.len.inc(Natural(x.counter.wait()))
  
proc take*[D, C](x: var MpscQueue[D, C]): D = 
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
    MySigCounter = SigCounter[cint]

  proc signalMySigCounter(c: var SigCounterBase) = 
    var buf = 1'u64
    if MySigCounter(c).value.write(buf.addr, sizeof(buf)) < 0:
      raiseOSError(osLastError())
  
  proc waitMySigCounter(c: var SigCounterBase): uint64 = 
    var buf = 0'u64
    if MySigCounter(c).value.read(buf.addr, sizeof(buf)) < 0:
      raiseOSError(osLastError())
    result = buf 

  proc intMySigCounter(fd: cint): MySigCounter = 
    result.signalImpl = signalMySigCounter
    result.waitImpl = waitMySigCounter
    result.value = fd

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
  var efd = eventfd(0, 0)
  if efd < 0:
    raiseOSError(osLastError())
  var mq = initMpscQueue[ptr Task, cint](intMySigCounter(efd), 4)

  proc producerFunc() {.thread.} =
    for i in 1..10000:
      mq.add(createTask(i)) 

  proc consumerFunc() {.thread.} =
    while counter < 40000:
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
    if close(efd) < 0:
      raiseOSError(osLastError())
    doAssert sum == ((1 + 10000) * (10000 div 2)) * 4 # (1 + n) * n / 2

  test()




  