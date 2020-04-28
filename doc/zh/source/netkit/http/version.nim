#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module contains a definition of HTTP version. 

type
  HttpVersion* = tuple ## HTTP version number.
    orig: string
    major: Natural
    minor: Natural

const 
  HttpVersion10* = "HTTP/1.0"
  HttpVersion11* = "HTTP/1.1"
  HttpVersion20* = "HTTP/2.0"

proc parseHttpVersion*(s: string): HttpVersion  {.raises: [ValueError].} = discard
  ## Converts a string to HTTP version. A ``ValueError`` is raised when ``s`` is not a valid version. Currently
  ## only `"HTTP/1.0"` and `"HTTP/1.1"` are valid versions.
  ## 
  ## Examples:
  ## 
  ## .. code-block::nim
  ## 
  ##   let version = parseHttpVersion("HTTP/1.1")
  ##   assert version.orig == "HTTP/1.1"
  ##   assert version.major == 1
  ##   assert version.minor == 1