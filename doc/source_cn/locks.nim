#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块实现了异步锁。 IO 在涉及到 “流” 的时候， 不可避免的引入 “序” 的问题。 为了保证多个读写 “序”
## 的正确， 需要异步锁进行同步或者说是排队。 通常， 您不会直接使用异步锁。 异步锁作为 Netkit 的底层机制
## 控制 IO “序” 的一致性， 并对外提供 “锁” 无关的开放 API 。 
##
## 与同步风格的锁一样， 您应该总是以 “窗口” 的方式操作锁， 并尽可能将锁与某个特定对象绑定， 以避免 “死锁”、
## “活锁” 等问题。 

import asyncdispatch

type
  AsyncLock* = object
    locked: bool

proc acquire*(L: AsyncLock): Future[void] = discard
  ## 尝试获取一把锁。 

proc release*(L: AsyncLock) = discard
  ## 释放已经获取的锁。 

proc isLocked*(L: AsyncLock): bool = discard
  ## 检查 ``L`` 是否处于锁住状态。 