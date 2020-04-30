#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块定义了一个通用对象 ``HttpMetadata`` ，该对象抽象了 HTTP 以简化对元数据的使用。
## 
## 概述
## ========================
## 
## HTTP 消息支持挂载元数据。当前，有两种类型的元数据，都出现在 chunked 编码的消息。它们是：
## 
## - Chunk Extensions
## - Trailers
## 
## .. container:: r-fragment
## 
##   Chunk Extensions
##   -----------------
## 
##   经过 chunked 编码的消息，每个数据块可以包含零个到多个块扩展。这些扩展紧跟在块大小之后，提供块的元数据（例如签名或哈希）。
## 
##   每个扩展都是一个以 ``=`` 作为分隔符的名称/值对，例如 ``language = en``; 多个扩展名以 ``';'`` 作为分隔符组合在一起，例如 ``language=en; city=London`` 。
## 
##   例子：
## 
##   .. code-block::http
## 
##     HTTP/1.1 200 OK 
##     Transfer-Encoding: chunked
##   
##     9; language=en; city=London\r\n 
##     Developer\r\n 
##     0\r\n 
##     \r\n
## 
## .. container:: r-fragment
## 
##   Trailers
##   --------
## 
##   经过 chunked 编码的消息，可以在尾部挂载元数据 trailers。trailers 实际上是一个或多个 HTTP 响应头字段，允许发送方在消息末尾添加其他元信息。
##   这些元信息可以随着消息正文的发送而动态生成，例如消息完整性检查，消息数字签名或处理后消息的最终状态等。
## 
##   注意：仅当客户端在请求头包含 ``TE``（ ``TE：trailers`` ）时，服务器才能在响应中挂载 trailers。
## 
##   例子：
## 
##   .. code-block::http
## 
##     HTTP/1.1 200 OK 
##     Transfer-Encoding: chunked
##     Trailer: Expires
##   
##     9\r\n 
##     Developer\r\n 
##     0\r\n 
##     Expires: Wed, 21 Oct 2015 07:28:00 GMT\r\n
##     \r\n
## 
## 用法
## ========================
## 
## 出于性能方面的考虑， ``HttpMetadata`` 不会进一步解析 ``trailers`` 和 ``extensions`` 的内容。
## 您可以使用 ``parseChunkTrailers`` 和 ``parseChunkExtensions`` 分别提取它们的内容。
## 
## .. container:: r-fragment
## 
##   Chunk Extensions
##   ----------------
## 
##   提取内容：
## 
##   .. code-block::nim
## 
##     import netkit/http/metadata
##     import netkit/http/chunk
## 
##     let metadata = HttpMetadata(
##       kind: HttpMetadataKind.ChunkExtensions, 
##       extensions: "; a1=v1; a2=v2"
##     )
##     let extensions = parseChunkExtensions(metadata.extensions)
##     assert extensions[0].name == "a1"
##     assert extensions[0].value == "v1"
##     assert extensions[1].name == "a2"
##     assert extensions[1].value == "v2"
## 
## .. container:: r-fragment
## 
##   Trailers
##   --------------
## 
##   提取内容：
## 
##   .. code-block::nim
## 
##     import netkit/http/metadata
##     import netkit/http/chunk
## 
##     let metadata = HttpMetadata(
##       kind: HttpMetadataKind.ChunkTrailers, 
##       trailers: @["Expires: Wed, 21 Oct 2015 07:28:00 GMT"]
##     )
##     let tailers = parseChunkTrailers(metadata.trailers)
##     assert tailers["Expires"][0] == "Wed, 21 Oct 2015 07:28:00 GMT"

type
  HttpMetadataKind* {.pure.} = enum  ## 元数据的类型。
    None,                            
    ChunkTrailers,                   
    ChunkExtensions                  

  HttpMetadata* = object  ##元数据对象。
    case kind*: HttpMetadataKind
    of HttpMetadataKind.ChunkTrailers:
      trailers*: seq[string] 
    of HttpMetadataKind.ChunkExtensions:
      extensions*: string    
    of HttpMetadataKind.None:
      discard 

