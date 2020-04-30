#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    destribution, for details about the copyright.

## HTTP 1.1 支持 chunked 编码，允许将 HTTP 消息拆分成多个块逐块地传输。通常，服务器最常使用 chunked 消息，
## 但是客户端也可以用来处理比较大的请求。
## 
## 在消息头添加 ``Transfer-Encoding: chunked`` ，消息体就会进行 chunked 编码并且逐块地传输。
## 在传输过程中需要编码和解码，这个模块提供了针对这些编码解码的工具。
## 
## 概述
## ========================
## 
## .. container:: r-fragment
## 
##   块的格式
##   ------------------------
##   
##   经过 chunked 编码的 HTTP 消息 (不管是由客户端发送还是服务器发送)，其消息体都由零个到多个 chunks、一个 terminating chunk、trailers、
##   一个 final CRLF (即回车换行) 组成。
##  
##   每个块 (chunk) 最开始是块大小和块扩展 (chunk extension) ，后面跟着块数据 (chunk data)。块大小是十六进制字符，表示块数据的实际尺寸。
##   块扩展是可选的，以分号 ``';'`` 作为分隔符，每一部分是一个名值对，名值对以 ``'='`` 作为分隔符。比如 ``"; a=1; b=2"`` 。
## 
##   终止块 (terminating chunk) 是一个普通的块 (chunk)，只不过其块大小总是 ``0`` ，表示没有数据。其后面跟着 trailers，trailers 也是可选的，
##   由常规的 HTTP 头字段组成，作为元数据挂载在消息尾部。
##   
##   HTTP 规范规定，只有在收到请求带有 ``TE`` 头字段时，才允许在响应中发送 trailers 。当然，这说明 trailers 只在服务器发出的响应消息中才有用。
## 
##   ..
## 
##     看看 `Chunked transfer encoding <https://en.wikipedia.org/wiki/Chunked_transfer_encoding>`_ 了解更多。
## 
## .. container:: r-fragment
## 
##   例子
##   ------------------------
## 
##   一个 chunked 消息体的例子：
## 
##   .. code-block::http
## 
##     5;\r\n                                      # chunk-size and chunk-extensions (empty)
##     Hello\r\n                                   # data
##     9; language=en; city=London\r\n             # chunk-size and chunk-extensions
##     Developer\r\n                               # data
##     0\r\n                                       # terminating chunk ---------------------
##     Expires: Wed, 21 Oct 2015 07:28:00 GMT\r\n  # trailer
##     \r\n                                        # final CRLF-----------------------------
## 
## .. container:: r-fragment
## 
##   关于 \\n and \\L 
##   ------------------------
## 
##   由于在 Nim 语言中 \\n 不能表示为一个字符 (而是字符串)，所以我们使用 `\\L` 表示换行符号。 
## 
## 用法
## ========================
## 
## .. container:: r-fragment
## 
##   编码
##   ------------------------
## 
##   实现上面例子的 chunked 消息体：
## 
##   .. code-block::nim
## 
##     import netkit/http/chunk
##     import netkit/http/headerfield
## 
##     assert encodeChunk("Hello") == "5;\r\nHello\r\n"
## 
##     assert encodeChunk("Developer", {
##       "language": "en",
##       "city": "London"
##     }) == "9; language=en; city=London\r\nDeveloper\r\n"
## 
##     assert encodeChunkEnd(initHeaderFields({
##       "Expires": "Wed, 21 Oct 2015 07:28:00 GMT"
##     })) == "0\r\nExpires: Wed, 21 Oct 2015 07:28:00 GMT\r\n\r\n"
##   
##   这个例子演示了编码函数的字符串版本。不过，netkit 也提供了更高效的方案，请参看下面。
## 
##   使用指针缓冲区编码
##   --------------------------------
## 
##   持续的从一个文件读数据，同时把数据编码：
## 
##   .. code-block::nim
## 
##     import netkit/http/chunk
##     import netkit/http/headerfield
##     
##     var source: array[64, byte]
##     var dest: array[128, byte]
##     
##     # open a large file
##     var file = open("test.blob") 
##     
##     while true:
##       let readLen = file.readBuffer(source.addr, 64)
## 
##       if readLen > 0:
##         let encodeLen = encodeChunk(source.addr, readLen, dest.addr, 128)
##         # handle dest, encodeLen ...
## 
##       # read EOF
##       if readLen < 64: 
##         echo encodeChunkEnd(initHeaderFields({
##           "Expires": "Wed, 21 Oct 2015 07:28:00 GMT"
##         }))
##         break
## 
##   ..
## 
##     当您对性能非常关注或者正在处理大量数据时，考虑使用指针缓冲区方案。
## 
## .. container:: r-fragment
## 
##   解码
##   ------------------------
## 
##   解析由块尺寸 (chunk size) 和块扩展 (chunk extensions) 组成的字符序列：
## 
##   .. code-block::nim
## 
##     import netkit/http/chunk
## 
##     let header = parseChunkHeader("1A; a1=v1; a2=v2") 
##     assert header.size == 26
##     assert header.extensions == "; a1=v1; a2=v2"
## 
##   解析块扩展 (chunk extensions) 相关的字符序列：
## 
##   .. code-block::nim
## 
##     import netkit/http/chunk
## 
##     let extensions = parseChunkExtensions("; a1=v1; a2=v2") 
##     assert extensions[0].name == "a1"
##     assert extensions[0].value == "v1"
##     assert extensions[1].name == "a2"
##     assert extensions[1].value == "v2"
## 
##   解析 trailers 相关的字符序列：
## 
##   .. code-block::nim
## 
##     import netkit/http/chunk
## 
##     let tailers = parseChunkTrailers(@["Expires: Wed, 21 Oct 2015 07:28:00 GMT"]) 
##     assert tailers["Expires"][0] == "Wed, 21 Oct 2015 07:28:00 GMT"

import strutils
import strtabs
import netkit/misc
import netkit/http/spec
import netkit/http/limits
import netkit/http/headerfield

type
  ChunkHeader* = object ## 表示块 (chunk) 的头部。
    size*: Natural      
    extensions*: string 

  ChunkExtension* = tuple ## 表示块扩展 (chunk extensions)。
    name: string          
    value: string  

proc parseChunkHeader*(s: string): ChunkHeader {.raises: [ValueError].} = discard
  ## 把字符串转换成一个 ``ChunkHeader`` 。
  ##
  ## 例子：
  ## 
  ## .. code-block::nim
  ## 
  ##   parseChunkHeader("64") # => (100, "")
  ##   parseChunkHeader("64; name=value") # => (100, "; name=value")

proc parseChunkExtensions*(s: string): seq[ChunkExtension] = discard
  ## 把字符串转换成一组 ``(name, value)`` 对，该字符串表示块扩展。 
  ## 
  ## 例子： 
  ## 
  ## .. code-block::nim
  ## 
  ##   let extensions = parseChunkExtensions(";a1=v1;a2=v2") 
  ##   assert extensions[0].name == "a1"
  ##   assert extensions[0].value == "v1"
  ##   assert extensions[1].name == "a2"
  ##   assert extensions[1].value == "v2"

proc parseChunkTrailers*(ts: openArray[string]): HeaderFields = discard
  ## 把一组字符串转换为一个 ``HeaderFields`` ，该组字符串表示一些 trailers。 
  ## 
  ## 例子： 
  ## 
  ## .. code-block::nim
  ## 
  ##   let fields = parseChunkTrailers(@["Expires: Wed, 21 Oct 2015 07:28:00 GMT"]) 
  ##              # => ("Expires", "Wed, 21 Oct 2015 07:28:00 GMT")  
  ##   assert fields["Expires"][0] == "Wed, 21 Oct 2015 07:28:00 GMT"

proc encodeChunk*(
  source: pointer, 
  dest: pointer, 
  size: Natural
): Natural = discard
  ## 编码一块数据， ``source`` 指定被编码的数据， ``size`` 指定数据的字节长度，编码后的结果存储到 ``dest`` 。
  ## 
  ## 注意： ``dest`` 必须比 ``size`` 至少大 ``21`` 字节长度，否则，将没有足够的空间存储编码后的数据。
  ## 
  ## 例子：
  ## 
  ## .. code-block::nim
  ## 
  ##   let source = "Developer"
  ##   let dest = newString(source.len + 21)
  ##   encodeChunk(source.cstring, source.len, dest.cstring, dest.len)
  ##   assert dest == "9\r\nDeveloper\r\n"

proc encodeChunk*(
  source: pointer, 
  dest: pointer, 
  size: Natural,
  extensions = openArray[ChunkExtension]
): Natural = discard
  ## 编码一块数据， ``source`` 指定被编码的数据， ``size`` 指定数据的字节长度， ``extensions`` 指定块扩展。
  ## 编码后的结果存储到 ``dest`` 。
  ## 
  ## 注意： ``dest`` 必须比 ``size`` 至少大 ``21 + extensions.len`` 字节长度，否则，将没有足够的空间存储编码后的数据。
  ## 
  ## 例子：
  ## 
  ## .. code-block::nim
  ## 
  ##   let source = "Developer"
  ##   let extensions = "language=en; city=London"
  ##   let dest = newString(source.len + 21 + extensions.len)
  ##   encodeChunk(source.cstring, source.len, dest.cstring, dest.len, extensions)
  ##   assert dest == "9; language=en; city=London\r\nDeveloper\r\n"

proc encodeChunk*(source: string): string = discard
  ## 编码一块数据。
  ## 
  ## 例子：
  ## 
  ## .. code-block::nim
  ## 
  ##   let dest = encodeChunk("Developer")
  ##   assert dest == "9\r\nDeveloper\r\n"

proc encodeChunk*(source: string, extensions: openArray[ChunkExtension]): string = discard
  ## 编码一块数据。 ``extensions`` 指定块扩展。
  ## 
  ## 例子：
  ## 
  ## .. code-block::nim
  ## 
  ##   let dest = encodeChunk("Developer", {
  ##     "language": "en",
  ##     "city": "London"
  ##   })
  ##   assert dest == "9; language=en; city=London\r\nDeveloper\r\n"

proc encodeChunkEnd*(): string = discard
  ## 返回一个由 terminating chunk 和 final CRLF 组成的块，表示消息的尾部。
  ## 
  ## 例子： 
  ## 
  ## .. code-block::nim
  ## 
  ##   let dest = encodeChunkEnd()
  ##   assert dest == "0\r\n\r\n"

proc encodeChunkEnd*(trailers: HeaderFields): string = discard
  ## 返回一个由 terminating chunk、trailers 和 final CRLF 组成的块，表示消息的尾部。 ``trailers`` 指定挂载的元数据。
  ## 
  ## 例子： 
  ## 
  ## .. code-block::nim
  ## 
  ##   let dest = encodeChunkEnd(initHeaderFields({
  ##     "Expires": "Wed, 21 Oct 2015 07:28:00 GM"
  ##   }))
  ##   assert dest == "0\r\nExpires: Wed, 21 Oct 2015 07:28:00 GM\r\n\r\n"
