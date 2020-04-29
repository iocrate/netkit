#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 本模块实现了一个可增长的缓冲区 ``VectorBuffer``。该缓冲区可以根据需要成倍增长，直到某个临界值。当到达
## 临界值时，继续增长将引起异常。

import netkit/misc
import netkit/buffer/constants

type 
  VectorBuffer* = object of RootObj ## 一个可增长的缓冲区。
    value: seq[byte]
    endPos: Natural                                  
    capacity: Natural
    minCapacity: Natural
    maxCapacity: Natural

proc initVectorBuffer*(
  minCapacity: Natural = BufferSize,
  maxCapacity: Natural = BufferSize * 8
): VectorBuffer = discard
  ## 初始化一个 ``VectorBuffer` 。 ``minCapacity`` 指定最小容量，``maxCapacity`` 指定最大容量。

proc capacity*(b: VectorBuffer): Natural = discard
  ## 返回缓冲区的当前容量。

proc minCapacity*(b: VectorBuffer): Natural = discard
  ## 返回缓冲区的最小容量。

proc maxCapacity*(b: VectorBuffer): Natural = discard
  ## 返回缓冲区的最大容量。

proc len*(b: VectorBuffer): Natural = discard
  ## 返回缓冲区存储的数据长度。

proc reset*(b: var VectorBuffer): Natural = discard
  ## 重置缓冲区，恢复到初始容量，同时清空所有已存储的数据。

proc expand*(b: var VectorBuffer) {.raises: [OverflowError].} = discard
  ## 扩展缓冲区的容量，使其增长一倍。如果超过了最大容量，则抛出 ``OverflowError`` 。

proc next*(b: var VectorBuffer): (pointer, Natural) = discard
  ## 返回下一个安全的可存储区域。返回值包括可存储区域的地址和长度。 
  ## 
  ## 例子：
  ## 
  ## .. code-block::nim
  ##     
  ##   var source = "Hello World"
  ##   var (regionPtr, regionLen) = buffer.next()
  ##   var length = min(regionLen, s.len)
  ##   copyMem(regionPtr, source.cstring, length) 

proc pack*(b: var VectorBuffer, size: Natural): Natural = discard
  ## 告诉缓冲区，由当前存储位置向后 ``size`` 长度的字节晋升为数据。返回实际晋升的长度。
  ## 
  ## 当调用 ``next()`` 时，仅仅向缓冲区内部的存储空间写入数据，但是缓冲区无法得知写入了多少数据。
  ## ``pack()`` 告诉缓冲区写入的数据长度。
  ## 
  ## 每当调用 ``next()`` 时，都应当立刻调用 ``pack()`` 。
  ## 
  ## 例子：
  ## 
  ## .. code-block::nim
  ##     
  ##   var source = "Hello World"
  ##   var (regionPtr, regionLen) = buffer.next()
  ##   var length = min(regionLen, s.len)
  ##   copyMem(regionPtr, source.cstring, length) 
  ##   var n = buffer.pack(length)

proc add*(b: var VectorBuffer, source: pointer, size: Natural): Natural = discard
  ## 从 ``source`` 复制最多 ``size`` 长度的数据，存储到缓冲区。返回实际存储的长度。这个函数是 ``next()`` 
  ## ``pack()`` 组合调用的简化版本，区别是额外执行一次复制。
  ## 
  ## 当您非常看重性能时，使用 ``next`` ``pack`` 组合调用；当您比较看重使用方便时，使用 ``add`` 。
  ## 
  ## .. code-block::nim
  ##     
  ##   var source = "Hello World"
  ##   var n = buffer.add(source.cstring, source.len)

proc get*(b: var VectorBuffer, dest: pointer, size: Natural, start: Natural): Natural = discard
  ## 从 ``start`` 开始，获取最多 ``size`` 长度的数据，将它们复制到目标空间 ``dest`` ，返回实际复制的数量。

proc clear*(b: var VectorBuffer): Natural = discard
  ## 删除所有已存储的数据。