#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module provides basic tools related to HTTP.

import uri
import netkit/http/spec
import netkit/http/httpmethod
import netkit/http/version
import netkit/http/status
import netkit/http/headerfield

type
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

proc toResponseStr*(H: HttpHeader): string = 
  ## Converts ``H`` into a string that is a response header follows the HTTP Protocol. 
  assert H.kind == HttpHeaderKind.Response
  result.add(HttpVersion11)
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
  ## Converts ``code`` into a string that is a response header follows the HTTP Protocol. That is, only the 
  ## status line, the header fields is empty.
  result.add(HttpVersion11)
  result.add(SP)
  result.add($code)
  result.add(CRLF)
  result.add(CRLF)  

proc toRequestStr*(H: HttpHeader): string = 
  ## Converts ``H`` into a string that is a request header follows the HTTP Protocol. 
  assert H.kind == HttpHeaderKind.Request
  result.add($H.reqMethod)
  result.add(SP)
  result.add($H.url.encodeUrl())
  result.add(SP)
  result.add(HttpVersion11)
  result.add(CRLF)
  for key, value in H.fields.pairs():
    result.add(key)
    result.add(": ")
    result.add(value)
    result.add(CRLF)
  result.add(CRLF)
