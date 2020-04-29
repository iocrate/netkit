#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块定义 HTTP 相关的读操作的抽象。
## 
## 概述
## ========================
## 
## 服务器从客户端读取传入的请求，而客户端从服务器读取返回的响应。
## 
## ``HttpReader`` 是读操作的基对象， ``ServerRequest`` 和 ``ClientResponse`` 继承自该对象。 ``ServerRequest`` 表示来自客户端的请求，
## ``ClientResponse`` 表示来自服务器的响应。

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
  HttpReader* = ref object of RootObj ## 表示 HTTP 相关的读操作。
    conn: HttpConnection
    lock: AsyncLock
    header*: HttpHeader
    metadata: HttpMetadata
    onEnd: proc () {.gcsafe, closure.}
    contentLen: Natural
    chunked: bool
    readable: bool

  ServerRequest* = ref object of HttpReader ## 表示来自客户端的请求。
  ClientResponse* = ref object of HttpReader ## 表示来自服务器的响应。

proc newServerRequest*(conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}): ServerRequest = discard
  ## 创建一个新的 ``ServerRequest`` 。

proc newClientResponse*(conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}): ClientResponse = discard
  ## 创建一个新的 ``ClientResponse`` 。
  
proc reqMethod*(req: ServerRequest): HttpMethod {.inline.} = discard
  ## 返回请求方法。
  
proc url*(req: ServerRequest): string {.inline.} = discard
  ## 返回 url。
 
proc status*(res: ClientResponse): HttpCode {.inline.} = discard
  ## 返回状态码。
 
proc version*(reader: HttpReader): HttpVersion {.inline.} = discard
  ## 返回 HTTP 版本。
  
proc fields*(reader: HttpReader): HeaderFields {.inline.} = discard
  ## 返回头字段集合。
  
proc metadata*(reader: HttpReader): HttpMetadata {.inline.} = discard
  ## 返回元数据。
  
proc ended*(reader: HttpReader): bool {.inline.} = discard
  ## 如果底部连接已断开或无法读取更多数据，则返回 ``true`` 。

proc normalizeSpecificFields*(reader: HttpReader) = discard
  ## 规范化一些特殊的头字段。

proc read*(reader: HttpReader, buf: pointer, size: range[int(LimitChunkDataLen)..high(int)]): Future[Natural] {.async.} = discard
  ## 读取数据直到 ``size`` 字节，读取的数据填充在 ``buf`` 。
  ## 
  ## 返回值是实际读取的字节数。这个值可能小于 ``size``。 ``0`` 值表示 ``EOF`` ，即无法读取更多数据。
  ## 
  ## 如果读过程中出现系统错误，则会触发 ``OSError`` 异常；如果在成功读取之前连接断开，则会触发 ``ReadAbortedError`` 异常。

proc read*(reader: HttpReader): Future[string] {.async.} = discard
  ## 读取数据直到 ``size`` 字节，读取的数据以字符串返回。
  ## 
  ## 如果返回值是 ``""``， 表示 ``EOF`` ，即无法读取更多数据。
  ## 
  ## 如果读过程中出现系统错误，则会触发 ``OSError`` 异常；如果在成功读取之前连接断开，则会触发 ``ReadAbortedError`` 异常。

proc readAll*(reader: HttpReader): Future[string] {.async.} = discard
  ## 读取所有可读的数据，以字符串返回。
  ## 
  ## 如果读过程中出现系统错误，则会触发 ``OSError`` 异常；如果在成功读取之前连接断开，则会触发 ``ReadAbortedError`` 异常。
  
proc readDiscard*(reader: HttpReader): Future[void] {.async.} = discard
  ## 读取所有可读的数据，并丢掉这些数据。
  ## 
  ## 如果读过程中出现系统错误，则会触发 ``OSError`` 异常；如果在成功读取之前连接断开，则会触发 ``ReadAbortedError`` 异常。