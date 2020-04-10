#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 本模块实现了一个动态增长的缓冲区 ``VectorBuffer`` 。 该缓冲区可以根据您的需要成倍增长，直到某个临界值。 当到达
## 临界值， 继续增长将引起异常。 

import netkit/misc
import netkit/buffer/constants

type 
  VectorBuffer* = object of RootObj                  ## 一个增长的缓冲区。 
    value: seq[char]
    endPos: Natural                                  
    capacity: Natural
    minCapacity: Natural
    maxCapacity: Natural

proc initVectorBuffer*(
  minCapacity: Natural = BufferSize,
  maxCapacity: Natural = BufferSize * 8
): VectorBuffer = discard
  ## 初始化一个 ``VectorBuffer`` 对象。  ``minCapacity`` 指定最小容量， ``maxCapacity`` 指定最大容量。 

proc capacity*(b: VectorBuffer): Natural = discard
  ## 获取缓冲区的当前容量。 

proc minCapacity*(b: VectorBuffer): Natural = discard
  ## 获取缓冲区的最小容量。 

proc maxCapacity*(b: VectorBuffer): Natural = discard
  ## 获取缓冲区的最大容量。 

proc len*(b: VectorBuffer): Natural = discard
  ## 获取缓冲区当前存储的数据长度。 

proc reset*(b: var VectorBuffer): Natural = discard
  ## 重置缓冲区， 恢复到初始容量， 同时清空所有已存储的数据。 

proc expand*(b: var VectorBuffer) = discard
  ## 扩展缓冲区的容量，增长一倍。 如果超过了最大容量， 则抛出异常。 

proc next*(b: var VectorBuffer): (pointer, Natural) = discard
  ## 获取下一个安全的可存储区域。 返回值表示可存储区域的指针和可存储长度。  之后， 您可以利用返回的指针和长度手动
  ## 存储数据。 比如： 
  ## 
  ## ..code-block::nim
  ##     
  ##   var source = "Hello World"
  ##   var (regionPtr, regionLen) = b.next()
  ##   var length = min(regionLen, s.len)
  ##   copyMem(regionPtr, source.cstring, length) 

proc pack*(b: var VectorBuffer, size: Natural): Natural = discard
  ## 告诉缓冲区， 当前存储位置向后 ``size`` 长度成为有效数据。 返回实际有效的长度。 
  ## 
  ## 当调用 ``next()`` 时， 仅仅将缓冲区内部的存储空间写入数据， 但是缓冲区无法得知写入了多少有效数据。 
  ## ``pack()`` 告诉缓冲区实际写入的有效数据长度。 
  ## 
  ## 每当调用 ``next()`` 时， 都应当立刻调用 ``pack()`` 。 
  ## 
  ## ..code-block::nim
  ##     
  ##   var source = "Hello World"
  ##   var (regionPtr, regionLen) = b.next()
  ##   var length = min(regionLen, s.len)
  ##   copyMem(regionPtr, source.cstring, length) 
  ##   var n = b.pack(length)

proc add*(b: var VectorBuffer, source: pointer, size: Natural): Natural = discard
  ##从源 ``source`` 复制最多 ``size`` 长度的数据， 写入到缓冲区。 返回实际写入的长度。 这个函数是 ``next()`` 
  ## ``pack()`` 组合调用的简化版本， 区别是额外进行一次复制， 而不是直接写入缓冲区。 
  ## 
  ## 当您对性能非常看重时， 考虑使用 ``next()`` ``pack()`` 组合调用；当您对调用便捷比较看重时， 使用 ``put()`` 。 
  ## 
  ## ..code-block::nim
  ##     
  ##   var source = "Hello World"
  ##   var n = b.put(source.cstring, source.len)

proc get*(b: var VectorBuffer, dest: pointer, size: Natural, start: Natural): Natural = discard
  ## 从 ``start`` 开始， 获取当前存储的数据， 最多 ``size`` 个数据， 将其复制到目标空间 ``dest`` ， 返回实际复制的数量。 

proc clear*(b: var VectorBuffer): Natural = discard
  ## 删除所有已存储的数据。 