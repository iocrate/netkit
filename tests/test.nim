discard """
  cmd:      "nim c -r --styleCheck:hint --panics:on $options $file"
  matrix:   "--gc:arc"
  targets:  "c"
  nimout:   ""
  action:   "run"
  exitcode: 0
  timeout:  60.0
"""

#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import unittest
import asyncdispatch
import netkit/http/base

# template f(t: untyped) =
#   proc cb() = 
#     let fut = t
#     fut.callback = proc () =
#       discard
  
#   echo "f()"    
#   cb()

# proc test(): char =
#   echo "..."
#   return 'a'

# proc futDemo(): Future[int] = 
#   echo "futDemo()"
#   result = newFuture[int]()

# f: futDemo()

# proc f1(a: uint) =
#   discard

# var a = "abc"
# var b = a

# var x = "efg"

# template f(): string =
#   ##echo repr x
#   x.shallow()
#   x

type
  Opt = enum
    M, N

  B = object 
    case kind: Opt
    of M:
      a*: string
    of N:
      b*: string

proc initResponseHeader(): B =
  echo "...1"
  result = B(kind: N)
  echo "...2"

# proc f()  = 
#   var a = initResponseHeader()
#   echo "..."

var a = initResponseHeader()
echo "...3"