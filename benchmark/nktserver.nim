import netkit/http, asyncdispatch

var server = newAsyncHttpServer()

server.onRequest = proc (req: ServerRequest, res: ServerResponse) {.async.} =
  try:
    discard await req.readAll()
    # await res.write(Http200, {
    #   "Content-Length": "11"
    # })
    # await res.write("Hello World")
    await res.write("HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nHello World")
    res.writeEnd()
  except ReadAbortedError:
    echo "Got ReadAbortedError: ", getCurrentExceptionMsg()
  except WriteAbortedError:
    echo "Got WriteAbortedError: ", getCurrentExceptionMsg()
  except Exception:
    echo "Got Exception: ", getCurrentExceptionMsg()

waitFor server.serve(Port(8080), "127.0.0.1")

