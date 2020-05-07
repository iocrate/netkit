#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module provides an abstraction of write operations related to HTTP.
## 
## Overview
## ========================
## 
## A server writes a response to a client, and a client writes a request to a server.
## 
## ``HttpWriter`` is a base object for write operations, ``ServerResponse`` and ``ClientRequest`` 
## inherit from it. ``ServerResponse`` represents a response from a server, and ``ClientRequest``
## represents a request from a client.

import strutils
import asyncdispatch
import nativesockets
import netkit/locks 
import netkit/http/exception
import netkit/http/status 
import netkit/http/headerfield 
import netkit/http/header 
import netkit/http/connection

type
  HttpWriter* = ref object of RootObj ## An abstraction of write operations related to HTTP.
    conn: HttpConnection
    lock: AsyncLock
    onEnd: proc () {.gcsafe, closure.}
    writable: bool

  ServerResponse* = ref object of HttpWriter ## Represents a response from a server.
  ClientRequest* = ref object of HttpWriter ## Represents a request from a client.

proc init(writer: HttpWriter, conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}) = 
  writer.conn = conn
  writer.lock = initAsyncLock()
  writer.onEnd = onEnd
  writer.writable = true

proc newServerResponse*(conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}): ServerResponse = 
  ## Creates a new ``ServerResponse``.
  new(result)
  result.init(conn, onEnd)

proc newClientRequest*(conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}): ClientRequest = 
  ## Creates a new ``ClientRequest``.
  new(result)
  result.init(conn, onEnd)

proc ended*(writer: HttpWriter): bool {.inline.} =
  ## Returns ``true`` if the underlying connection has been closed or writer has been shut down.
  writer.conn.closed or not writer.writable

template writeByGuard(writer: HttpWriter, buf: pointer, size: Natural) = 
  if writer.conn.closed:
    raise newException(WriteAbortedError, "Connection has been closed")
  if not writer.writable:
    raise newException(WriteAbortedError, "Write after ended")
  let writeFuture = writer.conn.write(buf, size) 
  yield writeFuture
  if writeFuture.failed:
    writer.conn.close()
    raise writeFuture.readError()

proc write*(writer: HttpWriter, buf: pointer, size: Natural): Future[void] {.async.} =
  ## Writes ``size`` bytes from ``buf`` to the writer.
  ## 
  ## If a system error occurs during writing, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful writing or the writer has been shut down, a ``WriteAbortedError`` will be raised.
  await writer.lock.acquire()
  try:
    writer.writeByGuard(buf, size)
  finally:
    writer.lock.release()

proc write*(writer: HttpWriter, data: string): Future[void] {.async.} =
  ## Writes a string to the writer.
  ## 
  ## If a system error occurs during writing, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful writing or the writer has been shut down, a ``WriteAbortedError`` will be raised.
  await writer.lock.acquire()
  GC_ref(data)
  try:
    writer.writeByGuard(data.cstring, data.len)
  finally:
    GC_unref(data)
    writer.lock.release()

proc write*(
  writer: HttpWriter, 
  statusCode: HttpCode
): Future[void]  =
  ## Writes a message header to the writer.
  ## 
  ## If a system error occurs during writing, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful writing or the writer has been shut down, a ``WriteAbortedError`` will be raised.
  return writer.write(statusCode.toResponseStr())

proc write*(
  writer: HttpWriter, 
  statusCode: HttpCode,
  fields: openArray[tuple[name: string, value: string]]
): Future[void]  =
  ## Writes a message header to the writer.
  ## 
  ## If a system error occurs during writing, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful writing or the writer has been shut down, a ``WriteAbortedError`` will be raised.
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
  ## Writes a message header to the writer.
  ## 
  ## If a system error occurs during writing, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful writing or the writer has been shut down, a ``WriteAbortedError`` will be raised.
  return writer.write(
    HttpHeader(
      kind: HttpHeaderKind.Response, 
      statusCode: statusCode,
      fields: initHeaderFields(fields)).toResponseStr())

proc writeEnd*(writer: HttpWriter) =
  ## Shuts down writer. Data is no longer allowed to be written, otherwise an ``WriteAbortedError`` will be raised.
  if writer.writable:
    writer.writable = false
    if not writer.conn.closed:
      writer.onEnd()