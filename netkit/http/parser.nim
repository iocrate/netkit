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
##     let s = "\0\r\nExpires": "Wed, 21 Oct 2015 07:28:00 GMT\r\n\r\n"
##     buffer.add(s.cstring, s.len)
##     assert parser.parseChunkEnd(buffer, trailers) == true
##     buffer.del(s.len)
##     
##     assert trailers[0] == "Expires": "Wed, 21 Oct 2015 07:28:00 GMT"
## 
##   See **chunk** module and **metadata** module for more information about terminating chunk and trailers.


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
  HttpParser* = object ## HTTP message parser.
    secondaryBuffer: string
    currentLineLen: Natural
    currentFieldName: string
    currentFieldCount: Natural
    state*: HttpParseState
    startLineState: StartLineState
    
  HttpParseState* {.pure.} = enum
    StartLine, FieldName, FieldValue, Body

  StartLineState {.pure.} = enum
    Method, Url, Version, Code, Reason

  MarkProcessState {.pure.} = enum
    Unknown, Token, Crlf

proc initHttpParser*(): HttpParser =
  ## Initialize a ``HttpParser``.
  discard

proc clear*(p: var HttpParser) = 
  ## Reset this parser to clear all status. 
  ## 
  ## Since ``HttpParser`` is an incremental, various state will be saved during the parsing process. 
  ## This proc resets all states in order to start a new parsing process.
  p.secondaryBuffer = ""
  p.currentLineLen = 0
  p.currentFieldName = ""
  p.currentFieldCount = 0
  p.state = HttpParseState.StartLine
  p.startLineState = StartLineState.Method

proc popToken(p: var HttpParser, buf: var MarkableCircularBuffer, size: Natural = 0): string = 
  if p.secondaryBuffer.len > 0:
    p.secondaryBuffer.add(buf.popMarks(size))
    result = move(p.secondaryBuffer)
    # p.secondaryBuffer = "" # not need anymore
  else:
    result = buf.popMarks(size)
  if result.len == 0:
    raise newHttpError(Http400)

proc popMarksToSecondaryIfFull(p: var HttpParser, buf: var MarkableCircularBuffer) = 
  if buf.len == buf.capacity:
    p.secondaryBuffer.add(buf.popMarks())

proc markChar(p: var HttpParser, buf: var MarkableCircularBuffer, c: char): bool = 
  let oldLen = buf.lenMarks
  result = buf.markUntil(c)
  let newLen = buf.lenMarks
  p.currentLineLen.inc((newLen - oldLen).int)

proc markCharOrCRLF(p: var HttpParser, buf: var MarkableCircularBuffer, c: char): MarkProcessState = 
  result = MarkProcessState.UNKNOWN
  for ch in buf.marks():
    p.currentLineLen.inc()
    if ch == c:
      result = MarkProcessState.TOKEN
      return
    elif ch == LF:
      let s = p.popToken(buf)
      if s.len > 2 or (s.len == 2 and s[0] != CR):
        raise newHttpError(Http400)
      result = MarkProcessState.CRLF
      p.currentLineLen = 0
      return

proc markRequestLineChar(p: var HttpParser, buf: var MarkableCircularBuffer, c: char): bool = 
  result = p.markChar(buf, c)
  if p.currentLineLen.int > LimitStartLineLen:
    raise newHttpError(Http400, "Request Line Too Long")

proc markRequestLineCharOrCRLF(p: var HttpParser, buf: var MarkableCircularBuffer, c: char): MarkProcessState = 
  result = p.markCharOrCRLF(buf, c)
  if p.currentLineLen.int > LimitStartLineLen:
    raise newHttpError(Http400, "Request Line Too Long")

proc markRequestFieldChar(p: var HttpParser, buf: var MarkableCircularBuffer, c: char): bool = 
  result = p.markChar(buf, c)
  if p.currentLineLen.int > LimitHeaderFieldLen:
    raise newHttpError(Http400, "Header Field Too Long")

proc markRequestFieldCharOrCRLF(p: var HttpParser, buf: var MarkableCircularBuffer, c: char): MarkProcessState = 
  result = p.markCharOrCRLF(buf, c)
  if p.currentLineLen.int > LimitHeaderFieldLen:
    raise newHttpError(Http400, "Header Field Too Long")

proc parseHttpHeader*(p: var HttpParser, buf: var MarkableCircularBuffer, header: var HttpHeader): bool = 
  ## Parses the header of a HTTP message. ``buf`` specifies a circular buffer, which stores the data to be parsed. ``header`` 
  ## specifies the message header object that output when the parsing is complete. Returns ``true`` if the parsing is complete.
  ## 
  ## Depending on the value of the ``kind`` attribute of ``header``, different resolutions are taken. When ``kind=Request``, 
  ## a message is parsed as a request. When ``kind=Response``, a message is parsed as a request.
  ## 
  ## This process is performed incrementally, that is, the next parsing will continue from the previous 
  ## position.
  result = false
  while true:
    case p.state
    of HttpParseState.StartLine:
      case header.kind
      of HttpHeaderKind.Request:
        while true:
          case p.startLineState
          of StartLineState.Method:
            case p.markRequestLineCharOrCRLF(buf, SP)
            of MarkProcessState.Token:
              header.reqMethod = p.popToken(buf, 1).parseHttpMethod()
              p.startLineState = StartLineState.Url
            of MarkProcessState.CRLF:
              # [RFC7230-3.5](https://tools.ietf.org/html/rfc7230#section-3.5) 
              # SHOULD ignore at least one empty line (CRLF) received prior to the request-line
              discard
            of MarkProcessState.UNKNOWN:
              p.popMarksToSecondaryIfFull(buf)
              return
          of StartLineState.Url:
            if p.markRequestLineChar(buf, SP):
              header.url = p.popToken(buf, 1).decodeUrl()
              p.startLineState = StartLineState.Version
            else:
              p.popMarksToSecondaryIfFull(buf)
              return
          of StartLineState.Version:
            if p.markRequestLineChar(buf, LF):
              var version = p.popToken(buf, 1)
              # [RFC7230-3.5](https://tools.ietf.org/html/rfc7230#section-3.5) 
              # Although the line terminator for the start-line and header fields is the sequence 
              # CRLF, a recipient MAY recognize a single LF as a line terminator and ignore any 
              # preceding CR.
              let lastIdx = version.len - 1
              if version[lastIdx] == CR:
                version.setLen(lastIdx)
              header.version = version.parseHttpVersion()
              p.currentLineLen = 0
              p.state = HttpParseState.FieldName
              break
            else:
              p.popMarksToSecondaryIfFull(buf)
              return
          else:
            raise newException(Exception, "Imposible StartLineState " & $p.startLineState)
      of HttpHeaderKind.Response:
        raise newException(Exception, "Not implemented yet")
    of HttpParseState.FieldName:
      case p.markRequestFieldCharOrCRLF(buf, COLON)
      of MarkProcessState.Token:
        p.currentFieldName = p.popToken(buf, 1)
        # [RFC7230-3](https://tools.ietf.org/html/rfc7230#section-3) 
        # A recipient that receives whitespace between the start-line and the first 
        # header field MUST either reject the message as invalid or consume each 
        # whitespace-preceded line without further processing of it.
        if p.currentFieldName[0] in WSP:
          raise newHttpError(Http400, "Bad Header Field")
        # [RFC7230-3.2.4](https://tools.ietf.org/html/rfc7230#section-3.2.4) 
        # A server MUST reject any received request message that contains whitespace 
        # between a header field-name and colon with a response code of 400.
        if p.currentFieldName[^1] in WSP:
          raise newHttpError(Http400, "Bad Header Field")
        p.state = HttpParseState.FieldValue
      of MarkProcessState.Crlf:
        p.currentFieldName = ""
        p.currentLineLen = 0
        p.state = HttpParseState.Body
        return true
      of MarkProcessState.Unknown:
        p.popMarksToSecondaryIfFull(buf)
        break
    of HttpParseState.FieldValue:
      if p.markRequestFieldChar(buf, LF):
        # [RFC7230-3.5](https://tools.ietf.org/html/rfc7230#section-3.5) 
        # Although the line terminator for the start-line and header fields is the sequence 
        # CRLF, a recipient MAY recognize a single LF as a line terminator and ignore any 
        # preceding CR.
        var fieldValue = p.popToken(buf, 1)
        let lastIdx = fieldValue.len - 1
        if fieldValue[lastIdx] == CR:
          fieldValue.setLen(lastIdx)
        fieldValue.removePrefix(WSP)
        fieldValue.removeSuffix(WSP)
        if fieldValue.len == 0:
          raise newHttpError(Http400, "Bad Header Field")
        header.fields.add(p.currentFieldName, fieldValue)
        p.currentFieldCount.inc()
        if p.currentFieldCount > LimitHeaderFieldCount:
          raise newHttpError(Http431)
        p.currentLineLen = 0
        p.state = HttpParseState.FieldName
      else:
        p.popMarksToSecondaryIfFull(buf)
        return
    of HttpParseState.Body:
      return true

proc parseChunkHeader*(
  p: var HttpParser, 
  buf: var MarkableCircularBuffer,
  header: var ChunkHeader
): bool = 
  ## Parse the size and extensions of a data chunk that encoded by ``Transfor-Encoding: chunked``.
  ## 
  ## This process is performed incrementally, that is, the next parsing will continue from the previous 
  ## position.
  result = false
  let succ = p.markChar(buf, LF)
  if p.currentLineLen.int > LimitChunkHeaderLen:
    raise newHttpError(Http400, "Chunk Header Too Long")
  if succ:
    var token = p.popToken(buf, 1)
    let lastIdx = token.len - 1
    if lastIdx > 0 and token[lastIdx] == CR:
      token.setLen(lastIdx)
    p.currentLineLen = 0
    result = true
    var res = token.parseChunkHeader()
    header.size = res.size
    header.extensions = move(res.extensions)
  else:
    p.popMarksToSecondaryIfFull(buf)

proc parseChunkEnd*(
  p: var HttpParser, 
  buf: var MarkableCircularBuffer, 
  trailers: var seq[string]
): bool = 
  ## Parse the tail of a message that encoded by ``Transfor-Encoding: chunked``.
  ## 
  ## This process is performed incrementally, that is, the next parsing will continue from the previous 
  ## position.
  result = false
  while true:
    let succ = p.markChar(buf, LF)
    if p.currentLineLen.int > LimitChunkTrailerLen:
      raise newHttpError(Http400, "Chunk Trailer Too Long")
    if succ:
      var token = p.popToken(buf, 1)
      let lastIdx = token.len - 1
      if lastIdx > 0 and token[lastIdx] == CR:
        token.setLen(lastIdx)
      p.currentLineLen = 0
      if token.len == 0:
        return true
      trailers.add(token)
    else:
      p.popMarksToSecondaryIfFull(buf)
      break
  