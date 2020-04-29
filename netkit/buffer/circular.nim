#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module implements a circular buffer ``CircularBuffer`` and a markable circular buffer ``MarkableCircularBuffer``
## that supports incremental marking.
##
## Overview
## ========================
## 
## ``CircularBuffer`` uses a fixed-length array as a storage container, and the two ends of the array are 
## connected together. It does not need to have its elements shuffled around when one is consumed. This lends 
## itself easily to buffering data streams.
## 
## .. image::https://upload.wikimedia.org/wikipedia/commons/thumb/b/b7/Circular_buffer.svg/400px-Circular_buffer.svg.png
##    :align: center
## 
## At a certain moment, its storage state is similar to:
##
## .. code-block::nim
##
##   [   empty   |---data---|   empty  ]
##
## - see `Circular buffer Wiki <https://en.wikipedia.org/wiki/Circular_buffer>`_  
## - see `Circular buffer Wiki 中文 <https://zh.wikipedia.org/wiki/%E7%92%B0%E5%BD%A2%E7%B7%A9%E8%A1%9D%E5%8D%80>`_ 
##
## ``MarkableCircularBuffer`` inherits from ``CircularBuffer`` , and adds the function of incremental marking, allowing 
## the data stored to be marked. Increment means that the next operation will always continue from the previous end 
## position.  Incremental marking simplifies some tedious tasks such as scanning, analysis and so on.
##
## .. container:: r-fragment
##
##   Storage methods 
##   ----------------------
##
##   The circular buffer provides two storage methods: manual storage and automatic storage.
##
##   Manual storage is a low-level operation, which can obtain better performance but is more complicated.
##   You need to directly manipulate the storable space involved in ``next`` and ``pack``, and use ``copyMem``, 
##   ``read(file, pointer, size)`` or other similar methods to directly store data. This is an unsafe method, but there 
##   is no  additional copy, so you can get better performance.
##
##   Automatic storage is a high-level operation, storing data with ``add``. This is a safer and simpler method, but 
##   it has additional copy overhead.
##
## .. container:: r-fragment
##
##   Marking
##   -----------
##
##   ``MarkableCircularBuffer`` allows marking data. ``marks()`` iterates the stored data one by one in the form of 
##   characters (bytes), and marks the characters (bytes) at the same time. This is especially useful for data analysis, 
##   such as searching a CRLF. When you find the desired mark, you can use ``popMarks`` to extract the marked data.
##
## .. container:: r-fragment
##
##   Increment
##   -----------
##   
##   In most IO scenarios, you need to read or write data repeatedly. ``MarkableCircularBuffer`` provides incremental 
##   support for this  environment, incrementally storing data and incrementally marking data, so that you don't have 
##   to worry about losing data state in a loop operation.
##
## .. container:: r-fragment
##
##   Thread safety
##   -----------
##
##   ``CircularBuffer`` and ``MarkableCircularBuffer`` does not guarantees thread safety. When you use them in multiple
##   threads, you should be responsible for conditional competition.
##
## Usage
## ========================
## 
## .. container:: r-fragment
##
##   Manual storage
##   ---------------
## 
##   Manual storage can be divided into three steps:
##
##   1. Gets the address and the length of a storable space： 
## 
##   .. code-block::nim
##
##     var buffer = initMarkableCircularBuffer()
##     var (regionPtr, regionLen) = buffer.next()
## 
##   2. Operates the storable space to store data：
## 
##   .. code-block::nim
##
##     var readLen = socket.read(regionPtr, regionLen)
## 
##   3. Tell the buffer the length of the stored data：
## 
##   .. code-block::nim
##
##     var packLen = buffer.pack(n)
##
## .. container:: r-fragment
##
##   Automatic storage
##   ------------------
## 
##   To store a character:
##
##   .. code-block::nim
##
##     var n = buffer.add('A')
##
##   To store a string:
## 
##   .. code-block::nim
##
##     var str = "ABC"
##     var n = buffer.add(str.cstring, 3)
##
## .. container:: r-fragment
##
##   Marking
##   -----------
## 
##   To search a string ending with a newline character:
##
##   .. code-block::nim
##     
##     var buffer = initMarkableCircularBuffer()
##     var str = "foo\Lbar\L"
##     assert buffer.add(str.cstring, str.len) == str.len
##     
##     var lineString = ""
## 
##     for c in buffer.marks():
##       if c == '\L':
##         lineString = buffer.popMarks(1)
##         break
##     assert lineString == "foo"
## 
##     for c in buffer.marks():
##       if c == '\L':
##         lineString = buffer.popMarks(1)
##         break
##     assert lineString == "bar"
##
##   ``markUntil`` makes this process easier:
##
##   .. code-block::nim
##
##     var buffer = initMarkableCircularBuffer()
##     var str = "foo\Lbar\L"
##     assert buffer.add(str.cstring, str.len) == str.len
##     
##     var lineString = ""
## 
##     assert buffer.markUntil('\L')
##     assert lineString == "foo"
## 
##     assert buffer.markUntil('\L')
##     assert lineString == "bar"
##
## .. container:: r-fragment
##
##   Read data
##   -----------
## 
##   Copy the stored data to a specified memory and delete the data:
##
##   .. code-block::nim
## 
##     var buffer = initMarkableCircularBuffer()
##     var str = "foo\Lbar\L"
##     assert buffer.add(str.cstring, str.len) == str.len
##     assert buffer.len == str.len
##     
##     var dest = newString(64)
##     var getLen = buffer.get(dest, destLen)
##     var delLen = buffer.del(getLen)
##     dest.setLen(getLen)
## 
##     assert dest == "foo\Lbar\L"
##     assert buffer.len == 0
## 
##   Copy the stored data to a string and delete the data:
##
##   .. code-block::nim
## 
##     var buffer = initMarkableCircularBuffer()
##     var str = "foo\Lbar\L"
##     assert buffer.add(str.cstring, str.len) == str.len
##     assert buffer.len == str.len
##     
##     var foo = buffer.get(3)
##     assert foo == "foo"

import netkit/misc
import netkit/buffer/constants

type 
  CircularBuffer* = object of RootObj                
    ## A circular buffer. Note that the maximum length of its storage space is ``BufferSize``.
    value: array[0..BufferSize, byte]
    startPos: Natural                                #  0..n-1 
    endPos: Natural                                  #  0..n-1 
    endMirrorPos: Natural                            #  0..2n-1 

  MarkableCircularBuffer* = object of CircularBuffer 
    ## A markable circular buffer.
    markedPos: Natural                               #  0..2n-1 

proc initCircularBuffer*(): CircularBuffer = 
  ## Initializes an ``CircularBuffer``. 
  discard

proc capacity*(b: CircularBuffer): Natural {.inline.} = 
  ## Returns the capacity of this buffer.
  BufferSize

proc len*(b: CircularBuffer): Natural {.inline.} = 
  ## Returns the length of the data stored in this buffer.
  b.endMirrorPos - b.startPos

proc next*(b: var CircularBuffer): (pointer, Natural) = 
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
  result[1] = if b.endMirrorPos < BufferSize: BufferSize - b.endPos
              else: b.startPos - b.endPos

proc pack*(b: var CircularBuffer, size: Natural): Natural = 
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
  if b.endMirrorPos < BufferSize:
    result = min(size, BufferSize - b.endPos) 
    b.endMirrorPos = b.endMirrorPos + result
    b.endPos = b.endMirrorPos mod BufferSize
  else:
    result = min(size, b.startPos - b.endPos) 
    b.endMirrorPos = b.endMirrorPos + result
    b.endPos = b.endMirrorPos mod BufferSize

proc add*(b: var CircularBuffer, source: pointer, size: Natural): Natural = 
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
  ## Stores a character ``c`` in the buffer and returns the actual stored length. If the storage space is full, it will 
  ## return ``0``, otherwise ``1``.
  let region = b.next()
  result = min(region[1], 1)
  if result > 0:
    cast[ptr char](region[0])[] = c
    discard b.pack(result)

proc get*(b: var CircularBuffer, dest: pointer, size: Natural): Natural = 
  ## Gets up to ``size`` of the stored data, and copy the data to the space ``dest``. Returns the actual number copied.
  result = min(size, b.endMirrorPos - b.startPos)
  if b.startPos + result <= BufferSize: # only right
    copyMem(dest, b.value.addr.offset(b.startPos), result)
  else:                                 # both right and left
    let majorLen = BufferSize - b.startPos
    copyMem(dest, b.value.addr.offset(b.startPos), majorLen)
    copyMem(dest.offset(majorLen), b.value.addr, result - majorLen)
  
proc get*(b: var CircularBuffer, size: Natural): string = 
  ## Gets up to ``size`` of the  stored data and returns as a string. 
  let length = min(b.endMirrorPos - b.startPos, size)
  result = newString(length)
  discard b.get(result.cstring, length)

proc get*(b: var CircularBuffer): string = 
  ## Gets all stored data and returns as a string.
  result = b.get(b.endMirrorPos - b.startPos)

proc del*(b: var CircularBuffer, size: Natural): Natural = 
  ## Deletes up to ``size`` of the stored data and returns the actual number deleted.
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
  ## Initializes an ``MarkableCircularBuffer``. 
  discard
      
proc del*(b: var MarkableCircularBuffer, size: Natural): Natural = 
  ## Deletes up to ``size`` of the stored data and returns the actual number deleted.
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
  ## Iterate over the stored data, and marks the data at the same time.
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
  ## Marks the stored data one by one until a byte is ``c``. ``false`` is returned if no byte is ``c``.
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
  ## Returns the length of the stored data that has been marked.
  b.markedPos - b.startPos

proc popMarks*(b: var MarkableCircularBuffer, n: Natural = 0): string = 
  ## Pops the marked data, skip the data from the end forward by ``n`` bytes, and return it as a string. At the same time, 
  ## delete these data.
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

