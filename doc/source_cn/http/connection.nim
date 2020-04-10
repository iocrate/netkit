#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

# Incoming Request on HTTP Server 的边界条件：
#
# 1. 不同连接的请求读，一定不存在竞争问题。
#
# 2. 同一个连接，不同请求的读，一定不存在竞争问题。因为后一个请求总是在前一个请求 EOF 后才能引用。也就谁说，对于
#    [req1, req2]，req1.read() 总是立刻返回 EOF 。
#
#        r1 = req1.read() # 立即返回 EOF，保存在 Future.value
#        r2 = req2.read()
#
#        await r2
#        await r1
#
#    ------------------------------------------------------
#
#        r2 = req2.read() 
#        r1 = req1.read() # 立即返回 EOF，保存在 Future.value
#
#        await r2
#        await r1
#
# 3. 同一个连接，同一个请求，不同次序的读，存在竞争问题，特别是非 chunked 编码的时候，必须进行排队。
#
#        r1_1 = req1.read()
#        r1_2 = req1.read()
#
#        await r1_2
#        await r1_1 
#
# 4. 不同连接的响应写，一定不存在竞争问题。
#
# 5. 同一个连接，不同响应的写，一定不存在竞争问题。因为后一个请求总是在前一个请求 EOF 后才能引用。也就谁说，对于
#    [req1, req2]，req1.write() 总是立刻返回 EOF 。
#
# 6. 同一个连接，同一个响应，不同次序的写，一定不存在竞争问题。因为不对写数据进行内部处理，而是直接交给底层 socket。

import strutils
import deques
import asyncdispatch
import nativesockets
import netkit/misc
import netkit/buffer/constants as buffer_constants
import netkit/buffer/circular
import netkit/http/base 
import netkit/http/constants as http_constants
import netkit/http/parser

type
  HttpConnection* = ref object ## 表示客户端与服务器之间的一个活跃的通信连接。 这个对象不由用户代码直接构造。 
    buffer: MarkableCircularBuffer
    parser: HttpParser
    requestHandler: RequestHandler
    socket: AsyncFD
    address: string
    closed: bool
    readEnded: bool

  ReadQueue = object
    data: Deque[proc () {.closure, gcsafe.}] 
    reading: bool

  Request* = ref object ## 表示一次 HTTP 请求。 这个对象不由用户代码直接构造。 
    conn: HttpConnection
    header: RequestHeader
    readQueue: ReadQueue
    contentLen: Natural
    chunked: bool
    readEnded: bool
    writeEnded: bool
    
  RequestHandler* = proc (req: Request): Future[void] {.closure, gcsafe.}

proc newHttpConnection*(socket: AsyncFD, address: string, handler: RequestHandler): HttpConnection = discard
  ## 初始化一个 ``HttpConnection`` 对象。 

proc newRequest*(conn: HttpConnection): Request = discard
  ## 初始化一个 ``Request`` 对象。 

proc reqMethod*(req: Request): HttpMethod {.inline.} = discard
  ## 获取请求方法。 

proc url*(req: Request): string {.inline.} = discard
  ## 获取请求的 URL 字符串。 

proc version*(req: Request): HttpVersion {.inline.} = discard
  ## 获取请求的 HTTP 版本号码。 

proc fields*(req: Request): HeaderFields {.inline.} = discard
  ## 获取请求头对象。 每个头字段值是一个字符串序列。

proc processNextRequest*(conn: HttpConnection): Future[void] = discard
  ## 处理下一条 HTTP 请求。

proc read*(req: Request, buf: pointer, size: range[int(LimitChunkedDataLen)..high(int)]): Future[Natural] = discard
  ## 读取最多 ``size`` 个数据， 读取的数据填充在 ``buf``， 返回实际读取的数量。 如果返回 ``0``， 
  ## 表示已经到达数据尾部，不会再有数据可读。 如果数据是 ``Transfer-Encoding: chunked`` 编码的，则
  ## 自动进行解码，并填充一块数据。 
  ## 
  ## ``size`` 最少是 ``LimitChunkedDataLen``。 这是因为， 如果数据是 ``Transfer-Encoding: chunked`` 
  ## 编码的， 则 ``buf`` 必须有足够空间存储解码后的数据。 

proc read*(req: Request): Future[string] = discard
  ## 读取最多 ``size`` 个数据， 读取的数据填充在 ``buf``， 返回实际读取的数量。 如果返回 ``0``， 
  ## 表示已经到达数据尾部，不会再有数据可读。 如果数据是 ``Transfer-Encoding: chunked`` 编码的，则
  ## 自动进行解码，并填充一块数据。 
  ## 
  ## ``size`` 最少是 ``LimitChunkedDataLen``。 这是因为， 如果数据是 ``Transfer-Encoding: chunked`` 
  ## 编码的， 则 ``buf`` 必须有足够空间存储解码后的数据。 

proc readAll*(req: Request): Future[string] {.async.} = discard
  ## 读取所有数据， 直到数据尾部， 即不再有数据可读。 返回所有读到的数据。 

proc readDiscard*(req: Request): Future[void] {.async.} = discard
  ## 读取所有数据， 直到数据尾部， 即不再有数据可读。 不保存所有读到的数据。 当你对数据不感兴趣时， 这个函数
  ## 会比较有用处。

proc isEOF*(req: Request): bool = discard
  ## 判断 ``req`` 的读是否已经到达数据尾部，不再有数据可读。 到达尾部，有可能是客户端已经发送完所有必要的数据； 
  ## 也有可能客户端提前关闭了发送端，使得读操作提前完成。 

proc isTrailer*(req: Request): bool = discard
  ## 判断 ``req`` 接收的数据是不是 ``Transfer-Encoding: chunked`` 编码， 并且现在所读的数据是一个 Trailer 。  

proc write*(req: Request, buf: pointer, len: Natural): Future[void] {.async.} = discard
  ## 写入响应数据。 ``buf`` 指定数据源， ``len`` 指定数据源的长度。 

proc write*(req: Request, data: string): Future[void] = discard
  ## 写入响应数据。 ``data`` 指定数据源。 

proc write*(
  req: Request, 
  statusCode: HttpCode,
  fields: openArray[tuple[name: string, value: string]]
): Future[void]  = discard
  ## 写入响应数据。 ``statusCode`` 指定状态码， ``fields`` 指定头字段。 数据被转换为一行 HTTP 状态行， 因此， 只
  ## 有当第一次向 ``req`` 写入数据时， 才调用这个函数， 并且只使用一次。 
  ## 
  ## 等价于 ``write($initResponseHeader(statusCode, fields))`` 。 

proc write*(
  req: Request, 
  statusCode: HttpCode,
  fields: openArray[tuple[name: string, value: seq[string]]]
): Future[void] = discard
  ## 写入响应数据。 ``statusCode`` 指定状态码， ``fields`` 指定头字段。 数据被转换为一行 HTTP 状态行， 因此， 只
  ## 有当第一次向 ``req`` 写入数据时， 才调用这个函数， 并且只使用一次。 
  ## 
  ## 写入响应数据。 等价于 ``write($initResponseHeader(statusCode, fields))`` 。

proc writeEnd*(req: Request) = discard
  ## 写入结尾信号。 之后， 不能再向 ``req`` 写入数据， 否则将抛出异常。
















