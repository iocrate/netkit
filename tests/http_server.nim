#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import unittest 
import asyncdispatch
import netkit/http/base
import netkit/http/connection
import netkit/http/server as httpserver
import netkit/http/exception

test "todo":
  discard

# let server = newAsyncHttpServer()

# server.onRequest = proc (req: Request) {.async.} =
#   try:
#     var buf = newString(1024)
#     while not req.eof:
#       let n = await req.read(buf.cstring, 1024)

#     await req.write(Http200, {
#       "Content-Length": "11"
#     })
#     await req.write("Hello")
#     await req.write(" ")
#     await req.write("World")
#     req.writeEnd()
#   except ReadIncompleteError:
#     discard
#   except WriteAbortedError:
#     discard

# waitFor server.serve(8001.Port, "127.0.0.1")

