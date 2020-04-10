#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

# TODO: 翻译 doc/source/buffer/circular.nim 的注释， 将英文版追加到本文件
# TODO: 更多单元测试， 测试稳定性和安全性
# TODO: Benchmark Test

import netkit/misc
import netkit/buffer/constants

type 
  VectorBuffer* = object of RootObj                  ## A growable buffer.
    value: seq[char]
    endPos: Natural                                  #  0..n-1 
    capacity: Natural
    minCapacity: Natural
    maxCapacity: Natural

proc initVectorBuffer*(
  minCapacity: Natural = BufferSize,
  maxCapacity: Natural = BufferSize * 8
): VectorBuffer = 
  ## Initializes an ``VectorBuffer`` object. 
  result.capacity = minCapacity
  result.minCapacity = minCapacity
  result.maxCapacity = maxCapacity
  result.value = newSeqOfCap[char](minCapacity)

proc capacity*(b: VectorBuffer): Natural = 
  ## Gets the capacity of the buffer.
  b.capacity

proc minCapacity*(b: VectorBuffer): Natural = 
  ## Gets the minimum capacity of the buffer.
  b.minCapacity

proc maxCapacity*(b: VectorBuffer): Natural = 
  ## Gets the maximum capacity of the buffer.
  b.maxCapacity

proc len*(b: VectorBuffer): Natural = 
  ## Gets the length of the data currently stored in the buffer.
  b.endPos

proc reset*(b: var VectorBuffer): Natural = 
  ## Resets the buffer to restore to the original capacity while clear all stored data.
  b.capacity = b.minCapacity
  b.endPos = 0
  b.value = newSeqOfCap[char](b.capacity)

proc expand*(b: var VectorBuffer) = 
  ## Expands the capacity of the buffer. If it exceeds the maximum capacity, an exception is thrown.
  let newCapacity = b.capacity * 2
  if newCapacity > b.maxCapacity:
    raise newException(OverflowError, "capacity overflow")
  var newValue = newSeqOfCap[char](newCapacity)
  copyMem(newValue.addr, b.value.addr, b.endPos)
  b.capacity = newCapacity
  b.value.shallowCopy(newValue)

proc next*(b: var VectorBuffer): (pointer, Natural) = 
  ## Gets the next safe storage region. The return value indicates the pointer and length of the storage 
  ## region. After that, you can use the returned pointer and length to store data manually.
  ## 
  ## ..code-block::nim
  ##     
  ##   var source = "Hello World"
  ##   var (regionPtr, regionLen) = b.next()
  ##   var length = min(regionLen, s.len)
  ##   copyMem(regionPtr, source.cstring, length) 
  result[0] = b.value.addr.offset(b.endPos)
  result[1] = b.capacity - b.endPos

proc pack*(b: var VectorBuffer, size: Natural): Natural = 
  ## Tells the buffer that packing ``size`` lengths of data. Returns the actual length packed.
  ## 
  ## When ``next()`` is called, Although data has been written inside the buffer, but the buffer cannot tell how 
  ## much valid data has been written. ``pack ()`` tells the buffer how much valid data is actually written.
  ## 
  ## Whenever ``next()`` is called, ``pack()`` should be called immediately.
  ## 
  ## ..code-block::nim
  ##     
  ##   var source = "Hello World"
  ##   var (regionPtr, regionLen) = b.next()
  ##   var length = min(regionLen, s.len)
  ##   copyMem(regionPtr, source.cstring, length) 
  ##   var n = b.pack(length)
  result = min(size, b.capacity - b.endPos) 
  b.endPos = b.endPos + result

proc add*(b: var VectorBuffer, source: pointer, size: Natural): Natural = 
  ## Copies up to `` size`` lengths of data from `` source``. Returns the actual length copied. This 
  ## is a simplified version of the `` next () `` `` pack () `` combination call. The difference is
  ## that an additional copy operation is made instead of writing directly to the buffer.
  ## 
  ## When you focus on performance, consider using ``next ()``, ``pack ()`` combination calls; 
  ## when you focus on convenience of the invocation, use ``put ()``.
  ## 
  ## ..code-block::nim
  ##     
  ##   var source = "Hello World"
  ##   var n = b.put(source.cstring, source.len)
  result = min(size, b.capacity - b.endPos)
  copyMem(b.value.addr.offset(b.endPos), source, result)
  b.endPos = b.endPos + result

proc get*(b: var VectorBuffer, dest: pointer, size: Natural, start: Natural): Natural = 
  ## Gets up to ``size`` of the stored data from ``start`` position, copy the data to the space ``dest``. Returns the 
  ## actual number copied.
  if start >= b.endPos or size == 0:
    return 0
  result = min(size, b.endPos - start)
  copyMem(dest, b.value.addr.offset(start), result)

proc clear*(b: var VectorBuffer): Natural = 
  ## Deletes all the stored data. 
  b.endPos = 0