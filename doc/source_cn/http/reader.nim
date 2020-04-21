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
import netkit/http/connection
import netkit/http/constants as http_constants
import netkit/http/exception
import netkit/http/codecs/chunk 
import netkit/http/codecs/metadata 

type
  HttpReader* = ref object of RootObj ##
    conn: HttpConnection
    lock: AsyncLock
    header*: HttpHeader
    metadata: HttpMetadata
    onEnd: proc () {.gcsafe, closure.}
    contentLen: Natural
    chunked: bool
    readable: bool

  ServerRequest* = ref object of HttpReader ## 
  ClientResponse* = ref object of HttpReader ## 

proc newServerRequest*(conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}): ServerRequest = discard
  ##

proc newClientResponse*(conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}): ClientResponse = discard
  ##

proc reqMethod*(req: ServerRequest): HttpMethod {.inline.} = discard
  ## 获取请求方法。 

proc url*(req: ServerRequest): string {.inline.} = discard
  ## 获取请求的 URL 字符串。 

proc version*(req: HttpReader): HttpVersion {.inline.} = discard
  ## 获取请求的 HTTP 版本号码。 

proc fields*(req: HttpReader): HeaderFields {.inline.} = discard
  ## 获取请求头对象。 每个头字段值是一个字符串序列。 

proc metadata*(reader: HttpReader): HttpMetadata {.inline.} = discard
  ## 

proc ended*(reader: HttpReader): bool {.inline.} = discard
  ## 

proc normalizeSpecificFields*(reader: HttpReader) = discard
  ## 

proc read*(reader: HttpReader, buf: pointer, size: range[int(LimitChunkDataLen)..high(int)]): Future[Natural] = discard
  ## Reads up to ``size`` bytes from the request, storing the results in the ``buf``. 
  ## 
  ## The return value is the number of bytes actually read. This might be less than ``size``.
  ## A value of zero indicates ``eof``, i.e. at the end of the request.
  ## 
  ## If the return future is failed, ``OsError`` or ``ReadAbortedError`` may be raised.

proc read*(reader: HttpReader): Future[string] = discard
  ## Reads up to ``size`` bytes from the request, storing the results as a string. 
  ## 
  ## If the return value is ``""``, that indicates ``eof``, i.e. at the end of the request.
  ## 
  ## If the return future is failed, ``OsError`` or ``ReadAbortedError`` may be raised.

proc readAll*(reader: HttpReader): Future[string] = discard
  ## Reads all bytes from the request, storing the results as a string. 
  ## 
  ## If the return future is failed, ``OsError`` or ``ReadAbortedError`` may be raised.
  ## 
proc readDiscard*(reader: HttpReader): Future[void] = discard
  ## Reads all bytes from the request, discarding the results. 
  ## 
  ## If the return future is failed, ``OsError`` or ``ReadAbortedError`` may be raised.