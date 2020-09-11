
import std/math
import std/options
import netkit/sync/locks
import netkit/sync/semaphores

type
  XpscMode* {.pure, size: sizeof(uint8).} = enum
    SPSC, MPSC

  XpscQueue*[D, S] = object 
    mode: XpscMode
    writeLock: SpinLock
    data: ptr UncheckedArray[D]
    head: Natural
    tail: Natural 
    cap: Natural
    len: Natural
    mask: Natural
    semaphore: Semaphore[S]
    tryAddImpl: proc (Q: var XpscQueue[D, S], item: sink D): bool {.nimcall, gcsafe.}
    addImpl: proc (Q: var XpscQueue[D, S], item: sink D) {.nimcall, gcsafe.}

proc `=destroy`*[D, S](Q: var XpscQueue[D, S]) = 
  if Q.data != nil:
    for i in 0..<Q.len: 
      `=destroy`(Q.data[i])
    deallocShared(Q.data)
    Q.data = nil
    `=destroy`(Q.semaphore)

proc `=sink`*[D, S](dest: var XpscQueue[D, S], source: XpscQueue[D, S]) = 
  `=destroy`(dest)
  dest.mode = source.mode
  dest.writeLock = source.writeLock
  dest.data = source.data
  dest.head = source.head
  dest.tail = source.tail
  dest.cap = source.cap
  dest.len = source.len
  dest.mask = source.mask
  dest.semaphore = source.semaphore
  dest.tryAddImpl = source.tryAddImpl
  dest.addImpl = source.addImpl

proc `=`*[D, S](dest: var XpscQueue[D, S], source: XpscQueue[D, S]) =
  if dest.data != source.data: 
    `=destroy`(dest)
    dest.mode = source.mode
    dest.writeLock = source.writeLock
    if source.data != nil:
      dest.data = cast[ptr UncheckedArray[D]](allocShared0(sizeof(D) * source.cap))
      copyMem(dest.data, source.data, sizeof(D) * source.len)
    dest.head = source.head
    dest.tail = source.tail
    dest.cap = source.cap
    dest.len = source.len
    dest.mask = source.mask
    dest.semaphore = source.semaphore
    dest.tryAddImpl = source.tryAddImpl
    dest.addImpl = source.addImpl

proc spscTryAdd[D, S](Q: var XpscQueue[D, S], item: sink D): bool = 
  result = true
  let next = (Q.tail + 1) and Q.mask
  if unlikely(next == Q.head):
    return false
  Q.data[Q.tail] = item
  Q.tail = next
  fence()
  Q.semaphore.signal()

proc spscAdd[D, S](Q: var XpscQueue[D, S], item: sink D)  = 
  let next = (Q.tail + 1) and Q.mask
  while unlikely(next == Q.head):
    cpuRelax()
  Q.data[Q.tail] = item
  Q.tail = next
  fence()
  Q.semaphore.signal()

proc mpscTryAdd[D, S](Q: var XpscQueue[D, S], item: sink D): bool = 
  result = true
  if not Q.writeLock.tryAcquire():
    return false
  let next = (Q.tail + 1) and Q.mask
  if unlikely(next == Q.head):
    Q.writeLock.release()
    return false
  Q.data[Q.tail] = item
  Q.tail = next
  Q.writeLock.release()
  Q.semaphore.signal()

proc mpscAdd[D, S](Q: var XpscQueue[D, S], item: sink D) = 
  Q.writeLock.acquire()
  let next = (Q.tail + 1) and Q.mask
  while unlikely(next == Q.head):
    cpuRelax()
  Q.data[Q.tail] = item
  Q.tail = next
  Q.writeLock.release()
  Q.semaphore.signal()

proc initXpscQueue*[D, S](Q: var XpscQueue[D, S], semaphore: Semaphore[S], mode: XpscMode, cap: Natural = 1024) =
  assert isPowerOfTwo(cap)
  Q.mode = mode
  case mode
  of XpscMode.SPSC:
    Q.tryAddImpl = spscTryAdd[D, S]
    Q.addImpl = spscAdd[D, S]
  of XpscMode.MPSC:
    Q.tryAddImpl = mpscTryAdd[D, S]
    Q.addImpl = mpscAdd[D, S]
    Q.writeLock.initSpinLock()
  Q.data = cast[ptr UncheckedArray[D]](allocShared0(sizeof(D) * cap))
  Q.head = 0
  Q.tail = 0
  Q.cap = cap
  Q.mask = cap - 1
  Q.len = 0
  Q.semaphore = semaphore

proc tryAdd*[D, S](Q: var XpscQueue[D, S], item: sink D): bool {.inline.} = 
  Q.addTryImpl(Q, item)

proc add*[D, S](Q: var XpscQueue[D, S], item: sink D) {.inline.} = 
  Q.addImpl(Q, item)

proc tryPop*[D, S](Q: var XpscQueue[D, S]): Option[D] = 
  if Q.len > 0:
    result = some(move(Q.data[Q.head]))
    Q.head = (Q.head + 1) and Q.mask
    Q.len.dec()

proc pop*[D, S](Q: var XpscQueue[D, S]): D = 
  while Q.len == 0:
    Q.len.inc(Natural(Q.semaphore.wait()))
  fence()
  result = move(Q.data[Q.head])
  Q.head = (Q.head + 1) and Q.mask
  Q.len.dec()

iterator popAll*[D, S](Q: var XpscQueue[D, S]): D = 
  if Q.len == 0:
    Q.len.inc(Natural(Q.semaphore.wait()))
  for i in 0..<Q.len:
    yield move(Q.data[Q.head])
    Q.head = (Q.head + 1) and Q.mask
    Q.len.dec()

proc len*[D, S](Q: var XpscQueue[D, S]): Natural {.inline.} = 
  Q.len

when isMainModule and defined(linux):
  import std/os
  import std/posix
  import netkit/platforms/posix/linux/eventfd

  type 
    MySemaphore = Semaphore[cint]

  proc signal(c: var MySemaphore) = 
    var buf = 1'u64
    if c.value.write(buf.addr, sizeof(buf)) < 0:
      raiseOSError(osLastError())
  
  proc wait(c: var MySemaphore): uint64 = 
    var buf = 0'u64
    if c.value.read(buf.addr, sizeof(buf)) < 0:
      raiseOSError(osLastError())
    result = buf 

  proc intMySemaphore(fd: cint): MySemaphore = 
    result.value = fd
    result.signalImpl = signal
    result.waitImpl = wait

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

  var 
    counter = 0
    sum = 0
    efd: cint
    mq: XpscQueue[ptr Task, cint]
    producers: array[4, Thread[void]]
    comsumer: Thread[void]

  proc producerFunc() {.thread.} =
    for i in 1..10000:
      mq.add(createTask(i)) 

  proc consumerFunc() {.thread.} =
    while counter < 40000:
      for task in mq.popAll():
        counter.inc()
        sum.inc(task.val)
        task.destroy()

  proc test() = 
    efd = eventfd(0, 0)
    if efd < 0:
      raiseOSError(osLastError())
    mq.initXpscQueue(intMySemaphore(efd), XpscMode.MPSC, 4)
    for i in 0..<4:
      createThread(producers[i], producerFunc)
    createThread(comsumer, consumerFunc)
    joinThreads(producers)
    joinThreads(comsumer)
    if close(efd) < 0:
      raiseOSError(osLastError())
    doAssert sum == ((1 + 10000) * (10000 div 2)) * 4 # (1 + n) * n / 2

  test()

