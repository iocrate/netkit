#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块实现了一个增量的 HTTP 消息解析器。该解析器支持解析请求消息和响应消息。
## 
## 解析器是增量的，这表示可以连续解析消息，而不管消息是一次交付还是分成多个部分。这使得该解析器特别适合复杂的 IO 传输环境。
## 
## 用法
## ========================
## 
## .. container:: r-fragment
## 
##   解析消息头
##   ------------------------------
## 
##   例子：
## 
##   .. code-block::nim 
## 
##     import netkit/http/parser
##     import netkit/http/header
##     import netkit/buffer/circular
## 
##     var parser = initHttpParser()
##     var buffer = initMarkableCircularBuffer()
##     var header = HttpHeader(kind: HttpHeaderKind.Request)
##     var finished = false
## 
##     while not finished:
##       put data to buffer ...
##       finished = parser.parseHttpHeader(buffer, header)
## 
##   另一个例子：
## 
##   .. code-block::nim 
## 
##     import netkit/http/parser
##     import netkit/http/header
##     import netkit/buffer/circular
## 
##     var parser = initHttpParser()
##     var buffer = initMarkableCircularBuffer()
##     var header = HttpHeader(kind: HttpHeaderKind.Request)
##     
##     # 第一次解析
##     let messageRequestLine = "GET / HTTP/1.1\r\n"
##     buffer.add(messageRequestLine.cstring, messageRequestLine.len)
##     assert parser.parseHttpHeader(buffer, header) == false
##     buffer.del(messageRequestLine.len)
##     
##     # 第二次解析
##     let messageHeaderFields = "Host: www.iocrate.com\r\n\r\n"
##     buffer.add(messageHeaderFields.cstring, messageHeaderFields.len)
##     assert parser.parseHttpHeader(buffer, header) == true
##     buffer.del(messageHeaderFields.len)
##     
##     assert header.reqMethod == HttpGet
##     assert header.url == "/"
##     assert header.version.orig == "HTTP/1.1"
##     assert header.fields["Host"][0] == "www.iocrate.com"
## 
## .. container:: r-fragment
##     
##   解析 chunked 编码消息的块的头部
##   ------------------------------
## 
##   例子：
## 
##   .. code-block::nim
## 
##     import netkit/http/parser
##     import netkit/http/chunk
##     import netkit/buffer/circular
## 
##     var parser = initHttpParser()
##     var buffer = initMarkableCircularBuffer()
##     var header: ChunkHeader
##     var finished = false
## 
##     while not finished:
##       put data to buffer ...
##       finished = parser.parseChunkHeader(buffer, header)
## 
##   另一个例子：
## 
##   .. code-block::nim 
## 
##     import netkit/http/parser
##     import netkit/http/chunk
##     import netkit/buffer/circular
## 
##     var parser = initHttpParser()
##     var buffer = initMarkableCircularBuffer()
##     var header: ChunkHeader
##     
##     let s = "9; language=en; city=London\r\n"
##     buffer.add(s.cstring, s.len)
##     assert parser.parseChunkHeader(buffer, header) == true
##     buffer.del(s.len)
##     
##     assert header.size == 9
##     assert header.extensions == "; language=en; city=London"
## 
##   See **chunk** module and **metadata** module for more information about chunked encoding.
## 
## .. container:: r-fragment
## 
##    解析 chunked 编码消息的尾部
##   ------------------------------
## 
##   例子：
## 
##   .. code-block::nim
## 
##     import netkit/http/parser
##     import netkit/http/chunk
##     import netkit/buffer/circular
## 
##     var parser = initHttpParser()
##     var buffer = initMarkableCircularBuffer()
##     var trailers: seq[string]
##     var finished = false
## 
##     while not finished:
##       put data to buffer ...
##       finished = parser.parseChunkEnd(buffer, trailers)
##  
##   另一个例子：
## 
##   .. code-block::nim 
## 
##     import netkit/http/parser
##     import netkit/http/chunk
##     import netkit/buffer/circular
## 
##     var parser = initHttpParser()
##     var buffer = initMarkableCircularBuffer()
##     var trailers: seq[string]
##     
##     let s = "\0\r\nExpires": "Wed, 21 Oct 2015 07:28:00 GMT\r\n\r\n"
##     buffer.add(s.cstring, s.len)
##     assert parser.parseChunkEnd(buffer, trailers) == true
##     buffer.del(s.len)
##     
##     assert trailers[0] == "Expires": "Wed, 21 Oct 2015 07:28:00 GMT"
## 
##   看看 **chunk** 模块和 **metadata** 模块了解更多关于 terminating chunk and trailers 的信息。


import strutils
import netkit/buffer/circular
import netkit/http/limits
import netkit/http/exception
import netkit/http/spec
import netkit/http/uri
import netkit/http/httpmethod
import netkit/http/version
import netkit/http/status
import netkit/http/headerfield
import netkit/http/header
import netkit/http/chunk

type
  HttpParser* = object ## HTTP 消息解析器。
    secondaryBuffer: string
    currentLineLen: Natural
    currentFieldName: string
    currentFieldCount: Natural
    state: HttpParseState
    startLineState: StartLineState
    
  HttpParseState {.pure.} = enum
    StartLine, FieldName, FieldValue, Body

  StartLineState {.pure.} = enum
    Method, Url, Version, Code, Reason

  MarkProcessState {.pure.} = enum
    Unknown, Token, Crlf

proc initHttpParser*(): HttpParser =
  ## 初始化一个 ``HttpParser`` 。
  discard

proc clear*(p: var HttpParser) = discard
  ## 重置解析器以清除所有状态。 
  ## 
  ## 由于解析器是增量的，因此在解析过程中将保存许多状态。此函数将重置所有状态，以开始新的解析过程。
  
proc parseHttpHeader*(p: var HttpParser, buf: var MarkableCircularBuffer, header: var HttpHeader): bool = discard
  ## 解析 HTTP 消息的头部。 ``buf`` 指定一个循环缓冲区，存储被解析的数据。 ``header`` 指定解析完成时输出的消息标头对象。 如果解析完成，则返回 ``true`` 。
  ## 
  ## 根据 ``header`` 的 ``kind`` 属性值，采用不同的解析方案。当 ``kind = Request`` 时，消息被解析为请求。当 ``kind = Response`` 时，消息被解析为响应。
  ## 
  ## 此过程是增量执行的，也就是说，下一次解析将从上一次结束的位置继续。

proc parseChunkHeader*(
  p: var HttpParser, 
  buf: var MarkableCircularBuffer,
  header: var ChunkHeader
): bool = discard
  ## 解析通过 chunked 编码消息的块的头部（大小和扩展名）。
  ## 
  ## 此过程是增量执行的，也就是说，下一次解析将从上一次结束的位置继续。

proc parseChunkEnd*(
  p: var HttpParser, 
  buf: var MarkableCircularBuffer, 
  trailers: var seq[string]
): bool = discard
  ## 解析通过 chunked 编码消息的尾部（终止块、trailers、final CRLF）。
  ## 
  ## 此过程是增量执行的，也就是说，下一次解析将从上一次结束的位置继续。
