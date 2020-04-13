#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 本模块实现了一个循环缓冲区 ``CircularBuffer`` 和一个支持增量标记的循环缓冲区 ``MarkableCircularBuffer`` 。 
##
## ``CircularBuffer`` 内部使用一个固定长度的数组作为存储容器， 并在存储数据的时候执行循环存储。 即， 当到达尾部时， 缓冲区查看另一
## 端是否仍有空闲空间， 如果有的话， 则使用这些空闲空间继续存储数据， 直到全满为止。 某一个时刻， 其存储状态类似： 
##
## ..code-block::nim
##
##   ``[   空   |---data---|   空  ]``
##
## - 参看 `Circular buffer Wiki <https://en.wikipedia.org/wiki/Circular_buffer>`_  
## - 参看 `Circular buffer Wiki-中文 <https://zh.wikipedia.org/wiki/%E7%92%B0%E5%BD%A2%E7%B7%A9%E8%A1%9D%E5%8D%80>`_ 
##
## ``MarkableCircularBuffer`` 继承自 ``CircularBuffer`` ， 增加了增量标记的功能， 您可以对存储的数据进行标记。所谓增量， 是指每
## 次操作之后， 下一次从上一次结束的位置继续。 增量标记简化了诸如 “扫描” 、 “分析” 等等一些繁琐的工作。  
##
##
## 关于存储方法
## -----------
##
## 循环缓冲区提供两种存储方法： 手动存储和自动存储。 
##
## 手动存储是低阶操作， 专门面向低消耗设计。 您需要操作返回的可存储空间的指针和长度， 
## 利用 ``copyMem`` 或者其他类似的操作直接存储， 这种方式是一种不安全的方式， 但是由于减少了一次复制操作， 性能更高。 
##
## 自动存储是高阶操作， 提供 
## ``put`` 调用， 是较为安全简单的存储方式， 有额外的复制开销。 
##
## 关于标记
## -----------
##
## ``MarkableCircularBuffer`` 支持标记数据。 ``marks()`` 以字符 (字节) 的形式逐个迭代已存储的数据， 同时标记该字符 (字节)。 这
## 在进行数据解析时特别有用， 比如查找特定字符 CRLF。然后， 您可以使用 ``popMarks()`` 把标记的所有数据提取出来。 
##
## 关于增量
## -----------
##
## 在大部分 IO 场景里， 数据不是一次性读取或者写入完成的， 通常要经过多次循环操作。 ``MarkableCircularBuffer`` 特意为
## 这种反复操作的环境提供增量支持， 增量存储数据并且增量标记数据， 这样您不必担心在循环操作的过程中丢失数据状态。 
##
## 关于线程安全
## -----------
##
## ``CircularBuffer`` 和 ``MarkableCircularBuffer`` 都不保证线程安全。 当您在多线程环境使用时， 您应该负责线程竞争的控制。 
##
## 如何使用
## -----------
##
## 1. 手动存储： 
##
##        var buffer = initMarkableCircularBuffer()
##        var (regionPtr, regionLen) = buffer.next()
## 
##        var readLen = socket.read(regionPtr, regionLen)
##        var packLen = buffer.pack(n)
##
## 2. 自动存储：
##
##        var n = buffer.put('A')
##
##    或者：
##
##        var str = "ABC"
##        var n = buffer.put(str.cstring, 3)
##
## 3. 标记， 并获取标记的数据：
##
##        for c in buffer.marks():
##          if c == '\L':
##            var lineString = buffer.popMarks(1)
##            break
##
##    或者：
##
##        var res = buffer.markUntil('\L')
##
## 4. 获取指定长度的数据， 删除指定长度的数据：
##
##        var getLen = buffer.get(dest, destLen)
##        var delLen = buffer.del(getLen)

import netkit/misc
import netkit/buffer/constants

type 
  CircularBuffer* = object of RootObj                
    ## 一个数据结构。 它使用一个固定大小的缓冲区， 存储数据的时候两端如同是连接成环状。 
    data: array[0..BufferSize, byte]
    startPos: Natural                                
    endPos: Natural                                  
    endMirrorPos: Natural                            

  MarkableCircularBuffer* = object of CircularBuffer 
    ## 一个可标记的循环缓冲区对象， 支持增量标记存储的数据。 当扫描或者分析数据时， 特别有用。 
    markedPos: Natural                               

proc initCircularBuffer*(): CircularBuffer = discard
  ## 初始化一个 ``CircularBuffer`` 对象。 
  
proc initMarkableCircularBuffer*(): MarkableCircularBuffer = discard
  ## 初始化一个 ``MarkableCircularBuffer`` 对象。 
  
proc capacity*(b: CircularBuffer): Natural = discard
  ## 获取缓冲区的容量。 

proc len*(b: CircularBuffer): Natural = discard
  ## 获取缓冲区当前存储的数据长度。 

proc next*(b: var CircularBuffer): (pointer, Natural) = discard
  ## 获取下一个安全的可存储区域。 返回值表示可存储区域的指针和可存储长度。 每次操作只能获得一块， 之后， 
  ## 您可以利用返回的指针和长度手动存储数据。比如： 
  ## 
  ## ..code-block::nim
  ##     
  ##   var source = "Hello World"
  ##   var (regionPtr, regionLen) = b.next()
  ##   var length = min(regionLen, s.len)
  ##   copyMem(regionPtr, source.cstring, length) 

proc pack*(b: var CircularBuffer, size: Natural): Natural = discard
  ## 告诉缓冲区， 当前存储位置向后 ``size`` 长度成为有效数据。 返回实际有效的长度。 
  ## 
  ## 当调用 ``next()`` 时， 仅仅将缓冲区内部的存储空间写入数据， 但是缓冲区无法得知写入了多少有效数据。 
  ## ``pack()`` 告诉缓冲区实际写入的有效数据长度。 
  ## 
  ## 每当调用 ``next()`` 时， 都应当立刻调用 ``pack()`` 。 
  ## 
  ## ..code-block::nim
  ##     
  ##   var source = "Hello World"
  ##   var (regionPtr, regionLen) = b.next()
  ##   var length = min(regionLen, s.len)
  ##   copyMem(regionPtr, source.cstring, length) 
  ##   var n = b.pack(length)

proc add*(b: var CircularBuffer, source: pointer, size: Natural): Natural = discard
  ## 从源 ``source`` 复制最多 ``size`` 长度的数据， 写入到缓冲区。 返回实际写入的长度。 这个函数是 ``next()`` 
  ## ``pack()`` 组合调用的简化版本， 区别是额外进行一次复制， 而不是直接写入缓冲区。 
  ## 
  ## 当您对性能非常看重时， 考虑使用 ``next()`` ``pack()`` 组合调用；当您对调用便捷比较看重时， 使用 ``put()`` 。 
  ## 
  ## ..code-block::nim
  ##     
  ##   var source = "Hello World"
  ##   var n = b.put(source.cstring, source.len)

proc add*(b: var CircularBuffer, c: char): Natural = discard
  ## 写入一个字符 ``c`` ， 返回实际写入的长度。 如果存储空间已满， 则会返回 ``0``， 否则返回 ``1`` 。 

proc get*(b: var CircularBuffer, dest: pointer, size: Natural): Natural = discard
  ## 获取当前存储的数据， 最多 ``size`` 个， 将其复制到目标空间 ``dest`` 。 返回实际复制的数量。 
  
proc get*(b: var CircularBuffer, size: Natural): string = discard
  ## 获取当前存储的数据， 最多 ``size`` 个， 以一个字符串返回。 

proc get*(b: var CircularBuffer): string = discard
  ## 获取当前存储的数据， 以一个字符串返回。 

proc del*(b: var CircularBuffer, size: Natural): Natural = discard
  ## 删除当前存储的数据， 最多 ``size`` 个。 返回实际删除的数量。 删除操作总是从存储队列的最前方开始。 

iterator items*(b: CircularBuffer): char = discard
  ## 迭代当前存储的数据。 
      
proc del*(b: var MarkableCircularBuffer, size: Natural): Natural = discard
  ## 删除当前存储的数据， 最多 ``size`` 个。 返回实际删除的数量。 删除操作总是从存储队列的最前方开始。 

iterator marks*(b: var MarkableCircularBuffer): char = discard
  ## 迭代当前存储的数据， 并进行标记。 
  ## 
  ## 注意， 标记是增量进行的， 也就是说， 下一次调用标记操作时将从上一次标记结束的位置继续。 
  ## 
  ## ``MarkableCircularBuffer`` 提供了多个名称带有 mark 的标记迭代器和函数。 
  ## 
  ## ..code-block::nim
  ##     
  ##   var s = "Hello World\R\L"
  ##   var n = b.put(s.cstring, s.len)
  ## 
  ##   for c in b.marks():
  ##     if c == '\L':
  ##       break

proc mark*(b: var MarkableCircularBuffer, size: Natural): Natural = discard
  ## 立刻标记缓冲区的数据， 直到 ``size`` 个或者到达数据尾部。 返回实际标记的数量。 
  ## 
  ## 注意， 标记是增量进行的， 也就是说， 下一次调用标记操作时将从上一次标记结束的位置继续。

proc markUntil*(b: var MarkableCircularBuffer, c: char): bool = discard
  ## 逐个标记缓冲区的数据， 直到遇到一个字节是 ``c`` ， 并返回 ``true`` ； 如果没有字节是 ``c`` ， 则返回
  ##  ``false`` 。 
  ## 
  ## 注意， 标记是增量进行的， 也就是说， 下一次调用标记操作时将从上一次标记结束的位置继续。 

proc markAll*(b: var MarkableCircularBuffer) = discard
  ## 立刻标记缓冲区存储的所有数据。 
  ## 
  ## 注意， 标记是增量进行的， 也就是说， 下一次调用标记操作时将从上一次标记结束的位置继续。

proc lenMarks*(b: MarkableCircularBuffer): Natural = discard
  ## 获取已标记的数据长度。 

proc popMarks*(b: var MarkableCircularBuffer, n: Natural = 0): string = discard
  ## 获取已标记的数据， 同时在缓冲区内部删除这些数据。 返回的数据会在尾部向前跳过 ``n`` 个字节。