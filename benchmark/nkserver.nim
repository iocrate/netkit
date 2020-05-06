import netkit/http, asyncdispatch

var server = newAsyncHttpServer()

server.onRequest = proc (req: ServerRequest, res: ServerResponse) {.async.} =
  discard await req.readAll()
  # await res.write(Http200, {
  #   "Content-Length": "11"
  # })
  # await res.write("Hello World")
  await res.write("HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nHello World")
  res.writeEnd()

waitFor server.serve(Port(8080), "127.0.0.1")

