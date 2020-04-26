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

proc parseHttpVersion*(s: string): HttpVersion  {.raises: [ValueError].} =
  ## Convert a string to HTTP version.
  if s.len != 8 or s[6] != '.':
    raise newException(ValueError, "Invalid Http Version")
  let major = s[5].ord - 48
  let minor = s[7].ord - 48
  if major != 1 or minor notin {0, 1}:
    raise newException(ValueError, "Invalid Http Version")
  const name = "HTTP/"
  var i = 0
  while i < 5:
    if name[i] != s[i]:
      raise newException(ValueError, "Invalid Http Version")
    i.inc()
  result = (s, major.Natural, minor.Natural)
