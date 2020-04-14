#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import netkit/misc
import netkit/http/base

proc parseChunkSizer*(s: string): ChunkSizer = 
  result.size = 0
  var i = 0
  while true:
    case s[i]
    of '0'..'9':
      result.size = result.size shl 4 or (s[i].ord() - '0'.ord())
    of 'a'..'f':
      result.size = result.size shl 4 or (s[i].ord() - 'a'.ord() + 10)
    of 'A'..'F':
      result.size = result.size shl 4 or (s[i].ord() - 'A'.ord() + 10)
    # of '\0': # TODO: what'is this
    #   break
    of ';':
      result.extensions = s[i..^1]
      break
    else:
      raise newException(ValueError, "Invalid Chunk Encoded")
    i.inc()

proc toChunkSize*(x: Natural): string = 
  ## 请注意， 当前 ``Natural`` 最大值是 ``high(int64)`` 。 当 ``Natural`` 最大值超过 ``high(int64)``
  ## 的时候， 该函数将不再准确。 
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

proc encodeToChunk*(source: pointer, sourceSize: Natural, dist: pointer, distSize: Natural) =
  ## 
  ## TODO: 优化 
  if distSize - sourceSize < 10:
    raise newException(OverflowError, "dist size must be large than souce")
  let chunksize = sourceSize.toChunkSize()  
  assert chunkSize.len <= 5
  copyMem(dist, chunksize.cstring, chunksize.len)
  cast[ptr char](dist.offset(chunksize.len))[] = CR
  cast[ptr char](dist.offset(chunksize.len + 1))[] = LF
  copyMem(dist.offset(chunksize.len + 2), source, sourceSize)
  cast[ptr char](dist.offset(chunksize.len + 2 + sourceSize))[] = CR
  cast[ptr char](dist.offset(chunksize.len + 2 + sourceSize + 1))[] = LF

proc encodeToChunk*(source: pointer, sourceSize: Natural, dist: pointer, distSize: Natural, extensions: string) =
  ## 
  ## TODO: 优化 
  if distSize - sourceSize - extensions.len < 10:
    raise newException(OverflowError, "dist size must be large than souce")
  let chunksize = sourceSize.toChunkSize()  
  assert chunkSize.len <= 5
  copyMem(dist, chunksize.cstring, chunksize.len)
  copyMem(dist.offset(chunksize.len), extensions.cstring, extensions.len)
  cast[ptr char](dist.offset(chunksize.len + extensions.len))[] = CR
  cast[ptr char](dist.offset(chunksize.len + 1 + extensions.len))[] = LF
  copyMem(dist.offset(chunksize.len + 2 + extensions.len), source, sourceSize)
  cast[ptr char](dist.offset(chunksize.len + 2 + sourceSize + extensions.len))[] = CR
  cast[ptr char](dist.offset(chunksize.len + 2 + sourceSize + 1 + extensions.len))[] = LF