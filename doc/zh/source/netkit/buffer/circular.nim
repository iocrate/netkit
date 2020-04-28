#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块实现了循环缓冲区 ``CircularBuffer`` 和支持增量标记的循环缓冲区 ``MarkableCircularBuffer`` 。
##
## Overview
## ========================
## 
## ``CircularBuffer`` 内部使用一个固定长度的数组作为存储容器，数组的两端如同连接在一起。当一个数据元素被消费后，
## 其余数据元素不需要移动其存储位置。这使其非常适合缓存数据流。
## 
## .. image::https://upload.wikimedia.org/wikipedia/commons/thumb/b/b7/Circular_buffer.svg/400px-Circular_buffer.svg.png
##    :align: center
## 
## 某一时刻，其存储状态类似： 
##
## .. code-block::nim
##
##   [   空   |---data---|   空  ]
##
## - 参看 `Circular buffer Wiki <https://en.wikipedia.org/wiki/Circular_buffer>`_  
## - 参看 `Circular buffer Wiki 中文 <https://zh.wikipedia.org/wiki/%E7%92%B0%E5%BD%A2%E7%B7%A9%E8%A1%9D%E5%8D%80>`_ 
##
## ``MarkableCircularBuffer`` 继承自 ``CircularBuffer`` ，增加了增量标记的功能，允许对存储的数据进行标记。所谓增量，
## 是指下一次操作总是从上一次结束的位置继续。增量标记简化了诸如 “扫描” 、“分析” 等等一些繁琐的工作。 
##
## .. container:: r-fragment
##
##   存储方法
##   -----------
##
##   循环缓冲区提供两种存储方法： 手动存储和自动存储。
##
##   手动存储是低阶操作，能获得更优的性能但是操作更复杂。您需要直接操作 ``next`` ``pack`` 涉及到的可存储空间的指针，
##   利用 ``copyMem`` 、 ``read(file, pointer, size)`` 或者其他类似的方式直接存储数据。这是一种不安全的方式，
##   但是由于减少了额外的复制，性能更高。
##
##   自动存储是高阶操作，通过 ``add`` 存储数据。这是较为安全并且简单的存储方式，但是有额外的复制开销。
##
## .. container:: r-fragment
##
##   标记
##   -----------
##
##   ``MarkableCircularBuffer`` 支持标记数据。 ``marks()`` 以字符 (字节) 的形式逐个迭代已存储的数据，同时标记该字符 (字节)。
##   这在进行数据分析时特别有用，比如查找 CRLF。当找到期望的标记后，您可以使用 ``popMarks()`` 把已标记的数据提取出来。
##
## .. container:: r-fragment
##
##   增量
##   -----------
##
##   在大部分 IO 场景里，数据并非一次性读取或者写入完成的，通常要经过多次循环操作。 ``MarkableCircularBuffer`` 
##   特意为这种反复操作的环境提供增量支持，增量存储数据并且增量标记数据，这样您不必担心在循环操作的过程中丢失数据状态。
##
## .. container:: r-fragment
##
##   线程安全
##   -----------
##
##   ``CircularBuffer`` 和 ``MarkableCircularBuffer`` 都不保证线程安全。当您在多线程环境使用时，您应该负责控制线程竞争。
##
## Usage
## ========================
## 
## .. container:: r-fragment
##
##   手动存储
##   -----------
## 
##   手动存储的过程分为三步：
##
##   1. 获取可存储空间的地址和长度： 
## 
##   .. code-block::nim
##
##     var buffer = initMarkableCircularBuffer()
##     var (regionPtr, regionLen) = buffer.next()
## 
##   2. 直接操作可存储空间以存储数据：
## 
##   .. code-block::nim
##
##     var readLen = socket.read(regionPtr, regionLen)
## 
##   3. 告诉缓冲区，存储数据的长度：
## 
##   .. code-block::nim
##
##     var packLen = buffer.pack(n)
##
## .. container:: r-fragment
##
##   自动存储
##   -----------
## 
##   存入一个字符：
##
##   .. code-block::nim
##
##     var n = buffer.add('A')
##
##   存入一个字符串：
## 
##   .. code-block::nim
##
##     var str = "ABC"
##     var n = buffer.add(str.cstring, 3)
##
## .. container:: r-fragment
##
##   标记
##   -----------
## 
##   查找以换行符为结尾的字符串：
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
##   ``markUntil`` 让这个过程更加简单：
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
##   读取数据
##   -----------
## 
##   将存储的数据复制到一块指定的内存，并删除数据：
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
##   将存储的数据复制到一个字符串，并删除数据：
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
    ## 一个循环缓冲区。
    data: array[0..BufferSize, byte]
    startPos: Natural                                
    endPos: Natural                                  
    endMirrorPos: Natural                            

  MarkableCircularBuffer* = object of CircularBuffer 
    ## 一个可标记的循环缓冲区。
    markedPos: Natural                               

proc initCircularBuffer*(): CircularBuffer = discard
  ## 初始化一个 ``CircularBuffer`` 。
  
proc initMarkableCircularBuffer*(): MarkableCircularBuffer = discard
  ## 初始化一个 ``MarkableCircularBuffer`` 。
  
proc capacity*(b: CircularBuffer): Natural = discard
  ## 返回缓冲区的容量。

proc len*(b: CircularBuffer): Natural = discard
  ## 返回缓冲区存储的数据长度。

proc next*(b: var CircularBuffer): (pointer, Natural) = discard
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

proc pack*(b: var CircularBuffer, size: Natural): Natural = discard
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

proc add*(b: var CircularBuffer, source: pointer, size: Natural): Natural = discard
  ## 从 ``source`` 复制最多 ``size`` 长度的数据，存储到缓冲区。返回实际存储的长度。这个函数是 ``next()`` 
  ## ``pack()`` 组合调用的简化版本，区别是额外执行一次复制。
  ## 
  ## 当您非常看重性能时，使用 ``next()`` ``pack()`` 组合调用；当您比较看重使用方便时，使用 ``add()`` 。
  ## 
  ## .. code-block::nim
  ##     
  ##   var source = "Hello World"
  ##   var n = buffer.add(source.cstring, source.len)

proc add*(b: var CircularBuffer, c: char): Natural = discard
  ## 存储一个字符 ``c`` ，返回实际存储的长度。如果存储空间已满，则会返回 ``0`` ，否则返回 ``1`` 。

proc get*(b: var CircularBuffer, dest: pointer, size: Natural): Natural = discard
  ## 获取存储的数据，最多 ``size`` 个，将数据复制到目标空间 ``dest`` 。返回实际复制的数量。
  
proc get*(b: var CircularBuffer, size: Natural): string = discard
  ## 获取存储的数据，最多 ``size`` 个，以一个字符串返回。

proc get*(b: var CircularBuffer): string = discard
  ## 获取存储的所有数据，以一个字符串返回。

proc del*(b: var CircularBuffer, size: Natural): Natural = discard
  ## 删除存储的数据，最多 ``size`` 个。返回实际删除的数量。删除总是从存储队列的最前方开始。

iterator items*(b: CircularBuffer): char = discard
  ## 迭代存储的数据。
      
proc del*(b: var MarkableCircularBuffer, size: Natural): Natural = discard
  ## 删除存储的数据，最多 ``size`` 个。返回实际删除的数量。删除总是从存储队列的最前方开始。

iterator marks*(b: var MarkableCircularBuffer): char = discard
  ## 迭代存储的数据，并进行标记。
  ## 
  ## 注意，标记是增量进行的，也就是说，下一次操作将从上一次结束的位置继续。
  ## 
  ## 例子：
  ## 
  ## .. code-block::nim
  ##     
  ##   var s = "Hello World\R\L"
  ##   var n = buffer.add(s.cstring, s.len)
  ## 
  ##   for c in buffer.marks():
  ##     if c == '\L':
  ##       break

proc mark*(b: var MarkableCircularBuffer, size: Natural): Natural = discard
  ## 立刻标记存储的数据，直到 ``size`` 个或者到达数据尾部。返回实际标记的数量。
  ## 
  ## 注意，标记是增量进行的，也就是说，下一次操作将从上一次结束的位置继续。
  ## 
  ## 例子：
  ## 
  ## .. code-block::nim
  ##   
  ##   var buffer = initMarkableCircularBuffer()
  ##   var str = "foo\Lbar\L"
  ##   assert buffer.add(str.cstring, str.len) == str.len
  ## 
  ##   assert buffer.mark(3) == 3
  ##   assert buffer.popMarks() == "foo"

proc markUntil*(b: var MarkableCircularBuffer, c: char): bool = discard
  ## 逐个标记存储的数据，直到遇到一个字节是 ``c`` ，并返回 ``true`` ； 如果没有字节是 ``c`` ，则返回 ``false`` 。
  ## 
  ## 注意，标记是增量进行的，也就是说，下一次操作将从上一次结束的位置继续。
  ## 
  ## 例子：
  ## 
  ## .. code-block::nim
  ##   
  ##   var buffer = initMarkableCircularBuffer()
  ##   var str = "foo\Lbar\L"
  ##   assert buffer.add(str.cstring, str.len) == str.len
  ## 
  ##   assert buffer.markUntil('\L')
  ##   assert buffer.popMarks() == "foo\L"

proc markAll*(b: var MarkableCircularBuffer) = discard
  ## 立刻标记存储的所有数据。
  ## 
  ## 注意，标记是增量进行的，也就是说，下一次操作将从上一次结束的位置继续。
  ## 
  ## 例子：
  ## 
  ## .. code-block::nim
  ##   
  ##   var buffer = initMarkableCircularBuffer()
  ##   var str = "foo\Lbar\L"
  ##   assert buffer.add(str.cstring, str.len) == str.len
  ## 
  ##   buffer.markAll()
  ##   assert buffer.popMarks() == "foo\Lbar\L"

proc lenMarks*(b: MarkableCircularBuffer): Natural = discard
  ## 返回标记的数据长度。

proc popMarks*(b: var MarkableCircularBuffer, n: Natural = 0): string = discard
  ## 获取标记的数据，将数据在尾部向前跳过 ``n`` 个字节，以一个字符串返回。同时，删除这些数据。
  ## 
  ## 
  ## 
  ## 