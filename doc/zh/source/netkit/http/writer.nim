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
import netkit/http/httpmethod 
import netkit/http/version 
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

proc newServerResponse*(conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}): ServerResponse = discard
  ## Creates a new ``ServerResponse``.
  
proc newClientRequest*(conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}): ClientRequest = discard
  ## Creates a new ``ClientRequest``.

proc ended*(writer: HttpWriter): bool {.inline.} = discard
  ## Returns ``true`` if the underlying connection has been closed or writer has been shut down.

proc write*(writer: HttpWriter, buf: pointer, size: Natural): Future[void] {.async.} = discard
  ## Writes ``size`` bytes from ``buf`` to the writer.
  ## 
  ## If a system error occurs during writing, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful writing or the writer has been shut down, a ``ReadAbortedError`` will be raised.

proc write*(writer: HttpWriter, data: string): Future[void] {.async.} = discard
  ## Writes a string to the writer.
  ## 
  ## If a system error occurs during writing, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful writing or the writer has been shut down, a ``ReadAbortedError`` will be raised.

proc write*(
  writer: HttpWriter, 
  statusCode: HttpCode,
  fields: openArray[tuple[name: string, value: string]]
): Future[void]  = discard
  ## Writes a message header to the writer.
  ## 
  ## If a system error occurs during writing, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful writing or the writer has been shut down, a ``ReadAbortedError`` will be raised.

proc write*(
  writer: HttpWriter, 
  statusCode: HttpCode,
  fields: openArray[tuple[name: string, value: seq[string]]]
): Future[void] = discard
  ## Writes a message header to the writer.
  ## 
  ## If a system error occurs during writing, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful writing or the writer has been shut down, a ``ReadAbortedError`` will be raised.

proc writeEnd*(writer: HttpWriter) = discard
  ## Shuts down writer. Data is no longer allowed to be written, otherwise an ``WriteAbortedError`` will be raised.