#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module provides basic tools related to HTTP.

import tables
import strtabs
import strutils
import uri

type
  HttpCode* = enum ## HTTP status code. 
    Http100 = "100 Continue"  ## abcefg
                              ## fgg
    Http101 = "101 Switching Protocols" 
      ## HTTP 1023013012390213 8ewebdhasbew
      ## 31903u1412384189-41y-59
      ## 1312893128938123891398 
    Http200 = "200 OK"  ## 092319319
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

  HttpVersion* = tuple ## HTTP version number.
    orig: string
    major: Natural
    minor: Natural

  HeaderFields* = distinct Table[string, seq[string]] ## Represents the header fields of a HTTP message.

  HttpHeaderKind* {.pure.} = enum
    Request, Response

  HttpHeader* = object ## Represents the header of a HTTP message. Each message must contain only one header.
    case kind*: HttpHeaderKind
    of HttpHeaderKind.Request:
      reqMethod*: HttpMethod
      url*: string
    of HttpHeaderKind.Response:
      statusCode*: HttpCode
    version*: HttpVersion 
    fields*: HeaderFields 

const 
  # [RFC5234](https://tools.ietf.org/html/rfc5234#appendix-B.1)
  COLON* = ':'
  COMMA* = ','
  SEMICOLON* = ';'
  CR* = '\x0D'
  LF* = '\x0A'
  CRLF* = "\x0D\x0A"
  SP* = '\x20'
  HTAB* = '\x09'
  WSP* = {SP, HTAB}

proc initHeaderFields*(): HeaderFields =
  ## Initializes a ``HeaderFields``.
  result = HeaderFields(initTable[string, seq[string]]())

template addImpl(fields: var HeaderFields, name: string, value: string) = 
  let nameUA = name.toLowerAscii()
  if Table[string, seq[string]](fields).hasKey(nameUA):
    Table[string, seq[string]](fields)[nameUA].add(value)
  else:
    Table[string, seq[string]](fields)[nameUA] = @[value]

proc initHeaderFields*(pairs: openarray[tuple[name: string, value: seq[string]]]): HeaderFields =
  ## Initializes a ``HeaderFields``. ``pairs`` is a container consisting of ``(key, value)`` tuples.
  ## 
  ## The following example demonstrates how to deal with a single value, such as ``Content-Length``:
  ## 
  ## .. code-block::nim
  ## 
  ##   let fields = initHeaderFields({
  ##     "Content-Length": @["1"], 
  ##     "Content-Type": @["text/plain"]
  ##     "Cookie": @["SID=123; language=en"]
  ##   })
  ## 
  ## The following example demonstrates how to deal with ``Set-Cookie`` or a comma-separated list of values
  ## such as ``Accept``: 
  ## 
  ##   .. code-block::nim
  ## 
  ##     let fields = initHeaderFields({
  ##       "Set-Cookie": @["SID=123; path=/", "language=en"],
  ##       "Accept": @["audio/\*; q=0.2", "audio/basic"]
  ##     })
  result = HeaderFields(initTable[string, seq[string]]())
  for pair in pairs:
    for v in pair.value:
      result.addImpl(pair.name, v)

proc initHeaderFields*(pairs: openarray[tuple[name: string, value: string]]): HeaderFields =
  ## Initializes a ``HeaderFields``. ``pairs`` is a container consisting of ``(key, value)`` tuples.
  ## 
  ## The following example demonstrates how to deal with a single value, such as ``Content-Length``:
  ## 
  ## .. code-block::nim
  ## 
  ##   let fields = initHeaderFields({
  ##     "Content-Length": "16", 
  ##     "Content-Type": "text/plain"
  ##     "Cookie": "SID=123; language=en"
  ##   })
  result = HeaderFields(initTable[string, seq[string]]())
  for pair in pairs:
    result.addImpl(pair.name, pair.value)

proc clear*(fields: var HeaderFields) = 
  ## Resets this fields so that it is empty.
  Table[string, seq[string]](fields).clear()

proc `[]`*(fields: HeaderFields, name: string): seq[string] {.raises: [KeyError].} =
  ## Returns the value of the field associated with ``name``. If ``name`` is not in this fields, the 
  ## ``KeyError`` exception is raised. 
  ## 
  ## Examples: 
  ## 
  ## .. code-block::nim
  ## 
  ##   let fields = initHeaderFields({
  ##     "Content-Length": "16"
  ##   })
  ##   assert fields["Content-Length"][0] == "16"
  Table[string, seq[string]](fields)[name.toLowerAscii()]

proc `[]=`*(fields: var HeaderFields, name: string, value: seq[string]) =
  ## Sets ``value`` to the field associated with ``name``. Replaces any existing value.
  ## 
  ## Examples: 
  ## 
  ## .. code-block::nim
  ## 
  ##   let fields = initHeaderFields({
  ##     "Content-Length": "16"
  ##   })
  ##   fields["Content-Length"] == @["100"]
  Table[string, seq[string]](fields)[name.toLowerAscii()] = value

proc add*(fields: var HeaderFields, name: string, value: string) =
  ## Adds ``value`` to the field associated with ``name``. If ``name`` does not exist then create a new one.
  ## 
  ## Examples: 
  ## 
  ## .. code-block::nim
  ## 
  ##   let fields = initHeaderFields()
  ##   fields.add("Content-Length", "16")
  ##   fields.add("Cookie", "SID=123")
  ##   fields.add("Cookie", "language=en")
  ##   fields.add("Accept", "audio/\*; q=0.2")
  ##   fields.add("Accept", "audio/basic")
  addImpl(fields, name, value)

proc del*(fields: var HeaderFields, name: string) =
  ## Deletes the field associated with ``name``. 
  ## 
  ## Examples: 
  ## 
  ## .. code-block::nim
  ## 
  ##   fields.del("Content-Length")
  ##   fields.del("Cookie")
  ##   fields.del("Accept")
  Table[string, seq[string]](fields).del(name.toLowerAscii())

proc contains*(fields: HeaderFields, name: string): bool =
  ## Returns true if this fields contains the specified ``name``. 
  ## 
  ## Examples: 
  ## 
  ## .. code-block::nim
  ## 
  ##   let fields = initHeaderFields({
  ##     "Content-Length": "16"
  ##   })
  ##   assert fields.contains("Content-Length") == true
  ##   assert fields.contains("content-length") == true
  ##   assert fields.contains("ContentLength") == false
  Table[string, seq[string]](fields).contains(name.toLowerAscii())

proc len*(fields: HeaderFields): int = 
  ## Returns the number of names in this fields.
  Table[string, seq[string]](fields).len

iterator pairs*(fields: HeaderFields): tuple[name, value: string] =
  ## Yields each ``(name, value)`` pair.
  for k, v in Table[string, seq[string]](fields):
    for value in v:
      yield (k, value)

iterator names*(fields: HeaderFields): string =
  ## Yields each field name.
  for k in Table[string, seq[string]](fields).keys():
    yield k

proc getOrDefault*(
  fields: HeaderFields, 
  name: string,
  default = @[""]
): seq[string] =
  ## Returns the value of the field associated with ``name``. If ``name`` is not in this fields, then 
  ## ``default`` is returned.
  if fields.contains(name):
    return fields[name]
  else:
    return default

template `$`(fields: HeaderFields, res: string) =
  for key, value in Table[string, seq[string]](fields).pairs():
    for v in value:
      res.add(key)
      res.add(": ")
      res.add(v)
      res.add(CRLF)

proc `$`*(fields: HeaderFields): string =
  ## Converts this fields into a string that follows the HTTP Protocol.
  `$`(fields, result)

proc toResponseStr*(H: HttpHeader): string = 
  ## Converts ``H`` into a string that is a response header follows the HTTP Protocol. 
  assert H.kind == HttpHeaderKind.Response
  const Version = "HTTP/1.1"
  result.add(Version)
  result.add(SP)
  result.add($H.statusCode)
  result.add(CRLF)
  `$`(H.fields, result)
  result.add(CRLF)

proc toResponseStr*(code: HttpCode): string = 
  ## Converts ``code`` into a string that is a response header follows the HTTP Protocol. That is, only the 
  ## status line, the header fields is empty.
  const Version = "HTTP/1.1"
  result.add(Version)
  result.add(SP)
  result.add($code)
  result.add(CRLF)
  result.add(CRLF)  

proc toRequestStr*(H: HttpHeader): string = 
  ## Converts ``H`` into a string that is a request header follows the HTTP Protocol. 
  assert H.kind == HttpHeaderKind.Request
  const Version = "HTTP/1.1"
  result.add($H.reqMethod)
  result.add(SP)
  result.add($H.url.encodeUrl())
  result.add(SP)
  result.add(Version)
  result.add(CRLF)
  `$`(H.fields, result)
  result.add(CRLF)

proc toRequestStr*(reqMethod: HttpMethod, url: string): string = 
  ## Converts ``reqMethod`` and ``url`` into a string that is a request header follows the HTTP Protocol. 
  ## That is, only the request line, the header fields is empty.
  const Version = "HTTP/1.1"
  result.add($reqMethod)
  result.add(SP)
  result.add($url.encodeUrl())
  result.add(SP)
  result.add(Version)
  result.add(CRLF)
  result.add(CRLF) 

proc parseHttpCode*(code: int): HttpCode  {.raises: [ValueError].} =
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

proc parseHttpMethod*(s: string): HttpMethod {.raises: [ValueError].} =
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

proc parseHttpVersion*(s: string): HttpVersion  {.raises: [ValueError].} =
  ## Convert to the corresponding ``HttpVersion``.
  if s.len != 8 or s[6] != '.':
    raise newException(ValueError, "Invalid Http Version")
  let major = s[5].ord - 48
  let minor = s[7].ord - 48
  if major != 1 or minor notin {0, 1}:
    raise newException(ValueError, "Invalid Http Version")
  const name = "HTTP/"
  var i = 0
  while i < 5:
    if name[i] != s[i]:
      raise newException(ValueError, "Invalid Http Version")
    i.inc()
  result = (s, major.Natural, minor.Natural)
