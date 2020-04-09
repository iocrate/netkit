#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

# TODO: 翻译 doc/source/buffer/circular.nim 的注释， 将英文版追加到本文件
# TODO: 更多单元测试， 测试稳定性和安全性
# TODO: Benchmark Test

import netkit/misc, netkit/buffer/constants

type 
  CircularBuffer* = object of RootObj                
    ## A data structure that uses a single, fixed-size buffer as if it were connected end-to-end. 
    value: array[0..BufferSize, char]
    startPos: Natural                                #  0..n-1 
    endPos: Natural                                  #  0..n-1 
    endMirrorPos: Natural                            #  0..2n-1 

  MarkableCircularBuffer* = object of CircularBuffer 
    ## A markable circular buffer object that supports incremental marks.
    markedPos: Natural                               #  0..2n-1 

proc initCircularBuffer*(): CircularBuffer = 
  ## Initializes an ``CircularBuffer`` object. 
  discard

proc initMarkableCircularBuffer*(): MarkableCircularBuffer =
  discard

proc capacity*(b: CircularBuffer): Natural = 
  ## Gets the capacity of the buffer.
  BufferSize

proc len*(b: CircularBuffer): Natural = 
  ## Gets the length of the data.
  b.endMirrorPos - b.startPos

proc next*(b: var CircularBuffer): (pointer, Natural) = 
  ## Gets the next secure storage area. You can only get one block per operation.
  ## Returns the address and storable length of the area. Then you can manually
  ## store the data for that area.
  ## 
  ## ..code-block::nim
  ##     
  ##   var source = "Hello World"
  ##   var (regionPtr, regionLen) = b.next()
  ##   var length = min(regionLen, s.len)
  ##   copyMem(regionPtr, source.cstring, length) 
  result[0] = b.value.addr.offset(b.endPos)
  result[1] = if b.endMirrorPos < BufferSize: BufferSize - b.endPos
              else: b.startPos - b.endPos

proc pack*(b: var CircularBuffer, size: Natural): Natural = 
  ## The area of ``size`` length inside the buffer is regarded as valid data and returns the actual length.
  ## Once this operation is performed, this space will be forced to be used as valid data. In other words,
  ## this method increases the length of the buffer's valid data.
  ## 
  ## ..code-block::nim
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
  ## Writes ``source`` of ``size`` length to the buffer and returns the actual size written.
  ## 
  ## ..code-block::nim
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
  ## Writes char ``c`` and returns the actual length written.
  let region = b.next()
  result = min(region[1], 1)
  if result > 0:
    cast[ptr char](region[0])[] = c
    discard b.pack(result)

proc get*(b: var CircularBuffer, dest: pointer, size: Natural): Natural = 
  ## 
  result = min(size, b.endMirrorPos - b.startPos)
  if b.startPos + result <= BufferSize: # only right
    copyMem(dest, b.value.addr.offset(b.startPos), result)
  else:                                 # both right and left
    let majorLen = BufferSize - b.startPos
    copyMem(dest, b.value.addr.offset(b.startPos), majorLen)
    copyMem(dest.offset(majorLen), b.value.addr, result - majorLen)
  
proc get*(b: var CircularBuffer, size: Natural): string = 
  ## 
  let length = min(b.endMirrorPos - b.startPos, size)
  result = newString(length)
  discard b.get(result.cstring, length)

proc get*(b: var CircularBuffer): string = 
  ## 
  result = b.get(b.endMirrorPos - b.startPos)

proc del*(b: var CircularBuffer, size: Natural): Natural = 
  ## 
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
  ## Iterates over all available data (chars). 
  var i = b.startPos
  while i < b.endMirrorPos:
    yield b.value[i mod BufferSize]
    i.inc()
      
proc del*(b: var MarkableCircularBuffer, size: Natural): Natural = 
  ## 
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
  ##
  ## 
  ## ..code-block::nim
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
    yield b.value[i]

proc mark*(b: var MarkableCircularBuffer, size: Natural): Natural =
  ## 
  let m = b.markedPos + size
  if m <= b.endMirrorPos:
    b.markedPos = m
    result = size
  else:
    result = b.endMirrorPos - b.markedPos
    b.markedPos = b.endMirrorPos

proc markUntil*(b: var MarkableCircularBuffer, c: char): bool =
  ## 
  result = false
  for ch in b.marks():
    if ch == c:
      return true

proc markAll*(b: var MarkableCircularBuffer) =
  ## 
  b.markedPos = b.endMirrorPos

proc lenMarks*(b: MarkableCircularBuffer): Natural = 
  ## Gets the length of the data that has been makerd.
  b.markedPos - b.startPos

proc popMarks*(b: var MarkableCircularBuffer, n: Natural = 0): string = 
  ## Gets the currently marked data, skip backward ``n`` characters and deletes all marked data.
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

