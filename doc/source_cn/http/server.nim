#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块实现了一个异步的 HTTP 服务器。 

import asyncdispatch
import nativesockets
import os
import netkit/http/connection

type
  AsyncHttpServer* = ref object ## 一个服务器对象。 
    socket: AsyncFD
 
proc serve*(
  server: AsyncHttpServer, 
  port: Port = 8001.Port,
  address = "127.0.0.1"
): Future[void] {.async.} = discard
  ## 启动 HTTP 服务器， ``port`` 指定端口号， ``address`` 指定主机地址或者主机名。 

proc `onRequest=`*(server: AsyncHttpServer, handler: RequestHandler) = discard
  ## 为 ``server `` 指定一个请求处理器， 当收到一个 HTTP 请求时处理该请求。 