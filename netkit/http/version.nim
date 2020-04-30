#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module contains a definition of HTTP version. 

type
  HttpVersion* = enum ## HTTP version number.
    HttpVer10 = "HTTP/1.0", 
    HttpVer11 = "HTTP/1.1"
    HttpVer20 = "HTTP/2.0"

proc parseHttpVersion*(s: string): HttpVersion  {.raises: [ValueError].} =
  ## Converts a string to HTTP version. A ``ValueError`` is raised when ``s`` is not a valid version. Currently
  ## only `"HTTP/1.0"` and `"HTTP/1.1"` are valid versions.
  ## 
  ## Examples:
  ## 
  ## .. code-block::nim
  ## 
  ##   let version = parseHttpVersion("HTTP/1.1")
  ##   assert version == HttpVer11
  if s.len != 8 or s[6] != '.':
    raise newException(ValueError, "Invalid Http Version")
  let major = s[5].ord - 48
  let minor = s[7].ord - 48
  if major != 1:
    raise newException(ValueError, "Invalid Http Version")
  case minor
  of 0:
    result = HttpVer10
  of 1:
    result = HttpVer11
  else:
    raise newException(ValueError, "Invalid Http Version")
  const name = "HTTP/"
  var i = 0
  while i < 5:
    if name[i] != s[i]:
      raise newException(ValueError, "Invalid Http Version")
    i.inc()
  
