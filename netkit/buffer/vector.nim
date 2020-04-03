#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

# TODO: 翻译本注释内的说明
# TODO: 将翻译的文档以 reStructuredText 语法格式书写， 以便于 nimdoc 生成文档
# TODO: 更多测试
# TODO: Benchmark Test
## 本模块实现了一个动态增长的缓冲区 ``VectorBuffer`` 。 该缓冲区可以根据您的需要成倍增长，直到某个临界值。

import netkit/buffer/constants

type 
  VectorBuffer* = object of RootObj                  ## A growable buffer.
    value: seq[char]
    endPos: uint32                                   #  0..n-1 
    capacity: uint32
    minCapacity: uint32
    maxCapacity: uint32

template offset(p: pointer, n: uint32): pointer = 
  cast[pointer](cast[ByteAddress](p) + n.int64)

proc initVectorBuffer*(
  minCapacity: uint32 = BufferSize,
  maxCapacity: uint32 = BufferSize * 8
): VectorBuffer = 
  ## 初始化缓冲区。 ``minCapacity`` 指定最小容量， ``maxCapacity`` 指定最大容量。 
  result.capacity = minCapacity
  result.minCapacity = minCapacity
  result.maxCapacity = maxCapacity
  result.value = newSeqOfCap[char](minCapacity)

proc capacity*(b: VectorBuffer): uint32 = 
  ## Gets the capacity of the buffer.
  b.capacity

proc minCapacity*(b: VectorBuffer): uint32 = 
  ## Gets the min capacity of the buffer.
  b.minCapacity

proc maxCapacity*(b: VectorBuffer): uint32 = 
  ## Gets the max capacity of the buffer.
  b.maxCapacity

proc len*(b: VectorBuffer): uint32 = 
  ## Gets the length of the data.
  b.endPos

proc reset*(b: var VectorBuffer): uint32 = 
  ## 重置缓冲区，恢复到初始容量，并且清空所有数据。 
  b.capacity = b.minCapacity
  b.endPos = 0
  b.value = newSeqOfCap[char](b.capacity)

proc extend*(b: var VectorBuffer) = 
  ## 扩展缓冲区的容量，增长一倍。 如果超过了最大容量，则抛出异常。
  let newCapacity = b.capacity * 2
  if newCapacity > b.maxCapacity:
    raise newException(OverflowError, "capacity overflow")
  var newValue = newSeqOfCap[char](newCapacity)
  copyMem(newValue.addr, b.value.addr, b.endPos)
  b.capacity = newCapacity
  b.value.shallowCopy(newValue)

proc next*(b: var VectorBuffer): (pointer, uint32) = 
  ## Gets the next secure storage area. 
  ## Returns the address and storable length of the area. Then you can manually
  ## store the data for that area.
  ## 
  ## 获取下一个安全的存储区域， 返回该区域的地址和可存储长度。 之后， 您可以对该区域手动存储数据。 
  result[0] = b.value.addr.offset(b.endPos)
  result[1] = b.capacity - b.endPos

proc pack*(b: var VectorBuffer, size: uint32): uint32 = 
  ## The area of ``size`` length inside the buffer is regarded as valid data and returns the actual length.
  ## Once this operation is performed, this space will be forced to be used as valid data. In other words,
  ## this method increases the length of the buffer's valid data.
  #
  ## 将缓冲区内部 ``size`` 长度的空间区域视为有效数据， 返回实际有效的长度。 一旦执行这个操作， 这部分空间将被
  ## 强制作为有效数据使用。 换句话说， 这个方法增长了 ``buffer`` 有效数据的长度。 
  result = min(size, b.capacity - b.endPos) 
  b.endPos = b.endPos + result

proc put*(b: var VectorBuffer, source: pointer, size: uint32): uint32 = 
  ## Writes ``source`` of ``size`` length to the buffer and returns the actual size written.
  ##
  ## 从 ``source`` 写入 ``size`` 长度的数据， 返回实际写入的长度。 
  result = min(size, b.capacity - b.endPos)
  if result > 0'u32:
    copyMem(b.value.addr.offset(b.endPos), source, result)
    b.endPos = b.endPos + result

proc get*(b: var VectorBuffer, dest: pointer, size: uint32, start: uint32): uint32 = 
  ## 从 ``start`` 开始，获取最多 ``size`` 个数据， 将其复制到目标空间 ``dest`` ， 返回实际复制的数量。 
  result = min(size, b.endPos - start)
  if result > 0'u32:
    copyMem(dest, b.value.addr.offset(start), result)
  elif result < 0'u32:
    result = 0

proc clear*(b: var VectorBuffer): uint32 = 
  ## 删除所有数据。 
  b.endPos = 0