#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module provides basic tools related to HTTP.

import tables
import strutils

type
  HttpCode* = enum ## HTTP status code. 
    Http100 = "100 Continue"
    Http101 = "101 Switching Protocols"
    Http200 = "200 OK"
    Http201 = "201 Created"
    Http202 = "202 Accepted"
    Http203 = "203 Non-Authoritative Information"
    Http204 = "204 No Content"
    Http205 = "205 Reset Content"
    Http206 = "206 Partial Content"
    Http300 = "300 Multiple Choices"
    Http301 = "301 Moved Permanently"
    Http302 = "302 Found"
    Http303 = "303 See Other"
    Http304 = "304 Not Modified"
    Http305 = "305 Use Proxy"
    Http307 = "307 Temporary Redirect"
    Http400 = "400 Bad Request"
    Http401 = "401 Unauthorized"
    Http403 = "403 Forbidden"
    Http404 = "404 Not Found"
    Http405 = "405 Method Not Allowed"
    Http406 = "406 Not Acceptable"
    Http407 = "407 Proxy Authentication Required"
    Http408 = "408 Request Timeout"
    Http409 = "409 Conflict"
    Http410 = "410 Gone"
    Http411 = "411 Length Required"
    Http412 = "412 Precondition Failed"
    Http413 = "413 Request Entity Too Large"
    Http414 = "414 Request-URI Too Long"
    Http415 = "415 Unsupported Media Type"
    Http416 = "416 Requested Range Not Satisfiable"
    Http417 = "417 Expectation Failed"
    Http418 = "418 I'm a teapot"
    Http421 = "421 Misdirected Request"
    Http422 = "422 Unprocessable Entity"
    Http426 = "426 Upgrade Required"
    Http428 = "428 Precondition Required"
    Http429 = "429 Too Many Requests"
    Http431 = "431 Request Header Fields Too Large"
    Http451 = "451 Unavailable For Legal Reasons"
    Http500 = "500 Internal Server Error"
    Http501 = "501 Not Implemented"
    Http502 = "502 Bad Gateway"
    Http503 = "503 Service Unavailable"
    Http504 = "504 Gateway Timeout"
    Http505 = "505 HTTP Version Not Supported"

  HttpMethod* = enum ## HTTP request method. 
    HttpHead = "HEAD",        
    HttpGet = "GET",         
    HttpPost = "POST",        
    HttpPut = "PUT", 
    HttpDelete = "DELETE", 
    HttpTrace = "TRACE", 
    HttpOptions = "OPTIONS", 
    HttpConnect = "CONNECT", 
    HttpPatch = "PATCH" 

  HttpVersion* = tuple ## Represents the HTTP version number.
    orig: string
    major: Natural
    minor: Natural

  HeaderFields* = distinct Table[string, seq[string]] ## 表示 HTTP 头字段集合。

  HttpHeaderKind* {.pure.} = enum
    Request, Response

  HttpHeader* = object of RootObj
    fields*: HeaderFields 
    version*: HttpVersion 
    case kind: HttpHeaderKind
    of HttpHeaderKind.Request:
      reqMethod*: HttpMethod
      url*: string
    of HttpHeaderKind.Response:
      statusCode*: HttpCode

  # RequestHeader* = object of HttpHeader ## Represents the header of a HTTP request packet. Each HTTP request should contains only one header.
  #   reqMethod*: HttpMethod
  #   url*: string

  # ResponseHeader* = object of HttpHeader ## Represents the header of a HTTP response packet. Each HTTP response should contains only one header.
  #   statusCode*: HttpCode

const 
  # [RFC5234](https://tools.ietf.org/html/rfc5234#appendix-B.1)
  SP* = '\x20'
  CR* = '\x0D'
  LF* = '\x0A'
  COLON* = ':'
  COMMA* = ','
  HTAB* = '\x09'
  CRLF* = "\x0D\x0A"
  WS* = {SP, HTAB}

proc toHttpCode*(code: int): HttpCode =
  ## Convert to the corresponding ``HttpCode``. 
  case code
  of 100: Http100
  of 101: Http101
  of 200: Http200
  of 201: Http201
  of 202: Http202
  of 203: Http203
  of 204: Http204
  of 205: Http205
  of 206: Http206
  of 300: Http300
  of 301: Http301
  of 302: Http302
  of 303: Http303
  of 304: Http304
  of 305: Http305
  of 307: Http307
  of 400: Http400
  of 401: Http401
  of 403: Http403
  of 404: Http404
  of 405: Http405
  of 406: Http406
  of 407: Http407
  of 408: Http408
  of 409: Http409
  of 410: Http410
  of 411: Http411
  of 412: Http412
  of 413: Http413
  of 414: Http414
  of 415: Http415
  of 416: Http416
  of 417: Http417
  of 418: Http418
  of 421: Http421
  of 422: Http422
  of 426: Http426
  of 428: Http428
  of 429: Http429
  of 431: Http431
  of 451: Http451
  of 500: Http500
  of 501: Http501
  of 502: Http502
  of 503: Http503
  of 504: Http504
  of 505: Http505
  else: raise newException(ValueError, "Not Implemented")

proc toHttpMethod*(s: string): HttpMethod {.raises: [ValueError].} =
  ## Convert to the corresponding ``HttpMethod``. 
  result =
    case s
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

proc toHttpVersion*(s: string): HttpVersion =
  ## 
  if s.len != 8 or s[6] != '.':
    raise newException(ValueError, "Bad Request")
  let major = s[5].ord - 48
  let minor = s[7].ord - 48
  if major != 1 or minor notin {0, 1}:
    raise newException(ValueError, "Bad Request")
  const name = "HTTP/"
  var i = 0
  while i < 5:
    if name[i] != s[i]:
      raise newException(ValueError, "Bad Request")
    i.inc()
  result = (s, major.Natural, minor.Natural)

proc initHeaderFields*(): HeaderFields =
  ## 
  result = HeaderFields(initTable[string, seq[string]]())

proc initHeaderFields*(pairs: openarray[tuple[name: string, value: seq[string]]]): HeaderFields =
  ## 
  var tabPairs: seq[tuple[name: string, value: seq[string]]] = @[]
  for pair in pairs:
    tabPairs.add((pair.name.toLowerAscii(), pair.value))
  result = HeaderFields(toTable[string, seq[string]](tabPairs))

proc initHeaderFields*(pairs: openarray[tuple[name: string, value: string]]): HeaderFields =
  ## 
  var tabPairs: seq[tuple[name: string, value: seq[string]]] = @[]
  for pair in pairs:
    tabPairs.add((pair.name.toLowerAscii(), @[pair.value]))
  result = HeaderFields(toTable[string, seq[string]](tabPairs))

proc `$`*(fields: HeaderFields): string =
  ## 
  return $(Table[string, seq[string]](fields))

proc clear*(fields: var HeaderFields) =
  ## 
  Table[string, seq[string]](fields).clear()

proc `[]`*(fields: HeaderFields, name: string): seq[string] =
  ## 
  Table[string, seq[string]](fields)[name.toLowerAscii()]

proc `[]=`*(fields: var HeaderFields, name: string, value: string) =
  ## 
  Table[string, seq[string]](fields)[name.toLowerAscii()] = @[value]

proc `[]=`*(fields: var HeaderFields, name: string, value: seq[string]) =
  ## 
  Table[string, seq[string]](fields)[name.toLowerAscii()] = value

proc add*(fields: var HeaderFields, name: string, value: string) =
  ## 
  let nameUA = name.toLowerAscii()
  if not Table[string, seq[string]](fields).hasKey(nameUA):
    Table[string, seq[string]](fields)[nameUA] = @[value]
  else:
    Table[string, seq[string]](fields)[nameUA].add(value)

proc del*(fields: var HeaderFields, name: string) =
  ## 
  Table[string, seq[string]](fields).del(name.toLowerAscii())

proc contains*(fields: HeaderFields, name: string): bool =
  ## 
  Table[string, seq[string]](fields).contains(name.toLowerAscii())

proc len*(fields: HeaderFields): int = 
  ## 
  Table[string, seq[string]](fields).len

proc getOrDefault*(
  fields: HeaderFields, 
  name: string,
  default = @[""]
): seq[string] =
  ## 
  if fields.contains(name):
    return fields[name]
  else:
    return default

proc getOrDefault*(
  fields: HeaderFields, 
  name: string,
  default = ""
): string =
  ## 
  if fields.contains(name):
    let s = fields[name]
    return s[s.len-1]
  else:
    return default

iterator pairs*(fields: HeaderFields): tuple[name, value: string] =
  ##  
  for k, v in Table[string, seq[string]](fields):
    for value in v:
      yield (k, value)

proc initRequestHeader*(): HttpHeader =
  ## 
  result.kind = HttpHeaderKind.Request
  result.fields = initHeaderFields()

proc initRequestHeader*(
  reqMethod: HttpMethod,
  url: string,
  fields: openarray[tuple[name: string, value: seq[string]]]
): HttpHeader =
  ## 
  result.kind = HttpHeaderKind.Request
  result.reqMethod = reqMethod
  result.url = url
  result.fields = initHeaderFields(fields)

proc initRequestHeader*(
  reqMethod: HttpMethod,
  url: string,
  fields: openarray[tuple[name: string, value: string]]
): HttpHeader =
  ## 
  result.kind = HttpHeaderKind.Request
  result.reqMethod = reqMethod
  result.url = url
  result.fields = initHeaderFields(fields)

proc initResponseHeader*(): HttpHeader =
  ## 
  result.kind = HttpHeaderKind.Response
  result.fields = initHeaderFields()

proc initResponseHeader*(
  statusCode: HttpCode,
  fields: openarray[tuple[name: string, value: seq[string]]]
): HttpHeader =
  ## 
  result.kind = HttpHeaderKind.Response
  result.statusCode = statusCode
  result.version = ("HTTP/1.1", 1.Natural, 1.Natural)
  result.fields = initHeaderFields(fields)

proc initResponseHeader*(
  statusCode: HttpCode,
  fields: openarray[tuple[name: string, value: string]]
): HttpHeader =
  ## 
  result.kind = HttpHeaderKind.Response
  result.statusCode = statusCode
  result.version = ("HTTP/1.1", 1.Natural, 1.Natural)
  result.fields = initHeaderFields(fields)

proc kind*(H: HttpHeader): HttpHeaderKind =
  ## 
  H.kind

proc toResponseHeaderStr*(H: HttpHeader): string = 
  ## 
  assert H.kind == HttpHeaderKind.Response
  result.add(H.version.orig & SP & $H.statusCode & CRLF)
  for name, value in H.fields.pairs():
    result.add(name & ": " & value & CRLF)
  result.add(CRLF)

proc toRequestHeaderStr*(H: HttpHeader): string = 
  ## 
  # TODO: 
  assert H.kind == HttpHeaderKind.Request

