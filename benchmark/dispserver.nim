import netkit/http/disp, nativesockets

var server = newAsyncHttpServer()

server.serve(Port(8080))
