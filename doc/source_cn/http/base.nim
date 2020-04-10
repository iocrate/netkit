#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块提供 HTTP 相关的基础工具。

import tables, strutils

type
  HttpCode* = enum ## HTTP 响应状态码。 
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

  HttpMethod* = enum ## HTTP 请求方法。 
    HttpHead = "HEAD",        
    HttpGet = "GET",         
    HttpPost = "POST",        
    HttpPut = "PUT", 
    HttpDelete = "DELETE", 
    HttpTrace = "TRACE", 
    HttpOptions = "OPTIONS", 
    HttpConnect = "CONNECT", 
    HttpPatch = "PATCH" 

  HttpVersion* = tuple ## 表示 HTTP 版本号。 
    orig: string
    major: Natural
    minor: Natural

  HeaderFields* = distinct Table[string, seq[string]] ## 表示 HTTP 头字段集合。 

  ChunkSizer* = object ## 表示 HTTP ``Transfer-Encoding: chunked`` 编码数据的尺寸部分。
    size*: Natural
    extensions*: string

  RequestHeader* = object ## 表示 HTTP 请求包的头部。 每一个 HTTP 请求应该包含且只包含一个头部。
    reqMethod*: HttpMethod
    url*: string
    version*: HttpVersion
    fields*: HeaderFields  

  ResponseHeader* = object ## 表示 HTTP 响应包的头部。 每一个 HTTP 响应应该包含且只包含一个头部。
    statusCode*: HttpCode
    version*: HttpVersion
    fields*: HeaderFields

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

proc toHttpCode*(code: int): HttpCode = discard
  ## 获取整数 ``code`` 对应的 HttpCode 表示。

proc toHttpMethod*(s: string): HttpMethod {.raises: [ValueError].} = discard
  ## 获取字符串 ``s`` 对应的 HttpMethod 表示。

proc toHttpVersion*(s: string): HttpVersion = discard
  ## 获取字符串 ``s`` 对应的 HttpVersion 表示。 请注意， ``s`` 必须是 ``"HTTP/1.1"`` 或者是 ``"HTTP/1.0"``， 
  ## 否则， 抛出异常。 当前， 仅支持 HTTP/1.1 和 HTTP/1.0。 

proc initHeaderFields*(): HeaderFields = discard
  ## 初始化一个 HTTP 头字段集合对象。

proc initHeaderFields*(pairs: openArray[tuple[name: string, value: seq[string]]]): HeaderFields = discard
  ## 初始化一个 HTTP 头字段集合对象。 ``pairs`` 指定初始字段集合，每个字段可以有多个值。

proc initHeaderFields*(pairs: openArray[tuple[name: string, value: string]]): HeaderFields = discard
  ## 初始化一个 HTTP 头字段集合对象。``pairs`` 指定初始字段集合，每个字段只有一个值。

proc `$`*(fields: HeaderFields): string = discard
  ## 返回对应的 HTTP 字符表示。

proc clear*(fields: var HeaderFields) = discard
  ## 清空所有字段。 

proc `[]`*(fields: HeaderFields, name: string): seq[string] = discard
  ## 获取名字为 ``name`` 的字段值序列，可能是零到多个。

proc `[]=`*(fields: var HeaderFields, name: string, value: string) = discard
  ## 设置名字为 ``name`` 的字段值。 这会清除所有 ``name`` 已经设置的值。

proc `[]=`*(fields: var HeaderFields, name: string, value: seq[string]) = discard
  ## 设置名字为 ``name`` 的字段值。 这会清除所有 ``name`` 已经设置的值。

proc add*(fields: var HeaderFields, name: string, value: string) = discard
  ## 为名字为 ``name`` 的字段添加一个值。 

proc del*(fields: var HeaderFields, name: string) = discard
  ## 删除名字为 ``name`` 的字段。 

proc contains*(fields: HeaderFields, name: string): bool = discard
  ## 判断是否包含 ``name`` 字段。 

proc len*(fields: HeaderFields): int = discard
  ## 获取字段数量。 
  
proc getOrDefault*(
  fields: HeaderFields, 
  name: string,
  default = @[""]
): seq[string] = discard
  ## 获取名为 ``name`` 的字段值，如果不存在则返回 ``default``。 

proc getOrDefault*(
  fields: HeaderFields, 
  name: string,
  default = ""
): string = discard
  ## 获取名为 ``name`` 的最后一个字段值，如果不存在则返回 ``default``。 

iterator pairs*(fields: HeaderFields): tuple[name, value: string] = discard
  ## 迭代每一个字段。 

proc initRequestHeader*(): RequestHeader = discard
  ## 初始化一个 HTTP 请求包的头部。 

proc initRequestHeader*(
  reqMethod: HttpMethod,
  url: string,
  fields: openArray[tuple[name: string, value: seq[string]]]
): RequestHeader = discard
  ## 初始化一个 HTTP 请求包的头部。 ``reqMethod`` 指定请求方法， ``url`` 指定请求路径， 
  ## ``fields`` 指定初始字段集合，每个字段可以有多个值。 

proc initRequestHeader*(
  reqMethod: HttpMethod,
  url: string,
  fields: openArray[tuple[name: string, value: string]]
): RequestHeader = discard
  ## 初始化一个 HTTP 请求包的头部。 ``reqMethod`` 指定请求方法， ``url`` 指定请求路径， 
  ## ``fields`` 指定初始字段集合，每个字段可以有多个值。 

proc initResponseHeader*(): ResponseHeader = discard
  ## 初始化一个 HTTP 响应包的头部。 

proc initResponseHeader*(
  statusCode: HttpCode,
  fields: openArray[tuple[name: string, value: seq[string]]]
): ResponseHeader = discard
  ## 初始化一个 HTTP 响应包的头部。  ``statusCode`` 指定状态码， HTTP 版本号设定为 "HTTP/1.1"， 
  ## ``fields`` 指定初始字段集合，每个字段可以有多个值。 

proc initResponseHeader*(
  statusCode: HttpCode,
  fields: openArray[tuple[name: string, value: string]]
): ResponseHeader = discard
  ## 初始化一个服务器端 HTTP 响应包的头部。  ``statusCode`` 指定状态码， HTTP 版本号设定为 "HTTP/1.1"， 
  ## ``fields`` 指定初始字段集合，每个字段可以有多个值。 

proc `$`*(H: ResponseHeader): string = discard
  ## 获取 ``ResponseHeader`` 的 HTTP 字符序列表示。
  
proc `$`*(H: RequestHeader): string = discard
  ## 获取 ``RequestHeader`` 的 HTTP 字符序列表示。 

