#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块定义 HTTP 相关的写操作的抽象。
## 
## 概述
## ========================
## 
## 服务器将响应发给客户端，客户端将请求发给服务器。
## 
## ``HttpWriter`` 是写操作的基对象， ``ServerResponse`` 和 ``ClientRequest`` 继承自该对象。 
## ``ServerResponse`` 表示服务器发出的响应， ``ClientRequest`` 表示客户端发出的请求。

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
  HttpWriter* = ref object of RootObj ## 表示 HTTP 相关的写操作。
    conn: HttpConnection
    lock: AsyncLock
    onEnd: proc () {.gcsafe, closure.}
    writable: bool

  ServerResponse* = ref object of HttpWriter ## 表示服务器发出的响应。
  ClientRequest* = ref object of HttpWriter ## 表示客户端发出的请求。

proc newServerResponse*(conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}): ServerResponse = discard
  ## 创建一个新的 ``ServerResponse`` 。
  
proc newClientRequest*(conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}): ClientRequest = discard
  ## 创建一个新的 ``ClientRequest`` 。

proc ended*(writer: HttpWriter): bool {.inline.} = discard
  ## 如果底部连接已断开或写端已经关闭，则返回 ``true`` 。

proc write*(writer: HttpWriter, buf: pointer, size: Natural): Future[void] = discard
  ## 从 ``buf`` 写入 ``size`` 字节的数据。
  ## 
  ## 如果写过程中出现系统错误，则会触发 ``OSError`` 异常；如果在成功写之前连接断开或者写端已经关闭，则会触发 ``WriteAbortedError`` 异常。

proc write*(writer: HttpWriter, data: string): Future[void] = discard
  ## 写入一个字符串。
  ## 
  ## 如果写过程中出现系统错误，则会触发 ``OSError`` 异常；如果在成功写之前连接断开或者写端已经关闭，则会触发 ``WriteAbortedError`` 异常。

proc write*(
  writer: HttpWriter, 
  statusCode: HttpCode
): Future[void]  = discard
  ## 写入一个消息头。
  ## 
  ## 如果写过程中出现系统错误，则会触发 ``OSError`` 异常；如果在成功写之前连接断开或者写端已经关闭，则会触发 ``WriteAbortedError`` 异常。

proc write*(
  writer: HttpWriter, 
  statusCode: HttpCode,
  fields: openArray[tuple[name: string, value: string]]
): Future[void]  = discard
  ## 写入一个消息头。
  ## 
  ## 如果写过程中出现系统错误，则会触发 ``OSError`` 异常；如果在成功写之前连接断开或者写端已经关闭，则会触发 ``WriteAbortedError`` 异常。

proc write*(
  writer: HttpWriter, 
  statusCode: HttpCode,
  fields: openArray[tuple[name: string, value: seq[string]]]
): Future[void] = discard
  ## 写入一个消息头。
  ## 
  ## 如果写过程中出现系统错误，则会触发 ``OSError`` 异常；如果在成功写之前连接断开或者写端已经关闭，则会触发 ``WriteAbortedError`` 异常。

proc writeEnd*(writer: HttpWriter) = discard
  ## 关闭写端。之后，不能继续向 ``writer`` 写入数据，否则将引发 ``WriteAbortedError`` 异常。
  