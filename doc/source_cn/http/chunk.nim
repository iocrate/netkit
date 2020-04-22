#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## HTTP 1.1 协议规范支持 chunked 编码， 通过在消息头添加 ``Transfer-Encoding: chunked`` 字段， 能够在不确定消息总大小的
## 前提下，将消息体逐块逐块地发送。 发送和接收的每一块数据都需要进行编码和解码。 本模块提供了处理这些编码和解码相关的工具。
## 
## 数据块和数据尾部
## --------------
## 
## 这样的编码， 将整个消息体拆成了数据块和数据尾部。 
## 
## 每一个经过 chunked 编码的数据块， 包括 chunk-size (指定数据块的大小)、 
## chunk-extensions (可选的， 指定扩展)、 chunk-data (实际数据) 。 按照习惯， 通常将这样的数据块表示为数据头和数据体。 
## 数据头包括 chunk-size 和 chunk-extensions； 数据体则是 chunk-data， 也就是实际数据 。 
## 
## 经过 chunked 编码的消息体， 最后面是数据尾部， 表示消息体的结束。 数据尾部支持挂载 trailers， 以允许发送方在消息后面添加
## 额外的元信息。 
## 
## HTTP 消息示例
## -------------
## 
## 以下是一个经过 chunked 编码的 HTTP 消息体的例子： 
## 
## ..code-block:http
## 
##   5;\r\n                                      # chunk-size 和 chunk-extensions
##   Hello\r\n                                   # chunk-data
##   9; language=en; city=London\r\n             # chunk-size 和 chunk-extensions
##   Developer\r\n                               # chunk-data
##   0\r\n                                       # 以下为数据尾部 -----------------
##   Expires: Wed, 21 Oct 2015 07:28:00 GMT\r\n  # trailer
##   \r\n                                        # ------------------------------
## 
## 使用指南 - 编码
## ----------------------------
## 
## 要实现上面例子表示的 HTTP 消息体， 您可以通过以下方法： 
## 
## ..code-block:nim
## 
##   var message = ""
## 
##   message.add(encodeChunk("Hello"))
##   message.add(encodeChunk("Developer", {
##     "language": "en",
##     "city": "London"
##   }))
##   message.add(encodeChunkEnd(initHeaderFields({
##     "Expires": "Wed, 21 Oct 2015 07:28:00 GM"
##   })))
## 
## 这个例子演示了 “字符串版本的 encodeChunk”， 本模块还提供了其他高效的编码函数， 你可以查看具体描述。 
## 
## 使用指南 - 解析
## ----------------------------
## 
## 要解析一个 chunk-size 和 chunk-extensions 组成的字符序列： 
## 
## ..code-block::nim
## 
##   let header = parseChunkHeader("1A; a1=v1; a2=v2") 
##   assert header.size = 26
##   assert header.extensions = "; a1=v1; a2=v2"
## 
## 要解析一个 chunk-extensions 字符序列： 
## 
## ..code-block::nim
## 
##   let extensions = parseChunkExtensions("; a1=v1; a2=v2") 
##   assert extensions[0].name = "a1"
##   assert extensions[0].value = "v1"
##   assert extensions[1].name = "a1"
##   assert extensions[1].value = "v1"
## 
## 要解析一组 tailers 字符序列： 
## 
## ..code-block::nim
## 
##   let tailers = parseChunkHeader(@["Expires: Wed, 21 Oct 2015 07:28:00 GMT"]) 
##   assert tailers["Expires"][0] == "Wed, 21 Oct 2015 07:28:00 GMT"
## 
## 关于 \n 和 \L 的注释
## -------------------
## 
## 由于在 Nim 语言中 \n 不能表示为一个字符 (而是字符串)， 所以我们使用 `\L` 表示换行符号。  

import strutils
import strtabs
import netkit/misc
import netkit/http/base
import netkit/http/constants as http_constants

type
  ChunkHeader* = tuple ## 表示一个数据分块的头部。 
    size: Natural      ## 分块大小。 
    extensions: string ## 分块扩展。 

  ChunkExtension* = tuple ## 表示一个分块扩展。 
    name: string          ## 扩展的名字。 
    value: string         ## 扩展的值。 

proc parseChunkHeader*(s: string): ChunkHeader {.raises: [ValueError].} = discard
  ## 把 ``s`` 转换为一个 ``ChunkHeader`` 。 该字符串经过 ``Transfer-Encoding: chunked`` 编码， 表示数据块的大小和扩展。 
  ## 
  ## 例子：
  ## 
  ## ..code-block::nim
  ## 
  ##   parseChunkHeader("64") # => (100, "")
  ##   parseChunkHeader("64; name=value") # => (100, "name=value")

proc parseChunkExtensions*(s: string): seq[ChunkExtension] = discard
  ## 把 ``s`` 转换为一个 ``(name, value)`` 对的序列。 该字符串经过 ``Transfer-Encoding: chunked`` 编码， 表示数据块的扩展。 
  ## 
  ## 例子：
  ## 
  ## ..code-block::nim
  ## 
  ##   let extensions = parseChunkExtensions("; a1=v1; a2=v2") 
  ##                  # => ("a1", "v1"), ("a2", "v2")
  ##   assert extensions[0].name == "a1"
  ##   assert extensions[0].value == "v1"
  ##   assert extensions[1].name == "a2"
  ##   assert extensions[1].value == "v2"

proc parseChunkTrailers*(trailers: openarray[string]): HeaderFields = discard
  ## 把 ``trailers`` 转换为一个 ``HeaderFields`` 。 经过 ``Transfer-Encoding: chunked`` 编码的消息， 其尾部允许挂载
  ## 元数据。 ``trailers`` 指定这些元数据。  
  ## 
  ## 例子：
  ## 
  ## ..code-block::nim
  ## 
  ##   let fields = parseChunkHeader(@["Expires: Wed, 21 Oct 2015 07:28:00 GMT"]) 
  ##              # => ("Expires", "Wed, 21 Oct 2015 07:28:00 GMT")  
  ##   assert fields["Expires"][0] == "Wed, 21 Oct 2015 07:28:00 GMT"

proc encodeChunk*(
  source: pointer, 
  ssize: Natural, 
  dest: pointer, 
  dsize: Natural
) = discard
  ## 使用 ``Transfer-Encoding: chunked`` 编码一块数据。 ``source`` 指定被编码的数据， ``ssize`` 指定 ``source`` 的长度。
  ## 编码完成的数据被拷贝到 ``dest``， ``dsize`` 指定``dest`` 的长度。 
  ## 
  ## 注意， ``dsize`` 必须比 ``ssize`` 至少大 ``21``， 否则， 将没有足够的空间存储编码后的数据， 从而引起异常。 
  ## 
  ## 这个函数利用两个缓冲区 ``source`` 和 ``dest`` 处理编码过程。 如果您需要频繁处理大量的数据， 并关注处理时的性能消耗， 那么
  ## 这个函数非常有用。 通过保存对 ``source`` 和 ``dest`` 两个缓冲区的引用， 您不需要再创建额外的存储空间来保存编码后的数据。  
  ## 
  ## 如果您并不十分关注处理时的性能消耗， 或者数据量并不大， 推荐使用下面的字符串版本的 ``encodeChunk`` 。 
  ## 
  ## 例子：
  ## 
  ## ..code-block::nim
  ## 
  ##   let source = "Developer"
  ##   let dest = newString(source.len + 21)
  ##   encodeChunk(source.cstring, source.len, dest.cstring, dest.len)
  ##   assert dest == "9\r\LDeveloper\r\L"

proc encodeChunk*(
  source: pointer, 
  ssize: Natural, 
  dest: pointer, 
  dsize: Natural, 
  extensions = string
) = discard
  ## 使用 ``Transfer-Encoding: chunked`` 编码一块数据。 ``source`` 指定被编码的数据， ``ssize`` 指定 ``source`` 的长度。
  ## 编码完成的数据被拷贝到 ``dest``， ``dsize`` 指定``dest`` 的长度。 ``extensions`` 指定分块扩展。 
  ## 
  ## 注意， ``dsize`` 必须比 ``ssize`` 至少大 ``21 + extensions.len``， 否则， 将没有足够的空间存储编码后的数据， 从而引起
  ## 异常。 
  ## 
  ## 这个函数利用两个缓冲区 ``source`` 和 ``dest`` 处理编码过程。 如果您需要频繁处理大量的数据， 并关注处理时的性能消耗， 那么
  ## 这个函数非常有用。 通过保存对 ``source`` 和 ``dest`` 两个缓冲区的引用， 您不需要再创建额外的存储空间来保存编码后的数据。  
  ## 
  ## 如果您并不十分关注处理时的性能消耗， 或者数据量并不大， 推荐使用下面的字符串版本的 ``encodeChunk`` 。 
  ## 
  ## 例子：
  ## 
  ## ..code-block::nim
  ## 
  ##   let source = "Developer"
  ##   let extensions = "language=en; city=London"
  ##   let dest = newString(source.len + 21 + extensions.len)
  ##   encodeChunk(source.cstring, source.len, dest.cstring, dest.len, extensions)
  ##   assert dest == "9; language=en; city=London\r\LDeveloper\r\L"

proc encodeChunk*(source: string): string = discard
  ## 返回一块经过 ``Transfer-Encoding: chunked`` 编码的数据块， 不挂载元数据。  
  ## 
  ## 这是字符串版本的 ``encodeChunk``， 使用更加方便简单。
  ## 
  ## 例子：
  ## 
  ## ..code-block::nim
  ## 
  ##   let out = encodeChunk("Developer")
  ##   assert out == "9\r\LDeveloper\r\L"

proc encodeChunk*(source: string, extensions: openarray[ChunkExtension]): string = discard
  ## 返回一块经过 ``Transfer-Encoding: chunked`` 编码的数据块。 ``source`` 指定被编码的数据， ``extensions`` 指定分块扩展。 
  ## 
  ## 这是字符串版本的 ``encodeChunk``， 使用更加方便简单。
  ## 
  ## 例子：
  ## 
  ## ..code-block::nim
  ## 
  ##   let out = encodeChunk("Developer", {
  ##     "language": "en",
  ##     "city": "London"
  ##   })
  ##   assert out == "9; language=en; city=London\r\LDeveloper\r\L"

proc encodeChunkEnd*(): string = discard
  ## 返回一块经过 ``Transfer-Encoding: chunked`` 编码的数据块尾部， 不挂载元数据。  
  ## 
  ## 例子： 
  ## 
  ## ..code-block:nim
  ## 
  ##   let out = encodeChunkEnd()
  ##   assert out == "0\r\L\r\L"
  
proc encodeChunkEnd*(trailers: HeaderFields): string = discard
  ## 返回一块经过 ``Transfer-Encoding: chunked`` 编码的数据块尾部。 ``trailers`` 指定挂载的元数据。
  ## 
  ## 例子： 
  ## 
  ## ..code-block:nim
  ## 
  ##   let out = encodeChunkEnd(initHeaderFields({
  ##     "Expires": "Wed, 21 Oct 2015 07:28:00 GM"
  ##   }))
  ##   assert out == "0\r\LExpires: Wed, 21 Oct 2015 07:28:00 GM\r\L\r\L"
   
   