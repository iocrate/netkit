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
import netkit/locks 
import netkit/buffer/constants as buffer_constants
import netkit/buffer/circular
import netkit/http/base 
import netkit/http/chunk 
import netkit/http/metadata 
import netkit/http/connection
import netkit/http/constants as http_constants

type
  HttpReader* = ref object of RootObj ##
    conn: HttpConnection
    # writer: HttpWriter 考虑使用一个 callback 
    lock: AsyncLock
    metadata: HttpMetadata
    header*: HttpHeader
    onEnd: proc () {.gcsafe, closure.}
    contentLen: Natural
    chunked: bool
    readable: bool

  ServerRequest* = ref object of HttpReader ## 
  ClientResponse* = ref object of HttpReader ## 

proc init(reader: HttpReader, conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}) = 
  reader.conn = conn
  reader.lock = initAsyncLock()
  reader.metadata = initHttpMetadata()
  reader.onEnd = onEnd
  reader.contentLen = 0
  reader.chunked = false
  reader.readable = true

proc newServerRequest*(conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}): ServerRequest = 
  ##
  new(result)
  result.init(conn, onEnd)
  result.header = HttpHeader(kind: HttpHeaderKind.Request)

proc newClientResponse*(conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}): ClientResponse = 
  ##
  new(result)
  result.init(conn, onEnd)
  result.header = HttpHeader(kind: HttpHeaderKind.Response)

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

proc normalizeSpecificFields*(reader: HttpReader) =
  # TODO: more normalized header fields
  reader.normalizeContentLength()
  reader.normalizeTransforEncoding()    

template readByGuard(reader: HttpReader, buf: pointer, size: Natural) = 
  let readFuture = reader.conn.readData(buf, size)
  yield readFuture
  if readFuture.failed:
    reader.conn.close()
    raise readFuture.readError()

template readContent(reader: HttpReader, buf: pointer, size: Natural): Natural = 
  assert not reader.conn.closed
  assert reader.readable 
  assert reader.contentLen > 0
  let n = min(reader.contentLen, size)
  reader.readByGuard(buf, n)
  reader.contentLen.dec(n)  
  if reader.contentLen == 0:
    reader.readable = false
    reader.onEnd()
    # if reader.writer.writable == false:
    #   case reader.header.kind 
    #   of HttpHeaderKind.Request:
    #     asyncCheck reader.conn.handleNextRequest()
    #   of HttpHeaderKind.Response:
    #     raise newException(Exception, "Not Implemented yet")
  n

template readContent(reader: HttpReader): string = 
  assert not reader.conn.closed
  assert reader.readable 
  let n = min(reader.contentLen, BufferSize)
  var buffer = newString(n)
  reader.readByGuard(buffer.cstring, n) # should need Gc_ref(result) ?
  buffer.shallow()                      # still ref result 
  reader.contentLen.dec(n)  
  if reader.contentLen == 0:
    reader.readable = false
    reader.onEnd()
    # if reader.writer.writable == false:
    #   case reader.header.kind 
    #   of HttpHeaderKind.Request:
    #     asyncCheck reader.conn.handleNextRequest()
    #   of HttpHeaderKind.Response:
    #     raise newException(Exception, "Not Implemented yet")
  buffer

template readChunkHeaderByGuard(reader: HttpReader, header: var ChunkHeader) = 
  # TODO: 考虑内存泄漏
  let readFuture = reader.conn.readChunkHeader(header.addr)
  yield readFuture
  if readFuture.failed:
    reader.conn.close()
    raise readFuture.readError()
  if header.extensions.len > 0:
    header.extensions.shallow()
    reader.metadata = initHttpMetadata(header.extensions)

template readChunkEndByGuard(reader: HttpReader, trailer: ptr seq[string]) = 
  let readFuture = reader.conn.readChunkEnd(trailer)
  yield readFuture
  if readFuture.failed:
    reader.conn.close()
    raise readFuture.readError()
  if trailer[].len > 0:
    # trailer.shallow()
    reader.metadata = initHttpMetadata(trailer[])

template readChunk(reader: HttpReader, buf: pointer, size: int): Natural =
  assert reader.conn.closed
  assert reader.readable
  assert reader.chunked
  var header: ChunkHeader
  # TODO: 考虑内存泄漏
  reader.readChunkHeaderByGuard(header)
  if header[0] == 0:
    var trailer: seq[string]
    reader.readChunkEndByGuard(trailer.addr)
    reader.readable = false
    reader.onEnd()
    # if reader.writer.writable == false:
    #   case reader.header.kind 
    #   of HttpHeaderKind.Request:
    #     asyncCheck reader.conn.handleNextRequest()
    #   of HttpHeaderKind.Response:
    #     raise newException(Exception, "Not Implemented yet")
  else:
    assert header[0] <= size
    reader.readByGuard(buf, header[0])
  header[0]

template readChunk(reader: HttpReader): string = 
  assert reader.conn.closed
  assert reader.readable
  assert reader.chunked
  var data = ""
  var header: ChunkHeader
  reader.readChunkHeaderByGuard(header)
  if header[0] == 0:
    var trailer: seq[string]
    reader.readChunkEndByGuard(trailer.addr)
    reader.readable = false
    reader.onEnd()
    # if reader.writer.writable == false:
    #   case reader.header.kind 
    #   of HttpHeaderKind.Request:
    #     asyncCheck reader.conn.handleNextRequest()
    #   of HttpHeaderKind.Response:
    #     raise newException(Exception, "Not Implemented yet")
  else:
    data = newString(header[0])
    reader.readByGuard(data.cstring, header[0])
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
