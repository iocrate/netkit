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



# a.add('d')

# echo repr a
# echo repr b

# var m = f()

# x.add("1")
# echo repr x
# echo repr m

proc toChunkSize(x: uint64): string {.noInit.} = 
  # TODO: 修复 bug，最大长度是 16 = 64 / 4
  const HexChars = "0123456789ABCDEF"
  var n = x
  var m = 0
  var s = newString(16)
  for j in countdown(15, 0):
    s[j] = HexChars[n and 0xF]
    n = n shr 4
    m.inc()
    if n == 0: 
      break
  result = newStringOfCap(m)
  for i in 16-m..15:
    result.add(s[i])

proc toChunkSize2(x: uint64): string {.noInit.} = 
  # TODO: 修复 bug，最大长度是 16 = 64 / 4
  const HexChars = "0123456789ABCDEF"
  var n = x
  var m = 0
  var s = newString(5) # sizeof(BiggestInt) * 10 / 16
  for j in countdown(4, 0):
    s[j] = HexChars[n and 0xF]
    n = n shr 4
    m.inc()
    if n == 0: 
      break
  result = newStringOfCap(m)
  for i in 5-m..<5:
    result.add(s[i])

echo toChunkSize(uint64.high), " ", toChunkSize2(uint64.high)
echo toChunkSize(1024000000), " ", toChunkSize2(1024000000)
# echo repr toChunkSize(1_000_000_000_000)
