#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import unittest, netkit/http/base, asyncdispatch

template f(t: untyped) =
  proc cb() = 
    let fut = t
    fut.callback = proc () =
      discard
  
  echo "f()"    
  cb()

proc test(): char =
  echo "..."
  return 'a'

proc futDemo(): Future[int] = 
  echo "futDemo()"
  result = newFuture[int]()

f: futDemo()