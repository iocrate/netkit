#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import buffer

# [RFC5234](https://tools.ietf.org/html/rfc5234#appendix-B.1)
const SP = '\x20'
const CR = '\x0D'
const LF = '\x0A'
const CRLF = "\x0D\x0A"
const COLON = ':'

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
    state: HttpParseState

    reqMethod: string
    url: string
    version: string
    

  HttpParseState* {.pure.} = enum
    METHOD, URL, VERSION, FIELD_NAME, FIELD_VALUE, BODY

  MarkResultKind {.pure.} = enum
    UNKNOWN, TOKEN, CRLF

proc popToken(p: var HttpParser, size: uint16 = 0): string = 
  if p.secondaryBuffer.len > 0:
    p.secondaryBuffer.add(p.buffer.popMarks(size))
    result = p.secondaryBuffer
    p.secondaryBuffer = ""
  else:
    result = p.buffer.popMarks(size)

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

proc markCharOrCRLF(p: var HttpParser, c: char): MarkResultKind = 
  result = MarkResultKind.UNKNOWN
  let oldLen = p.buffer.lenMarks
  for ch in p.buffer.marks():
    if ch == c:
      result = MarkResultKind.TOKEN
    elif ch == LF:
      if p.popToken() != CRLF:
        raise newException(EOFError, "无效的 CRLF")
      result = MarkResultKind.CRLF
  if result == MarkResultKind.CRLF:
    p.currentLineLen = 0
  else:
    let newLen = p.buffer.lenMarks
    p.currentLineLen.inc((newLen - oldLen).int)

proc markRequestLineCharOrCRLF(p: var HttpParser, c: char): MarkResultKind = 
  result = p.markCharOrCRLF(c)
  if p.currentLineLen.int > LimitRequestLine:
    raise newException(IndexError, "request-line too long")

proc markRequestFieldCharOrCRLF(p: var HttpParser, c: char): MarkResultKind = 
  result = p.markCharOrCRLF(c)
  if p.currentLineLen.int > LimitRequestFieldSize:
    raise newException(IndexError, "request-field too long")

proc parseRequest*(p: var HttpParser): bool = 
  ## 
  result = false
  while true:
    case p.state
    of HttpParseState.METHOD:
      case p.markRequestLineCharOrCRLF(SP)
      of MarkResultKind.TOKEN:
        p.state = HttpParseState.URL
        p.reqMethod = p.popToken(1)
        # TODO: normalize METHOD
      of MarkResultKind.CRLF:
        discard
      of MarkResultKind.UNKNOWN:
        p.popMarksToLargerIfFull()
        break
    of HttpParseState.URL:
      if p.markRequestLineChar(SP):
        p.state = HttpParseState.VERSION
        p.url = p.popToken(1)
        # TODO: normalize URL
      else:
        p.popMarksToLargerIfFull()
        break
    of HttpParseState.VERSION:
      if p.markRequestLineChar(LF):
        p.state = HttpParseState.FIELD_NAME
        p.currentLineLen = 0
        p.version = p.popToken(1)
        let lastIdx = p.version.len - 1
        if p.version[lastIdx] == CR:
          p.version.setLen(lastIdx)
        # TODO: normalize Version
      else:
        p.popMarksToLargerIfFull()
        break
    of HttpParseState.FIELD_NAME:
      case p.markRequestFieldCharOrCRLF(COLON)
      of MarkResultKind.TOKEN:
        p.state = HttpParseState.FIELD_VALUE
        # p.headers[p.popToken(1)] = ""
        # TODO: normalize Name
      of MarkResultKind.CRLF:
        p.state = HttpParseState.BODY
      of MarkResultKind.UNKNOWN:
        p.popMarksToLargerIfFull()
        break
    of HttpParseState.FIELD_VALUE:
      if p.markRequestFieldChar(LF): 
        p.state = HttpParseState.FIELD_NAME
        p.currentLineLen = 0
        # p.headers[headerName] = p.popToken(1)
        # if p.headers[headerName][p.headers[headerName].len-1] == CR:
        #   p.headers[headerName].setLen(p.headers[headerName].len - 1)
        # TODO: normalize Value
      else:
        p.popMarksToLargerIfFull()
        break
    of HttpParseState.BODY:
      discard

when isMainModule:
  import net
  while true:
    var parser: HttpParser
    var socket: Socket
    let (regionPtr, regionLen) = parser.buffer.next()
    let readLen = socket.recv(regionPtr, regionLen.int)
    if readLen == 0:
      ## TODO: close socket 对方关闭了连接
      discard 
    while true:
      case parser.state
      of HttpParseState.METHOD:
        if parser.markRequestLineChar(SP):
          parser.state = HttpParseState.URL
          parser.reqMethod = parser.popToken(1)
          # TODO: normalize Method
        else:
          # parser.popMarksToLargerIfFull()
          break
      of HttpParseState.URL:
        if parser.markRequestLineChar(SP):
          parser.state = HttpParseState.VERSION
          parser.url = parser.popToken(1)
          # TODO: normalize URL
        else:
          parser.popMarksToLargerIfFull()
          break
      of HttpParseState.VERSION:
        if parser.markRequestLineChar(LF):
          parser.state = HttpParseState.FIELD_NAME
          parser.currentLineLen = 0
          parser.version = parser.popToken(1)
          if parser.version[parser.version.len-1] == CR:
            parser.version.setLen(parser.version.len - 1)
          # TODO: normalize Version
        else:
          # parser.popMarksToLargerIfFull()
          break
      of HttpParseState.FIELD_NAME:
        let oldLen = parser.buffer.lenMarks
        var succ = false
        for c in parser.buffer.marks():
          if c == COLON:
            succ = true
          elif c == LF:
            parser.state = HttpParseState.BODY
            var a = parser.popToken(1)
            if not ((a[0] == CR and a.len == 1) or a.len == 0):
              raise newException(IndexError, "无效的 CRLF")
            continue
        let newLen = parser.buffer.lenMarks
        parser.currentLineLen.inc((newLen - oldLen).int)
        if parser.currentLineLen.int > LimitRequestFieldSize:
          raise newException(IndexError, "")
        if succ: # TODO: 常量
          parser.state = HttpParseState.FIELD_VALUE
          # parser.headers[parser.popToken(1)] = ""
          # TODO: normalize Name
        else:
          parser.popMarksToLargerIfFull()
          break
      of HttpParseState.FIELD_VALUE:
        if parser.markRequestFieldChar(LF): # TODO: 常量
          parser.state = HttpParseState.FIELD_NAME
          parser.currentLineLen = 0
          # parser.headers[headerName] = parser.popToken(1)
          # if parser.headers[headerName][parser.headers[headerName].len-1] == CR:
          #   parser.headers[headerName].setLen(parser.headers[headerName].len - 1)
          # TODO: normalize Value
        else:
          parser.popMarksToLargerIfFull()
          break
      of HttpParseState.BODY:
        discard
    


