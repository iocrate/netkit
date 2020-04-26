#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块提供 HTTP 相关的基础工具。

import tables
import strutils

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

  HeaderFields* = distinct Table[string, seq[string]] ## 表示一条 HTTP 消息的头字段集合。 

  HttpHeaderKind* {.pure.} = enum ## 
    Request, Response

  HttpHeader* = object ## 表示一条 HTTP 消息的头部。 每条消息只有一个头部。 
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
  SP* = '\x20'
  CR* = '\x0D'
  LF* = '\x0A'
  COLON* = ':'
  COMMA* = ','
  SEMICOLON* = ';'
  HTAB* = '\x09'
  CRLF* = "\x0D\x0A"
  WSP* = {SP, HTAB}

proc initHeaderFields*(): HeaderFields = discard
  ## 初始化一个 HTTP 头字段集合对象。 

proc initHeaderFields*(pairs: openArray[tuple[name: string, value: seq[string]]]): HeaderFields = discard
  ## 初始化一个 HTTP 头字段集合对象。 ``pairs`` 指定初始字段集合，每个字段可以有多个值。 
  ## 
  ## 下面的例子说明了如何处理单一值的头字段：
  ## 
  ## ..code-block::nim
  ## 
  ##   let fields = initHeaderFields({
  ##     "Content-Length": @["1"], 
  ##     "Content-Type": @["text/plain"]
  ##     "Cookie": @["SID=123; language=en"]
  ##   })
  ## 
  ## 下面的例子说明了如何处理 ``Set-Cookie`` 或者使用逗号分隔的多值的头字段 (比如 ``Accept``)：
  ## 
  ## ..code-block::nim
  ## 
  ##   let fields = initHeaderFields({
  ##     "Set-Cookie": @["SID=123; path=/", "language=en"],
  ##     "Accept": @["audio/*; q=0.2", "audio/basic"]
  ##   })

proc initHeaderFields*(pairs: openArray[tuple[name: string, value: string]]): HeaderFields = discard
  ## 初始化一个 HTTP 头字段集合对象。``pairs`` 指定初始字段集合，每个字段只有一个值。 
  ## 
  ## 下面的例子说明了如何处理单一值的头字段：
  ## 
  ## ..code-block::nim
  ## 
  ##   let fields = initHeaderFields({
  ##     "Content-Length": @["1"], 
  ##     "Content-Type": @["text/plain"]
  ##     "Cookie": @["SID=123; language=en"]
  ##   })

proc clear*(fields: var HeaderFields) = discard
  ## 清空所有字段。 

proc `[]`*(fields: HeaderFields, name: string): seq[string] = discard
  ## 获取名字为 ``name`` 的字段值， 可能是零到多个。 
  ## 
  ## 例子：  
  ## 
  ## ..code-block::nim
  ## 
  ##   let fields = initHeaderFields({
  ##     "Content-Length": "16"
  ##   })
  ##   assert fields["Content-Length"][0] == "16"

proc `[]=`*(fields: var HeaderFields, name: string, value: seq[string]) = discard
  ## 设置名字为 ``name`` 的字段值。 这会清除所有 ``name`` 已经设置的值。 
  ## 
  ## 例子： 
  ## 
  ## ..code-block::nim
  ## 
  ##   let fields = initHeaderFields({
  ##     "Content-Length": "16"
  ##   })
  ##   fields["Content-Length"] == @["100"]

proc add*(fields: var HeaderFields, name: string, value: string) = discard
  ## 为名字为 ``name`` 的字段添加一个值。 
  ## 
  ## 例子： 
  ## 
  ## ..code-block::nim
  ## 
  ##   let fields = initHeaderFields()
  ##   fields.add("Content-Length", "16")
  ##   fields.add("Cookie", "SID=123")
  ##   fields.add("Cookie", "language=en")
  ##   fields.add("Accept", "audio/*; q=0.2")
  ##   fields.add("Accept", "audio/basic")

proc del*(fields: var HeaderFields, name: string) = discard
  ## 删除名字为 ``name`` 的字段。 
  ## 
  ## 例子： 
  ## 
  ## ..code-block::nim
  ## 
  ##   fields.del("Content-Length")
  ##   fields.del("Cookie")
  ##   fields.del("Accept")

proc contains*(fields: HeaderFields, name: string): bool = discard
  ## 判断是否包含 ``name`` 字段。 
  ## 
  ## 例子： 
  ## 
  ## ..code-block::nim
  ## 
  ##   let fields = initHeaderFields({
  ##     "Content-Length": "16"
  ##   })
  ##   assert fields.contains("Content-Length") == true
  ##   assert fields.contains("content-length") == true
  ##   assert fields.contains("ContentLength") == false

proc len*(fields: HeaderFields): int = discard
  ## 获取字段数量。 

iterator pairs*(fields: HeaderFields): tuple[name, value: string] = discard
  ## 迭代每一个 ``(name, value)`` 对。 

iterator names*(fields: HeaderFields): string = discard
  ## 迭代每一个字段名。 
    
proc getOrDefault*(fields: HeaderFields, name: string, default = @[""]): seq[string] = discard
  ## 获取名为 ``name`` 的字段值， 如果不存在则返回 ``default``。 

proc `$`*(fields: HeaderFields): string = discard
  ## 把 ``fields`` 转换为遵循 HTTP 协议规范的字符串。 

proc toResponseStr*(H: HttpHeader): string = discard
  ## 把 ``H`` 转换为遵循 HTTP 协议规范的字符串。 该字符串是一个完整的 HTTP 响应头部。 

proc toResponseStr*(code: HttpCode): string = discard
  ## 把 ``code`` 转换为遵循 HTTP 协议规范的字符串。 该字符串是一个完整的 HTTP 响应头部， 但是头部字段是空的， 
  ## 只有状态行。   
  
proc toRequestStr*(H: HttpHeader): string = discard
  ## 把 ``H`` 转换为遵循 HTTP 协议规范的字符串。 该字符串是一个完整的 HTTP 请求头部。 
  
proc toRequestStr*(reqMethod: HttpMethod, url: string): string = discard
  ## 把 ``H`` 转换为遵循 HTTP 协议规范的字符串。 该字符串是一个完整的 HTTP 请求头部， 但是头部字段是空的， 
  ## 只有请求行。   

proc parseHttpCode*(code: int): HttpCode = discard
  ## 把整数 ``code`` 转换为对应的 HttpCode 表示。 

proc parseHttpMethod*(s: string): HttpMethod = discard
  ## 把字符串 ``s`` 转换为对应的 HttpMethod 表示。 

proc parseHttpVersion*(s: string): HttpVersion = discard
  ## 把字符串 ``s`` 转换为对应的 HttpVersion 表示。 请注意， ``s`` 必须是 ``"HTTP/1.1"`` 或者是 ``"HTTP/1.0"``， 
  ## 否则， 抛出异常。 当前， 仅支持 HTTP/1.1 和 HTTP/1.0。 

