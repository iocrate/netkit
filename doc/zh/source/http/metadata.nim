#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## HTTP 协议允许在消息中携带元数据。 当前， 有两种元数据， 这两种元数据都出现在经过 ``Transfer-Encoding: chunked`` 编码的
## 消息中。 这两种元数据是：
## 
## - Chunk Extensions
## - Trailer
## 
## 本模块定义了一个通用的对象 ``HttpMetadata``， 以抽象这些元数据， 以便于简化元数据的使用。 
## 
## Chunk Extensions
## -----------------
## 
## 经过 ``Transfer-Encoding: chunked`` 编码的消息， 其每一个数据块， 都允许包含零个或多个分块扩展。 这些分块扩展紧跟在分块
## 尺寸后面， 以支持元数据 。 您可以利用这些元数据对当前的数据块做特定处理。 元数据完全由您来决定， 比如一个签名、 哈希值、 或者
## 控制信息等等。 
## 
## 每个分块扩展是由 ``=`` 作为分隔符的名值对， 比如 ``language=en``； 多个分块扩展由 ``;`` 作为分隔符组合， 
## 比如 ``language=en; city=London`` 。 
## 
## 一个挂载分块扩展的例子： 
## 
## ..code-block:http
## 
##   HTTP/1.1 200 OK 
##   Transfer-Encoding: chunked
##   
##   9; language=en; city=London\r\n 
##   Developer\r\n 
##   0\r\n 
##   \r\n
## 
## Trailers
## --------
## 
## 经过 ``Transfer-Encoding: chunked`` 编码的消息， 允许在尾部携带 trailers 。 Trailers 实际上是一个或者多个 HTTP 响应头
## 字 段，允许发送方在消息后面添加额外的元信息， 这些元信息可能是随着消息主体的发送动态生成的， 比如消息的完整性校验、 消息的数字签 
## 名、或者消息经过处理之后的最终状态等。 
## 
## 请注意： 只有客户端的请求头部 ``TE`` 设置了 trailers 后 ( ``TE: trailers`` ) ， 服务器端才能在响应里挂载 trailers 。 
## 
## 一个挂载 trailers 的例子： 
## 
## ..code-block:http
## 
##   HTTP/1.1 200 OK 
##   Transfer-Encoding: chunked
##   Trailer: Expires
##   
##   9\r\n 
##   Developer\r\n 
##   0\r\n 
##   Expires: Wed, 21 Oct 2015 07:28:00 GMT\r\n
##   \r\n

type
  HttpMetadataKind* {.pure.} = enum ## 元数据种类。 
    None,                           ## 表示没有元数据。 
    ChunkTrailer,                   ## 表示元数据是 Trailer 。 
    ChunkExtensions                 ## 表示元数据是 Chunk Extensions 。 

  HttpMetadata* = object ## 元数据对象。 
    case kind*: HttpMetadataKind
    of HttpMetadataKind.ChunkTrailer:
      trailers*: seq[string] ## Trailers 集合， 每一项表示一个头字段。出于性能考虑， ``HttpMetadata`` 未对 ``trailers`` 
                             ## 的内容做进一步解析， 而是使用字符串序列保存。 您可以使用 chunk 模块的 ``parseChunkTrailers`` 
                             ## 将字符串序列转换成 ``HeaderFileds`` 以访问 trailers 的内容。  
    of HttpMetadataKind.ChunkExtensions:
      extensions*: string    ## Chunk Extensions 。出于性能考虑， ``HttpMetadata`` 未对 ``extensions`` 
                             ## 的内容做进一步解析， 而是使用字符串保存。 您可以使用 chunk 模块的 ``parseChunkExtensions``
                             ## 将字符串序列转换成 ``(name, value)`` 序列以访问 extensions 的内容。  
    of HttpMetadataKind.None:
      discard 
