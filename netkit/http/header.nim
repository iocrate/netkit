#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module contains a defination of the header of a HTTP message.
## 
## Overview
## ========================
## 
## A HTTP message consists of a header and a body. The header defines the operating parameters of an HTTP 
## transaction, and the body is the data bytes transmitted in an HTTP transaction message immediately following 
## the header. The header consists of a start line and zero or more header fields.
## 
## A message sent by a client is called a request, and a message sent by a server is called a response. 
## 
## The start line of a request is called request line, which consists of a request method, a url and a version. 
## The start line of a response is called status line, which consists of a status code, a reason and a version. 
## 
## .. 
## 
##   See `Hypertext Transfer Protocol <https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol>`_ for more information.
## 
## Usage
## ========================
## 
## .. container::r-fragment
## 
##   Request
##   -------
##   
##   To output a request message:
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
##     assert toResponseStr(header) == "GET / HTTP/1.1\r\nHost: www.iocrate.com\r\n\r\n"
## 
## .. container::r-fragment
##   
##   Response
##   --------
##   
##   To output a response message:
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
##     assert toResponseStr(header) == "200 OK HTTP/1.1\r\nHost: www.iocrate.com\r\n\r\n"
##   
##   To output a response message without fields:
## 
##   .. code-block::nim
## 
##      import netkit/http/status
##      import netkit/http/header
## 
##      assert toResponseStr(Http200) == "200 OK HTTP/1.1\r\n\r\n"
## 
##   

import uri
import netkit/http/spec
import netkit/http/httpmethod
import netkit/http/version
import netkit/http/status
import netkit/http/headerfield

type
  HttpHeaderKind* {.pure.} = enum ## Kind of HTTP message.
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

proc initRequestHeader*(reqMethod: HttpMethod, url: string, 
                            fields: HeaderFields): HttpHeader {.inline.} =
  ## Initiates HTTP request header.
  HttpHeader(kind: HttpHeaderKind.Request, reqMethod: reqMethod, url: url, version: HttpVer11)

proc initResponseHeader*(statusCode: HttpCode, fields: HeaderFields): HttpHeader {.inline.} =
  ## Initates HTTP response headers.
  HttpHeader(kind: HttpHeaderKind.Response, statusCode: statusCode, version: HttpVer11, fields: fields)

proc toResponseStr*(H: HttpHeader): string = 
  ## Returns a header of a response message. 
  ## 
  ## Examples:
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
  ##   assert toResponseStr(header) == "200 OK HTTP/1.1\r\nHost: www.iocrate.com\r\n\r\n"
  assert H.kind == HttpHeaderKind.Response
  result.add($HttpVer11)
  result.add(SP)
  result.add($H.statusCode)
  result.add(CRLF)
  for key, value in H.fields.pairs():
    result.add(key)
    result.add(": ")
    result.add(value)
    result.add(CRLF)
  result.add(CRLF)

proc toResponseStr*(code: HttpCode): string = 
  ## Returns a header of a response message, ``code`` specifies the status code. The header fields is empty.
  ## 
  ## Examples:
  ## 
  ## .. code-block::nim
  ## 
  ##   import netkit/http/status
  ##   import netkit/http/header
  ## 
  ##   assert toResponseStr(Http200) == "200 OK HTTP/1.1\r\n\r\n"
  result.add($HttpVer11)
  result.add(SP)
  result.add($code)
  result.add(CRLF)
  result.add(CRLF)  

proc toRequestStr*(H: HttpHeader): string = 
  ## Returns a header of a request message. 
  ## 
  ## Examples:
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
  ##   assert toResponseStr(HttpHeader) == "GET / HTTP/1.1\r\nHost: www.iocrate.com\r\n\r\n"
  assert H.kind == HttpHeaderKind.Request
  result.add($H.reqMethod)
  result.add(SP)
  result.add($H.url.encodeUrl())
  result.add(SP)
  result.add($HttpVer11)
  result.add(CRLF)
  for key, value in H.fields.pairs():
    result.add(key)
    result.add(": ")
    result.add(value)
    result.add(CRLF)
  result.add(CRLF)
