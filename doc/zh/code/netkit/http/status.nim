#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块包含 HTTP 状态码。
## 
## 概述
## ========================
## 
## 在 HTTP 1.0 及以后版本中，HTTP 响应的第一行称为状态行，包含数字状态代码（例如 ``404`` ）和原因短语（例如 ``Not Found`` ）。 
## 
## .. 
## 
##   看看 `Hypertext Transfer Protocol <https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol>`_ 了解更多。

type
  HttpCode* = enum ## HTTP 状态码。
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

proc parseHttpCode*(code: int): HttpCode  {.raises: [ValueError].} = discard
  ## 将整数转换为状态码。当 ``code`` 不是有效的状态码时，引发 ``ValueError`` 。
  ## 
  ## 例子：
  ## 
  ## .. code-block::nim
  ## 
  ##   assert parseHttpCode(100) == Http100
  ##   assert parseHttpCode(200) == Http200