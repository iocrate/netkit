#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import unittest
import asyncnet
import asyncdispatch
import netkit/http/base
import netkit/http/reader
import netkit/http/writer
import netkit/http/server as httpserver
import netkit/http/exception

suite "Echo":
  var server: AsyncHttpServer
  
  setup:
    proc serve() {.async.} = 
      server = newAsyncHttpServer()

      server.onRequest = proc (req: ServerRequest, res: ServerResponse) {.async.} =
        echo "request ..."
        try:
          var buf = newString(16)
          var data = ""
          while not req.ended:
            let readLen = await req.read(buf.cstring, 16)
            buf.setLen(readLen)
            data.add(buf)

          echo "res.write before ..."
          await res.write(Http200, {
            "Content-Length": $data.len
          })
          echo "res.write ..."
          var i = 0
          while i < data.len:
            await res.write(data[i..min(i+7, data.len-1)])
            i.inc(8)
          res.writeEnd()
          echo "res.writeEnd() ..."
        except ReadAbortedError:
          echo "Got ReadAbortedError: ", getCurrentExceptionMsg()
        except WriteAbortedError:
          echo "Got WriteAbortedError: ", getCurrentExceptionMsg()
        except Exception:
          echo "Got Exception: ", getCurrentExceptionMsg()

      await server.serve(Port(8001), "127.0.0.1")

    asyncCheck serve()
    waitFor sleepAsync(1)

  teardown:
    server.close()

  test "No messege body":
    proc request() {.async.} = 
      let client = await asyncnet.dial("127.0.0.1", Port(8001))
      await client.send("GET /iocrate/netkit HTTP/1.1\r\LHost: iocrate.com\r\L\r\L")
      let statusLine = await client.recvLine()
      let contentLenLine = await client.recvLine()
      let crlfLine = await client.recvLine()
      check:
        statusLine == "HTTP/1.1 200 OK"
        contentLenLine == "content-length: 0"
        crlfLine == "\r\L"
      echo "client 1 close()"
      client.close()

    waitFor request()

  test "With messege body":
    proc request() {.async.} = 
      let client = await asyncnet.dial("127.0.0.1", Port(8001))
      await client.send("""GET /iocrate/netkit HTTP/1.1
Host: iocrate.com
Content-Length: 12

foobarfoobar""")
      let statusLine = await client.recvLine()
      echo "req:", repr statusLine
      # 有时候返回空行
      let contentLenLine = await client.recvLine()
      let crlfLine = await client.recvLine()
      let body = await client.recv(12)
      check:
        statusLine == "HTTP/1.1 200 OK"
        contentLenLine == "content-length: 12"
        crlfLine == "\r\L"
        body == "foobarfoobar"
      echo "client 2 close()"
      client.close()

    waitFor request()
  
