#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import uri
import strutils
import netkit/buffer/circular
import netkit/http/base
import netkit/http/constants as http_constants

type
  HttpParser* = object ## HTTP 包解析器。 
    secondaryBuffer: string
    currentLineLen: Natural
    currentFieldName: string
    state: HttpParseState
    
  HttpParseState {.pure.} = enum
    METHOD, URL, VERSION, FIELD_NAME, FIELD_VALUE, BODY

  MarkProcessKind {.pure.} = enum
    UNKNOWN, TOKEN, CRLF

proc initHttpParser*(): HttpParser = discard
  ## 初始化一个 ``HttpParser`` 对象。 

proc parseRequest*(p: var HttpParser, req: var RequestHeader, buf: var MarkableCircularBuffer): bool = discard
  ## 解析 HTTP 请求包。这个过程是增量进行的，也就是说，下一次解析会从上一次解析继续。

proc parseChunkSizer*(p: var HttpParser, buf: var MarkableCircularBuffer): (bool, ChunkSizer) = discard
  ## 解析 HTTP 请求体中 ``Transfer-Encoding: chunked`` 编码的尺寸部分。 