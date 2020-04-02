#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import unittest, asyncdispatch
import netkit/http/base, netkit/http/session, netkit/http/server

test "todo":
  discard

# var server2 = new(AsyncHttpServer)

# proc handler(req: Request): Future[void] {.async.} =
#   await req.write($initServerResHeader(Http200, {
#     "Content-Length": "11"
#   }))
#   await req.write("Hello World")
#   await req.writeEnd()

# waitFor server2.serve(8001.Port, handler)
