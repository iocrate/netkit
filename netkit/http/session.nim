#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

# 这个文件很混乱，待整理！！！

import asyncdispatch, nativesockets, strutils
import netkit/buffer, netkit/http/base, netkit/http/parser

type
  HttpSession* = ref object ## 表示客户端与服务器之间的一个活跃的通信会话。 这个对象不由用户代码直接构造。 
    buffer: MarkableCircularBuffer
    parser: HttpParser
    requestHandler: RequestHandler
    socket: AsyncFD
    address: string

  Request* = ref object ## 表示客户端发起的一次 HTTP 请求。 这个对象不由用户代码直接构造。 
    session: HttpSession
    packetHeader: ServerReqHeader
    contentLen: int
    chunked: bool
    readEnded: bool
    writeEnded: bool
    
  RequestHandler* = proc (req: Request): Future[void] {.closure, gcsafe.}

proc newHttpSession*(socket: AsyncFD, address: string, handler: RequestHandler): HttpSession = 
  new(result)
  result.buffer = MarkableCircularBuffer()
  result.parser = HttpParser()
  result.requestHandler = handler
  result.socket = socket
  result.address = address

proc newRequest*(session: HttpSession): Request = 
  new(result)
  result.session = session
  result.packetHeader = initServerReqHeader()
  result.contentLen = 0
  result.chunked = false
  result.readEnded = false
  result.writeEnded = false

proc reqMethod*(req: Request): HttpMethod {.inline.} = 
  ## 获取请求方法。 
  req.packetHeader.reqMethod

proc url*(req: Request): string {.inline.} = 
  ## 获取请求的 URL 字符串。 
  req.packetHeader.url

proc version*(req: Request): HttpVersion {.inline.} = 
  req.packetHeader.version

proc headers*(req: Request): HttpHeaders {.inline.} = 
  ## 获取请求头对象。 每个头字段值是一个字符串序列。 
  req.packetHeader.headers

proc normalizeTransforEncoding(req: Request) =
  if req.headers.contains("Transfer-Encoding"):
    var chunkedNum = 0
    var values: seq[string]
    for value in req.headers["Transfer-Encoding"]:
      for x in value.split({SP, HTAB, COMMA}):
        if x.len > 0:
          if x == "chunked":
            chunkedNum.inc()
          values.add(x)
    if chunkedNum > 1:
      raise newException(ValueError, "Bad Request")
    if chunkedNum == 1:
      if values[values.len-1].toLower() == "chunked":
        req.chunked = true
      else:
        raise newException(ValueError, "Bad Request")

proc normalizeContentLength(req: Request) =
  if req.headers.contains("Content-Length"):
    if req.headers["Content-Length"].len > 1:
      raise newException(ValueError, "Bad Request")
    req.contentLen = req.headers["Content-Length"][0].parseInt()
    if req.contentLen < 0:
      raise newException(ValueError, "Bad Request")

proc normalizeSpecificFields(req: Request) =
  # 这个函数用来规范化常用的 HTTP Headers 字段
  #
  # TODO: 规范化更多的字段
  req.normalizeContentLength()
  req.normalizeTransforEncoding()

proc processNextRequest*(session: HttpSession) {.async.} = 
  var req: Request
  var parsed = false

  if session.buffer.len.int > 0:
    req = newRequest(session)
    parsed = session.parser.parseRequest(req.packetHeader, session.buffer)

  if not parsed:
    while true:
      let region = session.buffer.next()
      let recvLen = await session.socket.recvInto(region[0], region[1].int)
      if recvLen == 0:
        ## TODO: 标记 HttpSession 已经关闭
        session.socket.closeSocket()
        return 
      discard session.buffer.pack(recvLen.uint16)

      if req.isNil:
        req = newRequest(session)

      if session.parser.parseRequest(req.packetHeader, session.buffer):
        break

  req.normalizeSpecificFields()
  asyncCheck session.requestHandler(req)

proc read*(req: Request, buf: pointer, size: Natural): Future[int] {.async.} =
  ## 对 HTTP 请求 ``req`` 读取最多 ``size`` 个数据， 复制到 ``buf`` 存储空间， 返回实际读取的数量。 如果返回 ``0``， 
  ## 表示已经到达数据尾部，不会再有数据可读。 
  # TODO: 考虑 chunked
  # TODO: Future 优化
  if req.readEnded:
    return 0
  if req.contentLen > 0:
    result = min(req.contentLen, size)
    if result > 0:
      let session = req.session
      let restLen = session.buffer.len
      if restLen.int >= result:
        discard session.buffer.get(buf, restLen)
        discard session.buffer.del(restLen)
      else:
        discard session.buffer.get(buf, restLen)
        discard session.buffer.del(restLen)

        let (regionPtr, regionLen) = session.buffer.next()
        let readLen = await session.socket.recvInto(regionPtr, regionLen.int)
        if readLen == 0:
          req.readEnded = true
          session.socket.closeSocket()
          return 
        discard session.buffer.pack(readLen.uint16)

        let remainingLen = result.uint16 - restLen
        discard session.buffer.get(buf.offset(restLen), remainingLen)
        discard session.buffer.del(remainingLen)

      req.contentLen.dec(result)  

      if req.contentLen == 0:
        req.readEnded = true
        if req.writeEnded:
          asyncCheck session.processNextRequest()

proc write*(req: Request, buf: pointer, size: Natural): Future[void] {.async.} =
  ## 对 HTTP 请求 ``req`` 写入响应数据。 
  # TODO: 考虑 chunked
  # TODO: Future 优化
  if req.writeEnded:
    # TODO: 打印警告信息或者抛出异常
    return 

  await req.session.socket.send(buf, size)

proc write*(req: Request, data: string): Future[void] {.async.} =
  ## 对 HTTP 请求 ``req`` 写入响应数据。 
  # TODO: 考虑 chunked
  # TODO: Future 优化
  await req.write(data.cstring, data.len)

proc writeEnd*(req: Request): Future[void] {.async.} =
  ## 对 HTTP 请求 ``req`` 写入结尾信号。 
  # TODO: 考虑 chunked
  # TODO: Future 优化
  if not req.writeEnded:
    req.writeEnded = true
    if req.readEnded:
      asyncCheck req.session.processNextRequest()
