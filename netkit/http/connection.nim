#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

# TODO: 优化写操作。
# TODO: 添加客户端 API 和客户端连接池。

import asyncdispatch, nativesockets, strutils
import netkit/buffer/circular, netkit/http/base, netkit/http/parser

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
    
  RequestHandler* = proc (req: Request): Future[void] {.closure, gcsafe.}

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

proc read*(req: Request, buf: pointer, size: Natural): Future[int] {.async.} =
  ## 对 HTTP 请求 ``req`` 读取最多 ``size`` 个数据， 复制到 ``buf`` 存储空间， 返回实际读取的数量。 如果返回 ``0``， 
  ## 表示已经到达数据尾部，不会再有数据可读。 
  # TODO: 考虑 chunked
  if req.readEnded:
    return 0
  if req.contentLen > 0:
    result = min(req.contentLen, size)
    if result > 0:
      let conn = req.conn
      let restLen = conn.buffer.len
      if restLen.int >= result:
        discard conn.buffer.get(buf, restLen)
        discard conn.buffer.del(restLen)
      else:
        discard conn.buffer.get(buf, restLen)
        discard conn.buffer.del(restLen)

        let (regionPtr, regionLen) = conn.buffer.next()
        let readLen = await conn.socket.recvInto(regionPtr, regionLen.int)
        if readLen == 0:
          req.readEnded = true
          conn.socket.closeSocket()
          conn.closed = true
          return 
        discard conn.buffer.pack(readLen.uint32)

        let remainingLen = result.uint32 - restLen
        discard conn.buffer.get(buf.offset(restLen), remainingLen)
        discard conn.buffer.del(remainingLen)

      req.contentLen.dec(result)  

      if req.contentLen == 0:
        req.readEnded = true
        if req.writeEnded:
          asyncCheck conn.processNextRequest()

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





