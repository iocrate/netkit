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

proc newHttpConnection*(socket: AsyncFD, address: string): HttpConnection = 
  ## Creates a new ``HttpConnection``.
  new(result)
  result.buffer = initMarkableCircularBuffer()
  result.parser = initHttpParser()
  result.socket = socket
  result.address = address
  result.closed = false

proc close*(conn: HttpConnection) {.inline.} = discard
  ## Closes this connection to release the resources.

proc closed*(conn: HttpConnection): bool {.inline.} = discard
  ## Returns ``true`` if this connection is closed.

proc readHttpHeader*(conn: HttpConnection, header: ptr HttpHeader): Future[void] {.async.} = discard
  ## Reads the header of a HTTP message.
  ## 
  ## If a system error occurs during reading, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful reading, a ``ReadAbortedError`` will be raised.

proc readChunkHeader*(conn: HttpConnection, header: ptr ChunkHeader): Future[void] {.async.} = discard
  ## Reads the size and the extensions parts of a chunked data.
  ## 
  ## If a system error occurs during reading, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful reading, a ``ReadAbortedError`` will be raised.

proc readChunkEnd*(conn: HttpConnection, trailer: ptr seq[string]): Future[void] {.async.} = discard
  ## Reads the terminating chunk, trailer, and the final CRLF sequence of a chunked message. 
  ## 
  ## If a system error occurs during reading, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful reading, a ``ReadAbortedError`` will be raised.

proc readData*(conn: HttpConnection, buf: pointer, size: Natural): Future[Natural] {.async.} = discard 
  ## Reads up to ``size`` bytes from this connection, storing the results in the ``buf``. 
  ## 
  ## The return value is the number of bytes actually read. This might be less than ``size`` 
  ## that indicates the connection is at EOF. 
  ## 
  ## This proc should only be used to read the message body.
  ## 
  ## If a system error occurs during reading, an ``OsError``  will be raised. If the connection is  
  ## disconnected before successful reading, a ``ReadAbortedError`` will be raised.

proc write*(conn: HttpConnection, buf: pointer, size: Natural): Future[void] {.inline.} = discard
  ## Writes ``size`` bytes from ``buf`` to the connection. 
  ## 
  ## If a system error occurs during writing, an ``OsError``  will be raised. If the connection is 
  ## disconnected or other errors occurs before the write operation is successfully completed, a 
  ## ``WriteAbortedError`` exception will be raised.

proc write*(conn: HttpConnection, data: string): Future[void] {.inline.} = discard
  ## Writes a string to the connection.
  ## 
  ## If a system error occurs during writing, an ``OsError``  will be raised. If the connection is 
  ## disconnected or other errors occurs before the write operation is successfully completed, a 
  ## ``WriteAbortedError`` exception will be raised.