## This module implements a growable buffer ``VectorBuffer``. The buffer can grow exponentially as needed until
## it reaches a critical value. When the critical value is reached, continued growth will cause an exception.

import netkit/misc
import netkit/buffer/constants

type 
  VectorBuffer* = object of RootObj                  ## A growable buffer.
    value: seq[byte]
    endPos: Natural                                  #  0..n-1 
    capacity: Natural
    minCapacity: Natural
    maxCapacity: Natural

proc initVectorBuffer*(
  minCapacity: Natural = BufferSize,
  maxCapacity: Natural = BufferSize * 8
): VectorBuffer = 
  ## Initializes an ``VectorBuffer`` . 
  result.capacity = minCapacity
  result.minCapacity = minCapacity
  result.maxCapacity = maxCapacity
  result.value = newSeqOfCap[byte](minCapacity)

proc capacity*(b: VectorBuffer): Natural = 
  ## Returns the capacity of this buffer.
  b.capacity

proc minCapacity*(b: VectorBuffer): Natural = 
  ## Returns the minimum capacity of this buffer.
  b.minCapacity

proc maxCapacity*(b: VectorBuffer): Natural = 
  ## Returns the maximum capacity of this buffer.
  b.maxCapacity

proc len*(b: VectorBuffer): Natural = 
  ## Returns the length of the data currently stored in this buffer.
  b.endPos

proc reset*(b: var VectorBuffer): Natural = 
  ## Resets the buffer to restore to the original capacity while clear all stored data.
  b.capacity = b.minCapacity
  b.endPos = 0
  b.value = newSeqOfCap[byte](b.capacity)

proc expand*(b: var VectorBuffer) = 
  ## Expands the capacity of the buffer. If it exceeds the maximum capacity, an exception is raised.
  let newCapacity = b.capacity * 2
  if newCapacity > b.maxCapacity:
    raise newException(OverflowError, "capacity overflow")
  var newValue = newSeqOfCap[byte](newCapacity)
  copyMem(newValue.addr, b.value.addr, b.endPos)
  b.capacity = newCapacity
  b.value = move newValue

proc next*(b: var VectorBuffer): (pointer, Natural) = 
  ## Gets the next safe storage space. The return value includes the address and length of the storable 
  ## space. 
  ## 
  ## Examples:
  ## 
  ## .. code-block::nim
  ##     
  ##   var source = "Hello World"
  ##   var (regionPtr, regionLen) = buffer.next()
  ##   var length = min(regionLen, s.len)
  ##   copyMem(regionPtr, source.cstring, length) 
  result[0] = b.value.addr.offset(b.endPos)
  result[1] = b.capacity - b.endPos

proc pack*(b: var VectorBuffer, size: Natural): Natural = 
  ## Tells the buffer that ``size`` bytes from the current storage location are promoted to data. Returns the actual 
  ## length promoted.
  ## 
  ## When ``next()`` is called, data is written to the storage space inside the buffer, but the buffer cannot know 
  ## how much data was written. ``pack ()`` tells the buffer the length of the data written.
  ## 
  ## Whenever ``next()`` is called, ``pack()`` should be called immediately.
  ## 
  ## Examples:
  ## 
  ## .. code-block::nim
  ##     
  ##   var source = "Hello World"
  ##   var (regionPtr, regionLen) = buffer.next()
  ##   var length = min(regionLen, s.len)
  ##   copyMem(regionPtr, source.cstring, length) 
  ##   var n = buffer.pack(length)
  result = min(size, b.capacity - b.endPos) 
  b.endPos = b.endPos + result

proc add*(b: var VectorBuffer, source: pointer, size: Natural): Natural = 
  ## Copies up to ``size`` lengths of data from ``source`` and store the data in the buffer. Returns the actual length 
  ## copied. This is a simplified version of the ``next`` ``pack`` combination call. The difference is that an  
  ## additional copy operation is made instead of writing directly to the buffer.
  ## 
  ## Examples:
  ## 
  ## .. code-block::nim
  ##     
  ##   var source = "Hello World"
  ##   var n = buffer.add(source.cstring, source.len)
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