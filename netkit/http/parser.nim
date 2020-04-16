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
    startLineState: StartLineState
    
  HttpParseState {.pure.} = enum
    StartLine, FieldName, FieldValue, Body

  StartLineState {.pure.} = enum
    Method, Url, Version, Code, Reason

  MarkProcessState {.pure.} = enum
    Unknown, Token, Crlf

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
  ## 
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
              header.reqMethod = p.popToken(buf, 1).toHttpMethod()
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
              header.version = version.toHttpVersion()
              p.currentLineLen = 0
              p.state = HttpParseState.FieldName
              break
            else:
              p.popMarksToSecondaryIfFull(buf)
              return
          else:
            raise newException(ValueError, "Imposible StartLineState " & $p.startLineState)
      of HttpHeaderKind.Response:
        raise newException(Exception, "Not Implemented yet")
    of HttpParseState.FieldName:
      case p.markRequestFieldCharOrCRLF(buf, COLON)
      of MarkProcessState.Token:
        p.currentFieldName = p.popToken(buf, 1)
        # [RFC7230-3](https://tools.ietf.org/html/rfc7230#section-3) 
        # A recipient that receives whitespace between the start-line and the first 
        # header field MUST either reject the message as invalid or consume each 
        # whitespace-preceded line without further processing of it.
        if p.currentFieldName[0] in WS:
          raise newHttpError(Http400, "Bad Header Field")
        # [RFC7230-3.2.4](https://tools.ietf.org/html/rfc7230#section-3.2.4) 
        # A server MUST reject any received request message that contains whitespace 
        # between a header field-name and colon with a response code of 400.
        if p.currentFieldName[^1] in WS:
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
        fieldValue.removePrefix(WS)
        fieldValue.removeSuffix(WS)
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
  ## 
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
    let res = token.parseChunkHeader()
    header.size = res.size
    header.extensions.shallowCopy(res.extensions)
  else:
    p.popMarksToSecondaryIfFull(buf)

proc parseChunkEnd*(
  p: var HttpParser, 
  buf: var MarkableCircularBuffer, 
  trailer: var seq[string]
): bool = 
  ## 
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
      trailer.add(token)
    else:
      p.popMarksToSecondaryIfFull(buf)
      break
  