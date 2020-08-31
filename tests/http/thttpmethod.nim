discard """
  cmd:      "nim c -r --styleCheck:hint --panics:on $options $file"
  matrix:   "--gc:arc"
  targets:  "c"
  nimout:   ""
  action:   "run"
  exitcode: 0
  timeout:  60.0
"""
import netkit/http/httpmethod

doAssert parseHttpMethod("GET") == HttpGet
doAssert parseHttpMethod("POST") == HttpPost
doAssert parseHttpMethod("TRACE") == HttpTrace
doAssertRaises(ValueError):
  discard parseHttpMethod("get")
