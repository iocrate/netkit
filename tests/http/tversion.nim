discard """
  cmd:      "nim c -r --styleCheck:hint --panics:on $options $file"
  matrix:   "--gc:arc"
  targets:  "c"
  nimout:   ""
  action:   "run"
  exitcode: 0
  timeout:  60.0
"""
import netkit/http/version


doAssert parseHttpVersion("HTTP/1.1") == HttpVer11
doAssert parseHttpVersion("HTTP/1.0") == HttpVer10

doAssertRaises(ValueError):
  discard parseHttpVersion("HTTP/2.0")

doAssertRaises(ValueError):
  discard parseHttpVersion("HTTP/1.2")

doAssertRaises(ValueError):
  discard parseHttpVersion("HTTP/1.1.1")

doAssertRaises(ValueError):
  discard parseHttpVersion("1.0")

