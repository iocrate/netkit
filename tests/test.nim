#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import unittest, netkit/http/base, asyncdispatch

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

# var a = -100
# f1(a)

type
  Opt = ref object
    d: int

template f1(x: Opt) =
  proc cb() = 
    let o = x
    o.d = 100

  cb()

proc f(): Opt =
  let a = new(Opt)  
  f1(a)
  return a

echo repr f()
