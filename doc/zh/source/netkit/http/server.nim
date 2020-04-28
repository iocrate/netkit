#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import asyncdispatch
import nativesockets
import os
import netkit/http/base
import netkit/http/exception
import netkit/http/connection
import netkit/http/reader
import netkit/http/writer

when defined(posix):
  from posix import EBADF

type
  AsyncHttpServer* = ref object
    socket: AsyncFD
    domain: Domain
    onRequest: RequestHandler
    closed: bool

  RequestHandler* = proc (req: ServerRequest, res: ServerResponse): Future[void] {.closure, gcsafe.}

proc newAsyncHttpServer*(): AsyncHttpServer = discard
  ## 

proc `onRequest=`*(server: AsyncHttpServer, handler: RequestHandler) = discard
  ## 

proc close*(server: AsyncHttpServer) = discard
  ## 

proc serve*(
  server: AsyncHttpServer, 
  port: Port,
  address: string = "",
  domain = AF_INET
) {.async.} = discard
  ## Starts the process of listening for incoming HTTP connections on the
  ## specified ``address`` and ``port``.
  



