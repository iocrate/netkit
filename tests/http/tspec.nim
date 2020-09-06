discard """
  cmd:      "nim c -r --styleCheck:hint --panics:on $options $file"
  matrix:   "--gc:arc"
  targets:  "c"
  nimout:   ""
  action:   "run"
  exitcode: 0
  timeout:  60.0
"""
import netkit/http/spec


block test_header_name:
  checkFieldName("hello!")
  checkFieldName("+._~`a|&*+-#")
  checkFieldName("flywind123456")
  checkFieldName("FLYWIND_-'+!")

block test_header_value:
  # const ValueChars = { HTAB, SP, '\x21'..'\x7E', '\x80'..'\xFF' }
  checkFieldValue("hello!")
  checkFieldValue("+._~`a|&*+-#")
  checkFieldValue("flywind123456")
  checkFieldValue("FLYWIND_-'+!")
  checkFieldValue("fly\twind")
  checkFieldValue("fly?©wind®")
