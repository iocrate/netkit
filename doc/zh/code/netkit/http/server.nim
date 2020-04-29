#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块实现了一个 HTTP 服务器。

import asyncdispatch
import nativesockets
import os
import netkit/http/exception
import netkit/http/spec
import netkit/http/status
import netkit/http/connection
import netkit/http/reader
import netkit/http/writer

when defined(posix):
  from posix import EBADF

type
  AsyncHttpServer* = ref object ## 服务器。
    socket: AsyncFD
    domain: Domain
    onRequest: RequestHandler
    closed: bool

  RequestHandler* = proc (req: ServerRequest, res: ServerResponse): Future[void] {.closure, gcsafe.}

proc newAsyncHttpServer*(): AsyncHttpServer = discard
  ## 创建一个新的 ``AsyncHttpServer`` 。

proc `onRequest=`*(server: AsyncHttpServer, handler: RequestHandler) = discard
  ## 为服务器设置 hook 函数。每当有一个新的请求到来时，触发这个 hook 函数。

proc close*(server: AsyncHttpServer) = discard
  ## 关闭服务器以释放底部资源。

proc serve*(
  server: AsyncHttpServer, 
  port: Port,
  address: string = "",
  domain = AF_INET
) {.async.} = discard
  ## 启动服务器，侦听 ``address`` 和 ``port`` 传入的 HTTP 连接。