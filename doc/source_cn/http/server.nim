#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import asyncdispatch, nativesockets, os
import netkit/http/connection

type
  AsyncHttpServer* = ref object ## 服务器对象。 
    socket: AsyncFD
 
proc serve*(
  server: AsyncHttpServer, 
  port: Port = 8001.Port,
  handler: RequestHandler,
  address = "127.0.0.1"
): Future[void] {.async.} = discard
  ## 