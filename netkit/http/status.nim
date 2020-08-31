#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module contains HTTP status code.
## 
## Overview
## ========================
## 
## In HTTP/1.0 and since, the first line of the HTTP response is called the status line and includes a numeric 
## status code (such as "404") and a textual reason phrase (such as "Not Found"). The way the user agent handles 
## the response depends primarily on the code, and secondarily on the other response header fields. Custom
## status codes can be used, for if the user agent encounters a code it does not recognize, it can use the first
## digit of the code to determine the general class of the response.
## 
## .. 
## 
##   See `Hypertext Transfer Protocol <https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol>`_ for more information.

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

proc parseHttpCode*(code: int): HttpCode {.raises: [ValueError].} =
  ## Converts an integer to a status code. A ``ValueError`` is raised when ``code`` is not a valid code.
  runnableExamples:
    doAssert parseHttpCode(100) == Http100
    doAssert parseHttpCode(200) == Http200
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