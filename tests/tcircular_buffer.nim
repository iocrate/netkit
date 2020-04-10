#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import unittest
import netkit/buffer/constants
import netkit/buffer/circular

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
    check buffer.popMarks() == "abc"
    check buffer.len == 5

    (regionPtr, regionLen) = buffer.next()
    check regionLen == BufferSize - 8

    check buffer.markUntil('f')

    check buffer.lenMarks() == 3
    check buffer.popMarks(2) == "d"
    check buffer.len == 2

    (regionPtr, regionLen) = buffer.next()
    check regionLen == BufferSize - 8

    check buffer.mark(100) == 2

    check buffer.lenMarks() == 2
    check buffer.popMarks(1) == "g"
    check buffer.len == 0

    (regionPtr, regionLen) = buffer.next()
    check regionLen == BufferSize

  test "get and del":
    var dest = newString(8)

    check buffer.get(dest.cstring, 3) == 3
    check buffer.del(3) == 3
    dest.setLen(3)
    check dest == "abc"
    check buffer.len == 5

    check buffer.get(dest.cstring, 3) == 3
    check buffer.del(3) == 3
    dest.setLen(3)
    check dest == "def"
    check buffer.len == 2

    check buffer.get(dest.cstring, 3) == 2
    check buffer.del(3) == 2
    dest.setLen(2)
    check dest == "gh"
    check buffer.len == 0

    check buffer.get(dest.cstring, 3) == 0
    check buffer.del(3) == 0

  test "get and del with marks":
    for c in buffer.marks():
      if c == 'c':
        break

    (regionPtr, regionLen) = buffer.next()
    check regionLen < BufferSize

    check buffer.lenMarks() == 3
    check buffer.get(3) == "abc"
    check buffer.del(3) == 3
    check buffer.len == 5

    (regionPtr, regionLen) = buffer.next()
    check regionLen == BufferSize - 8

    check buffer.markUntil('f')

    check buffer.lenMarks() == 3
    check buffer.popMarks(2) == "d"
    check buffer.len == 2

    (regionPtr, regionLen) = buffer.next()
    check regionLen == BufferSize - 8

    check buffer.mark(100) == 2

    check buffer.lenMarks() == 2
    check buffer.get(1) == "g"
    check buffer.del(2) == 2
    check buffer.len == 0

    (regionPtr, regionLen) = buffer.next()
    check regionLen == BufferSize
