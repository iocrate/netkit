#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import unittest, strutils, netkit/http/base

type Opt = object

proc f(o: var Opt) = 
  echo 1

test "todo":
  var o = new(Opt)
  o[].f()

  echo("abc: " & @["a", "b"].join(", "))
  discard

  var s = "abc"

  var a = "123"

  a.shallowCopy(s)

  echo repr a
  echo a[2]

  