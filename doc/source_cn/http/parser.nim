#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块实现了一个增量的 HTTP 解析器， 同时支持解析请求消息和响应消息。 这个解析器是增量的， 意味着可以持续解析
## 消息而不管该消息是一次性传递还是分成多次传递。 这使得该解析器特别适合复杂的 IO 传输环境。 
## 
## 使用 - 解析消息头部
## ------------------------------
## 
## ..code-block::nim
## 
##   var parser = initHttpParser()
##   var buffer = initMarkableCircularBuffer()
##   var header = HttpHeader(kind: HttpHeaderKind.Request)
##   var finished = false
## 
##   while not finished:
##     put data to buffer ...
##     finished = parser.parseHttpHeader(buffer, header)
##     
## 使用 - 解析 chunked 数据块的头部
## ------------------------------
## 
## 关于 ``Transfer-Encoding: chunked`` 和 chunked 编码数据块请参看 chunk 模块和 metadata 模块。 
## 
## ..code-block::nim
## 
##   var parser = initHttpParser()
##   var buffer = initMarkableCircularBuffer()
##   var header: ChunkHeader
##   var finished = false
## 
##   while not finished:
##     put data to buffer ...
##     finished = parser.parseChunkHeader(buffer, header)
## 
## 使用 - 解析 chunked 数据块的尾部
## ------------------------------
## 
## 关于 ``Transfer-Encoding: chunked`` 和 chunked 编码数据块请参看 chunk 模块和 metadata 模块。 
## 
## ..code-block::nim
## 
##   var parser = initHttpParser()
##   var buffer = initMarkableCircularBuffer()
##   var trailers: seq[string]
##   var finished = false
## 
##   while not finished:
##     put data to buffer ...
##     finished = parser.parseChunkEnd(buffer, trailers)

# ==============  ==========   ======  ============================================
# Name            工具          用途    描述
# ==============  ==========   ======  ============================================
# Parsing         Parser       解析     将一个字符序列转换成一个对象树
# Unparsing       Unparser     反向解析  将一个对象树转换成一个字符序列
# Serialization   Serializer   序列化    将一个对象树转换成一个字符序列
# Deserialization Deserializer 反序列化  将一个字符序列转换成一个对象树
# Encoding        Encoder      编码     将一个字符序列进行扰码或者变换转换成另一个字符序列
# Decoding        Decoder      解码     将一个经过扰码或者变换的字符序列转换成原始的字符序列
# ==============  ==========   ======  ============================================

import uri
import strutils
import netkit/buffer/circular
import netkit/http/constants as http_constants
import netkit/http/base
import netkit/http/exception
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

proc initHttpParser*(): HttpParser = discard
  ## 初始化一个 ``HttpParser`` 对象。 

proc clear*(p: var HttpParser) = discard
  ## 重置 ``p`` 以清空所有的状态。 
  ## 
  ## 既然 ``HttpParser`` 是一个增量解释器， 在解析过程会保存各种各样的状态数据。 这个函数重置所有状态， 以便于开始一个新的解析过程。 

proc parseHttpHeader*(p: var HttpParser, buf: var MarkableCircularBuffer, header: var HttpHeader): bool = discard
  ## 解析消息头部。 ``buf`` 指定缓冲区， 该缓冲区存储了要被解析的数据； ``header`` 指定解析完成时输出的消息头部对象。
  ## 
  ## 根据 ``header`` 的 ``kind`` 属性值不同， 采取不同解析。 当 ``kind=Request`` 时， 则将消息作为请求解析； 当 ``kind=Response``
  ## 时， 则将消息作为响应解析。
  ## 
  ## 这个过程是增量进行的， 也就是说， 下一次解析会从上一次解析继续。 

proc parseChunkHeader*(p: var HttpParser, buf: var MarkableCircularBuffer, header: var ChunkHeader): bool = discard
  ## 解析经过 chunked 编码的数据块尺寸和扩展。 
  ## 
  ## 这个过程是增量进行的， 也就是说， 下一次解析会从上一次解析继续。 

proc parseChunkEnd*(p: var HttpParser, buf: var MarkableCircularBuffer, trailers: var seq[string]): bool = discard
  ## 解析经过 chunked 编码的数据结尾。 
  ## 
  ## 这个过程是增量进行的， 也就是说， 下一次解析会从上一次解析继续。 