#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import netkit/misc, netkit/http/base

proc decodeChunkSizer*(line: string): ChunkSizer = 
  result.size = 0
  var i = 0
  while true:
    case line[i]
    of '0'..'9':
      result.size = result.size shl 4 or (line[i].ord() - '0'.ord())
    of 'a'..'f':
      result.size = result.size shl 4 or (line[i].ord() - 'a'.ord() + 10)
    of 'A'..'F':
      result.size = result.size shl 4 or (line[i].ord() - 'A'.ord() + 10)
    of '\0': # TODO: what'is this
      break
    of ';':
      result.extensions = line[i..^1]
      break
    else:
      raise newException(ValueError, "Invalid Chunk Encoded")
    i.inc()

proc toChunkSize*(x: BiggestInt): string {.noInit.} = 
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