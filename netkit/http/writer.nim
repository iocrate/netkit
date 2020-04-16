#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 

import strutils
import asyncdispatch
import nativesockets
import netkit/locks 
import netkit/http/base 
import netkit/http/exception
import netkit/http/connection

type
  HttpWriter* = ref object of RootObj ##
    conn: HttpConnection
    lock: AsyncLock
    onEnd: proc () {.gcsafe, closure.}
    writable: bool

  ServerResponse* = ref object of HttpWriter ## 
  ClientRequest* = ref object of HttpWriter ## 

proc init(writer: HttpWriter, conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}) = 
  writer.conn = conn
  writer.lock = initAsyncLock()
  writer.onEnd = onEnd
  writer.writable = true

proc newServerResponse*(conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}): ServerResponse = 
  ##
  new(result)
  result.init(conn, onEnd)

proc newClientRequest*(conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}): ClientRequest = 
  ##
  new(result)
  result.init(conn, onEnd)

proc ended*(writer: HttpWriter): bool {.inline.} =
  ## 
  writer.conn.closed or not writer.writable

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
  # GC_ref(data)
  try:
    writer.writeByGuard(data.cstring, data.len)
  finally:
    # GC_unref(data)
    writer.lock.release()

proc write*(
  writer: HttpWriter, 
  statusCode: HttpCode,
  fields: openArray[tuple[name: string, value: string]]
): Future[void]  =
  ## 
  return writer.write(
    HttpHeader(
      kind: HttpHeaderKind.Response, 
      statusCode: statusCode,
      fields: initHeaderFields(fields)).toResponseStr())

proc write*(
  writer: HttpWriter, 
  statusCode: HttpCode,
  fields: openArray[tuple[name: string, value: seq[string]]]
): Future[void] =
  ## 
  return writer.write(
    HttpHeader(
      kind: HttpHeaderKind.Response, 
      statusCode: statusCode,
      fields: initHeaderFields(fields)).toResponseStr())

proc writeEnd*(writer: HttpWriter) =
  ## 
  if writer.writable:
    writer.writable = false
    if not writer.conn.closed:
      writer.onEnd()
      # case writer.reader.header.kind 
      # of HttpHeaderKind.Request:
      #   asyncCheck writer.reader.conn.handleNextRequest()
      # of HttpHeaderKind.Response:
      #   raise newException(Exception, "Not Implemented yet")
