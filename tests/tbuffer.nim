#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import unittest
import netkit/buffer

suite "MarkableCircularBuffer":
  setup:
    var buffer = MarkableCircularBuffer()
    var str = "abcdefgh"

    var (regionPtr, regionLen) = buffer.next()
    check regionLen == BufferSize

    copyMem(regionPtr, str.cstring, min(str.len, regionLen.int))
    discard buffer.pack(8)

  test "marks":
    for c in buffer.marks():
      if c == 'c':
        break

    (regionPtr, regionLen) = buffer.next()
    check regionLen < BufferSize

    check buffer.lenMarks() == 3
    check buffer.getMarks() == "abc"
    check buffer.len == 5

    (regionPtr, regionLen) = buffer.next()
    check regionLen == BufferSize - 8

    check buffer.markUntil('f')

    check buffer.lenMarks() == 3
    check buffer.getMarks() == "def"
    check buffer.len == 2

    (regionPtr, regionLen) = buffer.next()
    check regionLen == BufferSize - 8

    check buffer.mark(100) == 2

    check buffer.lenMarks() == 2
    check buffer.getMarks() == "gh"
    check buffer.len == 0

    (regionPtr, regionLen) = buffer.next()
    check regionLen == BufferSize

  test "moveTo":
    var dest = newString(8)

    var n1 = buffer.moveTo(dest.cstring, 3)
    dest.setLen(3)
    check n1 == 3
    check dest == "abc"
    check buffer.len == 5

    var n2 = buffer.moveTo(dest.cstring, 3)
    dest.setLen(3)
    check n2 == 3
    check dest == "def"
    check buffer.len == 2

    var n3 = buffer.moveTo(dest.cstring, 3)
    dest.setLen(2)
    check n3 == 2
    check dest == "gh"
    check buffer.len == 0

    var n4 = buffer.moveTo(dest.cstring, 3)
    check n4 == 0