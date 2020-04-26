#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module contains a definition of HTTP request method. 

type
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

proc parseHttpMethod*(s: string): HttpMethod {.raises: [ValueError].} =
  ## Convert a string to an HTTP request method. 
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