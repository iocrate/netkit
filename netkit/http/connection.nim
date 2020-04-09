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

# TODO: 优化写操作。
# TODO: 添加客户端 API 和客户端连接池。

# TODO: 考虑 socket recv 异常 （虽然不可能出现）如何处理，是否 close connection 
# TODO：考虑 markable object 处理器替代 markable buffer， 使 buffer 成为一个可替换的插件 
# TODO: 使用 {.noInit.} 优化 procs
# TODO: 优化 chunk 编码
# TODO: 考虑统一抽象编码解码相关的内容，比如 chunk 解码、编码；HTTP version、method HTTP header 编码解码；

import asyncdispatch, nativesockets, strutils, deques
import netkit/misc, netkit/buffer/constants as buffer_constants, netkit/buffer/circular
import netkit/http/base, netkit/http/constants as http_constants, netkit/http/parser

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

proc initReadQueue(): ReadQueue = 
  result.data = initDeque[proc () {.closure, gcsafe.}]()
  result.reading = false

template addOrCall[T](Q: var ReadQueue, retFuture: Future[T], wrapFuture: Future[T]) =
  ## 如果 ``Q`` 正在读状态，则将 ``wrapFuture`` 放入队列；否则，立刻调用 ``wrapFuture`` 。
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
  result.readQueue = initReadQueue()
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

proc readChunkUnsafe(req: Request, buf: pointer, size: range[int(LimitChunkedDataLen)..high(int)]): Future[Natural] {.async.} =
  ## 读取一块 chunked 数据， 读取的数据填充在 ``buf`` 。 ``size`` 最少是 ``LimitChunkedDataLen``，以防止块数据过长导致
  ## 溢出。 如果返回 ``0``， 表示已经到达数据尾部，不会再有数据可读。
  var chunkSizer: ChunkSizer
  if readChunkSizerUnsafe(req, chunkSizer):
    if chunkSizer.size == 0:
      req.readEnded = true
      if req.writeEnded:
        asyncCheck req.conn.processNextRequest()
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
      req.readEnded = true
      if req.writeEnded:
        asyncCheck req.conn.processNextRequest()
    else:
      result = newString(chunkSizer.size)
      discard await req.conn.readUntil(result.cstring, chunkSizer.size) # should need Gc_ref(result) ?
      if req.conn.closed:
        result = ""                                                     # still ref result

proc read*(req: Request, buf: pointer, size: range[int(LimitChunkedDataLen)..high(int)]): Future[Natural] =
  ## 读取最多 ``size`` 个数据， 读取的数据填充在 ``buf``， 返回实际读取的数量。 如果返回 ``0``， 
  ## 表示已经到达数据尾部，不会再有数据可读。 如果数据是 ``Transfer-Encoding: chunked`` 编码的，则
  ## 自动进行解码，并填充一块数据。 
  ## 
  ## ``size`` 最少是 ``LimitChunkedDataLen``。 
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
  ## 读取最多 ``size`` 个数据， 读取的数据填充在 ``buf``， 返回实际读取的数量。 如果返回 ``0``， 
  ## 表示已经到达数据尾部，不会再有数据可读。 如果数据是 ``Transfer-Encoding: chunked`` 编码的，则
  ## 自动进行解码，并填充一块数据。 
  ## 
  ## ``size`` 最少是 ``LimitChunkedDataLen``。 
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
  ## 读取所有数据， 直到数据尾部， 即不再有数据可读。 返回所有读到的数据。 
  while true:
    let data = await req.read()
    if data.len > 0:
      result.add(data)
    else:
      break

proc isEOF*(req: Request): bool =
  ## 判断 ``req`` 的读是否已经到达数据尾部，不再有数据可读。 到达尾部，有可能是客户端已经发送完所有必要的数据； 
  ## 也有可能客户端提前关闭了发送端，使得读操作提前完成。 
  req.conn.readEnded or req.readEnded

proc write*(req: Request, buf: pointer, size: Natural): Future[void] {.async.} =
  ## 对 HTTP 请求 ``req`` 写入响应数据。 
  if req.writeEnded:
    # TODO: 设计异常类型
    raise newException(IOError, "write after ended")
  await req.conn.socket.send(buf, size)

proc toChunkSize(x: BiggestInt): string {.noInit.} = 
  const HexChars = "0123456789ABCDEF"
  var n = x
  var m = 0
  var s = newString(5) # sizeof(BiggestInt) * 10 / 16
  for j in countdown(4, 0):
    s[j] = HexChars[n and 0xF]
    n = n shr 4
    m.inc()
    if n == 0: 
      break
  result = newStringOfCap(m)
  for i in 5-m..<5:
    result.add(s[i])

proc encodeToChunk*(source: pointer, sourceSize: Natural, dist: pointer, distSize: Natural) =
  ## 将 ``source`` 编码为 chunked 数据， 编码后的数据保存在 ``dist`` 。 ``dist`` 的长度 ``distSize`` 至少比 ``source``
  ## 的长度 ``sourceSize`` 大 10， 否则， 将抛出错误。
  ## TODO: 优化 
  if distSize - sourceSize < 10:
    raise newException(OverflowError, "dist size must be large than souce")
  let chunksize = sourceSize.toChunkSize()  
  assert chunkSize.len <= 5
  copyMem(dist, chunksize.cstring, chunksize.len)
  cast[ptr char](dist.offset(chunksize.len))[] = CR
  cast[ptr char](dist.offset(chunksize.len + 1))[] = LF
  copyMem(dist.offset(chunksize.len + 2), source, sourceSize)
  cast[ptr char](dist.offset(chunksize.len + 2 + sourceSize))[] = CR
  cast[ptr char](dist.offset(chunksize.len + 2 + sourceSize + 1))[] = LF

proc encodeToChunk*(source: pointer, sourceSize: Natural, dist: pointer, distSize: Natural, extensions: string) =
  ## 将 ``source`` 编码为 chunked 数据， 编码后的数据保存在 ``dist`` 。 ``dist`` 的长度 ``distSize`` 至少比 ``source``
  ## 的长度 ``sourceSize`` 大 10 + extensions.len， 否则， 将抛出错误。
  ## TODO: 优化 
  if distSize - sourceSize - extensions.len < 10:
    raise newException(OverflowError, "dist size must be large than souce")
  let chunksize = sourceSize.toChunkSize()  
  assert chunkSize.len <= 5
  copyMem(dist, chunksize.cstring, chunksize.len)
  copyMem(dist.offset(chunksize.len), extensions.cstring, extensions.len)
  cast[ptr char](dist.offset(chunksize.len + extensions.len))[] = CR
  cast[ptr char](dist.offset(chunksize.len + 1 + extensions.len))[] = LF
  copyMem(dist.offset(chunksize.len + 2 + extensions.len), source, sourceSize)
  cast[ptr char](dist.offset(chunksize.len + 2 + sourceSize + extensions.len))[] = CR
  cast[ptr char](dist.offset(chunksize.len + 2 + sourceSize + 1 + extensions.len))[] = LF

proc write*(req: Request, data: string): Future[void] =
  ## 对 HTTP 请求 ``req`` 写入响应数据。 
  # TODO: 考虑 chunked
  # TODO: 考虑 GC_ref data
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

proc writeEnd*(req: Request) =
  ## 对 HTTP 请求 ``req`` 写入结尾信号。 之后， 不能向 ``req`` 写入数据， 否则将抛出异常。 
  if not req.writeEnded:
    req.writeEnded = true
    if req.conn.readEnded:
      if not req.conn.closed:
        req.conn.socket.closeSocket()
        req.conn.closed = true
    else:
      if req.readEnded:
        asyncCheck req.conn.processNextRequest()


 



