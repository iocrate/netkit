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

proc parseHttpCode*(code: int): HttpCode  {.raises: [ValueError].} = discard
  ## Converts an integer to a status code. A ``ValueError`` is raised when ``code`` is not a valid code.
  ## 
  ## Examples:
  ## 
  ## .. code-block::nim
  ## 
  ##   assert parseHttpCode(100) == Http100
  ##   assert parseHttpCode(200) == Http200