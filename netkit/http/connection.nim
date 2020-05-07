#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module implements an HTTP connection between a client and a server. ``HttpConnection`` provides  
## several routines that can recognize the structure of HTTP messages transmitted over the network.
## 
## Usage
## ========================
## 
## .. container:: r-fragment
## 
##   Reads a message header
##   ----------------------
## 
##   .. code-block::nim
## 
##     import netkit/http/connection
##     import netkit/http/header
## 
##     type
##       Packet = ref object
##         header: HttpHeader
## 
##     var packet = new(Packet)
##     packet.header = HttpHeader(kind: HttpHeaderKind.Request)
##     
##     var conn = newHttpConnection(socket, address)
##     
##     try:
##       GC_ref(packet)
##       await conn.readHttpHeader(packet.header.addr)
##     finally:
##       GC_unref(packet)
## 
## .. container:: r-fragment
## 
##   Reads a message body
##   ------------------------ 
## 
##   .. code-block::nim
## 
##     let readLen = await conn.readData(buf, 1024)
## 
## .. container:: r-fragment
## 
##   Reads a message body that chunked
##   ------------------------------------------
## 
##   .. code-block::nim
## 
##     type
##       Packet = ref object
##         header: ChunkHeader
##     
##     try:
##       GC_ref(packet)
##       await conn.readChunkHeader(packet.header.addr)
##     finally:
##       GC_unref(packet)
##   
##     if header.size == 0: # read tail
##       var trailers: seq[string]
##       await conn.readEnd(trailers)
##     else:                
##       var chunkLen = header.size 
##       var buf = newString(header.size)
##       let readLen = await conn.readData(buf, header.size)
##       if readLen != header.size:
##         echo "Connection closed prematurely"
## 
## .. container:: r-fragment
## 
##   Sends a message
##   ---------------
## 
##   .. code-block::nim
## 
##     await conn.write("""
##     GET /iocrate/netkit HTTP/1.1
##     Host: iocrate.com
##     Content-Length: 12
##  
##     foobarfoobar
##     """)

import strutils
import asyncdispatch
import nativesockets
import netkit/misc
import netkit/buffer/circular
import netkit/http/header
import netkit/http/exception 
import netkit/http/parser
import netkit/http/chunk 

type
  HttpConnection* = ref object ## HTTP connection object.
    buffer: MarkableCircularBuffer
    parser: HttpParser
    socket: AsyncFD
    address: string
    closed: bool
    readTimeout: Natural

proc newHttpConnection*(socket: AsyncFD, address: string, readTimeout: Natural): HttpConnection = 
  ## Creates a new ``HttpConnection``. ``socket`` specifies the peer's socket descriptor, ``address`` specifies 
  ## the peer's network address, ``readTimeout`` specifies the timeout period of the read operation. 
  ## 
  ## Note that ``readTimeout`` also affects the keepalive timeout. When the last response is sent and there 
  ## is no further request for more than ``readTimeout`` milliseconds, a ``ReadAbortedError`` will be raised.
  new(result)
  result.buffer = initMarkableCircularBuffer()
  result.parser = initHttpParser()
  result.socket = socket
  result.address = address
  result.closed = false
  result.readTimeout = readTimeout

proc close*(conn: HttpConnection) {.inline.} = 
  ## Closes this connection to release the resources.
  conn.socket.closeSocket()
  conn.closed = true

proc closed*(conn: HttpConnection): bool {.inline.} = 
  ## Returns ``true`` if this connection is closed.
  conn.closed

proc read(conn: HttpConnection): Future[Natural] = 
  ## If a system error occurs during reading, an ``OsError`` will be raised.
  let retFuture = newFuture[Natural]("read")
  result = retFuture

  let region = conn.buffer.next()
  let recvFuture = conn.socket.recvInto(region[0], region[1])
  
  proc updateDate(fd: AsyncFD): bool =
    echo "Timeout ..."
    result = true
    if not recvFuture.finished:
      echo "retFuture.fail(newReadAbortedError, timeout)"
      recvFuture.clearCallbacks()
      retFuture.fail(newReadAbortedError("Read timeout", true))

  if conn.readTimeout > 0:
    addTimer(conn.readTimeout, false, updateDate) 

  recvFuture.callback = proc (fut: Future[int]) = 
    echo "recvFuture.callback"
    if fut.failed:
      retFuture.fail(fut.readError())
    else:
      let readLen = fut.read()
      if readLen == 0:
        retFuture.fail(newReadAbortedError("Connection closed prematurely"))
      else:
        discard conn.buffer.pack(readLen)
        retFuture.complete(readLen)

proc read(conn: HttpConnection, buf: pointer, size: Natural): Future[Natural] = 
  ## If a system error occurs during reading, an ``OsError`` will be raised.
  let retFuture = newFuture[Natural]("read")
  result = retFuture
  
  let recvFuture = conn.socket.recvInto(buf, size)
  
  proc updateDate(fd: AsyncFD): bool =
    result = true
    if not recvFuture.finished:
      recvFuture.clearCallbacks()
      retFuture.fail(newReadAbortedError("Read timeout", true))
      
  if conn.readTimeout > 0:
    addTimer(conn.readTimeout, false, updateDate) 

  recvFuture.callback = proc (fut: Future[int]) = 
    if fut.failed:
      retFuture.fail(fut.readError())
    else:
      let readLen = recvFuture.read()
      if readLen == 0:
        retFuture.fail(newReadAbortedError("Connection closed prematurely"))
      else:
        retFuture.complete(readLen)

proc readHttpHeader*(conn: HttpConnection, header: ptr HttpHeader): Future[void] {.async.} = 
  ## Reads the header of a HTTP message.
  ## 
  ## If a system error occurs during reading, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful reading, a ``ReadAbortedError`` will be raised.
  var succ = false
  conn.parser.clear()
  if conn.buffer.len > 0:
    succ = conn.parser.parseHttpHeader(conn.buffer, header[])
  while not succ:
    discard await conn.read()
    succ = conn.parser.parseHttpHeader(conn.buffer, header[])

proc readChunkHeader*(conn: HttpConnection, header: ptr ChunkHeader): Future[void] {.async.} = 
  ## Reads the size and the extensions parts of a chunked data.
  ## 
  ## If a system error occurs during reading, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful reading, a ``ReadAbortedError`` will be raised.
  var succ = false
  if conn.buffer.len > 0:
    succ = conn.parser.parseChunkHeader(conn.buffer, header[])
  while not succ:
    discard await conn.read()
    succ = conn.parser.parseChunkHeader(conn.buffer, header[])

proc readChunkEnd*(conn: HttpConnection, trailer: ptr seq[string]): Future[void] {.async.} =
  ## Reads the terminating chunk, trailer, and the final CRLF sequence of a chunked message. 
  ## 
  ## If a system error occurs during reading, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful reading, a ``ReadAbortedError`` will be raised.
  var succ = false
  if conn.buffer.len > 0:
    succ = conn.parser.parseChunkEnd(conn.buffer, trailer[])
  while not succ:
    discard await conn.read()
    succ = conn.parser.parseChunkEnd(conn.buffer, trailer[])

proc readData*(conn: HttpConnection, buf: pointer, size: Natural): Future[Natural] {.async.} =  
  ## Reads up to ``size`` bytes from this connection, storing the results in the ``buf``. 
  ## 
  ## The return value is the number of bytes actually read. This might be less than ``size`` 
  ## that indicates the connection is at EOF. 
  ## 
  ## This proc should only be used to read the message body.
  ## 
  ## If a system error occurs during reading, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful reading, a ``ReadAbortedError`` will be raised.
  result = conn.buffer.len
  if result >= size:
    discard conn.buffer.get(buf, size)
    discard conn.buffer.del(size)
    result = size
  else:
    if result > 0:
      discard conn.buffer.get(buf, result)
      discard conn.buffer.del(result)
    var remainingLen = size - result
    while remainingLen > 0:
      let n = await conn.read(buf.offset(result), remainingLen)
      discard conn.buffer.get(buf.offset(result), n)
      discard conn.buffer.del(n)
      result.inc(n)
      remainingLen.dec(n)  

proc write*(conn: HttpConnection, buf: pointer, size: Natural): Future[void] {.inline.} =
  ## Writes ``size`` bytes from ``buf`` to the connection. 
  ## 
  ## If a system error occurs during writing, an ``OsError``  will be raised. 
  result = conn.socket.send(buf, size)

proc write*(conn: HttpConnection, data: string): Future[void] {.inline.} =
  ## Writes a string to the connection.
  ## 
  ## If a system error occurs during writing, an ``OsError``  will be raised. 
  result = conn.socket.send(data)