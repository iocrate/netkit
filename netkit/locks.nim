#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import deques
import asyncdispatch

type
  AsyncLock* = object
    locked: bool
    waiters: Deque[Future[void]]

proc initAsyncLock*(): AsyncLock = 
  result.locked = false
  result.waiters = initDeque[Future[void]]()

proc acquire*(L: var AsyncLock): Future[void] = 
  result = newFuture[void]("acquire")
  if L.locked:
    L.waiters.addLast(result)
  else:
    L.locked = true
    result.complete()

proc release*(L: var AsyncLock) = 
  if L.locked:
    if L.waiters.len > 0:
      L.waiters.popFirst().complete()
    else:
      L.locked = false

proc isLocked*(L: AsyncLock): bool =
  L.locked
  