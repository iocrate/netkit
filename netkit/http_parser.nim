#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import buffer

# [RFC5234](https://tools.ietf.org/html/rfc5234#appendix-B.1)
const SP   = '\x20'
const CR   = '\x0D'
const LF   = '\x0A'
const CRLF = "\x0D\x0A"

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
    largeBuffer: string

    currentLineLen: int

    reqMethod: string
    url: string
    version: string

    state: HttpParseState
    

  HttpParseState* {.pure.} = enum
    METHOD, URL, VERSION, HEADER_NAME, HEADER_VALUE, BODY

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

proc popToken(p: var HttpParser, size: uint16): string = 
  if p.largeBuffer.len > 0:
    p.largeBuffer.add(p.buffer.popMarks(size))
    result = p.largeBuffer
    p.largeBuffer = ""
  else:
    result = p.buffer.popMarks(size)

proc popMarksToLargerIfFull(p: var HttpParser) = 
  if p.buffer.len == p.buffer.capacity:
    if p.largeBuffer.len > 0:
      p.largeBuffer.add(p.buffer.popMarks())
    else:
      p.largeBuffer = p.buffer.popMarks()

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
          parser.state = HttpParseState.HEADER_NAME
          parser.currentLineLen = 0
          parser.version = parser.popToken(1)
          if parser.version[parser.version.len-1] == CR:
            parser.version.setLen(parser.version.len - 1)
          # TODO: normalize Version
        else:
          # parser.popMarksToLargerIfFull()
          break
      of HttpParseState.HEADER_NAME:
        let oldLen = parser.buffer.lenMarks
        var succ = false
        for c in parser.buffer.marks():
          if c == ':':
            succ = true
          elif c == LF:
            parser.state = HttpParseState.BODY
            var a = parser.popToken(1)
            if not ((a[0] == CR and a.len == 1) or a.len == 0):
              raise newException(IndexError, "无效的 CRLF")
            continue
        let newLen = parser.buffer.lenMarks
        parser.currentLineLen.inc((newLen - oldLen).int)
        if parser.currentLineLen.int > LimitRequestLine:
          raise newException(IndexError, "")
        if succ: # TODO: 常量
          parser.state = HttpParseState.HEADER_VALUE
          # parser.headers[parser.popToken(1)] = ""
          # TODO: normalize Name
        else:
          parser.popMarksToLargerIfFull()
          break
      of HttpParseState.HEADER_VALUE:
        if parser.markRequestFieldChar(LF): # TODO: 常量
          parser.state = HttpParseState.HEADER_NAME
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
    


