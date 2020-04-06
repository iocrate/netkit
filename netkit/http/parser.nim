#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import uri, strutils, net
import netkit/buffer/circular, netkit/http/base

const LimitStartLineLen* {.intdefine.} = 8*1024 ## HTTP 起始行的最大长度。 
const LimitHeaderFieldLen* {.intdefine.} = 8*1024 ## HTTP 头字段的最大长度。 
const LimitHeaderFieldCount* {.intdefine.} = 100 ## HTTP 头字段的最大个数。 

type
  HttpParser* = object ## HTTP 包解析器。 
    secondaryBuffer: string
    currentLineLen: int
    currentFieldName: string
    state: HttpParseState
    
  HttpParseState {.pure.} = enum
    METHOD, URL, VERSION, FIELD_NAME, FIELD_VALUE, BODY

  MarkProcessKind {.pure.} = enum
    UNKNOWN, TOKEN, CRLF

proc initHttpParser*(): HttpParser =
  discard

proc popToken(p: var HttpParser, buf: var MarkableCircularBuffer, size: uint16 = 0): string = 
  if p.secondaryBuffer.len > 0:
    p.secondaryBuffer.add(buf.popMarks(size))
    result = p.secondaryBuffer
    p.secondaryBuffer = ""
  else:
    result = buf.popMarks(size)
  if result.len == 0:
    raise newException(ValueError, "Bad Request")

proc popMarksToSecondaryIfFull(p: var HttpParser, buf: var MarkableCircularBuffer) = 
  if buf.len == buf.capacity:
    p.secondaryBuffer.add(buf.popMarks())

proc markChar(p: var HttpParser, buf: var MarkableCircularBuffer, c: char): bool = 
  let oldLen = buf.lenMarks
  result = buf.markUntil(c)
  let newLen = buf.lenMarks
  p.currentLineLen.inc((newLen - oldLen).int)

proc markCharOrCRLF(p: var HttpParser, buf: var MarkableCircularBuffer, c: char): MarkProcessKind = 
  result = MarkProcessKind.UNKNOWN
  let oldLen = buf.lenMarks
  for ch in buf.marks():
    if ch == c:
      result = MarkProcessKind.TOKEN
      break
    elif ch == LF:
      if p.popToken(buf) != CRLF:
        raise newException(EOFError, "无效的 CRLF")
      result = MarkProcessKind.CRLF
      break
  if result == MarkProcessKind.CRLF:
    p.currentLineLen = 0
  else:
    let newLen = buf.lenMarks
    p.currentLineLen.inc((newLen - oldLen).int)

proc markRequestLineChar(p: var HttpParser, buf: var MarkableCircularBuffer, c: char): bool = 
  result = p.markChar(buf, c)
  if p.currentLineLen.int > LimitStartLineLen:
    raise newException(OverflowError, "request-line too long")

proc markRequestLineCharOrCRLF(p: var HttpParser, buf: var MarkableCircularBuffer, c: char): MarkProcessKind = 
  result = p.markCharOrCRLF(buf, c)
  if p.currentLineLen.int > LimitStartLineLen:
    raise newException(IndexError, "request-line too long")

proc markRequestFieldChar(p: var HttpParser, buf: var MarkableCircularBuffer, c: char): bool = 
  result = p.markChar(buf, c)
  if p.currentLineLen.int > LimitHeaderFieldLen:
    raise newException(OverflowError, "request-field too long")

proc parseRequest*(p: var HttpParser, req: var RequestHeader, buf: var MarkableCircularBuffer): bool = 
  ## 解析 HTTP 请求包。这个过程是增量进行的，也就是说，下一次解析会从上一次解析继续。
  result = false
  while true:
    case p.state
    of HttpParseState.METHOD:
      case p.markRequestLineCharOrCRLF(buf, SP)
      of MarkProcessKind.TOKEN:
        req.reqMethod = p.popToken(buf, 1).toHttpMethod()
        p.state = HttpParseState.URL
      of MarkProcessKind.CRLF:
        # [RFC7230-3.5](https://tools.ietf.org/html/rfc7230#section-3.5) 
        # SHOULD ignore at least one empty line (CRLF) received prior to the request-line
        discard
      of MarkProcessKind.UNKNOWN:
        p.popMarksToSecondaryIfFull(buf)
        break
    of HttpParseState.URL:
      if p.markRequestLineChar(buf, SP):
        req.url = p.popToken(buf, 1).decodeUrl()
        p.state = HttpParseState.VERSION
      else:
        p.popMarksToSecondaryIfFull(buf)
        break
    of HttpParseState.VERSION:
      if p.markRequestLineChar(buf, LF):
        p.currentLineLen = 0
        var version = p.popToken(buf, 1)
        # [RFC7230-3.5](https://tools.ietf.org/html/rfc7230#section-3.5) 
        # Although the line terminator for the start-line and header fields is the sequence 
        # CRLF, a recipient MAY recognize a single LF as a line terminator and ignore any 
        # preceding CR.
        let lastIdx = version.len - 1
        if version[lastIdx] == CR:
          version.setLen(lastIdx)
        req.version = version.toHttpVersion()
        p.state = HttpParseState.FIELD_NAME
      else:
        p.popMarksToSecondaryIfFull(buf)
        break
    of HttpParseState.FIELD_NAME:
      case p.markCharOrCRLF(buf, COLON)
      of MarkProcessKind.TOKEN:
        p.state = HttpParseState.FIELD_VALUE
        p.currentFieldName = p.popToken(buf, 1)
        let lastIdx = p.currentFieldName.len - 1
        # [RFC7230-3](https://tools.ietf.org/html/rfc7230#section-3) 
        # A recipient that receives whitespace between the start-line and the first 
        # header field MUST either reject the message as invalid or consume each 
        # whitespace-preceded line without further processing of it.
        if p.currentFieldName[0] in WS:
          raise newException(ValueError, "Bad Request")
        # [RFC7230-3.2.4](https://tools.ietf.org/html/rfc7230#section-3.2.4) 
        # A server MUST reject any received request message that contains whitespace 
        # between a header field-name and colon with a response code of 400.
        if p.currentFieldName[lastIdx] in WS:
          raise newException(ValueError, "Bad Request")
      of MarkProcessKind.CRLF:
        p.currentFieldName = ""
        p.state = HttpParseState.BODY
        return true
      of MarkProcessKind.UNKNOWN:
        p.popMarksToSecondaryIfFull(buf)
        break
    of HttpParseState.FIELD_VALUE:
      # [RFC7230-3.5](https://tools.ietf.org/html/rfc7230#section-3.5) 
      # Although the line terminator for the start-line and header fields is the sequence 
      # CRLF, a recipient MAY recognize a single LF as a line terminator and ignore any 
      # preceding CR.
      for c in buf.marks():
        p.currentLineLen.inc()
        if c == COMMA:
          var fieldValue = p.popToken(buf, 1)
          fieldValue.removePrefix(WS)
          fieldValue.removeSuffix(WS)
          if fieldValue.len == 0:
            raise newException(ValueError, "Bad Request")
          req.fields.add(p.currentFieldName, fieldValue)
        elif c == LF:
          var fieldValue = p.popToken(buf, 1)
          let lastIdx = fieldValue.len - 1
          if lastIdx >= 0 and fieldValue[lastIdx] == CR:
            fieldValue.setLen(lastIdx)
          fieldValue.removePrefix(WS)
          fieldValue.removeSuffix(WS)
          if fieldValue.len == 0:
            raise newException(ValueError, "Bad Request")
          req.fields.add(p.currentFieldName, fieldValue)
          if p.currentLineLen.int > LimitHeaderFieldLen:
            raise newException(OverflowError, "request-field too long")
          p.currentLineLen = 0
          p.state = HttpParseState.FIELD_NAME
          break  
      if p.state == HttpParseState.FIELD_VALUE:
        p.popMarksToSecondaryIfFull(buf)
    of HttpParseState.BODY:
      return true





