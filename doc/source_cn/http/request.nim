#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 

import strutils
import asyncdispatch
import nativesockets
import netkit/misc
import netkit/locks 
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
    closedError: ref Exception

  Request* = ref object ## 
    conn: HttpConnection
    header: RequestHeader
    readLock: AsyncLock
    writeLock: AsyncLock
    contentLen: Natural
    chunked: bool
    trailer: bool
    readEnded: bool
    writeEnded: bool
    
  RequestHandler* = proc (req: Request): Future[void] {.closure, gcsafe.}

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
  result.readLock = initAsyncLock()
  result.writeLock = initAsyncLock()
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

template readBuffer(conn: HttpConnection, buf: pointer, len: Natural) = 
  discard conn.buffer.get(buf, len)
  discard conn.buffer.del(len)

template readNativeSocket(conn: HttpConnection, buf: pointer, len: Natural): Natural = 
  var recvLen = 0
  let recvFuture = conn.socket.recvInto(buf, len)
  yield recvFuture
  if recvFuture.failed:
    conn.socket.closeSocket()
    conn.closed = true
    conn.closedError = recvFuture.readError()
  else:
    recvLen = recvFuture.read()
    if recvLen == 0:
        conn.socket.closeSocket()
        conn.closed = true 
  recvLen

template bufferLen(conn: HttpConnection): Natural = 
  conn.buffer.len.int

proc read*(conn: HttpConnection, buf: pointer, len: Natural): Future[Natural] {.async.} = 
  ## 
  result = conn.bufferLen
  if result >= len:
    conn.readBuffer(buf, len)
    result = len
  else:
    if result > 0:
      conn.readBuffer(buf, result)
    let remainingLen = len - result
    let readLen = conn.readNativeSocket(buf.offset(result), remainingLen)
    if readLen == 0:
      return
    if remainingLen > readLen:
      conn.readBuffer(buf.offset(result), readLen)
      result.inc(readLen)
    else:
      conn.readBuffer(buf.offset(result), remainingLen)
      result.inc(remainingLen)

proc readUntil*(conn: HttpConnection, buf: pointer, len: Natural): Future[Natural] {.async.} =  
  ## 
  result = conn.bufferLen
  if result >= len:
    conn.readBuffer(buf, len)
    result = len
  else:
    if result > 0:
      conn.readBuffer(buf, result)
    var remainingLen = len - result
    while true:
      let readLen = conn.readNativeSocket(buf.offset(result), remainingLen)
      if readLen == 0:
        return
      if remainingLen > readLen:
        conn.readBuffer(buf.offset(result), readLen)
        result.inc(readLen)
        remainingLen.dec(readLen)
      else:
        conn.readBuffer(buf.offset(result), remainingLen)
        result.inc(remainingLen)
        return

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
      var recvLen {.noInit.}: int 
      try:
        recvLen = await conn.socket.recvInto(region[0], region[1].int)
      except:
        conn.socket.closeSocket()
        conn.closed = true
        conn.closedError = getCurrentException()
        return
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

proc readUnsafe(req: Request, buf: pointer, size: Natural): Future[Natural] {.async.} =
  ## 读取最多 ``size`` 个数据， 读取的数据填充在 ``buf`` ， 返回实际读取的数量。 如果返回 ``0``， 
  ## 表示已经到达数据尾部，不会再有数据可读。 
  assert not req.conn.closed
  assert not req.readEnded
  assert not req.chunked
  assert req.contentLen > 0
  await req.readLock.acquire()
  result = await req.conn.read(buf, min(req.contentLen, size))
  req.contentLen.dec(result)  
  if req.contentLen == 0:
    req.readEnded = true
    if not req.conn.closed and req.writeEnded:
      asyncCheck req.conn.processNextRequest()
  req.readLock.release()

proc readUnsafe(req: Request): Future[string] {.async.} =
  ## 读取最多 ``size`` 个数据， 读取的数据填充在 ``buf`` ， 返回实际读取的数量。 如果返回 ``0``， 
  ## 表示已经到达数据尾部，不会再有数据可读。 
  assert not req.conn.closed
  assert not req.readEnded
  assert not req.chunked
  assert req.contentLen > 0
  await req.readLock.acquire()
  let size = min(req.contentLen, BufferSize.int)
  result = newString(size)
  let readLen = await req.conn.read(result.cstring, size) # should need Gc_ref(result) ?
  result.setLen(readLen)                                  # still ref result 
  req.contentLen.dec(readLen)  
  if req.contentLen == 0:
    req.readEnded = true
    if not req.conn.closed and req.writeEnded:
      asyncCheck req.conn.processNextRequest()
  req.readLock.release()

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
      conn.closed = true
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
      conn.closed = true
      break 
    discard conn.buffer.pack(recvLen.uint32)  
  succ

proc readChunkUnsafe(req: Request, buf: pointer, size: range[int(LimitChunkedDataLen)..high(int)]): Future[Natural] {.async.} =
  ## 读取一块 chunked 数据， 读取的数据填充在 ``buf`` 。 ``size`` 最少是 ``LimitChunkedDataLen``，以防止块数据过长导致
  ## 溢出。 如果返回 ``0``， 表示已经到达数据尾部，不会再有数据可读。
  await req.readLock.acquire()
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
      if req.conn.closed:
        result = 0
  req.readLock.release()

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
  if req.conn.closed or req.readEnded:
    retFuture.complete(0)
  else:
    req.readLock.acquire().callback = proc () =
      if req.chunked:
        req.readChunkUnsafe(buf, size).callback = proc (fut: Future[Natural]) =
          req.readLock.release()
          if fut.failed:
            retFuture.fail(fut.readError())
          else:
            retFuture.complete(fut.read())
      else:
        req.readUnsafe(buf, size).callback = proc (fut: Future[Natural]) =
          req.readLock.release()
          if fut.failed:
            retFuture.fail(fut.readError())
          else:
            retFuture.complete(fut.read())

proc read*(req: Request): Future[string] =
  ## 
  let retFuture = newFuture[string]("read")
  result = retFuture
  if req.conn.closed or req.readEnded:
    retFuture.complete("")
  else:
    req.readLock.acquire().callback = proc () =
      if req.chunked:
        req.readChunkUnsafe().callback = proc (fut: Future[string]) =
          req.readLock.release()
          if fut.failed:
            retFuture.fail(fut.readError())
          else:
            retFuture.complete(fut.read())
      else:
        req.readUnsafe().callback = proc (fut: Future[string]) =
          req.readLock.release()
          if fut.failed:
            retFuture.fail(fut.readError())
          else:
            retFuture.complete(fut.read())

proc readAll*(req: Request): Future[string] {.async.} =
  ## 
  while true:
    let data = await req.read()
    if data.len > 0:
      result.add(data)
    else:
      break

proc isEof*(req: Request): bool =
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
  await req.writeLock.acquire()
  # TODO: 判断失败
  await req.conn.socket.send(buf, size)
  req.writeLock.release()

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


 



