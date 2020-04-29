#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块实现了一个介于客户端和服务器的 HTTP 连接。 ``HttpConnection`` 能够识别网络传输的 HTTP 消息。
## 
## 使用
## ========================
## 
## .. container:: r-fragment
## 
##   读消息头
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
##   读消息体
##   ------------------------ 
## 
##   .. code-block::nim
## 
##     let readLen = await conn.readData(buf, 1024)
## 
## .. container:: r-fragment
## 
##   读 chunked 编码的消息体
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
##   写消息
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

# 关于 HTTP Server Request 的边界条件
# ----------------------------------
#
# 1. 不同连接的请求读，一定不存在竞争问题。
#
# 2. 同一个连接，不同请求的读，一定不存在竞争问题。因为后一个请求总是在前一个请求 EOF 后才能引用。也就谁说，对于
#    [req1, req2]，req1.read() 总是立刻返回 EOF 。
#
#        r1 = req1.read() # 立即返回 EOF，保存在 Future.value
#        r2 = req2.read()
#
#        await r2
#        await r1
#
#    ------------------------------------------------------
#
#        r2 = req2.read() 
#        r1 = req1.read() # 立即返回 EOF，保存在 Future.value
#
#        await r2
#        await r1
#
# 3. 同一个连接，同一个请求，不同次序的读，存在竞争问题，特别是非 chunked 编码的时候，必须进行排队。
#
#        r1_1 = req1.read()
#        r1_2 = req1.read()
#
#        await r1_2
#        await r1_1 
#
# 4. 不同连接的响应写，一定不存在竞争问题。
#
# 5. 同一个连接，不同响应的写，一定不存在竞争问题。因为后一个请求总是在前一个请求 EOF 后才能引用。也就谁说，对于
#    [req1, req2]，req1.write() 总是立刻返回 EOF 。
#
# 6. 同一个连接，同一个响应，不同次序的写，一定不存在竞争问题。因为不对写数据进行内部处理，而是直接交给底层 socket。
#
# 关于 HTTP Server Request 读的结果
# --------------------------------
#
# 1. NativeSocket.recv() => >0 
#
#    表示： 正常。
#    方法： 处理数据。 
#
# 2. NativeSocket.recv() => 0 
# 
#    表示： 对端关闭写， 但是不知道对端是否关闭读。 
#    方法： 根据 HTTP 协议规则， 可以知道， 收到 0 时， 只有两个情况： 本条请求未开始； 本条请求数据
#          不完整。 因此， 应当立刻关闭本端 socket 。 
#
# 3. NativeSocket.recv() => Error 
#    
#    表示： 本端出现错误。 
#    方法： 该连接不可以继续使用， 否则将出现未知的错误序列。 因此， 应当立刻关闭本端 socket 。 
#
# 关于 HTTP Server Request 写的结果
# --------------------------------
#
# 1. NativeSocket.write() => Void 
#
#    表示： 正常。
#    方法： 处理数据。 
#
# 2. NativeSocket.write() => Error 
#    
#    表示： 本端出现错误。 
#    方法： 该连接不可以继续使用， 否则将出现未知的错误序列。 因此， 应当立刻关闭本端 socket 。 

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
  HttpConnection* = ref object ## HTTP 连接.
    buffer: MarkableCircularBuffer
    parser: HttpParser
    socket: AsyncFD
    address: string
    closed: bool

proc newHttpConnection*(socket: AsyncFD, address: string): HttpConnection = 
  ## 创建一个新的 ``HttpConnection`` 。
  new(result)
  result.buffer = initMarkableCircularBuffer()
  result.parser = initHttpParser()
  result.socket = socket
  result.address = address
  result.closed = false

proc close*(conn: HttpConnection) {.inline.} = discard
  ## 关闭连接以释放底层资源。

proc closed*(conn: HttpConnection): bool {.inline.} = discard
  ## 判断连接是否已经关闭。

proc readHttpHeader*(conn: HttpConnection, header: ptr HttpHeader): Future[void] = discard
  ## 读取一个消息头部。 
  ## 
  ## 如果读过程中出现系统错误，则会触发 ``OSError`` 异常；如果在成功读取之前连接断开，则会触发 ``ReadAbortedError`` 异常。

proc readChunkHeader*(conn: HttpConnection, header: ptr ChunkHeader): Future[void] = discard
  ## 读取一个 chunked 编码的块的头部。 
  ## 
  ## 如果读过程中出现系统错误，则会触发 ``OSError`` 异常；如果在成功读取之前连接断开，则会触发 ``ReadAbortedError`` 异常。

proc readChunkEnd*(conn: HttpConnection, trailer: ptr seq[string]): Future[void] = discard
  ## 读取一个 chunked 编码终止块 (terminating chunk)、trailers、和 final CRLF。 
  ## 
  ## 如果读过程中出现系统错误，则会触发 ``OSError`` 异常；如果在成功读取之前连接断开，则会触发 ``ReadAbortedError`` 异常。

proc readData*(conn: HttpConnection, buf: pointer, size: Natural): Future[Natural] = discard 
  ## 读取数据直到 ``size`` 字节，读取的数据填充在 ``buf`` ，返回实际读取的字节数。如果返回值不等于 ``size`` ，说明
  ## 出现错误或者连接已经断开。如果出现错误或连接已经断开，则立刻返回；否则，将一直等待读取，直到 ``size`` 字节。 
  ## 
  ## 这个函数应该用来读取消息体。 
  ## 
  ## 如果读过程中出现系统错误，则会触发 ``OSError`` 异常；如果在成功读取之前连接断开，则会触发 ``ReadAbortedError`` 异常。

proc write*(conn: HttpConnection, buf: pointer, size: Natural): Future[void] {.inline.} = discard
  ## 写入数据。 ``buf`` 指定数据源， ``size`` 指定数据源的字节数。
  ## 
  ## 如果写过程中出现系统错误，则会触发 ``OSError`` 异常；如果在成功写之前连接断开，则会触发 ``WriteAbortedError`` 异常。

proc write*(conn: HttpConnection, data: string): Future[void] {.inline.} = discard
  ## 写入数据。 ``data`` 指定数据源。
  ## 
  ## 如果写过程中出现系统错误，则会触发 ``OSError`` 异常；如果在成功写之前连接断开，则会触发 ``WriteAbortedError`` 异常。