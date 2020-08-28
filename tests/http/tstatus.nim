discard """
  cmd:      "nim c -r --styleCheck:hint --panics:on $options $file"
  matrix:   "--gc:arc"
  targets:  "c"
  nimout:   ""
  action:   "run"
  exitcode: 0
  timeout:  60.0
"""
import netkit/http/status


doAssert parseHttpCode(100) == Http100
doAssert parseHttpCode(200) == Http200


doAssertRaises(ValueError):
  discard parseHttpCode(377)
