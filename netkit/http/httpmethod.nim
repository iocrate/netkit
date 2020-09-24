## This module contains a definition of HTTP request method. 
## 
## Overview
## ========================
## 
## HTTP defines methods to indicate the desired action to be performed on the identified resource. What this 
## resource represents, whether pre-existing data or data that is generated dynamically, depends on the  
## implementation of the server. Often, the resource corresponds to a file or the output of an executable
## residing on the server. 
## 
## .. 
## 
##   See `Hypertext Transfer Protocol <https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol>`_ for more information.

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

proc parseHttpMethod*(s: string): HttpMethod =
  ## Converts a string to an HTTP request method. A ``ValueError`` is raised when ``s`` is not a valid method.
  ## 
  ## Examples:
  ## 
  ## .. code-block::nim
  ## 
  ##   assert parseHttpMethod("GET") == HttpGet
  ##   assert parseHttpMethod("POST") == HttpPost
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