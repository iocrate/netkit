#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 

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
  HttpConnection* = ref object ## 
    buffer: MarkableCircularBuffer
    parser: HttpParser
    socket: AsyncFD
    address: string
    closed: bool

proc newHttpConnection*(socket: AsyncFD, address: string): HttpConnection = 
  ##
  new(result)
  result.buffer = initMarkableCircularBuffer()
  result.parser = initHttpParser()
  result.socket = socket
  result.address = address
  result.closed = false

proc close*(conn: HttpConnection) {.inline.} = 
  conn.socket.closeSocket()
  conn.closed = true

proc closed*(conn: HttpConnection): bool {.inline.} = 
  conn.closed

proc read(conn: HttpConnection): Future[Natural] {.async.} = 
  ##
  ##
  ## If the return future is failed, ``OsError`` may be raised.
  let region = conn.buffer.next()
  result = await conn.socket.recvInto(region[0], region[1])
  if result > 0:
    discard conn.buffer.pack(result)

proc readData*(conn: HttpConnection, buf: pointer, size: Natural): Future[Natural] {.async.} =  
  ## Reads up to ``size`` bytes from the connection, storing the results in the ``buf``. 
  ## 
  ## The return value is the number of bytes actually read. This might be less than ``size`` 
  ## that indicates the connection is EOF. 
  ## 
  ## If the return future is failed, ``OsError`` may be raised.
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

proc readHttpHeader*(conn: HttpConnection, header: ptr HttpHeader): Future[void] {.async.} = 
  ## 读取 HTTPHeader， 如果解析过程出现错误， 则抛出异常， 说明对端数据有错误 bad request 
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
  var succ = false
  if conn.buffer.len > 0:
    succ = conn.parser.parseChunkHeader(conn.buffer, header[])
  while not succ:
    let n = await conn.read()
    if n == 0:
      raise newException(ReadAbortedError, "Connection closed prematurely")
    succ = conn.parser.parseChunkHeader(conn.buffer, header[])

proc readChunkEnd*(conn: HttpConnection, trailer: ptr seq[string]): Future[void] {.async.} = 
  # TODO: 考虑内存安全
  var succ = false
  if conn.buffer.len > 0:
    succ = conn.parser.parseChunkEnd(conn.buffer, trailer[])
  while not succ:
    let n = await conn.read()
    if n == 0:
      raise newException(ReadAbortedError, "Connection closed prematurely")
    succ = conn.parser.parseChunkEnd(conn.buffer, trailer[])

proc write*(conn: HttpConnection, buf: pointer, size: Natural): Future[void] {.inline.} =
  ## Writes ``size`` bytes from ``buf`` to the connection ``conn``. 
  ## 
  ## If the return future is failed, ``OsError`` may be raised.
  result = conn.socket.send(buf, size)

proc write*(conn: HttpConnection, data: string): Future[void] {.inline.} =
  ## 
  ## If the return future is failed, ``OsError`` may be raised.
  result = conn.socket.send(data)