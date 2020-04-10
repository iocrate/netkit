#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 

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
  HttpConnection* = ref object ## 
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

  Request* = ref object ## 
    conn: HttpConnection
    header: RequestHeader
    readQueue: ReadQueue
    contentLen: Natural
    chunked: bool
    trailer: bool
    readEnded: bool
    writeEnded: bool
    
  RequestHandler* = proc (req: Request): Future[void] {.closure, gcsafe.}

proc initReadQueue(): ReadQueue = 
  result.data = initDeque[proc () {.closure, gcsafe.}]()
  result.reading = false

template addOrCall[T](Q: var ReadQueue, retFuture: Future[T], wrapFuture: Future[T]) =
  ## 
  template nextIfNotEmpty = 
    if Q.data.len > 0:
      Q.data.popFirst()()
    else:
      Q.reading = false

  template call =
    var fut: Future[T] 
    try:
      fut = wrapFuture
    except:
      nextIfNotEmpty()
      retFuture.fail(getCurrentException())
      return
    fut.callback = proc (fut: Future[T]) =
      nextIfNotEmpty()
      if fut.failed:
        retFuture.fail(fut.readError())
      else:
        retFuture.complete(fut.read())

  if Q.reading:
    Q.data.addLast(proc () = call)
  else:
    Q.reading = true
    call

proc newHttpConnection*(socket: AsyncFD, address: string, handler: RequestHandler): HttpConnection = 
  ##
  new(result)
  result.buffer = initMarkableCircularBuffer()
  result.parser = initHttpParser()
  result.requestHandler = handler
  result.socket = socket
  result.address = address
  result.closed = false

proc newRequest*(conn: HttpConnection): Request = 
  ##
  new(result)
  result.conn = conn
  result.header = initRequestHeader()
  result.readQueue = initReadQueue()
  result.contentLen = 0
  result.chunked = false
  result.trailer = false
  result.readEnded = false
  result.writeEnded = false

proc reqMethod*(req: Request): HttpMethod {.inline.} = 
  ##  
  req.header.reqMethod

proc url*(req: Request): string {.inline.} = 
  ## 
  req.header.url

proc version*(req: Request): HttpVersion {.inline.} = 
  ## 
  req.header.version

proc fields*(req: Request): HeaderFields {.inline.} = 
  ## 
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
  ## 
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
        conn.readEnded = true
        conn.closed = true
        return 
      discard conn.buffer.pack(recvLen.uint32)
  
      if req == nil:
        req = newRequest(conn)
  
      if conn.parser.parseRequest(req.header, conn.buffer):
        break
  
  req.normalizeSpecificFields()
  await conn.requestHandler(req)

proc read(conn: HttpConnection, buf: pointer, size: Natural): Future[Natural] {.async.} = 
  ## 读取最多 ``size`` 字节， 读取的数据填充在 ``buf``， 返回实际读取的数量。 如果返回 ``0``， 说明连接
  ## 已经关闭。 
  assert not conn.closed
  assert not conn.readEnded
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
      conn.readEnded = true
    else: 
      if remainingLen > recvLen:
        discard conn.buffer.get(buf.offset(result), recvLen.uint32)
        discard conn.buffer.del(recvLen.uint32)
        result.inc(recvLen)
      else:
        discard conn.buffer.get(buf.offset(result), remainingLen.uint32)
        discard conn.buffer.del(remainingLen.uint32)
        result.inc(remainingLen)

proc readUntil(conn: HttpConnection, buf: pointer, size: Natural): Future[Natural] {.async.} =  
  ## 读取直到 ``size`` 字节， 读取的数据填充在 ``buf``， 返回实际读取的数量。 如果返回值不等于 ``size``， 说明
  ## 连接已经关闭。如果连接关闭， 则返回；否则，一直读取，直到 ``size`` 字节。
  assert not conn.closed
  assert not conn.readEnded
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
        conn.readEnded = true
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

proc readUnsafe(req: Request, buf: pointer, size: Natural): Future[Natural] {.async.} =
  ## 读取最多 ``size`` 个数据， 读取的数据填充在 ``buf`` ， 返回实际读取的数量。 如果返回 ``0``， 
  ## 表示已经到达数据尾部，不会再有数据可读。 
  assert not req.readEnded
  assert not req.chunked
  assert req.contentLen > 0
  result = await req.conn.read(buf, min(req.contentLen, size))
  req.contentLen.dec(result)  
  if req.contentLen == 0:
    req.readEnded = true
    if not req.conn.readEnded and req.writeEnded:
      asyncCheck req.conn.processNextRequest()

proc readUnsafe(req: Request): Future[string] {.async.} =
  ## 读取最多 ``size`` 个数据， 读取的数据填充在 ``buf`` ， 返回实际读取的数量。 如果返回 ``0``， 
  ## 表示已经到达数据尾部，不会再有数据可读。 
  assert not req.readEnded
  assert not req.chunked
  assert req.contentLen > 0
  let size = min(req.contentLen, BufferSize.int)
  result = newString(size)
  let readLen = await req.conn.read(result.cstring, size) # should need Gc_ref(result) ?
  result.setLen(readLen)                                  # still ref result 
  req.contentLen.dec(readLen)  
  if req.conn.readEnded:
    req.readEnded = true
  elif req.contentLen == 0:
    req.readEnded = true
    if req.writeEnded:
      asyncCheck req.conn.processNextRequest()

template readChunkSizerUnsafe(req: Request, chunkSizer: ChunkSizer): bool = 
  let conn = req.conn
  var succ: bool
  while true:
    (succ, chunkSizer) = conn.parser.parseChunkSizer(conn.buffer)
    if succ:
      break
    let (regionPtr, regionLen) = conn.buffer.next()
    let recvFuture = conn.socket.recvInto(regionPtr, regionLen.int)
    yield recvFuture
    assert not recvFuture.failed # recvInto 一定不会抛出异常？  
    # if recvFuture.failed:
    #   raise recvFuture.readError()
    # else:
    let recvLen = recvFuture.read()
    if recvLen == 0:
      conn.readEnded = true
      break 
    discard conn.buffer.pack(recvLen.uint32)  
  succ

template readChunkEnd(req: Request, trailer: string): bool = 
  let conn = req.conn
  var succ: bool
  while true:
    (succ, trailer) = conn.parser.parseChunkEnd(conn.buffer)
    if succ:
      break
    let (regionPtr, regionLen) = conn.buffer.next()
    let recvFuture = conn.socket.recvInto(regionPtr, regionLen.int)
    yield recvFuture
    assert not recvFuture.failed # recvInto 一定不会抛出异常？  
    # if recvFuture.failed:
    #   raise recvFuture.readError()
    # else:
    let recvLen = recvFuture.read()
    if recvLen == 0:
      conn.readEnded = true
      break 
    discard conn.buffer.pack(recvLen.uint32)  
  succ

proc readChunkUnsafe(req: Request, buf: pointer, size: range[int(LimitChunkedDataLen)..high(int)]): Future[Natural] {.async.} =
  ## 读取一块 chunked 数据， 读取的数据填充在 ``buf`` 。 ``size`` 最少是 ``LimitChunkedDataLen``，以防止块数据过长导致
  ## 溢出。 如果返回 ``0``， 表示已经到达数据尾部，不会再有数据可读。
  var chunkSizer: ChunkSizer
  if readChunkSizerUnsafe(req, chunkSizer):
    if chunkSizer.size == 0:
      var trailer: string
      if readChunkEnd(req, trailer): # TODO: 修订
        if trailer.len == 0:
          req.readEnded = true
          if req.writeEnded:
            asyncCheck req.conn.processNextRequest()
        else:
          copyMem(buf, trailer.cstring, trailer.len) # TODO: 优化， 不使用 copy 
          req.trailer = true
          result = trailer.len
    else:
      assert chunkSizer.size <= size
      result = await req.conn.readUntil(buf, chunkSizer.size)
      if req.conn.readEnded:
        result = 0

proc readChunkUnsafe(req: Request): Future[string] {.async.} =
  ## 读取一块 chunked 数据。 HTTP 请求头中 ``Transfer-Encoding`` 必须包含 ``chunked`` 编码，否则
  ## 立刻返回 ``""``。此外，当 ``Transfer-Encoding`` 必须包含 ``chunked`` 编码时，如果返回 ``""``， 
  ## 表示已经到达数据尾部，不会再有数据可读。 
  # TODO: 合并 read
  # chunked size 必须小于 BufferSize；chunkedSizeLen 必须小于 BufferSize
  var chunkSizer: ChunkSizer
  if readChunkSizerUnsafe(req, chunkSizer):
    if chunkSizer.size == 0:
      var trailer: string
      if readChunkEnd(req, trailer): # TODO: 修订
        if trailer.len == 0:
          req.readEnded = true
          if req.writeEnded:
            asyncCheck req.conn.processNextRequest()
        else:
          req.trailer = true
          result = trailer # TODO: 优化
    else:
      result = newString(chunkSizer.size)
      discard await req.conn.readUntil(result.cstring, chunkSizer.size) # should need Gc_ref(result) ?
      if req.conn.closed:
        result = ""                                                     # still ref result

proc read*(req: Request, buf: pointer, size: range[int(LimitChunkedDataLen)..high(int)]): Future[Natural] =
  ## 
  let retFuture = newFuture[Natural]("read")
  result = retFuture
  if req.conn.readEnded or req.readEnded:
    retFuture.complete(0)
  else:
    if req.chunked:
      req.readQueue.addOrCall(retFuture): req.readChunkUnsafe(buf, size)
    else:
      req.readQueue.addOrCall(retFuture): req.readUnsafe(buf, size)

proc read*(req: Request): Future[string] =
  ## 
  let retFuture = newFuture[string]("read")
  result = retFuture
  if req.conn.readEnded or req.readEnded:
    retFuture.complete("")
  else:
    if req.chunked:
      req.readQueue.addOrCall(retFuture): req.readChunkUnsafe()
    else:
      req.readQueue.addOrCall(retFuture): req.readUnsafe()

proc readAll*(req: Request): Future[string] {.async.} =
  ## 
  while true:
    let data = await req.read()
    if data.len > 0:
      result.add(data)
    else:
      break

proc isEOF*(req: Request): bool =
  ## 
  req.conn.readEnded or req.readEnded

proc isTrailer*(req: Request): bool =
  ## 
  req.trailer

proc write*(req: Request, buf: pointer, size: Natural): Future[void] {.async.} =
  ## 
  if req.writeEnded:
    # TODO: 设计异常类型
    raise newException(IOError, "write after ended")
  await req.conn.socket.send(buf, size)

proc write*(req: Request, data: string): Future[void] =
  ## 
  # TODO: 考虑 GC_ref data
  return req.write(data.cstring, data.len)

proc write*(
  req: Request, 
  statusCode: HttpCode,
  fields: openArray[tuple[name: string, value: string]]
): Future[void]  =
  ## ``write($initResponseHeader(statusCode, fields))`` 。 
  return req.write($initResponseHeader(statusCode, fields))

proc write*(
  req: Request, 
  statusCode: HttpCode,
  fields: openArray[tuple[name: string, value: seq[string]]]
): Future[void] =
  ## ``write($initResponseHeader(statusCode, fields))`` 。 
  return req.write($initResponseHeader(statusCode, fields))

proc writeEnd*(req: Request) =
  ## 
  if not req.writeEnded:
    req.writeEnded = true
    if req.conn.readEnded:
      if not req.conn.closed:
        req.conn.socket.closeSocket()
        req.conn.closed = true
    else:
      if req.readEnded:
        asyncCheck req.conn.processNextRequest()


 



