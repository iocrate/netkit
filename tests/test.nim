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
import os

# import netkit/http/base

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

type
  Opt = object
    x: string

  Test = ref object
    opt: Opt

proc `=destroy`(a: var Opt) = 
  echo "=destroy"

# proc g() =
#   var t: Test = Test()

# g()

# GC_fullCollect()

type
  Context = object
    cb: proc () {.gcsafe.}

  ContextPtr = ptr Context

var thr: array[0..1, Thread[ContextPtr]]

proc threadFunc(ctx: ContextPtr) {.thread.} =
  ctx.cb()

proc f(s: var string): ContextPtr = 
  var a = s
  var m = "efg"

  proc cb() = 
    echo "..."
    echo "cb:", a
    echo "m:", m
    a.add("efg")
  
  var env = system.protect(cb.rawEnv)
  # system.dispose(env)
  var ctx = cast[ContextPtr](allocShared0(sizeof(Context)))
  ctx.cb = cb
  return ctx

proc main() =
  var s = "abc"
  s.shallow()
  var ctx = f(s)
  GC_fullCollect()
  createThread(thr[0], threadFunc, ctx) 
  GC_fullCollect()
  GC_fullCollect()
  var a = "eee"
  var b = "eee"
  var c = a 
  echo "c:", c
  echo "0:", repr s
  joinThreads(thr)
  echo "1:", repr s

main()
