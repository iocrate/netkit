#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import buffer, uri, tables

# [RFC5234](https://tools.ietf.org/html/rfc5234#appendix-B.1)
const SP = '\x20'
const CR = '\x0D'
const LF = '\x0A'
const COLON = ':'
const HTAB = '\x09'
const CRLF = "\x0D\x0A"
const WS = {SP, HTAB}

const LimitRequestLine* {.intdefine.} = 8*1024
const LimitRequestFieldSize* {.intdefine.} = 8*1024
const LimitRequestFieldCount* {.intdefine.} = 100

type
  HttpCode* = distinct range[0 .. 599]

  HttpMethod* = enum
    HttpHead,        ## Asks for the response identical to the one that would
                     ## correspond to a GET request, but without the response
                     ## body.
    HttpGet,         ## Retrieves the specified resource.
    HttpPost,        ## Submits data to be processed to the identified
                     ## resource. The data is included in the body of the
                     ## request.
    HttpPut,         ## Uploads a representation of the specified resource.
    HttpDelete,      ## Deletes the specified resource.
    HttpTrace,       ## Echoes back the received request, so that a client
                     ## can see what intermediate servers are adding or
                     ## changing in the request.
    HttpOptions,     ## Returns the HTTP methods that the server supports
                     ## for specified address.
    HttpConnect,     ## Converts the request connection to a transparent
                     ## TCP/IP tunnel, usually used for proxies.
    HttpPatch        ## Applies partial modifications to a resource.

  HttpParser* = object
    buffer: MarkableCircularBuffer
    secondaryBuffer: string
    currentLineLen: int
    currentFieldName: string
    currentRequest: Request
    state: HttpParseState

  Request* = ref object
    reqMethod: HttpMethod
    url: string
    version: tuple[orig: string, major, minor: int]
    headers: Table[string, seq[string]]  # TODO 开发 distinct Table 接口
    contentLen: int
    transferEncoding: TransferEncoding
    
  HttpParseState {.pure.} = enum
    INIT, statMethod, URL, VERSION, FIELD_NAME, FIELD_VALUE, BODY

  MarkProcessKind {.pure.} = enum
    UNKNOWN, TOKEN, CRLF

  TransferEncoding {.pure.} = enum
    UNKNOWN, CHUNKED

proc popToken(p: var HttpParser, size: uint16 = 0): string = 
  if p.secondaryBuffer.len > 0:
    p.secondaryBuffer.add(p.buffer.popMarks(size))
    result = p.secondaryBuffer
    p.secondaryBuffer = ""
  else:
    result = p.buffer.popMarks(size)
  if result.len == 0:
    raise newException(ValueError, "Bad Request")

proc popMarksToLargerIfFull(p: var HttpParser) = 
  if p.buffer.len == p.buffer.capacity:
    p.secondaryBuffer.add(p.buffer.popMarks())

proc markChar(p: var HttpParser, c: char): bool = 
  let oldLen = p.buffer.lenMarks
  result = p.buffer.markUntil(c)
  let newLen = p.buffer.lenMarks
  p.currentLineLen.inc((newLen - oldLen).int)

proc markRequestLineChar(p: var HttpParser, c: char): bool = 
  result = p.markChar(c)
  if p.currentLineLen.int > LimitRequestLine:
    raise newException(OverflowError, "request-line too long")

proc markRequestFieldChar(p: var HttpParser, c: char): bool = 
  result = p.markChar(c)
  if p.currentLineLen.int > LimitRequestFieldSize:
    raise newException(OverflowError, "request-field too long")

proc markCharOrCRLF(p: var HttpParser, c: char): MarkProcessKind = 
  result = MarkProcessKind.UNKNOWN
  let oldLen = p.buffer.lenMarks
  for ch in p.buffer.marks():
    if ch == c:
      result = MarkProcessKind.TOKEN
    elif ch == LF:
      if p.popToken() != CRLF:
        raise newException(EOFError, "无效的 CRLF")
      result = MarkProcessKind.CRLF
  if result == MarkProcessKind.CRLF:
    p.currentLineLen = 0
  else:
    let newLen = p.buffer.lenMarks
    p.currentLineLen.inc((newLen - oldLen).int)

proc markRequestLineCharOrCRLF(p: var HttpParser, c: char): MarkProcessKind = 
  result = p.markCharOrCRLF(c)
  if p.currentLineLen.int > LimitRequestLine:
    raise newException(IndexError, "request-line too long")

proc markRequestFieldCharOrCRLF(p: var HttpParser, c: char): MarkProcessKind = 
  result = p.markCharOrCRLF(c)
  if p.currentLineLen.int > LimitRequestFieldSize:
    raise newException(IndexError, "request-field too long")

proc parseHttpMethod(m: string): HttpMethod =
  result =
    case m
    of "GET": HttpGet
    of "POST": HttpPost
    of "HEAD": HttpHead
    of "PUT": HttpPut
    of "DELETE": HttpDelete
    of "PATCH": HttpPatch
    of "OPTIONS": HttpOptions
    of "CONNECT": HttpConnect
    of "TRACE": HttpTrace
    else: raise newException(ValueError, "Not Implemented")

proc parseHttpVersion(version: string): tuple[orig: string, major, minor: int] =
  if version.len != 8 or version[6] != '.':
    raise newException(ValueError, "Bad Request")
  let major = version[5].ord - 48
  let minor = version[7].ord - 48
  if major != 1 or minor != 1 or minor != 0:
    raise newException(ValueError, "Bad Request")
  const name = "HTTP/"
  var i = 0
  while i < 5:
    if name[i] != version[i]:
      raise newException(ValueError, "Bad Request")
    i.inc()
  result = (version, major, minor)

proc parseRequest*(p: var HttpParser): bool = 
  ## 解析 HTTP 请求包。这个过程是增量进行的，也就是说，下一次解析会从上一次解析继续。
  result = false
  while true:
    case p.state
    of HttpParseState.INIT:
      p.currentRequest = new(Request)
      p.currentRequest.headers = initTable[string, seq[string]](modeCaseInsensitive)
      p.state = HttpParseState.METHOD
    of HttpParseState.METHOD:
      # [RFC7230-3.5](https://tools.ietf.org/html/rfc7230#section-3.5) 
      # SHOULD ignore at least one empty line (CRLF) received prior to the request-line
      case p.markRequestLineCharOrCRLF(SP)
      of MarkProcessKind.TOKEN:
        p.currentRequest.reqMethod = p.popToken(1).parseHttpMethod()
        p.state = HttpParseState.URL
      of MarkProcessKind.CRLF:
        discard
      of MarkProcessKind.UNKNOWN:
        p.popMarksToLargerIfFull()
        break
    of HttpParseState.URL:
      if p.markRequestLineChar(SP):
        p.currentRequest.url = p.popToken(1).decode
        p.state = HttpParseState.VERSION
      else:
        p.popMarksToLargerIfFull()
        break
    of HttpParseState.VERSION:
      # [RFC7230-3.5](https://tools.ietf.org/html/rfc7230#section-3.5) 
      # Although the line terminator for the start-line and header fields is the sequence 
      # CRLF, a recipient MAY recognize a single LF as a line terminator and ignore any 
      # preceding CR.
      if p.markRequestLineChar(LF):
        p.currentLineLen = 0
        let version = p.popToken(1)
        let lastIdx = version.len - 1
        if version[lastIdx] == CR:
          version.setLen(lastIdx)
        p.currentRequest.version = version.parseHttpVersion()
        p.state = HttpParseState.FIELD_NAME
      else:
        p.popMarksToLargerIfFull()
        break
    of HttpParseState.FIELD_NAME:
      case p.markRequestFieldCharOrCRLF(COLON)
      of MarkProcessKind.TOKEN:
        p.state = HttpParseState.FIELD_VALUE
        p.currentFieldName = p.popToken(1)
        let lastIdx = p.currentFieldName.len - 1
        # [RFC7230-3](https://tools.ietf.org/html/rfc7230#section-3) 
        # A recipient that receives whitespace between the start-line and the first 
        # header field MUST either reject the message as invalid or consume each 
        # whitespace-preceded line without further processing of it.
        if p.currentFieldName[0] == SP or p.currentFieldName[0] == HTAB:
          raise newException(ValueError, "Bad Request")
        # [RFC7230-3.2.4](https://tools.ietf.org/html/rfc7230#section-3.2.4) 
        # A server MUST reject any received request message that contains whitespace 
        # between a header field-name and colon with a response code of 400.
        if p.currentFieldName[lastIdx] == CR or p.currentFieldName[lastIdx] == HTAB:
          raise newException(ValueError, "Bad Request")
      of MarkProcessKind.CRLF:
        p.currentFieldName = ""
        p.state = HttpParseState.BODY

        # TODO: 更多 Headers 解析存储
        # TODO: Set-Cookie 允许多个 Headers 并存
        # TODO: strtab => table
        # p.currentRequest.contentLen = p.currentRequest.headers.getOrDefault("Content-Length", "0").parseInt()
        # if p.currentRequest.headers.getOrDefault("Transfer-Encoding") == "chunked":
        #   p.currentRequest.transferEncoding = TransferEncoding.CHUNKED



        return true
      of MarkProcessKind.UNKNOWN:
        p.popMarksToLargerIfFull()
        break
    of HttpParseState.FIELD_VALUE:
      # [RFC7230-3.5](https://tools.ietf.org/html/rfc7230#section-3.5) 
      # Although the line terminator for the start-line and header fields is the sequence 
      # CRLF, a recipient MAY recognize a single LF as a line terminator and ignore any 
      # preceding CR.
      if p.markRequestFieldChar(LF): 
        let fieldValue = p.popToken(1).removePrefix(WS).removeSuffix(WS)
        if fieldValue.len == 0:
          raise newException(ValueError, "Bad Request")
        p.currentRequest.headers[p.currentFieldName].add(fieldValue.shallowCopy())
        p.currentLineLen = 0
        p.state = HttpParseState.FIELD_NAME
      else:
        p.popMarksToLargerIfFull()
        break
    of HttpParseState.BODY:
      return true

when isMainModule:
  import net

  var parser: HttpParser
  var socket: Socket

  while true:
    let (regionPtr, regionLen) = parser.buffer.next()
    let readLen = socket.recv(regionPtr, regionLen.int)
    if readLen == 0:
      ## TODO: close socket 对方关闭了连接
      discard 
    parser.buffer.pack(readLen)
    if not parser.parseRequest():
      continue

    var req = parser.currentRequest


