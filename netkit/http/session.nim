#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

# 这个文件很混乱，待整理！！！

import asyncdispatch, nativesockets, tables
import netkit/buffer, netkit/http/parser

type
  HttpSession* = ref object ## 表示客户端与服务器之间的一个活跃的通信会话。 这个对象不由用户代码直接构造。 
    buffer: MarkableCircularBuffer
    parser: HttpParser
    requestHandler: RequestHandler
    socket: AsyncFD

  Request* = ref object ## 表示客户端发起的一次 HTTP 请求。 这个对象不由用户代码直接构造。 
    session: HttpSession
    packet: RequestPacket
    # socket: AsyncFD
    contentLen: int
    chunked: bool
    readEnded: bool
    writeEnded: bool
    
  RequestHandler* = proc (req: Request): Future[void] {.closure, gcsafe.}

proc newHttpSession*(socket: AsyncFD, handler: RequestHandler): HttpSession = 
  new(result)
  result.buffer = MarkableCircularBuffer()
  result.parser = HttpParser()
  result.requestHandler = handler
  result.socket = socket

proc newRequest*(session: HttpSession): Request = 
  new(result)
  result.session = session
  result.chunked = false
  result.readEnded = false
  result.writeEnded = false

proc reqMethod*(req: Request): HttpMethod {.inline.} = 
  ## 获取请求方法。 
  req.packet.reqMethod

proc url*(req: Request): string {.inline.} = 
  ## 获取请求的 URL 字符串。 
  req.packet.url

proc version*(req: Request): tuple[orig: string, major, minor: int] {.inline.} = 
  req.packet.version

proc headers*(req: Request): Table[string, seq[string]] {.inline.} = 
  ## 获取请求头对象。 每个头字段值是一个字符串序列。 
  req.packet.headers

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
    parsed = session.parser.parseRequest(req.packet, session.buffer)

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

      if session.parser.parseRequest(req.packet, session.buffer):
        break

  req.normalizeSpecificFields()
  asyncCheck session.requestHandler(req)

proc read*(req: Request, buf: pointer, size: Natural): Future[Natural] {.async.} =
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

proc writeEnd*(req: Request): Future[void] {.async.} =
  ## 对 HTTP 请求 ``req`` 写入结尾信号。 
  # TODO: 考虑 chunked
  # TODO: Future 优化
  if not req.writeEnded:
    req.writeEnded = true
    if req.readEnded:
      asyncCheck req.session.processNextRequest()

  

