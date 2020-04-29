#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module implements an incremental HTTP parser. This parser supports parsing both request 
## messages and response messages. 
## 
## This parser is incremental, meaning that the message can be parsed continuously regardless 
## of whether the message is delivered at once or divided into multiple parts. This makes the 
## parser particularly suitable for complex IO transfer environments.
## 
## Usage
## ========================
## 
## .. container:: r-fragment
## 
##   Parse message header
##   ------------------------------
## 
##   For example:
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
##   Another example:
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
##     # parse first
##     let messageRequestLine = "GET / HTTP/1.1\r\n"
##     buffer.add(messageRequestLine.cstring, messageRequestLine.len)
##     assert parser.parseHttpHeader(buffer, header) == false
##     buffer.del(messageRequestLine.len)
##     
##     # parse second
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
##   Parse chunk header
##   ------------------------------
## 
##   For example:
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
##   Another example:
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
##     # parse first
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
##   Parse chunk tail
##   ------------------------------
## 
##   For example:
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
##   Another example:
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
##     # parse first
##     let s = "\0\r\nExpires": "Wed, 21 Oct 2015 07:28:00 GMT\r\n\r\n"
##     buffer.add(s.cstring, s.len)
##     assert parser.parseChunkEnd(buffer, trailers) == true
##     buffer.del(s.len)
##     
##     assert trailers[0] == "Expires": "Wed, 21 Oct 2015 07:28:00 GMT"
## 
##   See **chunk** module and **metadata** module for more information about terminating chunk and trailers.

import uri
import strutils
import netkit/buffer/circular
import netkit/http/limits
import netkit/http/exception
import netkit/http/spec
import netkit/http/httpmethod
import netkit/http/version
import netkit/http/status
import netkit/http/headerfield
import netkit/http/header
import netkit/http/chunk

type
  HttpParser* = object ## HTTP message parser.
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
  ## Initialize a ``HttpParser``.
  discard

proc clear*(p: var HttpParser) = discard
  ## Reset this parser to clear all status. 
  ## 
  ## Since ``HttpParser`` is an incremental, various state will be saved during the parsing process. 
  ## This proc resets all states in order to start a new parsing process.
  ## 
proc parseHttpHeader*(p: var HttpParser, buf: var MarkableCircularBuffer, header: var HttpHeader): bool = discard
  ## Parses the header of a HTTP message. ``buf`` specifies a circular buffer, which stores the data to be parsed. ``header`` 
  ## specifies the message header object that output when the parsing is complete. Returns ``true`` if the parsing is complete.
  ## 
  ## Depending on the value of the ``kind`` attribute of ``header``, different resolutions are taken. When ``kind=Request``, 
  ## a message is parsed as a request. When ``kind=Response``, a message is parsed as a request.
  ## 
  ## This process is performed incrementally, that is, the next parsing will continue from the previous 
  ## position.

proc parseChunkHeader*(
  p: var HttpParser, 
  buf: var MarkableCircularBuffer,
  header: var ChunkHeader
): bool = discard
  ## Parse the size and extensions of a data chunk that encoded by ``Transfor-Encoding: chunked``.
  ## 
  ## This process is performed incrementally, that is, the next parsing will continue from the previous 
  ## position.

proc parseChunkEnd*(
  p: var HttpParser, 
  buf: var MarkableCircularBuffer, 
  trailers: var seq[string]
): bool = discard
  ## Parse the tail of a message that encoded by ``Transfor-Encoding: chunked``.
  ## 
  ## This process is performed incrementally, that is, the next parsing will continue from the previous 
  ## position.