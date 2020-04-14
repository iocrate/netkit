#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import asyncdispatch
import netkit/http/base
import netkit/http/connection
import netkit/http/server as httpserver
import netkit/http/exception

# let server = newAsyncHttpServer()

# server.onRequest = proc (req: Request) {.async.} =
#   try:
#     var buf = newString(1024)
#     while not req.isReadEnded:
#       let n = await req.read(buf.cstring, 1024)

#     await req.write(Http200, {
#       "Content-Length": "300"
#     })
#     var i = 0
#     while i < 100:
#       await req.write("FOO")
#       i.inc()
#     req.writeEnd()
#   except ReadAbortedError:
#     echo "Got Error: ", getCurrentExceptionMsg()
#   except WriteAbortedError:
#     echo "Got Error: ", getCurrentExceptionMsg()
#   except Exception:
#     echo "Got Error: ", getCurrentExceptionMsg()

# waitFor server.serve(Port(8000), "127.0.0.1")


