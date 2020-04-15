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

  Request* = ref object ## 
    conn: HttpConnection
    header: RequestHeader
    readLock: AsyncLock
    writeLock: AsyncLock
    contentLen: Natural
    # chunked: bool
    trailer: bool
    # readEnded: bool
    # writeEnded: bool

    readableState: ReadableState
    readableMetaData: ReadableMetaData
    writableState: WritableState
    
  RequestHandler* = proc (req: Request): Future[void] {.closure, gcsafe.}

  ReadableState* {.pure.} = enum
    Data, Chunk, Eof

  ReadableMetaKind* {.pure.} = enum
    None, ChunkTrailer, ChunkExtensions

  ReadableMetaData* = object
    kind: ReadableMetaKind
    data: seq[tuple[name: string, value: string]]

  WritableState* {.pure.} = enum
    Ready, Eof

proc newHttpConnection(socket: AsyncFD, address: string, handler: RequestHandler): HttpConnection = 
  ##
  new(result)
  result.buffer = initMarkableCircularBuffer()
  result.parser = initHttpParser()
  result.requestHandler = handler
  result.socket = socket
  result.address = address
  result.closed = false

proc close(conn: HttpConnection) {.inline.} = 
  conn.socket.closeSocket()
  conn.closed = true

proc read(conn: HttpConnection): Future[Natural] {.async.} = 
  ##
  ##
  ## If the return future is failed, ``OsError`` may be raised.
  let region = conn.buffer.next()
  result = await conn.socket.recvInto(region[0], region[1])
  if result > 0:
    discard conn.buffer.pack(result)

proc read(conn: HttpConnection, buf: pointer, size: Natural): Future[Natural] {.async.} =  
  ## Reads up to ``size`` bytes from the connection, storing the results in the ``buf``. 
  ## 
  ## The return value is the number of bytes actually read. This might be less than ``size`` 
  ## that indicates the connection is EOF. 
  ## 
  ## If the return future is failed, ``OsError`` may be raised.
  result = conn.buffer.len
  if result >= size:
    discard conn.buffer.get(buf, size)
    discard conn.buffer.del(size)
    result = size
  else:
    if result > 0:
      discard conn.buffer.get(buf, result)
      discard conn.buffer.del(result)
    var remainingLen = size - result
    while remainingLen > 0:
      let readLen = await conn.socket.recvInto(buf.offset(result), remainingLen)
      if readLen == 0:
        return
      discard conn.buffer.get(buf.offset(result), readLen)
      discard conn.buffer.del(readLen)
      result.inc(readLen)
      remainingLen.dec(readLen)  

proc write(conn: HttpConnection, buf: pointer, size: Natural): Future[void] =
  ## Writes ``size`` bytes from ``buf`` to the connection ``conn``. 
  ## 
  ## If the return future is failed, ``OsError`` may be raised.
  result = conn.socket.send(buf, size)

proc write(conn: HttpConnection, data: string): Future[void] =
  ## 
  ## If the return future is failed, ``OsError`` may be raised.
  result = conn.socket.send(data)

proc newRequest*(conn: HttpConnection): Request = 
  ##
  new(result)
  result.conn = conn
  result.header = initRequestHeader()
  result.readLock = initAsyncLock()
  result.writeLock = initAsyncLock()
  result.contentLen = 0
  # result.chunked = false
  result.trailer = false
  # result.readEnded = false
  result.readableState = ReadableState.Data
  result.readableMetaData = ReadableMetaData()
  result.writableState = WritableState.Ready

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

proc readableState*(req: Request): ReadableState =
  ## 
  req.readableState

proc writableState*(req: Request): WritableState =
  ## 
  req.writableState

# proc isReadTrailer*(req: Request): bool =
#   ## 
#   req.trailer

proc normalizeTransforEncoding(req: Request) =
  if req.fields.contains("Transfer-Encoding"):
    let encodings = req.fields["Transfer-Encoding"]
    var i = 0
    for encoding in encodings:
      if encoding.toLowerAscii() == "chunked":
        if i != encodings.len-1:
          raise newException(ValueError, "Bad Request")
        req.readableState = ReadableState.Chunk
        req.contentLen = 0
        return
      i.inc()

proc normalizeContentLength(req: Request) =
  if req.fields.contains("Content-Length"):
    if req.fields["Content-Length"].len > 1:
      raise newException(ValueError, "Bad Request")
    req.contentLen = req.fields["Content-Length"][0].parseInt()
    if req.contentLen < 0:
      raise newException(ValueError, "Bad Request")
  if req.contentLen == 0:
    req.readableState = ReadableState.Eof

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
      echo "Got Parsing or NormalizeSpecificFields Error: ", getCurrentExceptionMsg()
      yield conn.write("HTTP/1.1 400 Bad Request\r\L\r\L") # discard error
      conn.close()
      return

  var req: Request
  var parsed = false
  
  if conn.buffer.len > 0:
    req = newRequest(conn)
    guard:
      parsed = conn.parser.parseRequest(req.header, conn.buffer)
  
  if not parsed:
    while true:
      let readFuture = conn.read()
      yield readFuture
      if readFuture.failed or readFuture.read() == 0:
        conn.close()
        return
  
      if req == nil:
        req = newRequest(conn)
      
      guard:
        if conn.parser.parseRequest(req.header, conn.buffer):
          break
  guard:
    req.normalizeSpecificFields()

  yield conn.requestHandler(req) # discard error

template readContent(req: Request, buf: pointer, size: Natural): Natural = 
  assert req.readableState == ReadableState.Data
  assert req.contentLen > 0
  let n = min(req.contentLen, size)
  let readFuture = req.conn.read(buf, n)
  yield readFuture
  if readFuture.failed:
    req.readableState = ReadableState.Eof
    req.conn.close()
    raise readFuture.readError()
  if readFuture.read() != n:
    req.readableState = ReadableState.Eof
    req.conn.close()
    raise newException(ReadAbortedError, "Connection closed prematurely")
  req.contentLen.dec(n)  
  if req.contentLen == 0:
    req.readableState = ReadableState.Eof
    if req.writableState == WritableState.Eof:
      asyncCheck req.conn.handleNextRequest()
  n

template readContent(req: Request): string = 
  assert req.readableState == ReadableState.Data
  assert req.contentLen > 0
  let n = min(req.contentLen, BufferSize)
  var buffer = newString(n)
  let readFuture = req.conn.read(buffer.cstring, n) # should need Gc_ref(result) ?
  yield readFuture
  if readFuture.failed:
    req.readableState = ReadableState.Eof
    req.conn.close()
    raise readFuture.readError()
  if readFuture.read() != n:
    req.readableState = ReadableState.Eof
    req.conn.close()
    raise newException(ReadAbortedError, "Connection closed prematurely")
  buffer.shallow()                                  # still ref result 
  req.contentLen.dec(n)  
  if req.contentLen == 0:
    req.readableState = ReadableState.Eof
    if req.writableState == WritableState.Eof:
      asyncCheck req.conn.handleNextRequest()
  buffer

template readChunkHeader(req: Request, chunkSizer: ChunkHeader) = 
  let conn = req.conn
  var succ = false
  while true:
    try:
      (succ, chunkSizer) = conn.parser.parseChunkHeader(conn.buffer)
    except:
      req.readableState = ReadableState.Eof
      req.conn.close()
      raise newException(ReadAbortedError, "Bad chunked transmission")
    if succ:
      break
    let readFuture = req.conn.read()
    yield readFuture
    if readFuture.failed or readFuture.read() == 0:
      req.readableState = ReadableState.Eof
      req.conn.close()
      raise newException(ReadAbortedError, "Connection closed prematurely")

template readChunkEnd(req: Request, trailer: string) = 
  let conn = req.conn
  var succ = false
  while true:
    try:
      (succ, trailer) = conn.parser.parseChunkEnd(conn.buffer)
    except:
      req.readableState = ReadableState.Eof
      req.conn.close()
      raise newException(ReadAbortedError, "Bad chunked transmission")
    if succ:
      break
    let readFuture = req.conn.read()
    yield readFuture
    if readFuture.failed or readFuture.read() == 0:
      req.readableState = ReadableState.Eof
      req.conn.close()
      raise newException(ReadAbortedError, "Connection closed prematurely")

template readChunk(req: Request, buf: pointer, size: int): Natural =
  assert req.readableState == ReadableState.Chunk
  
  var readLen = 0

  template handleEnd = 
    var trailer: string
    readChunkEnd(req, trailer)
    if trailer.len == 0:
      req.trailer = false
      req.readableState = ReadableState.Eof
      if req.writableState == WritableState.Eof:
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
      let readFuture = req.conn.read(buf, chunkSizer[0])
      yield readFuture
      if readFuture.failed:
        req.readableState = ReadableState.Eof
        req.conn.close()
        raise readFuture.readError()
      readLen = readFuture.read()
      if readLen != chunkSizer[0]:
        req.readableState = ReadableState.Eof
        req.conn.close()
        raise newException(ReadAbortedError, "Connection closed prematurely")
  readLen

template readChunk(req: Request): string = 
  # chunked size 必须小于 BufferSize；chunkedSizeLen 必须小于 BufferSize
  assert req.readableState == ReadableState.Chunk
  
  var readData = ""

  template handleEnd = 
    readChunkEnd(req, readData)
    if readData.len == 0:
      req.trailer = false
      req.readableState = ReadableState.Eof
      if req.writableState == WritableState.Eof:
        asyncCheck req.conn.handleNextRequest()
    else:
      readData.shallow()
      req.trailer = true

  if req.trailer:
    handleEnd()
  else:
    var chunkSizer: ChunkHeader
    req.readChunkHeader(chunkSizer)
    if chunkSizer[0] == 0:
      handleEnd()
    else:
      readData = newString(chunkSizer[0])
      let readFuture = req.conn.read(readData.cstring, chunkSizer[0])
      yield readFuture
      if readFuture.failed:
        req.readableState = ReadableState.Eof
        req.conn.close()
        raise readFuture.readError()
      if readFuture.read() != chunkSizer[0]:
        req.readableState = ReadableState.Eof
        req.conn.close()
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
    case req.readableState:
    of ReadableState.Eof:
      discard
    of ReadableState.Data:
      result = req.readContent(buf, size)
    of ReadableState.Chunk:
      result = req.readChunk(buf, size)
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
    case req.readableState:
    of ReadableState.Eof:
      discard
    of ReadableState.Data:
      result = req.readContent()
    of ReadableState.Chunk:
      result = req.readChunk()
  finally:
    req.readLock.release()

proc readAll*(req: Request): Future[string] {.async.} =
  ## Reads all bytes from the request, storing the results as a string. 
  ## 
  ## If the return future is failed, ``OsError`` or ``ReadAbortedError`` may be raised.
  await req.readLock.acquire()
  try:
    case req.readableState:
    of ReadableState.Eof:
      discard
    of ReadableState.Data:
      result = newString(req.contentLen)
      while req.readableState != ReadableState.Eof:
        result.add(req.readContent())
    of ReadableState.Chunk:
      while req.readableState != ReadableState.Eof:
        result.add(req.readChunk())
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
    case req.readableState:
    of ReadableState.Eof:
      discard
    of ReadableState.Data:
      while req.readableState != ReadableState.Eof:
        discard req.readContent(buffer.cstring, LimitChunkDataLen)
    of ReadableState.Chunk:
      while req.readableState != ReadableState.Eof:
        discard req.readChunk(buffer.cstring, LimitChunkDataLen)
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
    if req.writableState == WritableState.Eof:
      raise newException(WriteAbortedError, "Write after ended")
    try:
      await req.conn.write(buf, size)
    except:
      req.readableState = ReadableState.Eof
      req.conn.close()
      raise getCurrentException()
  finally:
    req.readLock.release()

proc write*(req: Request, data: string): Future[void] {.async.} =
  ## 
  await req.readLock.acquire()
  GC_ref(data)
  try:
    if req.conn.closed:
      raise newException(WriteAbortedError, "Connection has been closed")
    if req.writableState == WritableState.Eof:
      raise newException(WriteAbortedError, "Write after ended")
    try:
      await req.conn.write(data.cstring, data.len)
    except:
      req.readableState = ReadableState.Eof
      req.conn.close()
      raise getCurrentException()
  finally:
    GC_unref(data)
    req.readLock.release()

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
  if req.writableState != WritableState.Eof:
    req.writableState = WritableState.Eof
    if not req.conn.closed and req.readableState == ReadableState.Eof:
      asyncCheck req.conn.handleNextRequest()

proc handleHttpConnection*(socket: AsyncFD, address: string, handler: RequestHandler) = 
  ##
  asyncCheck newHttpConnection(socket, address, handler).handleNextRequest() 





