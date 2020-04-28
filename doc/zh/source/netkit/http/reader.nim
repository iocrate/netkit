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

proc newServerRequest*(conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}): ServerRequest = discard
  ## Creates a new ``ServerRequest``.

proc newClientResponse*(conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}): ClientResponse = discard
  ## Creates a new ``ClientResponse``.
  
proc reqMethod*(req: ServerRequest): HttpMethod {.inline.} = discard
  ## Returns the request method. 
  
proc url*(req: ServerRequest): string {.inline.} = discard
  ## Returns the url. 
 
proc status*(res: ClientResponse): HttpCode {.inline.} = discard
  ## Returns the status code. 
 
proc version*(reader: HttpReader): HttpVersion {.inline.} = discard
  ## Returns the HTTP version. 
  
proc fields*(reader: HttpReader): HeaderFields {.inline.} = discard
  ## Returns the header fields. 
  
proc metadata*(reader: HttpReader): HttpMetadata {.inline.} = discard
  ## Returns the metadata. 
  
proc ended*(reader: HttpReader): bool {.inline.} = discard
  ## Returns ``true`` if the underlying connection has been disconnected or no more data can be read.

proc normalizeSpecificFields*(reader: HttpReader) = discard
  # TODO: more normalized header fields
  ## Normalizes a few special header fields.

proc read*(reader: HttpReader, buf: pointer, size: range[int(LimitChunkDataLen)..high(int)]): Future[Natural] {.async.} = discard
  ## Reads up to ``size`` bytes, storing the results in the ``buf``. 
  ## 
  ## The return value is the number of bytes actually read. This might be less than ``size``.
  ## A value of zero indicates ``EOF``, i.e. no more data can be read.
  ## 
  ## If a system error occurs during reading, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful reading, a ``ReadAbortedError`` will be raised.

proc read*(reader: HttpReader): Future[string] {.async.} = discard
  ## Reads up to ``size`` bytes, storing the results as a string. 
  ## 
  ## If the return value is ``""``, that indicates ``eof``, i.e. at the end of the request.
  ## 
  ## If a system error occurs during reading, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful reading, a ``ReadAbortedError`` will be raised.

proc readAll*(reader: HttpReader): Future[string] {.async.} = discard
  ## Reads all bytes, storing the results as a string. 
  ## 
  ## If a system error occurs during reading, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful reading, a ``ReadAbortedError`` will be raised.
  
proc readDiscard*(reader: HttpReader): Future[void] {.async.} = discard
  ## Reads all bytes, discarding the results. 
  ## 
  ## If the return future is failed, ``OsError`` or ``ReadAbortedError`` may be raised.