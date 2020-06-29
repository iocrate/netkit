

import std/math
import std/options
import netkit/locks

type
  MpscQueue*[T] = object of RootObj
    writeLock: SpinLock
    data: ptr UncheckedArray[T]
    head, tail, cap, mask: Natural

proc init*[T](x: var MpscQueue[T], initialSize: Natural = 4) =
  assert isPowerOfTwo(initialSize)
  x.writeLock = initSpinLock()
  x.cap = initialSize
  x.mask = initialSize - 1
  x.data = cast[ptr UncheckedArray[T]](allocShared0(sizeof(T) * initialSize))

proc produce*[T](x: var MpscQueue[T], item: sink T): bool = 
  withLock x.writeLock:
    let next = (x.tail + 1) and x.mask
    if unlikely(next == x.head):
      return false
    x.data[x.tail] = item
    x.tail = next
    return true

proc produceUntil*[T](x: var MpscQueue[T], item: sink T) = 
  withLock x.writeLock:
    let next = (x.tail + 1) and x.mask
    while unlikely(next == x.head):
      cpuRelax()
    x.data[x.tail] = item
    x.tail = next
  
proc comsume*[T](x: var MpscQueue[T]): Option[T] = 
  if x.head == x.tail:
    return none
  result = move(x.data[x.head])
  x.head = (x.head + 1) and x.mask
  
proc comsumeUntil*[T](x: var MpscQueue[T]): T = 
  while x.head == x.tail:
    cpuRelax()
  result = move(x.data[x.head])
  x.head = (x.head + 1) and x.mask

iterator comsumes*[T](x: var MpscQueue[T]): lent T =
  ## Yield every element of `deq`.
  ##
  while x.head != x.tail:
    yield x.data[x.head]
    reset(x.data[x.head])
    x.head = (x.head + 1) and x.mask

when isMainModule:
  var counter = 0
  var mq: MpscQueue[int] 
  mq.init()

  proc produceThreadFunc() {.thread.} =
    for i in 0..<600000:
      mq.produceUntil(i) 

  proc consumeThreadFunc() {.thread.} =
    while counter < 1800000:
      for x in mq.comsumes():
        counter.inc()

  proc test() = 
    var producers: array[3, Thread[void]]
    var comsumer: Thread[void]
    for i in 0..<3:
      createThread(producers[i], produceThreadFunc)
    createThread(comsumer, consumeThreadFunc)
    joinThreads(producers)
    joinThreads(comsumer)
    doAssert counter == 1800000

  test()
