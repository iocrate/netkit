#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import unittest, asyncdispatch
import netkit/http/base, netkit/http/connection, netkit/http/server as httpserver

test "todo":
  discard

let server = new(AsyncHttpServer)

proc handler(req: Request) {.async.} =
  await req.write(Http200, {
    "Content-Length": "11"
  })
  await req.write("Hello")
  await req.write(" ")
  await req.write("World")
  await req.writeEnd()

waitFor server.serve(8001.Port, handler)

