#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 

import uri
import strutils
import netkit/buffer/circular
import netkit/http/constants as http_constants
import netkit/http/base
import netkit/http/chunk
import netkit/http/exception

type
  HttpParser* = object ## HTTP packet parser.
    secondaryBuffer: string
    currentLineLen: Natural
    currentFieldName: string
    currentFieldCount: Natural
    state: HttpParseState
    
  HttpParseState {.pure.} = enum
    METHOD, URL, VERSION, FIELD_NAME, FIELD_VALUE, BODY

  MarkProcessKind {.pure.} = enum
    UNKNOWN, TOKEN, CRLF

proc initHttpParser*(): HttpParser =
  ## 
  discard

proc popToken(p: var HttpParser, buf: var MarkableCircularBuffer, size: Natural = 0): string = 
  if p.secondaryBuffer.len > 0:
    p.secondaryBuffer.add(buf.popMarks(size))
    result = p.secondaryBuffer
    p.secondaryBuffer = ""
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

proc markCharOrCRLF(p: var HttpParser, buf: var MarkableCircularBuffer, c: char): MarkProcessKind = 
  result = MarkProcessKind.UNKNOWN
  for ch in buf.marks():
    p.currentLineLen.inc()
    if ch == c:
      result = MarkProcessKind.TOKEN
      return
    elif ch == LF:
      if p.popToken(buf) != CRLF:
        raise newHttpError(Http400)
      result = MarkProcessKind.CRLF
      p.currentLineLen = 0
      return

proc markRequestLineChar(p: var HttpParser, buf: var MarkableCircularBuffer, c: char): bool = 
  result = p.markChar(buf, c)
  if p.currentLineLen.int > LimitStartLineLen:
    raise newHttpError(Http400, "Request Line Too Long")

proc markRequestLineCharOrCRLF(p: var HttpParser, buf: var MarkableCircularBuffer, c: char): MarkProcessKind = 
  result = p.markCharOrCRLF(buf, c)
  if p.currentLineLen.int > LimitStartLineLen:
    raise newHttpError(Http400, "Request Line Too Long")

proc markRequestFieldCharOrCRLF(p: var HttpParser, buf: var MarkableCircularBuffer, c: char): MarkProcessKind = 
  result = p.markCharOrCRLF(buf, c)
  if p.currentLineLen.int > LimitHeaderFieldLen:
    raise newHttpError(Http400, "Header Field Too Long")

proc parseRequest*(p: var HttpParser, req: var RequestHeader, buf: var MarkableCircularBuffer): bool = 
  ## 
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
        var version = p.popToken(buf, 1)
        # [RFC7230-3.5](https://tools.ietf.org/html/rfc7230#section-3.5) 
        # Although the line terminator for the start-line and header fields is the sequence 
        # CRLF, a recipient MAY recognize a single LF as a line terminator and ignore any 
        # preceding CR.
        let lastIdx = version.len - 1
        if version[lastIdx] == CR:
          version.setLen(lastIdx)
        req.version = version.toHttpVersion()
        p.currentLineLen = 0
        p.state = HttpParseState.FIELD_NAME
      else:
        p.popMarksToSecondaryIfFull(buf)
        break
    of HttpParseState.FIELD_NAME:
      case p.markRequestFieldCharOrCRLF(buf, COLON)
      of MarkProcessKind.TOKEN:
        p.currentFieldName = p.popToken(buf, 1)
        # [RFC7230-3](https://tools.ietf.org/html/rfc7230#section-3) 
        # A recipient that receives whitespace between the start-line and the first 
        # header field MUST either reject the message as invalid or consume each 
        # whitespace-preceded line without further processing of it.
        if p.currentFieldName[0] in WS:
          raise newHttpError(Http400, "Invalid Header Field")
        # [RFC7230-3.2.4](https://tools.ietf.org/html/rfc7230#section-3.2.4) 
        # A server MUST reject any received request message that contains whitespace 
        # between a header field-name and colon with a response code of 400.
        if p.currentFieldName[^1] in WS:
          raise newHttpError(Http400, "Invalid Header Field")
        p.state = HttpParseState.FIELD_VALUE
      of MarkProcessKind.CRLF:
        p.currentFieldName = ""
        p.currentLineLen = 0
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
            raise newHttpError(Http400, "Invalid Header Field")
          req.fields.add(p.currentFieldName, fieldValue)
        elif c == LF:
          var fieldValue = p.popToken(buf, 1)
          let lastIdx = fieldValue.len - 1
          if fieldValue[lastIdx] == CR:
            fieldValue.setLen(lastIdx)
          fieldValue.removePrefix(WS)
          fieldValue.removeSuffix(WS)
          if fieldValue.len == 0:
            raise newHttpError(Http400, "Invalid Header Field")
          req.fields.add(p.currentFieldName, fieldValue)
          p.state = HttpParseState.FIELD_NAME
          break  
      if p.state == HttpParseState.FIELD_VALUE:
        p.popMarksToSecondaryIfFull(buf)
      else:
        p.currentFieldCount.inc()
        if p.currentFieldCount > LimitHeaderFieldCount:
          raise newHttpError(Http431)
        if p.currentLineLen > LimitHeaderFieldLen:
          raise newHttpError(Http400, "Header Field Too Long")
        p.currentLineLen = 0
    of HttpParseState.BODY:
      return true

proc parseChunkHeader*(p: var HttpParser, buf: var MarkableCircularBuffer): (bool, ChunkHeader) = 
  ## 
  result[0] = false
  let succ = p.markChar(buf, LF)
  if p.currentLineLen.int > LimitChunkHeaderLen:
    raise newHttpError(Http400, "Chunk Header Too Long")
  if succ:
    var line = p.popToken(buf, 1)
    let lastIdx = line.len - 1
    if lastIdx > 0 and line[lastIdx] == CR:
      line.setLen(lastIdx)
    p.currentLineLen = 0
    result[0] = true
    result[1] = line.parseChunkHeader()
  else:
    p.popMarksToSecondaryIfFull(buf)
    
proc parseChunkEnd*(p: var HttpParser, buf: var MarkableCircularBuffer): (bool, string) = 
  ## 
  result[0] = false
  let succ = p.markChar(buf, LF)
  if p.currentLineLen.int > LimitChunkDataLen:
    raise newHttpError(Http400, "Chunk Trailer Too Long")
  if succ:
    result[1] = p.popToken(buf, 1)
    let lastIdx = result[1].len - 1
    if lastIdx > 0 and result[1][lastIdx] == CR:
      result[1].setLen(lastIdx)
    result[0] = true
    p.currentLineLen = 0
  else:
    p.popMarksToSecondaryIfFull(buf)