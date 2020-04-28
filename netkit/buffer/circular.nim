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
  CircularBuffer* = object of RootObj                
    ## A data structure that uses a single, fixed-size buffer as if it were connected end-to-end. 
    value: array[0..BufferSize, byte]
    startPos: Natural                                #  0..n-1 
    endPos: Natural                                  #  0..n-1 
    endMirrorPos: Natural                            #  0..2n-1 

  MarkableCircularBuffer* = object of CircularBuffer 
    ## A markable circular buffer object that supports incremental marks.
    markedPos: Natural                               #  0..2n-1 

proc initCircularBuffer*(): CircularBuffer = 
  ## Initializes an ``CircularBuffer`` object. 
  discard

proc capacity*(b: CircularBuffer): Natural {.inline.} = 
  ## Gets the capacity of the buffer.
  BufferSize

proc len*(b: CircularBuffer): Natural {.inline.} = 
  ## Gets the length of the data currently stored in the buffer.
  b.endMirrorPos - b.startPos

proc next*(b: var CircularBuffer): (pointer, Natural) = 
  ## Gets the next safe storage region. The return value indicates the pointer and length of the storage 
  ## region. After that, you can use the returned pointer and length to store data manually.
  ## 
  ## .. code-block::nim
  ##     
  ##   var source = "Hello World"
  ##   var (regionPtr, regionLen) = b.next()
  ##   var length = min(regionLen, s.len)
  ##   copyMem(regionPtr, source.cstring, length) 
  result[0] = b.value.addr.offset(b.endPos)
  result[1] = if b.endMirrorPos < BufferSize: BufferSize - b.endPos
              else: b.startPos - b.endPos

proc pack*(b: var CircularBuffer, size: Natural): Natural = 
  ## Tells the buffer that packing ``size`` lengths of data. Returns the actual length packed.
  ## 
  ## When ``next()`` is called, Although data has been written inside the buffer, but the buffer cannot tell how 
  ## much valid data has been written. ``pack ()`` tells the buffer how much valid data is actually written.
  ## 
  ## Whenever ``next()`` is called, ``pack()`` should be called immediately.
  ## 
  ## .. code-block::nim
  ##     
  ##   var source = "Hello World"
  ##   var (regionPtr, regionLen) = b.next()
  ##   var length = min(regionLen, s.len)
  ##   copyMem(regionPtr, source.cstring, length) 
  ##   var n = b.pack(length)
  if b.endMirrorPos < BufferSize:
    result = min(size, BufferSize - b.endPos) 
    b.endMirrorPos = b.endMirrorPos + result
    b.endPos = b.endMirrorPos mod BufferSize
  else:
    result = min(size, b.startPos - b.endPos) 
    b.endMirrorPos = b.endMirrorPos + result
    b.endPos = b.endMirrorPos mod BufferSize

proc add*(b: var CircularBuffer, source: pointer, size: Natural): Natural = 
  ## Copies up to `` size`` lengths of data from `` source``. Returns the actual length copied. This 
  ## is a simplified version of the `` next () `` `` pack () `` combination call. The difference is
  ## that an additional copy operation is made instead of writing directly to the buffer.
  ## 
  ## When you focus on performance, consider using ``next ()``, ``pack ()`` combination calls; 
  ## when you focus on convenience of the invocation, use ``put ()``.
  ## 
  ## .. code-block::nim
  ##     
  ##   var source = "Hello World"
  ##   var n = b.put(source.cstring, source.len)
  result = min(BufferSize - b.len, size)
  let region = b.next()
  if region[1] >= result:
    copyMem(region[0], source, result)
    discard b.pack(result)
  else:
    copyMem(region[0], source, region[1])
    discard b.pack(region[1])
    let d = result - region[1]
    let region2 = b.next()
    copyMem(region2[0], source.offset(region[1]), d)
    discard b.pack(d)

proc add*(b: var CircularBuffer, c: char): Natural = 
  ## Writes a character ``c`` to the buffer and returns the actual number written. Returns ``0`` if the buffer
  ## is full, or ``1``.
  let region = b.next()
  result = min(region[1], 1)
  if result > 0:
    cast[ptr char](region[0])[] = c
    discard b.pack(result)

proc get*(b: var CircularBuffer, dest: pointer, size: Natural): Natural = 
  ## Gets up to ``size`` of the stored data, copy the data to the space ``dest``. Returns the actual number copied.
  result = min(size, b.endMirrorPos - b.startPos)
  if b.startPos + result <= BufferSize: # only right
    copyMem(dest, b.value.addr.offset(b.startPos), result)
  else:                                 # both right and left
    let majorLen = BufferSize - b.startPos
    copyMem(dest, b.value.addr.offset(b.startPos), majorLen)
    copyMem(dest.offset(majorLen), b.value.addr, result - majorLen)
  
proc get*(b: var CircularBuffer, size: Natural): string = 
  ## Gets up to ``size`` of the  stored data, returns as a string. 
  let length = min(b.endMirrorPos - b.startPos, size)
  result = newString(length)
  discard b.get(result.cstring, length)

proc get*(b: var CircularBuffer): string = 
  ## Gets all stored data and returns as a string.
  result = b.get(b.endMirrorPos - b.startPos)

proc del*(b: var CircularBuffer, size: Natural): Natural = 
  ## Deletes up to ``size`` of the stored data, and returns the actual number deleted.
  result = min(size, b.endMirrorPos - b.startPos)
  b.startPos = b.startPos + result
  if b.startPos < b.endMirrorPos:
    if b.startPos < BufferSize:
      discard
    elif b.startPos == BufferSize:
      b.startPos = 0
      b.endMirrorPos = b.endPos
    else:
      b.startPos = b.startPos mod BufferSize
      b.endMirrorPos = b.endPos
  else:
    b.startPos = 0
    b.endPos = 0
    b.endMirrorPos = 0

iterator items*(b: CircularBuffer): char =
  ## Iterates over the stored data. 
  var i = b.startPos
  while i < b.endMirrorPos:
    yield b.value[i mod BufferSize].chr
    i.inc()

proc initMarkableCircularBuffer*(): MarkableCircularBuffer =
  ## Initializes an ``MarkableCircularBuffer`` object. 
  discard
      
proc del*(b: var MarkableCircularBuffer, size: Natural): Natural = 
  ## Deletes up to ``size`` of the stored data, and returns the actual number deleted.
  result = min(size, b.endMirrorPos - b.startPos)
  b.startPos = b.startPos + result
  if b.startPos < b.endMirrorPos:
    if b.startPos < BufferSize:
      if b.startPos > b.markedPos:
        b.markedPos = b.startPos
    elif b.startPos == BufferSize:
      if b.startPos > b.markedPos:
        b.markedPos = 0
      else:
        b.markedPos = b.markedPos mod BufferSize
      b.startPos = 0
      b.endMirrorPos = b.endPos
    else:
      let newStartPos = b.startPos mod BufferSize
      if b.startPos > b.markedPos:
        b.markedPos = newStartPos
      else:
        b.markedPos = b.markedPos mod BufferSize
      b.startPos = newStartPos
      b.endMirrorPos = b.endPos
  else:
    b.startPos = 0
    b.endPos = 0
    b.endMirrorPos = 0  
    b.markedPos = 0

iterator marks*(b: var MarkableCircularBuffer): char =
  ## Iterate over the stored data and marks it.
  ## 
  ## Note that the marking is performed incrementally, that is, when the marking operation is called next time, it will 
  ## continue from the position where it last ended.
  ## 
  ## .. code-block::nim
  ##     
  ##   var s = "Hello World\R\L"
  ##   var n = b.put(s.cstring, s.len)
  ## 
  ##   for c in b.marks():
  ##     if c == '\L':
  ##       break
  while b.markedPos < b.endMirrorPos:
    let i = b.markedPos mod BufferSize
    b.markedPos.inc()
    yield b.value[i].chr

proc mark*(b: var MarkableCircularBuffer, size: Natural): Natural =
  ## Marks the stored data in the buffer immediately until it reaches ``size`` or reaches the end of the data. Returns 
  ## the actual number marked.
  ## 
  ## Note that the marking is performed incrementally, that is, when the marking operation is called next time, it will 
  ## continue from the position where it last ended.
  let m = b.markedPos + size
  if m <= b.endMirrorPos:
    b.markedPos = m
    result = size
  else:
    result = b.endMirrorPos - b.markedPos
    b.markedPos = b.endMirrorPos

proc markUntil*(b: var MarkableCircularBuffer, c: char): bool =
  ## Marks the stored data one by one until one byte is ``c``. False is returned if no byte is ``c``.
  ## 
  ## Note that the marking is performed incrementally, that is, when the marking operation is called next time, it will 
  ## continue from the position where it last ended.
  result = false
  for ch in b.marks():
    if ch == c:
      return true

proc markAll*(b: var MarkableCircularBuffer) =
  ## Marks all the stored data. 
  ## 
  ## Note that the marking is performed incrementally, that is, when the marking operation is called next time, it will 
  ## continue from the position where it last ended.
  b.markedPos = b.endMirrorPos

proc lenMarks*(b: MarkableCircularBuffer): Natural {.inline.} = 
  ## Gets the length of the stored data that has been marked.
  b.markedPos - b.startPos

proc popMarks*(b: var MarkableCircularBuffer, n: Natural = 0): string = 
  ## Pops all the marked data, skip backward ``n`` characters. This operation deletes all marked data.
  if b.markedPos == b.startPos:
    return ""

  let resultPos = b.markedPos - n
  let resultLen = resultPos - b.startPos

  if resultLen > 0:
    result = newString(resultLen)
    if resultPos <= BufferSize: # only right
      copyMem(result.cstring, b.value.addr.offset(b.startPos), resultLen)
    else:                       # both right and left
      let d1 = BufferSize - b.startPos
      copyMem(result.cstring, b.value.addr.offset(b.startPos), d1)
      copyMem(result.cstring.offset(d1), b.value.addr, resultLen - d1)

  if b.markedPos == b.endMirrorPos: 
    b.startPos = 0
    b.endPos = 0
    b.endMirrorPos = 0
  elif b.markedPos >= BufferSize: 
    b.startPos = b.markedPos - BufferSize
    b.endMirrorPos = b.endPos
  elif b.markedPos < BufferSize: 
    b.startPos = b.markedPos

  b.markedPos = b.startPos

