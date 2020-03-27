#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个文件非常混乱，现在请先忽略 !!!!!!!!!!!!!!!!!!!!!!!!!!!

## 这个模块提供 HTTP 消息包的解析功能，便于在 IO 的时候能给其提供
## 非常方便的解析函数。我希望这个模块的解析粒度非常精细，以便于在今后
## 更容易的进行调优。
##
## 今天先开始写一个简单的 HTTP Request Packet 分析功能。按照我们
## 所了解的，一个 HTTP Request Packet 是这样的：
##
##  
## METHOD| |URL| |VERSION|CRLF
## KEY|:| |VALUE|CRLF
## CRLF
## BODY
##
##
## 1. 双端 buffer
## 
##    采用双端 buffer 以最大化读取 data 的效率：
## 
##    a. [      {d}  |        ]  某一时刻，buffer 剩余 {d}，则从 {d} 向后直到读满 buffer
##    b. [          {d}       ]  某一时刻，buffer 剩余 {d}，则从 {d} 向后直到读满 buffer
##    c. [           | {d}    ]  某一时刻，buffer 剩余 {d}，则从 0 向后直到读到 {d} 前面
##
##    buffer.size = 4k * 2

#
# [RFC7230](https://tools.ietf.org/html/rfc7230#section-3.5)
#
#   In the interest of robustness, a server that is expecting to receive
#   and parse a request-line SHOULD ignore at least one empty line (CRLF)
#   received prior to the request-line.


# [RFC7230](https://tools.ietf.org/html/rfc7230#section-3.5)
#
#   Although the line terminator for the start-line and header fields is 
#   the sequence CRLF, a recipient MAY recognize a single LF as a line 
#   terminator and ignore any preceding CR.

# [RFC5234](https://tools.ietf.org/html/rfc5234#appendix-B.1)
const SP   = '\x20'
const CR   = '\x0D'
const LF   = '\x0A'
const CRLF = "\x0D\x0A"

const BufferSize = 8000

# [RFC7230](https://tools.ietf.org/html/rfc7230#section-3.1.1)
# request-line = method SP request-target SP HTTP-version CRLF

type
  HttpCode* = distinct range[0 .. 599]

  HttpMethod* = enum
    HttpHead,        ## Asks for the response identical to the one that would
                     ## correspond to a GET request, but without the response
                     ## body.
    HttpGet,         ## Retrieves the specified resource.
    HttpPost,        ## Submits data to be processed to the identified
                     ## resource. The data is included in the body of the
                     ## request.
    HttpPut,         ## Uploads a representation of the specified resource.
    HttpDelete,      ## Deletes the specified resource.
    HttpTrace,       ## Echoes back the received request, so that a client
                     ## can see what intermediate servers are adding or
                     ## changing in the request.
    HttpOptions,     ## Returns the HTTP methods that the server supports
                     ## for specified address.
    HttpConnect,     ## Converts the request connection to a transparent
                     ## TCP/IP tunnel, usually used for proxies.
    HttpPatch        ## Applies partial modifications to a resource.

  RequestLine = object
    reqMethod: HttpMethod
    url: string
    version: tuple[orig: string, major, minor: int]

  RequestBuffer = object
    value: array[0..BufferSize, char]
    xStart: int
    xEnd: int
    xLen: int
    yStart: int
    yEnd: int
    yLen: int

iterator charsOfLine(buffer: RequestBuffer): char =   

proc extract(buffer: RequestBuffer, length: Positive): string = 
  assert length <= BufferSize
  assert length <= xLen + yLen  # 提取时，必须已经知道目标字符串的长度，并且在范围内

  result = newString(length)

  if xStart >= yStart: # 两个缓冲区连续
    # TODO
  else:                # y 在左，x 在右
    if xLen >= length:
      copyMem(result, cast[pointer](cast[ByteAddress](buffer.value) + xStart), length)
      
    else:
      copyMem(result, cast[pointer](cast[ByteAddress](buffer.value) + xStart), xLen)
      copyMem(cast[pointer](cast[ByteAddress](result.cstring) + xLen), 
              cast[pointer](cast[ByteAddress](buffer.value) + yStart),
              length - xLen)

      # let remain = length - xLen
      # if yLen >= remain:
      #   copyMem(result, buffer, remain)
      # else:
      #   copyMem(result, buffer, yLen)

  # TODO: 考虑移动 xStart、yStart 等等相关的位置

proc parseRequestLine(line: string): RequestLine = 
  discard






#            httpengine 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块提供 HTTP 消息包的解析功能，便于在 IO 的时候能给其提供
## 非常方便的解析函数。我希望这个模块的解析粒度非常精细，以便于在今后
## 更容易的进行调优。
##
## 今天先开始写一个简单的 HTTP Request Packet 分析功能。按照我们
## 所了解的，一个 HTTP Request Packet 是这样的：
##
##  
## METHOD| |URL| |VERSION|CRLF
## KEY|:| |VALUE|CRLF
## CRLF
## BODY
##
##
## 1. 双端 buffer
## 
##    采用双端 buffer 以最大化读取 data 的效率：
## 
##    a. [      {d}  |        ]  某一时刻，buffer 剩余 {d}，则从 {d} 向后直到读满 buffer
##    b. [          {d}       ]  某一时刻，buffer 剩余 {d}，则从 {d} 向后直到读满 buffer
##    c. [           | {d}    ]  某一时刻，buffer 剩余 {d}，则从 0 向后直到读到 {d} 前面
##
##    buffer.size = 4k * 2

#[ 

本模块实现了一个增量的可标记的双端缓冲 MarkedBuffer 。类似双端队列，双端缓冲顺序存储数据，并按照存储的顺序
提取数据；当正向存储满后，双端缓冲查看头部是否仍有空间，如果有则使用剩余的空间继续存储。

    [   空   {  data  }   空  ]

（1）关于标记

支持标记数据，您可以逐个标记数据，直到某个临界条件，并将所有标记的数据取出。这在进行数据解析时特别有用，比如
查找某个特定字符，然后把查找过程标记的数据提取出来作为一个特定符号使用

（2）关于增量

在大部分 IO，数据不是一次读取或者写出的，而是经过多次迭代。MarkedBuffer 以增量的方式存储数据，并以增量的方式
标记数据，这样您可以在反复 IO 过程里使用 MarkedBuffer 而不必担心状态丢失

（3）关于增长 (可能不支持)

通常，MarkedBuffer 使用一个固定长度的存储空间。当该空间存满后，您可以选择取出数据；或者，您可以 “增长” 空间，
增长的空间以原有的长度 × 2；为了内存安全，增长的空间使用 seq 类型存储

（4）关于线程安全

MarkedBuffer 不保证线程安全，当您在多线程使用时，您应该负责线程竞争的控制

]#

#
# [RFC7230](https://tools.ietf.org/html/rfc7230#section-3.5)
#
#   In the interest of robustness, a server that is expecting to receive
#   and parse a request-line SHOULD ignore at least one empty line (CRLF)
#   received prior to the request-line.


# [RFC7230](https://tools.ietf.org/html/rfc7230#section-3.5)
#
#   Although the line terminator for the start-line and header fields is 
#   the sequence CRLF, a recipient MAY recognize a single LF as a line 
#   terminator and ignore any preceding CR.

# [RFC5234](https://tools.ietf.org/html/rfc5234#appendix-B.1)
const SP   = '\x20'
const CR   = '\x0D'
const LF   = '\x0A'
const CRLF = "\x0D\x0A"

const LimitRequestLine* {.intdefine.} = 8*1024
const LimitRequestFieldSize* {.intdefine.} = 8*1024
const LimitRequestFieldCount* {.intdefine.} = 100

const BufferSize {.intdefine.}: int16 = 8*1024
const BufferOffside: int16 = BufferSize shr 1

# [RFC7230](https://tools.ietf.org/html/rfc7230#section-3.1.1)
# request-line = method SP request-target SP HTTP-version CRLF

#[
  如何使用 MarkableBuffer ？

  var buffer = MarkableBuffer()

  var (location, length) = buffer.next()

  # copy content to (location, length)

  for c in buffer.marks():
    if c == some:
      break

  var ident = buffer.get()

  buffer.copy(dest, destLen)
]#

type 
  MarkableBuffer* = object
    value: array[0..BufferSize.int, char]
    packedHead: int16
    packedTail: int16
    packed1Len: int16
    packed2Len: int16
    markedLen: int16

template offset(p: pointer, n: int) = 
  cast[pointer](cast[ByteAddress](p) + n)

proc next*(b: var MarkableBuffer): (pointer, int16) = 
# 得到下一块可写区域
  # let packedTail = (b.packedPos + b.packed1Len + b.packed2Len) % BufferSize
  result[0] = b.value.addr.offset(b.packedTail)
  result[1] = if b.packedHead < b.packedTail: BufferSize - b.packedTail
              else: BufferSize - b.packedTail - b.packed1Len 

proc pack*(b: var MarkableBuffer, n: Positive) = 
# 装箱；绑定当前可写区域，`n` 指定长度；实际长度可能小于 `n`，取决于当前方向可以填充的最大长度
  if b.packedHead > b.packedTail:
    let d = min(n, BufferSize - b.packed1Len - b.packed2Len) 
    b.packed2Len = b.packed2Len + d
    b.packedTail = b.packedTail + d
  elif b.packedHead < b.packedTail or b.packed1Len == 0:
    let d = min(n, BufferSize - b.packedTail) 
    b.packed1Len = b.packed1Len + d
    b.packedTail = (b.packedTail + d) mod BufferSize

iterator marks*(b: var MarkableBuffer): char =
# 迭代标记可用的字符，这个函数具有副作用，内部有一个计数器计算当前迭代的位置；
# 这是个单向一次性的迭代器，已经迭代过的字符无法继续迭代，特意为增量模式设定
  let totalLen = b.packed1Len + b.packed2Len
  while b.markedLen < totalLen:
    let i = (b.packedHead + b.markedLen) % BufferSize
    b.markedLen.inc()
    yield b.value[i]

proc get*(b: var MarkableBuffer, n: int16 = 0): string = 
# 获取当前已经标记的字符序列，`n` 表示向前略过指定字符
#
# 这个函数基于当前保存的计数提取字符序列
  if b.markedLen == 0:
    return ""

  let resultLen = b.markedLen - n
  if resultLen > 0:
    result = newString(resultLen)
    if b.packed1Len >= resultLen:
      copyMem(result.cstring, b.value.addr.offset(b.packedHead), resultLen)
    else:
      copyMem(result.cstring, b.value.addr.offset(b.packedHead), b.packed1Len)
      copyMem(result.cstring.offset(b.packed1Len), b.value.addr, resultLen - b.packed1Len)

  if b.packed1Len > b.markedLen:
    b.packedHead = b.packedHead + b.markedLen
    b.packed1Len = b.packed1Len - b.markedLen
  elif b.packed1Len == b.markedLen:
    b.packedHead = 0
    b.packedTail = b.packed2Len
    b.packed1Len = b.packedTail
    b.packed2Len = 0
  else:
    b.packedHead = (b.markedLen - b.packed1Len) mod b.packed2Len
    b.packedTail = b.packed1Len + b.packed2Len - b.markedLen
    b.packed1Len = b.packedTail
    b.packed2Len = 0
  b.markedLen = 0

proc copy*(b: var MarkableBuffer, dest: pointer, length: Positive): int16 = 
# 提取字符序列，转移到 `dest`，`length` 指定 dest 长度。提取的长度取决于当前可用的字符序列数量，
# 返回实际提取的数量。之前如果存在选择操作的话，则清除选择记录  
  if b.packed1Len > 0:
    let d1 = 0
    let d2 = 0
    d1 = min(b.packed1Len, length) 
    copyMem(dest, b.value.addr.offset(b.packedHead), d1)
    b.packed1Len = b.packed1Len - d1
    if b.packed1Len > 0:
      b.packedHead = b.packedHead + d1
    else:
      b.packedHead = 0
      if b.packed2Len > 0: 
        if length > d1:
          d2 = min(b.packed2Len, length - d1) 
          copyMem(dest.offset(d1), b.value.addr, d2)
          b.packedHead = d2 mod b.packed2Len
          b.packed2Len = b.packed2Len - d2
        b.packed1Len = b.packed2Len
        b.packed2Len = 0
    b.packedTail = (b.packedHead + b.packed1Len + b.packed2Len) mod BufferSize  
    b.markedLen = 0
    result = d1 + d2

