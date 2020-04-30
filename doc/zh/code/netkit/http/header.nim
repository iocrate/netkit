#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块包含了 HTTP 消息头的定义。
## 
## 概述
## ========================
## 
## HTTP 消息由头部和体部组成。头部定义 HTTP 传输的操作参数；体部是传输的数据，紧跟在头部之后，有可能是空的。头部由起始行和头部字段组成。
## 
## 客户端发出的消息称为请求消息，服务器发出的消息称为响应消息。
## 
## 请求消息的起始行称为请求行，由请求方法、URL 和版本号组成；响应消息的起始行称为状态行，由状态码、原因和版本号组成。
## 
## .. 
## 
##   看看 `Hypertext Transfer Protocol <https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol>`_ 了解更多。
## 
## 用法
## ========================
## 
## .. container::r-fragment
## 
##   请求
##   -------
##   
##   输出一个请求消息：
## 
##   .. code-block::nim
## 
##     import netkit/http/version
##     import netkit/http/httpmethod
##     import netkit/http/headerfields
##     import netkit/http/header
##   
##     var header = HttpHeader(
##       kind: HttpHeaderKind.Request, 
##       reqMethod: HttpGet, 
##       url: "/", 
##       version: HttpVer11, 
##       fields: initHeaderFields: {
##         "Host": "www.iocrate.com"
##       }
##     )
##     assert toResponseStr(Http200) = "GET / HTTP/1.1\r\nHost: www.iocrate.com\r\n\r\n"
## 
## .. container::r-fragment
##   
##   响应
##   --------
##   
##   输出一个响应消息：
##   
##   .. code-block::nim
## 
##     import netkit/http/version
##     import netkit/http/status
##     import netkit/http/headerfields
##     import netkit/http/header
##   
##     var header = HttpHeader(
##       kind: HttpHeaderKind.Response, 
##       statusCode: Http200, 
##       version: HttpVer11, 
##       fields: initHeaderFields: {
##         "Host": "www.iocrate.com"
##       }
##     )
##     assert toResponseStr(Http200) = "200 OK HTTP/1.1\r\nHost: www.iocrate.com\r\n\r\n"
##   
##   输出一个响应消息，但是不包含头字段：
## 
##   .. code-block::nim
## 
##      import netkit/http/status
##      import netkit/http/header
## 
##      assert toResponseStr(Http200) = "200 OK HTTP/1.1\r\n\r\n"
## 
##   

import uri
import netkit/http/spec
import netkit/http/httpmethod
import netkit/http/version
import netkit/http/status
import netkit/http/headerfield

type
  HttpHeaderKind* {.pure.} = enum ## HTTP 消息的类型。
    Request, Response

  HttpHeader* = object ## 表示 HTTP 消息头。每条消息只能有一个头部。
    case kind*: HttpHeaderKind
    of HttpHeaderKind.Request:
      reqMethod*: HttpMethod
      url*: string
    of HttpHeaderKind.Response:
      statusCode*: HttpCode
    version*: HttpVersion 
    fields*: HeaderFields 

proc initRequestHeader*(reqMethod: HttpMethod, url: string, 
                            fields: HeaderFields): HttpHeader {.inline.} = discard
  ## 初始化一个 HTTP 请求头。

proc initResponseHeader*(statusCode: HttpCode, fields: HeaderFields): HttpHeader {.inline.} = discard
  ## 初始化一个 HTTP 响应头。

proc toResponseStr*(H: HttpHeader): string = discard
  ## 返回一个字符串，表示 HTTP 响应消息的头部， ``H`` 指定头部的内容。
  ## 
  ## 例子：
  ## 
  ## .. code-block::nim
  ## 
  ##   import netkit/http/version
  ##   import netkit/http/status
  ##   import netkit/http/headerfields
  ##   import netkit/http/header
  ##   
  ##   var header = HttpHeader(
  ##     kind: HttpHeaderKind.Response, 
  ##     statusCode: Http200, 
  ##     version: HttpVer11, 
  ##     fields: initHeaderFields: {
  ##       "Host": "www.iocrate.com"
  ##     }
  ##   )
  ##   assert toResponseStr(Http200) = "200 OK HTTP/1.1\r\nHost: www.iocrate.com\r\n\r\n"

proc toResponseStr*(code: HttpCode): string = discard
  ## 返回一个字符串，表示 HTTP 响应消息的头部， ``code`` 指定头部的状态码。注意，返回的头部不包含头字段。
  ## 
  ## 例子：
  ## 
  ## .. code-block::nim
  ## 
  ##   import netkit/http/status
  ##   import netkit/http/header
  ## 
  ##   assert toResponseStr(Http200) = "200 OK HTTP/1.1\r\n\r\n"

proc toRequestStr*(H: HttpHeader): string = discard
  ## 返回一个字符串，表示 HTTP 请求消息的头部， ``H`` 指定头部的内容。
  ## 
  ## 例子：
  ## 
  ## .. code-block::nim
  ## 
  ##   import netkit/http/version
  ##   import netkit/http/httpmethod
  ##   import netkit/http/headerfields
  ##   import netkit/http/header
  ##   
  ##   var header = HttpHeader(
  ##     kind: HttpHeaderKind.Request, 
  ##     reqMethod: HttpGet, 
  ##     url: "/", 
  ##     version: HttpVer11, 
  ##     fields: initHeaderFields: {
  ##       "Host": "www.iocrate.com"
  ##     }
  ##   )
  ##   assert toResponseStr(Http200) = "GET / HTTP/1.1\r\nHost: www.iocrate.com\r\n\r\n"
