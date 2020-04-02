#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块提供 HTTP 相关的基础工具。

import tables, strutils

type
  HttpCode* = distinct range[0..599] ## HTTP 响应状态码。 

  HttpMethod* = enum ## HTTP 请求方法。 
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

  HttpVersion* = tuple ## 表示 HTTP 版本号。 
    orig: string
    major: int
    minor: int

  HttpHeaders* = distinct Table[string, seq[string]] ## 表示 HTTP 头字段集合。 

  ServerReqHeader* = object ## 表示服务器端 HTTP 请求包的头部。 每一个 HTTP 请求应该包含且只包含一个头部。
    reqMethod*: HttpMethod
    url*: string
    version*: HttpVersion
    headers*: HttpHeaders  # TODO 开发 distinct Table 接口

  ServerResHeader* = object ## 表示服务器端 HTTP 响应包的头部。 每一个 HTTP 响应应该包含且只包含一个头部。
    statusCode*: HttpCode
    headers*: HttpHeaders

  ClientReqHeader* = object ## 表示客户端 HTTP 请求包的头部。 每一个 HTTP 请求应该包含且只包含一个头部。
    reqMethod*: HttpMethod
    url*: string
    headers*: HttpHeaders  # TODO 开发 distinct Table 接口

  ClientResHeader* = object ## 表示客户端 HTTP 响应包的头部。 每一个 HTTP 响应应该包含且只包含一个头部。
    statusCode*: HttpCode
    version*: HttpVersion
    headers*: HttpHeaders

const
  Http100* = HttpCode(100)
  Http101* = HttpCode(101)
  Http200* = HttpCode(200)
  Http201* = HttpCode(201)
  Http202* = HttpCode(202)
  Http203* = HttpCode(203)
  Http204* = HttpCode(204)
  Http205* = HttpCode(205)
  Http206* = HttpCode(206)
  Http300* = HttpCode(300)
  Http301* = HttpCode(301)
  Http302* = HttpCode(302)
  Http303* = HttpCode(303)
  Http304* = HttpCode(304)
  Http305* = HttpCode(305)
  Http307* = HttpCode(307)
  Http400* = HttpCode(400)
  Http401* = HttpCode(401)
  Http403* = HttpCode(403)
  Http404* = HttpCode(404)
  Http405* = HttpCode(405)
  Http406* = HttpCode(406)
  Http407* = HttpCode(407)
  Http408* = HttpCode(408)
  Http409* = HttpCode(409)
  Http410* = HttpCode(410)
  Http411* = HttpCode(411)
  Http412* = HttpCode(412)
  Http413* = HttpCode(413)
  Http414* = HttpCode(414)
  Http415* = HttpCode(415)
  Http416* = HttpCode(416)
  Http417* = HttpCode(417)
  Http418* = HttpCode(418)
  Http421* = HttpCode(421)
  Http422* = HttpCode(422)
  Http426* = HttpCode(426)
  Http428* = HttpCode(428)
  Http429* = HttpCode(429)
  Http431* = HttpCode(431)
  Http451* = HttpCode(451)
  Http500* = HttpCode(500)
  Http501* = HttpCode(501)
  Http502* = HttpCode(502)
  Http503* = HttpCode(503)
  Http504* = HttpCode(504)
  Http505* = HttpCode(505)

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

proc `==`*(a, b: HttpCode): bool {.borrow.}
  ## 判断 HTTP 状态码是否相等。 
  
proc `$`*(httpMethod: HttpMethod): string = 
  ## 获取 ``HttpMethod`` 的 HTTP 字符序列表示。 
  return (system.`$`(httpMethod))[4..^1].toUpperAscii()

proc `$`*(code: HttpCode): string =
  ## 获取 ``HttpCode`` 的 HTTP 字符序列表示。
  case code.int
  of 100: "100 Continue"
  of 101: "101 Switching Protocols"
  of 200: "200 OK"
  of 201: "201 Created"
  of 202: "202 Accepted"
  of 203: "203 Non-Authoritative Information"
  of 204: "204 No Content"
  of 205: "205 Reset Content"
  of 206: "206 Partial Content"
  of 300: "300 Multiple Choices"
  of 301: "301 Moved Permanently"
  of 302: "302 Found"
  of 303: "303 See Other"
  of 304: "304 Not Modified"
  of 305: "305 Use Proxy"
  of 307: "307 Temporary Redirect"
  of 400: "400 Bad Request"
  of 401: "401 Unauthorized"
  of 403: "403 Forbidden"
  of 404: "404 Not Found"
  of 405: "405 Method Not Allowed"
  of 406: "406 Not Acceptable"
  of 407: "407 Proxy Authentication Required"
  of 408: "408 Request Timeout"
  of 409: "409 Conflict"
  of 410: "410 Gone"
  of 411: "411 Length Required"
  of 412: "412 Precondition Failed"
  of 413: "413 Request Entity Too Large"
  of 414: "414 Request-URI Too Long"
  of 415: "415 Unsupported Media Type"
  of 416: "416 Requested Range Not Satisfiable"
  of 417: "417 Expectation Failed"
  of 418: "418 I'm a teapot"
  of 421: "421 Misdirected Request"
  of 422: "422 Unprocessable Entity"
  of 426: "426 Upgrade Required"
  of 428: "428 Precondition Required"
  of 429: "429 Too Many Requests"
  of 431: "431 Request Header Fields Too Large"
  of 451: "451 Unavailable For Legal Reasons"
  of 500: "500 Internal Server Error"
  of 501: "501 Not Implemented"
  of 502: "502 Bad Gateway"
  of 503: "503 Service Unavailable"
  of 504: "504 Gateway Timeout"
  of 505: "505 HTTP Version Not Supported"
  else: $(int(code))

proc initHttpHeaders*(): HttpHeaders =
  ## 初始化一个 HTTP 头字段集合对象。
  result = HttpHeaders(initTable[string, seq[string]]())

proc initHttpHeaders*(pairs: openArray[tuple[name: string, value: seq[string]]]): HttpHeaders =
  ## 初始化一个 HTTP 头字段集合对象。 ``pairs`` 指定初始字段集合，每个字段可以有多个值。
  result = HttpHeaders(pairs.toTable())

proc initHttpHeaders*(pairs: openArray[tuple[name: string, value: string]]): HttpHeaders =
  ## 初始化一个 HTTP 头字段集合对象。``pairs`` 指定初始字段集合，每个字段只有一个值。
  var tabPairs: seq[tuple[name: string, value: seq[string]]] = @[]
  for pair in pairs:
    tabPairs.add((pair.name.toUpperAscii(), @[pair.value]))
  result = HttpHeaders(tabPairs.toTable())

proc `$`*(headers: HttpHeaders): string =
  ## 返回对应的 HTTP 字符表示。
  return $(Table[string, seq[string]](headers))

proc clear*(headers: var HttpHeaders) =
  ## 清空所有字段。 
  Table[string, seq[string]](headers).clear()

proc `[]`*(headers: HttpHeaders, name: string): seq[string] =
  ## 获取名字为 ``name`` 的字段值序列，可能是零到多个。 
  Table[string, seq[string]](headers)[name.toUpperAscii()]

proc `[]=`*(headers: var HttpHeaders, name: string, value: string) =
  ## 设置名字为 ``name`` 的字段值。 这会清除所有 ``name`` 已经设置的值。
  Table[string, seq[string]](headers)[name.toUpperAscii()] = @[value]

proc `[]=`*(headers: var HttpHeaders, name: string, values: seq[string]) =
  ## 设置名字为 ``name`` 的字段值。 这会清除所有 ``name`` 已经设置的值。
  Table[string, seq[string]](headers)[name.toUpperAscii()] = values

proc add*(headers: var HttpHeaders, name: string, value: string) =
  ## 为名字为 ``name`` 的字段添加一个值。 
  let nameUA = name.toUpperAscii
  if not Table[string, seq[string]](headers).hasKey(nameUA):
    Table[string, seq[string]](headers)[nameUA] = @[value]
  else:
    Table[string, seq[string]](headers)[nameUA].add(value)

proc del*(headers: var HttpHeaders, name: string) =
  ## 删除名字为 ``name`` 的字段。 
  Table[string, seq[string]](headers).del(name.toUpperAscii())

proc contains*(headers: HttpHeaders, name: string): bool =
  ## 判断是否包含 ``name`` 字段。 
  Table[string, seq[string]](headers).contains(name.toUpperAscii())

proc len*(headers: HttpHeaders): int = 
  ## 获取字段数量。 
  Table[string, seq[string]](headers).len

proc getOrDefault*(
  headers: HttpHeaders, 
  name: string,
  default = @[""]
): seq[string] =
  ## 获取名为 ``name`` 的字段值，如果不存在则返回 ``default``。 
  if headers.contains(name):
    return headers[name]
  else:
    return default

proc getOrDefault*(
  headers: HttpHeaders, 
  name: string,
  default = ""
): string =
  ## 获取名为 ``name`` 的最后一个字段值，如果不存在则返回 ``default``。 
  if headers.contains(name):
    let s = headers[name]
    return s[s.len-1]
  else:
    return default

iterator pairs*(headers: HttpHeaders): tuple[name, value: string] =
  ## 迭代每一个字段。 
  for k, v in Table[string, seq[string]](headers):
    for value in v:
      yield (k, value)

proc initServerReqHeader*(): ServerReqHeader =
  ## 初始化一个服务器端 HTTP 请求包的头部。
  result.headers = HttpHeaders(initTable[string, seq[string]]())

proc initServerResHeader*(): ServerResHeader =
  ## 初始化一个服务器端 HTTP 响应包的头部。
  result.statusCode = Http200
  result.headers = HttpHeaders(initTable[string, seq[string]]())

proc initServerResHeader*(
  statusCode: HttpCode,
  headers: openArray[tuple[name: string, value: seq[string]]]
): ServerResHeader =
  ## 初始化一个服务器端 HTTP 响应包的头部。 ``headers`` 指定初始字段集合，每个字段可以有多个值。
  result.statusCode = statusCode
  result.headers = initHttpHeaders(headers)

proc initServerResHeader*(
  statusCode: HttpCode,
  headers: openArray[tuple[name: string, value: string]]
): ServerResHeader =
  ## 初始化一个服务器端 HTTP 响应包的头部。 ``headers`` 指定初始字段集合，每个字段只有一个值。
  result.statusCode = statusCode
  result.headers = initHttpHeaders(headers)

proc initClientReqHeader*(): ClientReqHeader =
  ## 初始化一个客户端 HTTP 请求包的头部。
  result.reqMethod = HttpGet
  result.url = "/"
  result.headers = HttpHeaders(initTable[string, seq[string]]())

proc initClientReqHeader*(
  reqMethod: HttpMethod,
  url: string,
  headers: openArray[tuple[name: string, value: seq[string]]]
): ClientReqHeader =
  ## 初始化一个客户端 HTTP 请求包的头部。 ``headers`` 指定初始字段集合，每个字段可以有多个值。
  result.reqMethod = reqMethod
  result.url = url
  result.headers = initHttpHeaders(headers)

proc initClientReqHeader*(
  reqMethod: HttpMethod,
  url: string,
  headers: openArray[tuple[name: string, value: string]]
): ClientReqHeader =
  ## 初始化一个客户端 HTTP 请求包的头部。 ``headers`` 指定初始字段集合，每个字段只有一个值。
  result.reqMethod = reqMethod
  result.url = url
  result.headers = initHttpHeaders(headers)

proc initClientResHeader*(): ClientResHeader =
  ## 初始化一个客户端 HTTP 响应包的头部。
  result.headers = HttpHeaders(initTable[string, seq[string]]())

proc `$`*(H: ServerResHeader): string = 
  ## 获取 ``ServerResHeader`` 的 HTTP 字符序列表示。 
  # TODO: 优化
  result.add("HTTP/1.1 " & $H.statusCode & CRLF)
  for name, value in H.headers.pairs():
    result.add(name & ": " & value & CRLF)
  result.add(CRLF)

proc `$`*(H: ClientReqHeader): string = 
  ## 获取 ``ClientReqHeader`` 的 HTTP 字符序列表示。 
  # TODO: 
  discard
