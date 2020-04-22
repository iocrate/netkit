#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

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
import netkit/http/base
import netkit/http/exception 
import netkit/http/parser
import netkit/http/chunk 

type
  HttpConnection* = ref object ## 表示客户端与服务器之间的一个活跃的通信连接。 这个对象不由用户代码直接构造。 
    buffer: MarkableCircularBuffer
    parser: HttpParser
    socket: AsyncFD
    address: string
    closed: bool

proc newHttpConnection*(socket: AsyncFD, address: string): HttpConnection = discard
  ## 初始化一个 ``HttpConnection`` 对象。 

proc close*(conn: HttpConnection) {.inline.} = discard
  ##

proc closed*(conn: HttpConnection): bool {.inline.} = discard
  ##

proc readData*(conn: HttpConnection, buf: pointer, size: Natural): Future[Natural] = discard
  ## 读取直到 ``size`` 字节， 读取的数据填充在 ``buf``， 返回实际读取的数量。 如果返回值不等于 ``size``， 说明
  ## 连接已经关闭。如果连接关闭， 则返回；否则，一直读取，直到 ``size`` 字节。 

proc readHttpHeader*(conn: HttpConnection, header: ptr HttpHeader): Future[void] = discard
  ##

proc readChunkHeader*(conn: HttpConnection, header: ptr ChunkHeader): Future[void] = discard
  ##

proc readChunkEnd*(conn: HttpConnection, trailer: ptr seq[string]): Future[void] = discard
  ##

proc write*(conn: HttpConnection, buf: pointer, size: Natural): Future[void] {.inline.} = discard
  ## 写入响应数据。 ``buf`` 指定数据源， ``len`` 指定数据源的长度。 

proc write*(conn: HttpConnection, data: string): Future[void] {.inline.} = discard
  ## 写入响应数据。 ``data`` 指定数据源。 
