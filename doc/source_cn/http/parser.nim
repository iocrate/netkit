#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

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
  HttpParser* = object ## HTTP 包解析器。 
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
  ## 

proc parseHttpHeader*(p: var HttpParser, buf: var MarkableCircularBuffer, header: var HttpHeader): bool = discard
  ## 解析 HTTP 请求包。这个过程是增量进行的，也就是说，下一次解析会从上一次解析继续。

proc parseChunkHeader*(p: var HttpParser, buf: var MarkableCircularBuffer, header: var ChunkHeader): bool = discard
  ## 解析 HTTP 请求体中 ``Transfer-Encoding: chunked`` 编码的尺寸部分。 

proc parseChunkEnd*(p: var HttpParser, buf: var MarkableCircularBuffer, trailer: var seq[string]): bool = discard
  ## 解析 HTTP 请求体中 ``Transfer-Encoding: chunked`` 编码的结尾部分。 