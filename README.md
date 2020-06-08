Netkit 
==========

[![Build Status](https://travis-ci.org/iocrate/netkit.svg?branch=master)](https://travis-ci.org/iocrate/netkit)
[![Build Status](https://dev.azure.com/iocrate/netkit/_apis/build/status/iocrate.netkit?branchName=master)](https://dev.azure.com/iocrate/netkit/_build/latest?definitionId=1&branchName=master)

Netkit hopes to serve as a versatile network development kit, providing tools commonly used in network programming. Netkit should be out of the box, stable and secure. Netkit contains a number of commonly used network programming tools, such as TCP, UDP, TLS, HTTP, HTTPS, WebSocket and related utilities.

Netkit is not intended to be a high-level productivity development tool, but rather a reliable and efficient network infrastructure. Netkit consists of several submodules, each of which provides some network tools.

**Now, Netkit is under active development.**

- [Documentation - BTW: temporary, requires a more friendly homepage](https://iocrate.github.io/netkit.html)
- [Documentation zh - BTW: temporary, requires a more friendly homepage](https://iocrate.github.io/zh/netkit.html)

A new IO engine, inspired by Netty, which has a (selector) loop pool in multi-thread non-blocking mode, is being developed in **devel** branch. Indeed, we are no longer satisfied with the IO engine in standard library. 

Run Test
---------

There is a script that automatically runs tests. Check config.nims for details. ``$ nim test -d:modules=<file_name>`` tests the specified file, for example, ``$ nim test -d:modules=tbuffer`` tests the file **tests/tbuffer.nim**. ``$ nimble test`` tests all test files in the **tests** directory.

Make Documentation
-------------------

There is a script that automatically generate documentation. Check config.nims for details. ``$ nim docs -d:lang=en`` generates documentation for the source code, an English version. ``$ nimble docs -d:lang=zh`` generates a Chinese version of the documentation. ``$ nim docs`` generates both English version and Chinese version for the documentation.

The code comments are written in English. The Chinese version of these comments is placed in ``${projectDir}/doc/zh/code``.

TODO List
-----------------------

- [ ] IO Engine - Event Loop Pool; Multi-thread mode; Non-blocking socket, pipe; Blocking regular file;
- [x] buffer
    - [x] circular
    - [x] vector
- [ ] tcp
- [ ] udp
- [ ] http
    - [x] limits
    - [x] exception
    - [x] spec
    - [x] httpmethod
    - [x] version
    - [x] status
    - [x] headerfield
    - [x] header
    - [x] chunk
    - [x] metadata
    - [x] cookie
    - [x] parser
    - [x] connection
    - [x] reader
    - [x] writer
    - [x] server
    - [ ] client
    - [ ] clientpool
- [ ] websocket
- [ ] Write document page and provide more friendly document management.
- [ ] Enhance the function of docpolisher, add github link to the document and add return link of the previous page and the home page. 

Contributing to Netkit
-----------------------

- Write and make more Chinese and English documents
- Add more strict unit tests
- Add benchmark or stress test
- Add code to support new features
- Fix bugs
- Fix errors in documentation

A little demonstration
-----------------------

Streaming all your IO!

```nim
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
```
