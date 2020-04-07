#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

# 几种请求读的错序情况：
#
# 1. 两个请求之间：
#
#      <req1, req2>
#
#      r1 = req1.read() # 立即返回，保存在 Future.value
#      r2 = req2.read()
#
#      await r2
#      await r1 
#
#    没有问题，req2 总是在 req1.readEnded 后才能获取
#
# 2. 两个请求之间：
#
#      <req1, req2>
#    
#      r2 = req2.read() 
#      r1 = req1.read() # 立即返回，保存在 Future.value
#
#      await r2
#      await r1 立即返回
#  
#    没有问题，req2 总是在 req1.readEnded 后才能获取
#
# 3. 同一个请求之间：
#
#      <req1>
#
#      r1_1 = req1.read()
#      r1_2 = req1.read()
#
#      await r1_2
#      await r1_1 
#  
#    需要排队 [r1_1, r1_2] 

# TODO: 优化写操作。
# TODO: 添加客户端 API 和客户端连接池。

import asyncdispatch, nativesockets, strutils, deques
import netkit/buffer/constants, netkit/buffer/circular, netkit/http/base, netkit/http/parser

type
  HttpConnection* = ref object ## 表示客户端与服务器之间的一个活跃的通信连接。 这个对象不由用户代码直接构造。 
    buffer: MarkableCircularBuffer
    parser: HttpParser
    requestHandler: RequestHandler
    socket: AsyncFD
    address: string
    closed: bool

  Request* = ref object ## 表示一次 HTTP 请求。 这个对象不由用户代码直接构造。 
    conn: HttpConnection
    header: RequestHeader
    contentLen: int
    chunked: bool
    readEnded: bool
    writeEnded: bool

    readQueue: Deque[proc ()] 
    
  RequestHandler* = proc (req: Request): Future[void] {.closure, gcsafe.}

template offset(p: pointer, n: int): pointer = 
  cast[pointer](cast[ByteAddress](p) + n)

proc newHttpConnection*(socket: AsyncFD, address: string, handler: RequestHandler): HttpConnection = 
  new(result)
  result.buffer = initMarkableCircularBuffer()
  result.parser = initHttpParser()
  result.requestHandler = handler
  result.socket = socket
  result.address = address
  result.closed = false

proc newRequest*(conn: HttpConnection): Request = 
  new(result)
  result.conn = conn
  result.header = initRequestHeader()
  result.contentLen = 0
  result.chunked = false
  result.readEnded = false
  result.writeEnded = false
  result.readQueue = initDeque[proc ()](4)

proc reqMethod*(req: Request): HttpMethod {.inline.} = 
  ## 获取请求方法。 
  req.header.reqMethod

proc url*(req: Request): string {.inline.} = 
  ## 获取请求的 URL 字符串。 
  req.header.url

proc version*(req: Request): HttpVersion {.inline.} = 
  req.header.version

proc fields*(req: Request): HeaderFields {.inline.} = 
  ## 获取请求头对象。 每个头字段值是一个字符串序列。 
  req.header.fields

proc normalizeTransforEncoding(req: Request) =
  if req.fields.contains("Transfer-Encoding"):
    let encodings = req.fields["Transfer-Encoding"]
    var i = 0
    for encoding in encodings:
      if encoding.toLowerAscii() == "chunked":
        if i != encodings.len-1:
          raise newException(ValueError, "Bad Request")
        req.chunked = true
        return
      i.inc()

proc normalizeContentLength(req: Request) =
  if req.fields.contains("Content-Length"):
    if req.fields["Content-Length"].len > 1:
      raise newException(ValueError, "Bad Request")
    req.contentLen = req.fields["Content-Length"][0].parseInt()
    if req.contentLen < 0:
      raise newException(ValueError, "Bad Request")

proc normalizeSpecificFields(req: Request) =
  # 这个函数用来规范化常用的 HTTP Headers 字段
  #
  # TODO: 规范化更多的字段
  req.normalizeContentLength()
  req.normalizeTransforEncoding()

proc processNextRequest*(conn: HttpConnection): Future[void] {.async.} = 
  ## 处理下一条 HTTP 请求。
  var req: Request
  var parsed = false
  
  if conn.buffer.len.int > 0:
    req = newRequest(conn)
    parsed = conn.parser.parseRequest(req.header, conn.buffer)
  
  if not parsed:
    while true:
      let region = conn.buffer.next()
      let recvLen = await conn.socket.recvInto(region[0], region[1].int)
      if recvLen == 0:
        conn.socket.closeSocket()
        conn.closed = true
        return 
      discard conn.buffer.pack(recvLen.uint32)
  
      if req == nil:
        req = newRequest(conn)
  
      if conn.parser.parseRequest(req.header, conn.buffer):
        break
  
  req.normalizeSpecificFields()
  await conn.requestHandler(req)

proc readOnce(conn: HttpConnection, buf: pointer, size: Positive): Future[Natural] {.async.} = 
  # TODO: async 转换为 Future，benchmark test
  assert conn.closed == false
  result = conn.buffer.len.int
  if result >= size:
    discard conn.buffer.get(buf, size.uint32)
    discard conn.buffer.del(size.uint32)
    result = size
  else:
    if result > 0:
      discard conn.buffer.get(buf, result.uint32)
      discard conn.buffer.del(result.uint32)
    let remainingLen = size - result
    let recvLen = await conn.socket.recvInto(buf.offset(result), remainingLen)
    if recvLen == 0:
      conn.socket.closeSocket()
      conn.closed = true
    else: 
      if remainingLen > recvLen:
        discard conn.buffer.get(buf.offset(result), recvLen.uint32)
        discard conn.buffer.del(recvLen.uint32)
        result.inc(recvLen)
      else:
        discard conn.buffer.get(buf.offset(result), remainingLen.uint32)
        discard conn.buffer.del(remainingLen.uint32)
        result.inc(remainingLen)

proc readUntil(conn: HttpConnection, buf: pointer, size: Positive): Future[Natural] {.async.} =  
  # TODO: async 转换为 Future，benchmark test
  assert conn.closed == false
  result = conn.buffer.len.int
  if result >= size:
    discard conn.buffer.get(buf, size.uint32)
    discard conn.buffer.del(size.uint32)
    result = size
  else:
    if result > 0:
      discard conn.buffer.get(buf, result.uint32)
      discard conn.buffer.del(result.uint32)
    var remainingLen = size - result
    while true:
      let recvLen = await conn.socket.recvInto(buf.offset(result), remainingLen)
      if recvLen == 0:
        conn.socket.closeSocket()
        conn.closed = true
        return 
      if remainingLen > recvLen:
        discard conn.buffer.get(buf.offset(result), recvLen.uint32)
        discard conn.buffer.del(recvLen.uint32)
        result.inc(recvLen)
        remainingLen.dec(recvLen)
      else:
        discard conn.buffer.get(buf.offset(result), remainingLen.uint32)
        discard conn.buffer.del(remainingLen.uint32)
        result.inc(remainingLen)
        break

template addRead[T](req: Request, retFuture: Future[T], futureCall: Future[T]) =
  proc cb() = 
    let innerFuture: Future[T] = futureCall
    innerFuture.callback = proc (fut: Future[T]) =
      if fut.failed:
        retFuture.fail(fut.readError())
      else:
        retFuture.complete(fut.read())
      if req.readQueue.len > 0:
        req.readQueue.popFirst()()

  req.readQueue.addFirst(cb)
  if req.readQueue.len == 1:
    req.readQueue.popFirst()()

proc readUnsafe(req: Request, buf: pointer, size: Positive): Future[Natural] {.async.} =
  ## 对 HTTP 请求 ``req`` 读取最多 ``size`` 个数据， 复制到 ``buf`` 存储空间， 返回实际读取的数量。 如果返回 ``0``， 
  ## 表示已经到达数据尾部，不会再有数据可读。 
  # TODO: 考虑 chunked
  if not req.readEnded and req.contentLen > 0:
    result = await readOnce(req.conn, buf, min(req.contentLen, size))
    req.contentLen.dec(result)  
    if req.conn.closed:
      req.readEnded = true
    elif req.contentLen == 0:
      req.readEnded = true
      if req.writeEnded:
        asyncCheck req.conn.processNextRequest()

proc read*(req: Request, buf: pointer, size: Positive): Future[Natural] =
  ## 对 HTTP 请求 ``req`` 读取最多 ``size`` 个数据， 复制到 ``buf`` 存储空间， 返回实际读取的数量。 如果返回 ``0``， 
  ## 表示已经到达数据尾部，不会再有数据可读。 
  # TODO: 考虑 chunked
  result = newFuture[Natural]("read")
  req.addRead(result): req.readUnsafe(buf, size)

proc parseChunkSize*(line: string): int = 
  result = 0
  var i = 0
  while true:
    case line[i]
    of '0'..'9':
      result = result shl 4 or (line[i].ord() - '0'.ord())
    of 'a'..'f':
      result = result shl 4 or (line[i].ord() - 'a'.ord() + 10)
    of 'A'..'F':
      result = result shl 4 or (line[i].ord() - 'A'.ord() + 10)
    of '\0': # TODO: what'is this
      break
    of ';':
      # TODO: chunk-extensions
      break
    else:
      raise newException(ValueError, "Invalid Chunk Encoded")
    i.inc()

proc readChunkUnsafe(req: Request): Future[string] {.async.} =
  ## 对 HTTP 请求 ``req`` 读取最多 ``size`` 个数据， 复制到 ``buf`` 存储空间， 返回实际读取的数量。 如果返回 ``""``， 
  ## 表示已经到达数据尾部，不会再有数据可读。 
  # TODO: 合并 read
  # chunked size 必须小于 BufferSize；chunkedSizeLen 必须小于 BufferSize
  if not req.readEnded and req.chunked:
    let conn = req.conn

    while true:
      let retMark = conn.buffer.markUntil(LF)
      # TODO: 发送 bad request error，并关闭连接
      if conn.buffer.len >= BufferSize or conn.buffer.len.int > 1000: 
        req.readEnded = true
        conn.socket.closeSocket()
        conn.closed = true
        return 
      if retMark:
        break
      let (regionPtr, regionLen) = conn.buffer.next()
      let recvLen = await conn.socket.recvInto(regionPtr, regionLen.int)
      if recvLen == 0:
        req.readEnded = true
        conn.socket.closeSocket()
        conn.closed = true
        return 
      discard conn.buffer.pack(recvLen.uint32)

    var line = conn.buffer.popMarks(1)
    let lastIdx = line.len - 1
    if lastIdx > 0 and line[lastIdx] == CR:
      line.setLen(lastIdx)
    let chunkSize = line.parseChunkSize()

    if chunkSize == 0:
      req.readEnded = true
      if req.writeEnded:
        asyncCheck conn.processNextRequest()
    else:
      result = newString(chunkSize)
      # TODO: 考虑 result.cstring 的 gc_ref gc_unref
      let readLen = await req.conn.readUntil(result.cstring, chunkSize)
      if req.conn.closed:
        result = ""
        req.readEnded = true
        if req.writeEnded:
          asyncCheck conn.processNextRequest()

proc readChunk*(req: Request): Future[string] =
  result = newFuture[string]("readChunk")
  req.addRead(result): req.readChunkUnsafe()

proc write*(req: Request, buf: pointer, size: Natural): Future[void] {.async.} =
  ## 对 HTTP 请求 ``req`` 写入响应数据。 
  # TODO: 考虑 chunked
  if req.writeEnded:
    # TODO: 打印警告信息或者抛出异常
    # raise newException(IOError, "write after ended")
    return 

  await req.conn.socket.send(buf, size)

proc write*(req: Request, data: string): Future[void] =
  ## 对 HTTP 请求 ``req`` 写入响应数据。 
  # TODO: 考虑 chunked
  return req.write(data.cstring, data.len)

proc write*(
  req: Request, 
  statusCode: HttpCode,
  fields: openArray[tuple[name: string, value: string]]
): Future[void]  =
  ## 对 HTTP 请求 ``req`` 写入响应数据。 等价于 ``write($initResponseHeader(statusCode, fields))`` 。 
  return req.write($initResponseHeader(statusCode, fields))

proc write*(
  req: Request, 
  statusCode: HttpCode,
  fields: openArray[tuple[name: string, value: seq[string]]]
): Future[void] =
  ## 对 HTTP 请求 ``req`` 写入响应数据。 等价于 ``write($initResponseHeader(statusCode, fields))`` 。 
  return req.write($initResponseHeader(statusCode, fields))

proc writeEnd*(req: Request): Future[void] {.async.} =
  ## 对 HTTP 请求 ``req`` 写入结尾信号。 
  # TODO: 考虑 chunked
  if req.writeEnded:
    return

  req.writeEnded = true
  if req.readEnded:
    asyncCheck req.conn.processNextRequest()


 


