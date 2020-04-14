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
import netkit/http/chunk 
import netkit/http/constants as http_constants
import netkit/http/parser
import netkit/http/exception

type
  HttpConnection = ref object ## 
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

proc newHttpConnection(socket: AsyncFD, address: string, handler: RequestHandler): HttpConnection = 
  ##
  new(result)
  result.buffer = initMarkableCircularBuffer()
  result.parser = initHttpParser()
  result.requestHandler = handler
  result.socket = socket
  result.address = address
  result.closed = false

template readBuffer(conn: HttpConnection, buf: pointer, size: Natural) = 
  discard conn.buffer.get(buf, size)
  discard conn.buffer.del(size)

template readNativeSocket(conn: HttpConnection, buf: pointer, size: Natural): Natural = 
  var recvLen = 0
  let recvFuture = conn.socket.recvInto(buf, size)
  yield recvFuture
  if recvFuture.failed:
    conn.socket.closeSocket()
    conn.closed = true
    raise recvFuture.readError()
  else:
    recvLen = recvFuture.read()
    if recvLen == 0:
        conn.socket.closeSocket()
        conn.closed = true 
  recvLen

template bufferLen(conn: HttpConnection): Natural = 
  conn.buffer.len.int

proc read(conn: HttpConnection, buf: pointer, size: Natural): Future[Natural] {.async.} = 
  ## Reads up to ``size`` bytes from the connection, storing the results in the ``buf``. 
  ## 
  ## The return value is the number of bytes actually read. This might be less than ``size``.
  ## A value of zero indicates the connection closed.
  ## 
  ## If the return future is failed, ``OsError`` may be raised.
  result = conn.bufferLen
  if result >= size:
    conn.readBuffer(buf, size)
    result = size
  else:
    if result > 0:
      conn.readBuffer(buf, result)
    let remainingLen = size - result
    let readLen = conn.readNativeSocket(buf.offset(result), remainingLen)
    if readLen == 0:
      return
    if remainingLen > readLen:
      conn.readBuffer(buf.offset(result), readLen)
      result.inc(readLen)
    else:
      conn.readBuffer(buf.offset(result), remainingLen)
      result.inc(remainingLen)

proc readUntil(conn: HttpConnection, buf: pointer, size: Natural): Future[Natural] {.async.} =  
  ## Reads up to ``size`` bytes from the connection, storing the results in the ``buf``. 
  ## 
  ## The return value is the number of bytes actually read. This might be less than ``size`` 
  ## that indicates the connection closed. 
  ## 
  ## If the return future is failed, ``OsError`` may be raised.
  result = conn.bufferLen
  if result >= size:
    conn.readBuffer(buf, size)
    result = size
  else:
    if result > 0:
      conn.readBuffer(buf, result)
    var remainingLen = size - result
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

proc write(conn: HttpConnection, buf: pointer, size: Natural): Future[void] {.async.} =
  ## Writes ``size`` bytes from ``buf`` to the connection ``conn``. 
  ## 
  ## If the return future is failed, ``OsError`` may be raised.
  try:
    await conn.socket.send(buf, size)
  except:
    conn.socket.closeSocket()
    conn.closed = true
    conn.closedError = getCurrentException()  
    raise getCurrentException()  

proc write(conn: HttpConnection, data: string): Future[void] {.async.} =
  ## 
  ## If the return future is failed, ``OsError`` may be raised.
  GC_ref(data)
  try:
    await conn.socket.send(data.cstring, data.len)
  except:
    conn.socket.closeSocket()
    conn.closed = true
    conn.closedError = getCurrentException()  
    raise getCurrentException() 
  finally:
    GC_unref(data)

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

proc isReadEnded*(req: Request): bool =
  ## 
  req.conn.closed or req.readEnded

proc isWriteEnded*(req: Request): bool =
  ## 
  req.conn.closed or req.writeEnded

proc isReadTrailer*(req: Request): bool =
  ## 
  req.trailer

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

proc handleNextRequest(conn: HttpConnection): Future[void] {.async.} = 
  template guard(stmts: untyped) = 
    try:
      stmts
    except:
      yield conn.write("HTTP/1.1 400 Bad Request\c\L\c\L") # discard error
      conn.socket.closeSocket()
      conn.closed = true
      return

  var req: Request
  var parsed = false
  
  if conn.bufferLen > 0:
    req = newRequest(conn)
    guard:
      parsed = conn.parser.parseRequest(req.header, conn.buffer)
  
  if not parsed:
    while true:
      let region = conn.buffer.next()
      let readLen = conn.readNativeSocket(region[0], region[1].Natural)
      if readLen == 0:
        return 
      discard conn.buffer.pack(readLen)
  
      if req == nil:
        req = newRequest(conn)
      
      guard:
        if conn.parser.parseRequest(req.header, conn.buffer):
          break
  guard:
    req.normalizeSpecificFields()
    
  yield conn.requestHandler(req) # discard error

template readContent(req: Request, buf: pointer, size: Natural): Natural = 
  assert not req.conn.closed
  assert not req.readEnded
  assert not req.chunked
  assert req.contentLen >= size
  let readFuture = req.conn.read(buf, min(req.contentLen, size))
  yield readFuture
  if readFuture.failed:
    raise readFuture.readError()
  let readLen = readFuture.read()
  if readLen == 0:
    raise newException(ReadAbortedError, "Connection closed prematurely")
  req.contentLen.dec(readLen)  
  if req.contentLen == 0:
    req.readEnded = true
    if req.writeEnded:
      asyncCheck req.conn.handleNextRequest()
  readLen

template readContent(req: Request): string = 
  assert not req.conn.closed
  assert not req.readEnded
  assert not req.chunked
  assert req.contentLen > 0
  let size = min(req.contentLen, BufferSize.int)
  var buffer = newString(size)
  let readFuture = req.conn.read(buffer.cstring, size) # should need Gc_ref(result) ?
  yield readFuture
  if readFuture.failed:
    raise readFuture.readError()
  let readLen = readFuture.read()
  if readLen == 0:
    raise newException(ReadAbortedError, "Connection closed prematurely")
  buffer.setLen(readLen)                               # still ref result 
  buffer.shallow()
  req.contentLen.dec(readLen)  
  if req.contentLen == 0:
    req.readEnded = true
    if req.writeEnded:
      asyncCheck req.conn.handleNextRequest()
  buffer

template readChunkHeader(req: Request, chunkSizer: ChunkHeader) = 
  let conn = req.conn
  var succ = false
  while true:
    try:
      (succ, chunkSizer) = conn.parser.parseChunkHeader(conn.buffer)
    except:
      raise newException(ReadAbortedError, "Bad chunked transmission")
    if succ:
      break
    let (regionPtr, regionLen) = conn.buffer.next()
    let readLen = conn.readNativeSocket(regionPtr, regionLen)
    if readLen == 0:
      raise newException(ReadAbortedError, "Connection closed prematurely")
    discard conn.buffer.pack(readLen) 

template readChunkEnd(req: Request, trailer: string) = 
  let conn = req.conn
  var succ = false
  while true:
    try:
      (succ, trailer) = conn.parser.parseChunkEnd(conn.buffer)
    except:
      raise newException(ReadAbortedError, "Bad chunked transmission")
    if succ:
      break
    let (regionPtr, regionLen) = conn.buffer.next()
    let readLen = conn.readNativeSocket(regionPtr, regionLen)
    if readLen == 0:
      raise newException(ReadAbortedError, "Connection closed prematurely")
    discard conn.buffer.pack(readLen) 

template readChunk(req: Request, buf: pointer, size: int): Natural =
  assert not req.conn.closed
  assert not req.readEnded
  assert req.chunked
  
  var readLen = 0

  template handleEnd = 
    var trailer: string
    readChunkEnd(req, trailer)
    if trailer.len == 0:
      req.trailer = false
      req.readEnded = true
      if req.writeEnded:
        asyncCheck req.conn.handleNextRequest()
    else:
      copyMem(buf, trailer.cstring, trailer.len) 
      req.trailer = true
      readLen = trailer.len

  if req.trailer:
    handleEnd()
  else:
    var chunkSizer: ChunkHeader
    req.readChunkHeader(chunkSizer)
    if chunkSizer[0] == 0:
      handleEnd()
    else:
      assert chunkSizer[0] <= size
      let readFuture = req.conn.readUntil(buf, chunkSizer[0])
      yield readFuture
      if readFuture.failed:
        raise readFuture.readError()
      readLen = readFuture.read()
      if readLen == 0:
        raise newException(ReadAbortedError, "Connection closed prematurely")
  readLen

template readChunk(req: Request): string = 
  # TODO: 合并 read
  # chunked size 必须小于 BufferSize；chunkedSizeLen 必须小于 BufferSize
  assert not req.conn.closed
  assert not req.readEnded
  assert req.chunked
  
  var readData = ""

  template handleEnd = 
    readChunkEnd(req, readData)
    if readData.len == 0:
      req.trailer = false
      req.readEnded = true
      if req.writeEnded:
        asyncCheck req.conn.handleNextRequest()
    else:
      readData.shallow()
      req.trailer = true

  if req.trailer:
    handleEnd()
  else:
    var chunkSizer: ChunkHeader
    req.readChunkHeader(chunkSizer)
    if chunkSizer.size == 0:
      handleEnd()
    else:
      readData = newString(chunkSizer.size)
      let readFuture = req.conn.readUntil(readData.cstring, chunkSizer.size)
      yield readFuture
      if readFuture.failed:
        raise readFuture.readError()
      let readLen = readFuture.read()
      if readLen < chunkSizer.size:
        raise newException(ReadAbortedError, "Connection closed prematurely")
      readData.shallow()
  readData

proc read*(req: Request, buf: pointer, size: range[int(LimitChunkDataLen)..high(int)]): Future[Natural] {.async.} =
  ## Reads up to ``size`` bytes from the request, storing the results in the ``buf``. 
  ## 
  ## The return value is the number of bytes actually read. This might be less than ``size``.
  ## A value of zero indicates ``eof``, i.e. at the end of the request.
  ## 
  ## If the return future is failed, ``OsError`` or ``ReadAbortedError`` may be raised.
  await req.readLock.acquire()
  try:
    if not req.conn.closed and req.readEnded:
      if req.chunked:
        result = req.readChunk(buf, size)
      else:
        result = req.readContent(buf, size)
  finally:
    req.readLock.release()

proc read*(req: Request): Future[string] {.async.} =
  ## Reads up to ``size`` bytes from the request, storing the results as a string. 
  ## 
  ## If the return value is ``""``, that indicates ``eof``, i.e. at the end of the request.
  ## 
  ## If the return future is failed, ``OsError`` or ``ReadAbortedError`` may be raised.
  await req.readLock.acquire()
  try:
    if not req.conn.closed and req.readEnded:
      if req.chunked:
        result = req.readChunk()
      else:
        result = req.readContent()
  finally:
    req.readLock.release()

proc readAll*(req: Request): Future[string] {.async.} =
  ## Reads all bytes from the request, storing the results as a string. 
  ## 
  ## If the return future is failed, ``OsError`` or ``ReadAbortedError`` may be raised.
  await req.readLock.acquire()
  try:
    if not req.chunked:
      result = newString(req.contentLen)
    while not req.isReadEnded:
      if req.chunked:
        result.add(req.readChunk())
      else:
        result.add(req.readContent())
  finally:
    req.readLock.release()

proc readDiscard*(req: Request): Future[void] {.async.} =
  ## Reads all bytes from the request, discarding the results. 
  ## 
  ## If the return future is failed, ``OsError`` or ``ReadAbortedError`` may be raised.
  await req.readLock.acquire()
  let buffer = newString(LimitChunkDataLen)
  GC_ref(buffer)
  try:
    while not req.isReadEnded:
      if req.chunked:
        discard req.readChunk(buffer.cstring, LimitChunkDataLen)
      else:
        discard req.readContent(buffer.cstring, LimitChunkDataLen)
  finally:
    GC_unref(buffer)
    req.readLock.release()

proc write*(req: Request, buf: pointer, size: Natural): Future[void] {.async.} =
  ## Writes ``size`` bytes from ``buf`` to the request ``req``.
  ## 
  ## If the return future is failed, ``OsError`` or ``WriteAbortedError`` may be raised.
  await req.readLock.acquire()
  try:
    if req.conn.closed:
      raise newException(WriteAbortedError, "Connection has been closed")
    if req.writeEnded:
      raise newException(WriteAbortedError, "Write after ended")
    await req.conn.write(buf, size)
  finally:
    req.readLock.release()

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
    if not req.conn.closed:
      if req.readEnded:
        asyncCheck req.conn.handleNextRequest()

proc handleHttpConnection*(socket: AsyncFD, address: string, handler: RequestHandler) = 
  ##
  asyncCheck newHttpConnection(socket, address, handler).handleNextRequest() 
