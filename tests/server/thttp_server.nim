discard """
  cmd:      "nim c -r --styleCheck:hint --panics:on $options $file"
  matrix:   "--gc:refc"
  targets:  "c"
  nimout:   ""
  action:   "run"
  exitcode: 0
  timeout:  60.0
"""

#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import unittest
import asyncnet
import asyncdispatch
import netkit/http

suite "In-order IO":
  var server: AsyncHttpServer
  
  setup:
    proc serve() {.async.} = 
      server = newAsyncHttpServer()

      server.onRequest = proc (req: ServerRequest, res: ServerResponse) {.async.} =
        try:
          var buf = newString(16)
          var data = ""
          while not req.ended:
            let readLen = await req.read(buf.cstring, 16)
            buf.setLen(readLen)
            data.add(buf)
          await res.write(Http200, {
            "Content-Length": $data.len
          })
          var i = 0
          while i < data.len:
            await res.write(data[i..min(i+7, data.len-1)])
            i.inc(8)
          res.writeEnd()
        except ReadAbortedError:
          echo "Got ReadAbortedError: ", getCurrentExceptionMsg()
        except WriteAbortedError:
          echo "Got WriteAbortedError: ", getCurrentExceptionMsg()
        except Exception:
          echo "Got Exception: ", getCurrentExceptionMsg()

      await server.serve(Port(8001), "127.0.0.1")

    asyncCheck serve()
    waitFor sleepAsync(10)

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
      client.close()

    waitFor request()

  test "With messege body":
    proc request() {.async.} = 
      let client = await asyncnet.dial("127.0.0.1", Port(8001))
      await client.send("""
GET /iocrate/netkit HTTP/1.1
Host: iocrate.com
Content-Length: 12

foobarfoobar""")
      let statusLine = await client.recvLine()
      let contentLenLine = await client.recvLine()
      let crlfLine = await client.recvLine()
      let body = await client.recv(12)
      check:
        statusLine == "HTTP/1.1 200 OK"
        contentLenLine == "content-length: 12"
        crlfLine == "\r\L"
        body == "foobarfoobar"
      client.close()

    waitFor request()
  
  test "Multiple messeges":
    proc request() {.async.} = 
      let client = await asyncnet.dial("127.0.0.1", Port(8001))
      await client.send("""
GET /iocrate/netkit HTTP/1.1
Host: iocrate.com
Content-Length: 36

foobarfoobarfoobarfoobarfoobarfoobar""")
      await sleepAsync(100)
      await client.send("""
GET /iocrate/netkit HTTP/1.1
Host: iocrate.com
Content-Length: 6

foobar

GET /iocrate/netkit HTTP/1.1
Host: iocrate.com
Content-Length: 12

foobarfoobar""")
      block response1:
        let statusLine = await client.recvLine()
        let contentLenLine = await client.recvLine()
        let crlfLine = await client.recvLine()
        let body = await client.recv(36)
        check:
          statusLine == "HTTP/1.1 200 OK"
          contentLenLine == "content-length: 36"
          crlfLine == "\r\L"
          body == "foobarfoobarfoobarfoobarfoobarfoobar"
      block response2:
        let statusLine = await client.recvLine()
        let contentLenLine = await client.recvLine()
        let crlfLine = await client.recvLine()
        let body = await client.recv(6)
        check:
          statusLine == "HTTP/1.1 200 OK"
          contentLenLine == "content-length: 6"
          crlfLine == "\r\L"
          body == "foobar"
      block response3:
        let statusLine = await client.recvLine()
        let contentLenLine = await client.recvLine()
        let crlfLine = await client.recvLine()
        let body = await client.recv(12)
        check:
          statusLine == "HTTP/1.1 200 OK"
          contentLenLine == "content-length: 12"
          crlfLine == "\r\L"
          body == "foobarfoobar"
      client.close()

    waitFor request()
    
suite "Out-of-order IO":
  test "read":
    var server: AsyncHttpServer

    proc serve() {.async.} = 
      server = newAsyncHttpServer()

      server.onRequest = proc (req: ServerRequest, res: ServerResponse) {.async.} =
        try:
          var data = ""

          let r1 = req.read()
          let r2 = req.read()
          let r3 = req.read()
          let r4 = req.read()

          let s4 = await r4
          let s3 = await r3
          let s1 = await r1
          let s2 = await r2

          check:
            # thttp_server.nim.cfg should include:
            #
            #   --define:BufferSize=16
            s1.len == 16
            s2.len == 16
            s3.len == 16
            s4.len == 16

            s1 == "foobar01foobar02"
            s2 == "foobar03foobar04"
            s3 == "foobar05foobar06"
            s4 == "foobar07foobar08"

          data.add(s1)
          data.add(s2)
          data.add(s3)
          data.add(s4)
          
          await res.write(Http200, {
            "Content-Length": $data.len
          })
          var i = 0
          while i < data.len:
            await res.write(data[i..min(i+7, data.len-1)])
            i.inc(8)
          res.writeEnd()
        except ReadAbortedError:
          echo "Got ReadAbortedError: ", getCurrentExceptionMsg()
        except WriteAbortedError:
          echo "Got WriteAbortedError: ", getCurrentExceptionMsg()
        except Exception:
          echo "Got Exception: ", getCurrentExceptionMsg()

      await server.serve(Port(8001), "127.0.0.1")
    
    proc request() {.async.} = 
      let client = await asyncnet.dial("127.0.0.1", Port(8001))
      await client.send("""
GET /iocrate/netkit HTTP/1.1
Host: iocrate.com
Content-Length: 64

foobar01foobar02foobar03foobar04foobar05foobar06foobar07foobar08""")
      let statusLine = await client.recvLine()
      let contentLenLine = await client.recvLine()
      let crlfLine = await client.recvLine()
      let body = await client.recv(64)
      check:
        statusLine == "HTTP/1.1 200 OK"
        contentLenLine == "content-length: 64"
        crlfLine == "\r\L"
        body == "foobar01foobar02foobar03foobar04foobar05foobar06foobar07foobar08"
      client.close()

    asyncCheck serve()
    waitFor sleepAsync(10)
    waitFor request()
    server.close()

  test "write":
    var server: AsyncHttpServer

    proc serve() {.async.} = 
      server = newAsyncHttpServer()

      server.onRequest = proc (req: ServerRequest, res: ServerResponse) {.async.} =
        try:
          var buf = newString(16)
          var data = ""
          while not req.ended:
            let readLen = await req.read(buf.cstring, 16)
            buf.setLen(readLen)
            data.add(buf)
          
          await res.write(Http200, {
            "Content-Length": $data.len
          })

          var w1 = res.write(data[0..15])
          var w2 = res.write(data[16..31])
          var w3 = res.write(data[32..47])
          var w4 = res.write(data[48..63])

          await w4
          await w3
          await w1
          await w2

          res.writeEnd()
        except ReadAbortedError:
          echo "Got ReadAbortedError: ", getCurrentExceptionMsg()
        except WriteAbortedError:
          echo "Got WriteAbortedError: ", getCurrentExceptionMsg()
        except Exception:
          echo "Got Exception: ", getCurrentExceptionMsg()

      await server.serve(Port(8001), "127.0.0.1")
    
    proc request() {.async.} = 
      let client = await asyncnet.dial("127.0.0.1", Port(8001))
      await client.send("""
GET /iocrate/netkit HTTP/1.1
Host: iocrate.com
Content-Length: 64

foobar01foobar02foobar03foobar04foobar05foobar06foobar07foobar08""")
      let statusLine = await client.recvLine()
      let contentLenLine = await client.recvLine()
      let crlfLine = await client.recvLine()
      let body = await client.recv(64)
      check:
        statusLine == "HTTP/1.1 200 OK"
        contentLenLine == "content-length: 64"
        crlfLine == "\r\L"
        body == "foobar01foobar02foobar03foobar04foobar05foobar06foobar07foobar08"
      client.close()

    asyncCheck serve()
    waitFor sleepAsync(10)
    waitFor request()
    server.close()

suite "Read Timeout":
  test "Wait for header":
    var server: AsyncHttpServer
    
    proc serve() {.async.} = 
      server = newAsyncHttpServer()

      server.onRequest = proc (req: ServerRequest, res: ServerResponse) {.async.} =
        try:
          let data = await req.readAll()
          check data.len == 0
          await res.write(Http200, {
            "Content-Length": "0"
          })
          res.writeEnd()
        except ReadAbortedError:
          echo "Got ReadAbortedError: ", getCurrentExceptionMsg()
        except WriteAbortedError:
          echo "Got WriteAbortedError: ", getCurrentExceptionMsg()
        except Exception:
          echo "Got Exception: ", getCurrentExceptionMsg()

      await server.serve(Port(8001), "127.0.0.1", readTimeout=100)
      
    proc request() {.async.} = 
      let client = await asyncnet.dial("127.0.0.1", Port(8001))
      await client.send("GET /iocrate/netkit HTTP/1.1\r\L")
      await sleepAsync(1000)
      await client.send("Host: iocrate.com\r\L\r\L")
      let statusLine = await client.recvLine()
      let connectionLine = await client.recvLine()
      when defined(windows):
        discard # asyncdispatch.close in windows, which is not a good solution
      else:
        check:
          statusLine == "HTTP/1.1 408 Request Timeout"
          connectionLine == "Connection: close"
      client.close()

    asyncCheck serve()
    waitFor sleepAsync(10)
    waitFor request()
    server.close()

  test "Wait for request":
    var server: AsyncHttpServer
    
    proc serve() {.async.} = 
      server = newAsyncHttpServer()

      server.onRequest = proc (req: ServerRequest, res: ServerResponse) {.async.} =
        try:
          let data = await req.readAll()
          await res.write(Http200, {
            "Content-Length": $data.len
          })
          await res.write(data)
          res.writeEnd()
        except ReadAbortedError as e:
          check e.timeout
        except WriteAbortedError:
          echo "Got WriteAbortedError: ", getCurrentExceptionMsg()
        except Exception:
          echo "Got Exception: ", getCurrentExceptionMsg()

      await server.serve(Port(8001), "127.0.0.1", readTimeout=100)
      
    proc request() {.async.} = 
      let client = await asyncnet.dial("127.0.0.1", Port(8001))
      await client.send("""
GET /iocrate/netkit HTTP/1.1
Host: iocrate.com
Content-Length: 12

foobar""")
      await sleepAsync(1000)
      await client.send("foobar")
      let statusLine = await client.recvLine()
      check:
        statusLine == ""
      client.close()

    asyncCheck serve()
    waitFor sleepAsync(10)
    waitFor request()
    server.close()