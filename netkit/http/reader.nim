#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module provides an abstraction of read operations related to HTTP.
## 
## Overview
## ========================
## 
## A server reads the incoming request from a client, and a client reads the returned response from a 
## server.
## 
## ``HttpReader`` is a base object for read operations, ``ServerRequest`` and ``ClientResponse`` 
## inherit from it. ``ServerRequest`` represents a incoming request from a client, and ``ClientResponse``
## represents a returned response from a server.

import strutils
import strtabs
import asyncdispatch
import nativesockets
import netkit/locks 
import netkit/buffer/constants as buffer_constants
import netkit/buffer/circular
import netkit/http/limits 
import netkit/http/exception
import netkit/http/spec 
import netkit/http/httpmethod 
import netkit/http/version 
import netkit/http/status
import netkit/http/headerfield  
import netkit/http/header 
import netkit/http/connection
import netkit/http/chunk 
import netkit/http/metadata 

type
  HttpReader* = ref object of RootObj ## An abstraction of read operations related to HTTP.
    conn: HttpConnection
    lock: AsyncLock
    header*: HttpHeader
    metadata: HttpMetadata
    onEnd: proc () {.gcsafe, closure.}
    contentLen: Natural
    chunked: bool
    readable: bool

  ServerRequest* = ref object of HttpReader ## Represents a incoming request from a client.
  ClientResponse* = ref object of HttpReader ## Represents a returned response from a server.

proc init(reader: HttpReader, conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}) = 
  reader.conn = conn
  reader.lock = initAsyncLock()
  reader.metadata = HttpMetadata(kind: HttpMetadataKind.None)
  reader.onEnd = onEnd
  reader.contentLen = 0
  reader.chunked = false
  reader.readable = true

proc newServerRequest*(conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}): ServerRequest = 
  ## Creates a new ``ServerRequest``.
  new(result)
  result.init(conn, onEnd)
  result.header = HttpHeader(kind: HttpHeaderKind.Request)

proc newClientResponse*(conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}): ClientResponse = 
  ## Creates a new ``ClientResponse``.
  new(result)
  result.init(conn, onEnd)
  result.header = HttpHeader(kind: HttpHeaderKind.Response)

proc reqMethod*(req: ServerRequest): HttpMethod {.inline.} = 
  ## Returns the request method. 
  req.header.reqMethod

proc url*(req: ServerRequest): string {.inline.} = 
  ## Returns the url. 
  req.header.url

proc status*(res: ClientResponse): HttpCode {.inline.} = 
  ## Returns the status code. 
  res.header.statusCode

proc version*(reader: HttpReader): HttpVersion {.inline.} = 
  ## Returns the HTTP version. 
  reader.header.version

proc fields*(reader: HttpReader): HeaderFields {.inline.} = 
  ## Returns the header fields. 
  reader.header.fields

proc metadata*(reader: HttpReader): HttpMetadata {.inline.} =
  ## Returns the metadata. 
  reader.metadata

proc ended*(reader: HttpReader): bool {.inline.} =
  ## Returns ``true`` if the underlying connection has been disconnected or no more data can be read.
  reader.conn.closed or not reader.readable

proc normalizeContentLength(reader: HttpReader) =
  if reader.fields.contains("Content-Length"):
    if reader.fields["Content-Length"].len > 1:
      raise newHttpError(Http400, "Bad content length")
    reader.contentLen = reader.fields["Content-Length"][0].parseInt()
    if reader.contentLen < 0:
      raise newHttpError(Http400, "Bad content length")
  if reader.contentLen == 0:
    reader.readable = false

proc normalizeTransforEncoding(reader: HttpReader) =
  if reader.fields.contains("Transfer-Encoding"):
    var encodings: seq[string]
    let items = reader.fields["Transfer-Encoding"]
    if items.len == 1:
      encodings = items[0].split(COMMA)
    elif items.len > 1:
      encodings.shallowCopy(items)
    else:
      return

    var i = 0
    let n = encodings.len - 1
    for encoding in encodings.items():
      var vencoding = encoding
      vencoding.removePrefix(SP)
      vencoding.removePrefix(SP)
      if vencoding.toLowerAscii() == "chunked":
        if i != n:
          raise newHttpError(Http400, "Bad transfer encoding")
        reader.chunked = true
        reader.readable = true
        reader.contentLen = 0
        return
      i.inc()

proc normalizeSpecificFields*(reader: HttpReader) =
  # TODO: more normalized header fields
  ## Normalizes a few special header fields.
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

template readChunkHeaderByGuard(reader: HttpReader, header: ChunkHeader) = 
  # TODO: 考虑内存泄漏
  let readFuture = reader.conn.readChunkHeader(header.addr)
  yield readFuture
  if readFuture.failed:
    reader.conn.close()
    raise readFuture.readError()
  if header.extensions.len > 0:
    header.extensions.shallow()
    reader.metadata = HttpMetadata(kind: HttpMetadataKind.ChunkExtensions, extensions: header.extensions)

template readChunkEndByGuard(reader: HttpReader) = 
  var trailersVar: seq[string]
  let readFuture = reader.conn.readChunkEnd(trailersVar.addr)
  yield readFuture
  if readFuture.failed:
    reader.conn.close()
    raise readFuture.readError()
  if trailersVar.len > 0:
    trailersVar.shallow()
    reader.metadata = HttpMetadata(kind: HttpMetadataKind.ChunkTrailers, trailers: trailersVar)

template readChunk(reader: HttpReader, buf: pointer, n: int): Natural =
  assert reader.conn.closed
  assert reader.readable
  assert reader.chunked
  var header: ChunkHeader
  # TODO: 考虑内存泄漏 GC_ref GC_unref
  reader.readChunkHeaderByGuard(header)
  if header.size == 0:
    reader.readChunkEndByGuard()
    reader.readable = false
    reader.onEnd()
  else:
    assert header.size <= n
    reader.readByGuard(buf, header.size)
  header.size

template readChunk(reader: HttpReader): string = 
  assert reader.conn.closed
  assert reader.readable
  assert reader.chunked
  var data = ""
  var header: ChunkHeader
  reader.readChunkHeaderByGuard(header)
  if header.size == 0:
    reader.readChunkEndByGuard()
    reader.readable = false
    reader.onEnd()
  else:
    data = newString(header.size)
    reader.readByGuard(data.cstring, header.size)
    data.shallow()
  data

proc read*(reader: HttpReader, buf: pointer, size: range[int(LimitChunkDataLen)..high(int)]): Future[Natural] {.async.} =
  ## Reads up to ``size`` bytes, storing the results in the ``buf``. 
  ## 
  ## The return value is the number of bytes actually read. This might be less than ``size``.
  ## A value of zero indicates ``EOF``, i.e. no more data can be read.
  ## 
  ## If a system error occurs during reading, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful reading, a ``ReadAbortedError`` will be raised.
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
  ## Reads up to ``size`` bytes, storing the results as a string. 
  ## 
  ## If the return value is ``""``, that indicates ``eof``, i.e. at the end of the request.
  ## 
  ## If a system error occurs during reading, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful reading, a ``ReadAbortedError`` will be raised.
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
  ## Reads all bytes, storing the results as a string. 
  ## 
  ## If a system error occurs during reading, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful reading, a ``ReadAbortedError`` will be raised.
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
  ## Reads all bytes, discarding the results. 
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
