#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import unittest, strutils

type Opt = object

proc f(o: var Opt) = 
  echo 1

test "todo":
  var o = new(Opt)
  o[].f()

  echo("abc: " & @["a", "b"].join(", "))
  discard