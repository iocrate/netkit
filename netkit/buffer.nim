#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## TODO: 翻译本注释内的说明
## TODO: 将翻译的文档以 reStructuredText 语法格式书写，以便于 nimdoc 生成文档
## TODO: 更多测试
## TODO: Benchmark Test
##
## 本模块实现了一个支持增量模式的可标记的循环缓冲 ``MarkableCircularBuffer``。``MarkableCircularBuffer`` 内部使用一个
## 固定长度的数组作为存储容器。``MarkableCircularBuffer`` 顺序的存储数据，直到尾部，到达尾部时，``MarkableCircularBuffer`` 
## 查看头部是否仍有空闲空间，如果有的话，则使用这些空闲空间继续存储数据，直到全满为止。当没有空闲空间时，您
## 必须取走已存储的数据，或者直接清空所有已存储的数据，才能继续存储新的数据。
##
## 某一个时刻，其存储状态类似：
##
##     [   空   |---data---|   空  ]
##
## `Circular buffer Wiki <https://en.wikipedia.org/wiki/Circular_buffer>`_
## `Circular buffer Wiki-中文 <https://zh.wikipedia.org/wiki/%E7%92%B0%E5%BD%A2%E7%B7%A9%E8%A1%9D%E5%8D%80>`_
##
## 关于标记
## -------
##
## 支持标记数据。``marks()`` 以字符的形式逐个迭代所有已存储的数据，同时标记该字符 (字节)。这在进行数据解析
## 时特别有用，比如您可以查找特定字符 CRCL，并使用 ``getMarks()`` 把查找过程标记的字符提取出来。
##
## 关于增量
## -------
##
## 在大部分 IO 场景里，数据不是一次性读取或者写入完成的，通常要经过多次循环操作。``MarkableCircularBuffer`` 特意为
## 这种反复操作的环境提供增量支持，增量存储数据并且增量标记数据，这样您不必担心在循环操作的过程中丢失数据状态。
##
## 关于线程安全
## -----------
##
## ``MarkableCircularBuffer`` 不保证线程安全，当您在多线程环境使用时，您应该负责线程竞争的控制。
##
## 关于存储方法
## -----------
##
## 提供两种存储方法：手动存储和自动存储。手动存储是低阶操作，您需要提供数据源的指针和长度，利用 ``copyMem`` 或
## 者其他类似的操作直接操作 ``MarkableCircularBuffer`` 的内部存储空间，这种方式是一种不安全的方式，但是由于减少了一
## 次复制操作，性能更高；自动存储提供 ``put`` 调用，是安全简单的存储方式，有额外的复制开销。
##
## 如何使用
## -------
##
## ``MarkableCircularBuffer`` 的使用过程可以归纳为以下图示：
##
##     获取有效的存储区域 -> 存储数据 -> 标记，提取标记序列 or 直接提取指定长度的序列 -> 清空数据
##
## 1. 手动存储：获取缓冲区下一块有效的存储区域，手动存储
##
##        var buffer = MarkableCircularBuffer()
##        var (regionPtr, regionLen) = buffer.next()
##  
##        var n = socket.read(regionPtr, regionLen)
##        buffer.pack(n)
##    
##    如果 ``length`` 为 ``0`` 说明已满无法继续存储
##
## 2. 自动存储：
##
##        var n = buffer.put('A')
##
##    或者
##
##        var str = "123"
##        var n = buffer.put(str.cstring, 3)
##
## 3. 标记，提取标记序列。这个过程清空所有已标记的数据
##
##        for c in buffer.marks():
##          if c == '\L':
##            break
##
##        var lineString = buffer.popMarks(1)
##
##    或者
##
##        buffer.markUntil('\L')
##
## 4. 您也直接提取指定长度的序列，同时重置所有已经标记的字符。这个过程清空有效长度的数据
##
##     var getLen = buffer.get(dest, destLen)
##     var delLen = buffer.del(getLen)

const BufferSize* {.intdefine.}: uint16 = 8*1024  # 0..65535/2

type 
  CircularBuffer* = object of RootObj                ## A circular buffer object.
    value: array[0..BufferSize.int, char]
    startPos: uint16                                 # 0..n-1 
    endPos: uint16                                   # 0..n-1 
    endMirrorPos: uint16                             # 0..2n-1 

  MarkableCircularBuffer* = object of CircularBuffer ## A markable circular buffer object that supports incremental marks.
    markedPos: uint16                                # 0..2n-1 

template offset*(p: pointer, n: uint16): pointer = 
  cast[pointer](cast[ByteAddress](p) + n.int)

proc capacity*(b: CircularBuffer): uint16 = 
  ## Gets the capacity of the buffer.
  BufferSize

proc len*(b: CircularBuffer): uint16 = 
  ## Gets the length of the data.
  b.endMirrorPos - b.startPos

proc next*(b: var CircularBuffer): (pointer, uint16) = 
  ## Gets the next secure storage area. You can only get one block per operation.
  ## Returns the address and storable length of the area. Then you can manually
  ## store the data for that area.
  ## 
  ## 获取下一个安全的存储区域，每次操作只能获得一块，返回该区域的地址和可存储长度。之后，您可以对该区域手动
  ## 存储数据。
  result[0] = offset(b.value.addr, b.endPos)
  result[1] = if b.endMirrorPos < BufferSize: BufferSize - b.endPos
              else: b.startPos - b.endPos

proc pack*(b: var CircularBuffer, size: uint16): uint16 = 
  ## The area of ``size`` length inside the buffer is regarded as valid data and returns the actual length.
  ## Once this operation is performed, this space will be forced to be used as valid data. In other words,
  ## this method increases the length of the buffer's valid data.
  #
  ## 将缓冲区内部 ``size`` 长度的空间区域视为有效数据，返回实际有效的长度。一旦执行这个操作，这部分空间将被
  ## 强制作为有效数据使用。换句话说，这个方法增长了 buffer 有效数据的长度。
  assert size > 0'u16
  if b.endMirrorPos < BufferSize:
    result = min(size, BufferSize - b.endPos) 
    b.endMirrorPos = b.endMirrorPos + result
    b.endPos = b.endMirrorPos mod BufferSize
  else:
    result = min(size, b.startPos - b.endPos) 
    b.endMirrorPos = b.endMirrorPos + result
    b.endPos = b.endMirrorPos mod BufferSize

proc put*(b: var CircularBuffer, source: pointer, size: uint16): uint16 = 
  ## Writes `source` of `size` length to the buffer and returns the actual size written.
  ##
  ## 从 `source` 写入 `size` 长度的数据，返回实际写入的长度。
  result = min(BufferSize - b.len, size)
  if result > 0'u16:
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

proc put*(b: var CircularBuffer, c: char): uint16 = 
  ## Writes char `c` and returns the actual length written.
  ##
  ## 写入一个字符 `c`，返回实际写入的长度。
  let region = b.next()
  result = min(region[1], 1)
  if result > 0'u16:
    cast[ptr char](region[0])[] = c
    discard b.pack(result)

proc get*(b: var CircularBuffer, dest: pointer, size: uint16): uint16 = 
  ## 获取最多 ``size`` 个数据，将其复制到目标空间 ``dest``，返回实际复制的数量。
  result = min(size, b.endMirrorPos - b.startPos)
  if result > 0'u16:
    if b.startPos + result <= BufferSize: # only right
      copyMem(dest, b.value.addr.offset(b.startPos), result)
    else:                                 # both right and left
      let majorLen = BufferSize - b.startPos
      copyMem(dest, b.value.addr.offset(b.startPos), majorLen)
      copyMem(dest.offset(majorLen), b.value.addr, result - majorLen)
  
proc get*(b: var CircularBuffer, size: uint16): string = 
  ## 获取最多 ``size`` 个数据，以一个字符串返回。
  let length = min(b.endMirrorPos - b.startPos, size)
  if length > 0'u16:
    result = newString(length)
    discard b.get(result.cstring, length)

proc get*(b: var CircularBuffer): string = 
  ## 获取所有数据，以一个字符串返回。
  result = b.get(b.endMirrorPos - b.startPos)

proc del*(b: var CircularBuffer, size: uint16): uint16 = 
  ## 删除最多 ``size`` 个数据，返回实际删除的数量。
  result = min(size, b.endMirrorPos - b.startPos)
  if result > 0'u16:
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
      
proc del*(b: var MarkableCircularBuffer, size: uint16): uint16 = 
  ## 删除最多 ``size`` 个数据，返回实际删除的数量。
  result = min(size, b.endMirrorPos - b.startPos)
  if result > 0'u16:
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
  ## 逐个标记缓冲区的数据，并 yield 每一个标记的数据。标记是增量进行的，也就是说，下一次标记会从上一次标记继续。
  while b.markedPos < b.endMirrorPos:
    let i = b.markedPos mod BufferSize
    b.markedPos.inc()
    yield b.value[i]

proc mark*(b: var MarkableCircularBuffer, size: uint16): uint16 =
  ## 立刻标记缓冲区的数据，直到 ``size`` 个或者到达数据尾部，返回实际标记的数量。标记是增量
  ## 进行的，也就是说，下一次标记会从上一次标记继续。
  let m = b.markedPos + size
  if m <= b.endMirrorPos:
    b.markedPos = m
    result = size
  else:
    result = b.endMirrorPos - b.markedPos
    b.markedPos = b.endMirrorPos

proc markUntil*(b: var MarkableCircularBuffer, c: char): bool =
  ## 逐个标记缓冲区的数据，直到遇到一个字节是 ``c``，并返回 ``true``；如果没有字节是 ``c``，则返回 ``false``。标记是增量
  ## 进行的，也就是说，下一次标记会从上一次标记继续。
  result = false
  for ch in b.marks():
    if ch == c:
      return true

proc markAll*(b: var MarkableCircularBuffer) =
  ## 立刻标记缓冲区所有的数据。标记是增量进行的，也就是说，下一次标记会从上一次标记继续。
  b.markedPos = b.endMirrorPos

proc lenMarks*(b: MarkableCircularBuffer): uint16 = 
  ## Gets the length of the data that has been makerd.
  b.markedPos - b.startPos

proc popMarks*(b: var MarkableCircularBuffer, size: uint16 = 0): string = 
  ## Gets the currently marked data, skip backward `n` characters and deletes all marked data.
  if b.markedPos == b.startPos:
    return ""

  let resultPos = b.markedPos - size
  let resultLen = resultPos - b.startPos

  if resultLen > 0'u16:
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

