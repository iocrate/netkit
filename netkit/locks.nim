#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module implements an asynchronous lock. When performing asynchronous input and output, the order of 
## reading and writing is very important. In order to ensure the correct order of reading and writing, locks
## are required for synchronization or queuing. 
## 
## Asynchronous locks are Netkit's underlying mechanism to provide IO consistency. Netkit provides open APIs 
## independent of "locks".
##
## As with synchronous style locks, you should always operate a lock in window mode and bind a lock to a 
## specific object as much as possible to avoid problems such as deadlock and livelock.

import deques
import asyncdispatch

type
  AsyncLock* = object ## An asynchronous lock.
    locked: bool
    waiters: Deque[Future[void]]

proc initAsyncLock*(): AsyncLock = 
  ## Initializes an ``AsyncLock``.
  result.locked = false
  result.waiters = initDeque[Future[void]]()

proc acquire*(L: var AsyncLock): Future[void] = 
  ## Tries to acquire a lock. When this future is completed, it indicates that the lock is acquired.
  result = newFuture[void]("acquire")
  if L.locked:
    L.waiters.addLast(result)
  else:
    L.locked = true
    result.complete()

proc release*(L: var AsyncLock) = 
  ## Releases the lock that has been acquired. 
  if L.locked:
    if L.waiters.len > 0:
      L.waiters.popFirst().complete()
    else:
      L.locked = false

proc isLocked*(L: AsyncLock): bool {.inline.} = 
  ## Returns ``true`` if ``L`` is locked.
  L.locked
  
type
  SpinLock* = object ## A spin lock.
    locked: bool

proc initSpinLock*(): SpinLock = 
  ## Initializes an ``SpinLock``.
  result.locked = false

proc acquire*(L: var SpinLock) {.inline.} = 
  ## Tries to acquire a lock. When this future is completed, it indicates that the lock is acquired.
  while not cas(addr L.locked, false, true): cpuRelax()

proc release*(L: var SpinLock) {.inline.} = 
  ## Releases the lock that has been acquired. 
  L.locked = false

proc isLocked*(L: SpinLock): bool {.inline.} = 
  ## Returns ``true`` if ``L`` is locked.
  L.locked
  
template withLock*(L: SpinLock, body: untyped) = 
  L.acquire()
  try:
    body
  finally:
    L.release()

when isMainModule:
  var spinLock = initSpinLock()
  var spinCount = 0

  proc spinThreadFunc() {.thread.} =
    for j in 0..<100000:
      withLock spinLock:
        spinCount = spinCount + 1   

  proc spinTest() = 
    var threads: array[8, Thread[void]]
    for i in 0..<8:
      createThread(threads[i], spinThreadFunc)
    joinThreads(threads)
    doAssert spinCount == 800000

  spinTest()

