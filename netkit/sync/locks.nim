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

type
  AsyncLock* = object ## An asynchronous lock.
    locked: bool

type
  SpinLock* = object ## A spin lock.
    locked: bool

proc initSpinLock*(L: var SpinLock) = 
  ## Initializes an ``SpinLock``.
  L.locked = false

proc acquire*(L: var SpinLock) {.inline.} = 
  ## Tries to acquire a lock. When this future is completed, it indicates that the lock is acquired.
  while not cas(addr L.locked, false, true): 
    cpuRelax()

proc tryAcquire*(L: var SpinLock): bool {.inline.} = 
  ## Tries to acquire a lock. When this future is completed, it indicates that the lock is acquired.
  cas(addr L.locked, false, true)

proc release*(L: var SpinLock) {.inline.} = 
  ## Releases the lock that has been acquired. 
  fence()
  L.locked = false

proc isLocked*(L: SpinLock): bool {.inline.} = 
  ## Returns ``true`` if ``L`` is locked.
  L.locked
  
template withLock*(L: SpinLock, action: untyped) = 
  L.acquire()
  try:
    action
  finally:
    L.release()

when isMainModule:
  var spinLock: SpinLock
  var spinCount = 0
  var spinThreads: array[8, Thread[void]]

  proc spinThreadFunc() {.thread.} =
    for j in 0..<100000:
      withLock spinLock:
        spinCount = spinCount + 1   

  proc spinTest() = 
    spinLock.initSpinLock()
    for i in 0..<8:
      createThread(spinThreads[i], spinThreadFunc)
    joinThreads(spinThreads)
    doAssert spinCount == 800000

  spinTest()

