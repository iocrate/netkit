#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 

import strutils
import strtabs
import asyncdispatch
import nativesockets
import netkit/misc
import netkit/locks 
import netkit/buffer/constants as buffer_constants
import netkit/buffer/circular
import netkit/http/base 
import netkit/http/chunk 
import netkit/http/metadata 
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

  HttpReader* = ref object of RootObj ##
    conn: HttpConnection
    writer: HttpWriter
    lock: AsyncLock
    contentLen: Natural
    chunked: bool
    readable: bool
    metadata: HttpMetadata
    header: HttpHeader

  HttpWriter* = ref object of RootObj ##
    conn: HttpConnection
    reader: HttpReader
    lock: AsyncLock
    writable: bool

  ServerRequest* = ref object of HttpReader ## 
  ServerResponse* = ref object of HttpWriter ## 
  ClientRequest* = ref object of HttpWriter ## 
  ClientResponse* = ref object of HttpReader ## 

  # Request* = ref object ## 
  #   conn: HttpConnection
  #   header: RequestHeader
  #   readLock: AsyncLock
  #   writeLock: AsyncLock
  #   contentLen: Natural
  #   metadata: HttpMetadata
    
  RequestHandler* = proc (req: ServerRequest, res: ServerResponse): Future[void] {.closure, gcsafe.}

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

proc write(conn: HttpConnection, buf: pointer, size: Natural): Future[void] {.inline.} =
  ## Writes ``size`` bytes from ``buf`` to the connection ``conn``. 
  ## 
  ## If the return future is failed, ``OsError`` may be raised.
  result = conn.socket.send(buf, size)

proc write(conn: HttpConnection, data: string): Future[void] {.inline.} =
  ## 
  ## If the return future is failed, ``OsError`` may be raised.
  result = conn.socket.send(data)

proc init(reader: HttpReader, conn: HttpConnection) = 
  reader.conn = conn
  reader.writer = nil
  reader.lock = initAsyncLock()
  reader.contentLen = 0
  reader.chunked = false
  reader.readable = true
  reader.metadata = initHttpMetadata()

proc init(writer: HttpWriter, conn: HttpConnection) = 
  writer.conn = conn
  writer.reader = nil
  writer.lock = initAsyncLock()
  writer.writable = true

proc newServerRequest(conn: HttpConnection): ServerRequest = 
  ##
  new(result)
  result.init(conn)
  result.header = initRequestHeader()

proc newServerResponse(conn: HttpConnection): ServerResponse = 
  ##
  new(result)
  result.init(conn)

proc newClientRequest(conn: HttpConnection): ClientRequest = 
  ##
  new(result)
  result.init(conn)

proc newClientResponse(conn: HttpConnection): ClientResponse = 
  ##
  new(result)
  result.init(conn)
  result.header = initResponseHeader()

proc reqMethod*(req: ServerRequest): HttpMethod {.inline.} = 
  ##  
  req.header.reqMethod

proc url*(req: ServerRequest): string {.inline.} = 
  ## 
  req.header.url

proc version*(reader: HttpReader): HttpVersion {.inline.} = 
  ## 
  reader.header.version

proc fields*(reader: HttpReader): HeaderFields {.inline.} = 
  ## 
  reader.header.fields

proc metadata*(reader: HttpReader): HttpMetadata {.inline.} =
  ## 
  reader.metadata

proc ended*(reader: HttpReader): bool {.inline.} =
  ## 
  reader.conn.closed or not reader.readable

proc ended*(writer: HttpWriter): bool {.inline.} =
  ## 
  writer.conn.closed or not writer.writable

proc normalizeTransforEncoding(reader: HttpReader) =
  if reader.fields.contains("Transfer-Encoding"):
    let encodings = reader.fields["Transfer-Encoding"]
    var i = 0
    for encoding in encodings:
      if encoding.toLowerAscii() == "chunked":
        if i != encodings.len-1:
          raise newException(ValueError, "Bad Request")
        reader.readable = false
        reader.contentLen = 0
        return
      i.inc()

proc normalizeContentLength(reader: HttpReader) =
  if reader.fields.contains("Content-Length"):
    if reader.fields["Content-Length"].len > 1:
      raise newException(ValueError, "Bad Request")
    reader.contentLen = reader.fields["Content-Length"][0].parseInt()
    if reader.contentLen < 0:
      raise newException(ValueError, "Bad Request")
  if reader.contentLen == 0:
    reader.readable = false

proc normalizeSpecificFields(reader: HttpReader) =
  # TODO: more normalized header fields
  reader.normalizeContentLength()
  reader.normalizeTransforEncoding()

proc handleNextRequest(conn: HttpConnection): Future[void] {.async.} = 
  template guard(stmts: untyped) = 
    try:
      stmts
    except:
      yield conn.write("HTTP/1.1 400 Bad Request\r\L\r\L") # discard error
      conn.close()
      return

  var req: ServerRequest
  var res: ServerResponse
  var parsed = false
  
  if conn.buffer.len > 0:
    req = newServerRequest(conn)
    guard:
      parsed = conn.parser.parseHttpHeader(req.header, conn.buffer)
  
  if not parsed:
    while true:
      let readFuture = conn.read()
      yield readFuture
      if readFuture.failed or readFuture.read() == 0:
        conn.close()
        return
  
      if req == nil:
        req = newServerRequest(conn)
      
      guard:
        if conn.parser.parseHttpHeader(req.header, conn.buffer):
          break
  guard:
    req.normalizeSpecificFields()

  res = newServerResponse(conn)
  req.writer = res
  res.reader = req

  yield conn.requestHandler(req, res) # discard error

template readByGuard(reader: HttpReader) = 
  let readFuture = reader.conn.read()
  yield readFuture
  if readFuture.failed or readFuture.read() == 0:
    reader.conn.close()
    raise newException(ReadAbortedError, "Connection closed prematurely")

template readByGuard(reader: HttpReader, buf: pointer, size: Natural) = 
  let readFuture = reader.conn.read(buf, size)
  yield readFuture
  if readFuture.failed:
    reader.conn.close()
    raise readFuture.readError()
  if readFuture.read() != size:
    reader.conn.close()
    raise newException(ReadAbortedError, "Connection closed prematurely")

template readContent(reader: HttpReader, buf: pointer, size: Natural): Natural = 
  assert not reader.conn.closed
  assert reader.readable 
  assert reader.contentLen > 0
  let n = min(reader.contentLen, size)
  reader.readByGuard(buf, n)
  reader.contentLen.dec(n)  
  if reader.contentLen == 0:
    reader.readable = false
    if reader.writer.writable == false:
      case reader.header.kind 
      of HttpHeaderKind.Request:
        asyncCheck reader.conn.handleNextRequest()
      of HttpHeaderKind.Response:
        raise newException(Exception, "Not Implemented yet")
  n

template readContent(reader: HttpReader): string = 
  assert not reader.conn.closed
  assert reader.readable 
  let n = min(reader.contentLen, BufferSize)
  var buffer = newString(n)
  reader.readByGuard(buffer.cstring, n) # should need Gc_ref(result) ?
  buffer.shallow()                   # still ref result 
  reader.contentLen.dec(n)  
  if reader.contentLen == 0:
    reader.readable = false
    if reader.writer.writable == false:
      case reader.header.kind 
      of HttpHeaderKind.Request:
        asyncCheck reader.conn.handleNextRequest()
      of HttpHeaderKind.Response:
        raise newException(Exception, "Not Implemented yet")
  buffer

template readChunkHeader(reader: HttpReader, chunkHeader: ChunkHeader) = 
  while true:
    try:
      if reader.conn.parser.parseChunkHeader(reader.conn.buffer, chunkHeader):
        if chunkHeader.extensions.len > 0:
          chunkHeader.extensions.shallow()
          reader.metadata = initHttpMetadata(chunkHeader.extensions)
        break
    except:
      reader.conn.close()
      raise newException(ReadAbortedError, "Bad chunked transmission")
    reader.readByGuard()

template readChunkEnd(reader: HttpReader) = 
  var trailer: seq[string]
  while true:
    try:
      if reader.conn.parser.parseChunkEnd(reader.conn.buffer, trailer):
        if trailer.len > 0:
          trailer.shallow()
          reader.metadata = initHttpMetadata(trailer)
        reader.readable = false
        break
    except:
      reader.conn.close()
      raise newException(ReadAbortedError, "Bad chunked transmission")
    reader.readByGuard()

template readChunk(reader: HttpReader, buf: pointer, size: int): Natural =
  assert reader.conn.closed
  assert reader.readable
  assert reader.chunked
  var chunkHeader: ChunkHeader
  reader.readChunkHeader(chunkHeader)
  if chunkHeader[0] == 0:
    reader.readChunkEnd()
    if reader.writer.writable == false:
      case reader.header.kind 
      of HttpHeaderKind.Request:
        asyncCheck reader.conn.handleNextRequest()
      of HttpHeaderKind.Response:
        raise newException(Exception, "Not Implemented yet")
  else:
    assert chunkHeader[0] <= size
    reader.readByGuard(buf, chunkHeader[0])
  chunkHeader[0]

template readChunk(reader: HttpReader): string = 
  assert reader.conn.closed
  assert reader.readable
  assert reader.chunked
  var data = ""
  var chunkHeader: ChunkHeader
  reader.readChunkHeader(chunkHeader)
  if chunkHeader[0] == 0:
    reader.readChunkEnd()
    if reader.writer.writable == false:
      case reader.header.kind 
      of HttpHeaderKind.Request:
        asyncCheck reader.conn.handleNextRequest()
      of HttpHeaderKind.Response:
        raise newException(Exception, "Not Implemented yet")
  else:
    data = newString(chunkHeader[0])
    reader.readByGuard(data.cstring, chunkHeader[0])
    data.shallow()
  data

proc read*(reader: HttpReader, buf: pointer, size: range[int(LimitChunkDataLen)..high(int)]): Future[Natural] {.async.} =
  ## Reads up to ``size`` bytes from the request, storing the results in the ``buf``. 
  ## 
  ## The return value is the number of bytes actually read. This might be less than ``size``.
  ## A value of zero indicates ``eof``, i.e. at the end of the request.
  ## 
  ## If the return future is failed, ``OsError`` or ``ReadAbortedError`` may be raised.
  await reader.lock.acquire()
  try:
    if not reader.ended:
      if reader.chunked:
        result = reader.readChunk(buf, size)
      else:
        result = reader.readContent(buf, size)
  finally:
    reader.lock.release()

proc read*(reader: HttpReader): Future[string] {.async.} =
  ## Reads up to ``size`` bytes from the request, storing the results as a string. 
  ## 
  ## If the return value is ``""``, that indicates ``eof``, i.e. at the end of the request.
  ## 
  ## If the return future is failed, ``OsError`` or ``ReadAbortedError`` may be raised.
  await reader.lock.acquire()
  try:
    if not reader.ended:
      if reader.chunked:
        result = reader.readChunk()
      else:
        result = reader.readContent()
  finally:
    reader.lock.release()

proc readAll*(reader: HttpReader): Future[string] {.async.} =
  ## Reads all bytes from the request, storing the results as a string. 
  ## 
  ## If the return future is failed, ``OsError`` or ``ReadAbortedError`` may be raised.
  await reader.lock.acquire()
  try:
    if reader.chunked:
      while not reader.ended:
        result.add(reader.readChunk())
    else:
      result = newString(reader.contentLen)
      while not reader.ended:
        result.add(reader.readContent())
  finally:
    reader.lock.release()

proc readDiscard*(reader: HttpReader): Future[void] {.async.} =
  ## Reads all bytes from the request, discarding the results. 
  ## 
  ## If the return future is failed, ``OsError`` or ``ReadAbortedError`` may be raised.
  await reader.lock.acquire()
  let buffer = newString(LimitChunkDataLen)
  GC_ref(buffer)
  try:
    if reader.chunked:
      while not reader.ended:
        discard reader.readChunk(buffer.cstring, LimitChunkDataLen)
    else:
      while not reader.ended:
        discard reader.readContent(buffer.cstring, LimitChunkDataLen)
  finally:
    GC_unref(buffer)
    reader.lock.release()

template writeByGuard(writer: HttpWriter, buf: pointer, size: Natural) = 
  if writer.conn.closed:
    raise newException(WriteAbortedError, "Connection has been closed")
  if not writer.writable:
    raise newException(WriteAbortedError, "Write after ended")
  let writeFuture = writer.conn.write(buf, size) 
  if writeFuture.failed:
    writer.conn.close()
    raise writeFuture.readError()

proc write*(writer: HttpWriter, buf: pointer, size: Natural): Future[void] {.async.} =
  ## Writes ``size`` bytes from ``buf`` to the request ``req``.
  ## 
  ## If the return future is failed, ``OsError`` or ``WriteAbortedError`` may be raised.
  await writer.lock.acquire()
  try:
    writer.writeByGuard(buf, size)
  finally:
    writer.lock.release()

proc write*(writer: HttpWriter, data: string): Future[void] {.async.} =
  ## 
  await writer.lock.acquire()
  GC_ref(data)
  try:
    writer.writeByGuard(data.cstring, data.len)
  finally:
    GC_unref(data)
    writer.lock.release()

proc write*(
  writer: HttpWriter, 
  statusCode: HttpCode,
  fields: openArray[tuple[name: string, value: string]]
): Future[void]  =
  ## ``write($initResponseHeader(statusCode, fields))`` 。 
  return writer.write($initResponseHeader(statusCode, fields))

proc write*(
  writer: HttpWriter, 
  statusCode: HttpCode,
  fields: openArray[tuple[name: string, value: seq[string]]]
): Future[void] =
  ## ``write($initResponseHeader(statusCode, fields))`` 。 
  return writer.write($initResponseHeader(statusCode, fields))

proc writeEnd*(writer: HttpWriter) =
  ## 
  if writer.writable:
    writer.writable = false
    if not writer.conn.closed and not writer.reader.readable:
      case writer.reader.header.kind 
      of HttpHeaderKind.Request:
        asyncCheck writer.reader.conn.handleNextRequest()
      of HttpHeaderKind.Response:
        raise newException(Exception, "Not Implemented yet")

proc handleHttpConnection*(socket: AsyncFD, address: string, handler: RequestHandler) = 
  ##
  asyncCheck newHttpConnection(socket, address, handler).handleNextRequest() 





