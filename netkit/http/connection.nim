#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module implements an HTTP connection. `` HttpConnection`` provides several 
## routines that can recognize the structure of HTTP messages transmitted over the network.
## 
## Usage
## -----
## 
## Creates a connection: 
## 
## ..code-block::nim
## 
##   var conn = newHttpConnection(socket, address)
## 
## Reads the header of a HTTP message:  
## 
## ..code-block::nim
## 
##   await conn.readHttpHeader(header)
## 
## Reads the body of a HTTP message:  
## 
## ..code-block::nim
## 
##   var readLen = 1024 
##   var size = 1024
##   while readLen == size:
##     readLen = await conn.readData(buf, size)
## 
## When the body of a message uses chunked encoding, reads it chunk by chunk:
## 
## ..code-block::nim
## 
##   await conn.readChunkHeader(header)
##   
##   if header.size == 0: # read tail
##     await conn.readEnd(trailers)
##   else:                
##     var exceptLen = header.size 
##     while exceptLen != 0:
##       let readLen = await conn.readData(buf, header.size)
##       exceptLen.inc(readLen)
## 
## Sends to peer:
## 
## ..code-block::nim
## 
##   await conn.readChunkHeader("""
##   GET /iocrate/netkit HTTP/1.1
##   Host: iocrate.com
##   Content-Length: 12
##
##   foobarfoobar
##   """)
## 
## Close a connection:
## 
## ..code-block::nim
## 
##   conn.close()

import strutils
import asyncdispatch
import nativesockets
import netkit/misc
import netkit/buffer/circular
import netkit/http/base
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

proc newHttpConnection*(socket: AsyncFD, address: string): HttpConnection = 
  ## Creates a new ``HttpConnection``.
  new(result)
  result.buffer = initMarkableCircularBuffer()
  result.parser = initHttpParser()
  result.socket = socket
  result.address = address
  result.closed = false

proc close*(conn: HttpConnection) {.inline.} = 
  ## Closes this connection to release the resources.
  conn.socket.closeSocket()
  conn.closed = true

proc closed*(conn: HttpConnection): bool {.inline.} = 
  ## Returns true if this connection is closed.
  conn.closed

proc read(conn: HttpConnection): Future[Natural] {.async.} = 
  ## If a system error occurs during reading, a ``OsError`` exception will be raised.
  let region = conn.buffer.next()
  result = await conn.socket.recvInto(region[0], region[1])
  if result > 0:
    discard conn.buffer.pack(result)

proc readHttpHeader*(conn: HttpConnection, header: ptr HttpHeader): Future[void] {.async.} = 
  ## Reads the header of a HTTP message.
  ## 
  ## If a system error occurs during reading, a ``OsError`` exception will be raised. If the connection is  
  ## disconnected before successful reading, a ``ReadAbortedError`` exception will be raised.
  var succ = false
  conn.parser.clear()
  if conn.buffer.len > 0:
    succ = conn.parser.parseHttpHeader(conn.buffer, header[])
  while not succ:
    let n = await conn.read()
    if n == 0:
      raise newException(ReadAbortedError, "Connection closed prematurely")
    succ = conn.parser.parseHttpHeader(conn.buffer, header[])

proc readChunkHeader*(conn: HttpConnection, header: ptr ChunkHeader): Future[void] {.async.} = 
  ## Reads the header of a data chunk of a message that encoded by ``Transfer-Encoding: chunked``.
  ## 
  ## If a system error occurs during reading, a ``OsError`` exception will be raised. If the connection is 
  ## disconnected before  successful reading, a ``ReadAbortedError`` exception will be raised.
  var succ = false
  if conn.buffer.len > 0:
    succ = conn.parser.parseChunkHeader(conn.buffer, header[])
  while not succ:
    let n = await conn.read()
    if n == 0:
      raise newException(ReadAbortedError, "Connection closed prematurely")
    succ = conn.parser.parseChunkHeader(conn.buffer, header[])

proc readChunkEnd*(conn: HttpConnection, trailer: ptr seq[string]): Future[void] {.async.} =
  ## Reads the tail of a message that encoded by ``Transfer-Encoding: chunked``. 
  ## 
  ## If a system error occurs during reading, a ``OsError`` exception will be raised. If the connection is 
  ## disconnected before  successful reading, a ``ReadAbortedError`` exception will be raised.
  var succ = false
  if conn.buffer.len > 0:
    succ = conn.parser.parseChunkEnd(conn.buffer, trailer[])
  while not succ:
    let n = await conn.read()
    if n == 0:
      raise newException(ReadAbortedError, "Connection closed prematurely")
    succ = conn.parser.parseChunkEnd(conn.buffer, trailer[])

proc readData*(conn: HttpConnection, buf: pointer, size: Natural): Future[Natural] {.async.} =  
  ## Reads up to ``size`` bytes from the connection, storing the results in the ``buf``. 
  ## 
  ## The return value is the number of bytes actually read. This might be less than ``size`` 
  ## that indicates the connection is EOF. 
  ## 
  ## This proc should be used to read the message body.
  ## 
  ## If a system error occurs during reading, a ``OsError`` exception will be raised. If the connection is  
  ## disconnected before successful reading, a ``ReadAbortedError`` exception will be raised.
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
      let n = await conn.socket.recvInto(buf.offset(result), remainingLen)
      if n == 0:
        raise newException(ReadAbortedError, "Connection closed prematurely")
      discard conn.buffer.get(buf.offset(result), n)
      discard conn.buffer.del(n)
      result.inc(n)
      remainingLen.dec(n)  

proc write*(conn: HttpConnection, buf: pointer, size: Natural): Future[void] {.inline.} =
  ## Writes ``size`` bytes from ``buf`` to the connection. 
  ## 
  ## If a system error occurs during writing, ``OsError`` will be raised. If the connection is closed or other 
  ## errors occurs before the write operation is successfully completed, a ``WriteAbortedError`` exception will be 
  ## raised.
  result = conn.socket.send(buf, size)

proc write*(conn: HttpConnection, data: string): Future[void] {.inline.} =
  ## 
  ## If a system error occurs during writing, ``OsError`` will be raised. If the connection is closed or other 
  ## errors occurs before the write operation is successfully completed, a ``WriteAbortedError`` exception will be 
  ## raised.
  result = conn.socket.send(data)