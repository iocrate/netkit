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
  Server = ref object
    onRequest: proc (): Future[void]

var server = new(Server)

server.onRequest = proc () {.async.} =
  await sleepAsync(1000)
  echo "handler ......"

asyncCheck server.onRequest()

runForever()