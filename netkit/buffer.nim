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
##     var buffer = MarkableCircularBuffer()
##     var (regionPtr, regionLen) = buffer.next()
##  
##     var n = socket.read(regionPtr, regionLen)
##     buffer.pack(n)
##    
##    如果 ``length`` 为 ``0`` 说明已满无法继续存储
##
## 2. 自动存储：
##
##    var n = buffer.put('A')
##
##    或者
##
##    var str = "123"
##    var n = buffer.put(str.cstring, 3)
##
## 3. 标记，提取标记序列。这个过程清空所有已标记的数据
##
##     for c in buffer.marks():
##       if c == '\L':
##         break
##
##     var lineString = buffer.getMarks(1)
##
## 4. 您也直接提取指定长度的序列，同时重置所有已经标记的字符。这个过程清空有效长度的数据
##
##     var n = buffer.copyTo(dest, destLen)
##
##    ``n`` 表示实际提取的长度，同时表示该长度的数据已经被清空。

const BufferSize* {.intdefine.}: uint16 = 8*1024  # 0..65535/2
const DoubleBufferSize: uint16 = 2'u16 * BufferSize   # 0..65535

type 
  MarkableCircularBuffer* = object         ## A markable circular buffer object that supports incremental marks.
    value: array[0..BufferSize.int, char]
    startPos: uint16                       # 0..<=n-1   
    endPos: uint16                         # 0..<=n-1   
    endMirrorPos: uint16                   # 0..<=2n-1  
    markedPos: uint16                      # 0..<=2n-1 

template offset(p: pointer, n: uint16): pointer = 
  cast[pointer](cast[ByteAddress](p) + n.int)

proc capacity*(b: MarkableCircularBuffer): uint16 = 
  ## Get the capacity of the buffer.
  BufferSize

proc len*(b: MarkableCircularBuffer): uint16 = 
  ## Gets the length of the data.
  b.endMirrorPos - b.startPos

proc next*(b: var MarkableCircularBuffer): (pointer, uint16) = 
  ## 获取下一个安全的存储区域，每次操作只能获得一块，返回该区域的地址和可存储长度。之后，您可以对该区域手动
  ## 存储数据。
  result[0] = offset(b.value.addr, b.endPos)
  result[1] = if b.endMirrorPos < BufferSize: BufferSize - b.endPos
              else: b.startPos - b.endPos

proc pack*(b: var MarkableCircularBuffer, n: uint16): uint16 = 
  ## 将 buffer 内部 ``n`` 长度的空间区域视为有效数据，返回实际有效的长度。一旦执行这个操作，这部分空间将被
  ## 强制作为有效数据使用。换句话说，这个方法增长了 buffer 有效数据的长度。
  assert n > 0'u16
  if b.endMirrorPos < BufferSize:
    result = min(n, BufferSize - b.endPos) 
    b.endMirrorPos = b.endMirrorPos + result
    b.endPos = b.endMirrorPos mod BufferSize
  else:
    result = min(n, b.startPos - b.endPos) 
    b.endMirrorPos = b.endMirrorPos + result
    b.endPos = b.endMirrorPos mod BufferSize

proc copyTo*(b: var MarkableCircularBuffer, dest: pointer, length: uint16): uint16 = 
  ## 直接提取指定长度的序列，将这些数据复制到目标空间。`dest` 指定目标空间，`length` 指定目标空间的长度。
  ## 返回实际复制的字节数量。
  ##
  ## 这个过程清空实际复制的数据。
  ## 这个过程重置所有已标记的数据。
  assert length > 0'u16

  if b.endMirrorPos == b.startPos:
    return 0'u16

  if b.endMirrorPos <= BufferSize: # only right
    result = min(b.endMirrorPos - b.startPos, length) 
    copyMem(dest, b.value.addr.offset(b.startPos), result)
    b.startPos = b.startPos + result
    if b.startPos == BufferSize:
      b.startPos = 0
      b.endMirrorPos = 0
  else:                            # both right and left
    var d1 = 0'u16
    var d2 = 0'u16

    d1 = min(BufferSize - b.startPos, length) 
    copyMem(dest, b.value.addr.offset(b.startPos), d1)
    b.startPos = b.startPos + d1
    if length > d1:
      d2 = min(b.endMirrorPos - BufferSize, length - d1) 
      copyMem(dest.offset(d1), b.value.addr, d2)
      if d2 == b.endPos:
        b.startPos = 0
        b.endPos = 0
        b.endMirrorPos = 0
      else:
        b.startPos = d2
        b.endMirrorPos = b.endPos
    elif b.startPos == BufferSize:
      b.startPos = 0
      b.endMirrorPos = b.endPos

    result = d1 + d2

  b.markedPos = b.startPos

proc put*(b: var MarkableCircularBuffer, data: pointer, length: uint16): uint16 = 
  ## 从 `data` 写入 `length` 长度的数据，返回实际写入的长度。
  let region = b.next()
  result = min(region[1], length)
  if result > 0'u16:
    copyMem(region[0], data, result)
    discard b.pack(result)

proc put*(b: var MarkableCircularBuffer, c: char): uint16 = 
  ## 写入一个字符 `c`，返回实际写入的长度。
  let region = b.next()
  result = min(region[1], 1)
  if result > 0'u16:
    cast[ptr char](region[0])[] = c
    discard b.pack(result)

iterator items*(b: var MarkableCircularBuffer): char =
  ## Iterates over all available data (chars) but not mark. 
  var i = b.startPos
  while i < b.endMirrorPos:
    yield b.value[i]
    i.inc()

iterator marks*(b: var MarkableCircularBuffer): char =
  ## Incrementally iterates over and marks all available data (chars). 
  while b.markedPos < b.endMirrorPos:
    let i = b.markedPos mod BufferSize
    b.markedPos.inc()
    yield b.value[i]

proc lenMarks*(b: MarkableCircularBuffer): uint16 = 
  ## Gets the length of the data that has been makerd.
  b.markedPos - b.startPos

proc getMarks*(b: var MarkableCircularBuffer, n: uint16 = 0): string = 
  ## Gets the currently marked data, skip backward `n` characters.
  ##
  ## This process clears all marked data.
  if b.markedPos == b.startPos:
    return ""

  let resultPos = b.markedPos - n
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