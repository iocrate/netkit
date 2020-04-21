#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    destribution, for details about the copyright.

## According to the HTTP protocol, a message whose header fields have ``Transfer-Encoding: chunked`` will be encoded, 
## so that the data is sent chunk by chunk as a stream. These data chunk require to be encoded and decoded. This module 
## provides tools for dealing with this type of encodings and decoding.

import strutils
import strtabs
import netkit/misc
import netkit/http/base
import netkit/http/constants as http_constants

type
  ChunkHeader* = object ## Represents the size portion of the encoded data via ``Transfer-Encoding: chunked``.
    size*: Natural
    extensions*: string

proc parseChunkHeader*(s: string): ChunkHeader = 
  ##
  ## ``"1C" => (28, "")``  
  ## ``"1C; name=value" => (28, "name=value")``
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
    of ';':
      result.extensions = s[i..^1]
      break
    else:
      raise newException(ValueError, "Bad chunked data")
    i.inc()

proc parseChunkTrailer*(lines: openarray[string]): HeaderFields = 
  ## 
  ## 
  ## ``"Expires: Wed, 21 Oct 2015 07:28:00 GMT" => ("Expires", "Wed, 21 Oct 2015 07:28:00 GMT")``  
  discard
  result = initHeaderFields()
  for line in lines:
    var i = 0
    for c in line:
      if c == COLON:
        break
      i.inc()
    if i > 0:
      result.add(line[0..i-1], line[i+1..^1])

proc parseChunkExtensions*(s: string): StringTableRef = 
  ## 
  ## 
  ## ``";a1=v1;a2=v2" => ("a1", "v1"), ("a2", "v2")``  
  ## ``";a1;a2=v2" => ("a1", ""  ), ("a2", "v2")``  
  discard
  ## TODO: implement it

proc toHex(x: Natural): string = 
  ## 请注意， 当前 ``Natural`` 最大值是 ``high(int64)`` 。 当 ``Natural`` 最大值超过 ``high(int64)``
  ## 的时候， 该函数将不再准确。 
  ## 
  ## ``28 => "1C"``
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

proc toChunkExtensions(args: openarray[tuple[name: string, value: string]]): string = 
  ## 
  ## 
  ## ``("a1", "v1"), ("a2", "v2") => ";a1=v1;a2=v2"``  
  ## ``("a1", ""  ), ("a2", "v2") => ";a1;a2=v2"``
  for arg in args:
    result.add(';')
    if arg.value.len > 0:
      result.add(arg.name)
      result.add('=')
      result.add(arg.value)
    else:
      result.add(arg.name)

template encodeChunkImpl(
  source: pointer, 
  ssize: Natural, 
  dest: pointer, 
  dsize: Natural, 
  extensionsStr: untyped, 
  chunkSizeStr: string
) = 
  copyMem(dest, chunkSizeStr.cstring, chunkSizeStr.len)
  var pos = chunkSizeStr.len
  when extensionsStr is string:
    if extensionsStr.len > 0:
      copyMem(dest.offset(pos), extensionsStr.cstring, extensionsStr.len)
      pos = pos + extensionsStr.len
  cast[ptr char](dest.offset(pos))[] = CR
  cast[ptr char](dest.offset(pos + 1))[] = LF
  copyMem(dest.offset(pos + 2), source, ssize)
  pos = pos + 2 + ssize
  cast[ptr char](dest.offset(pos))[] = CR
  cast[ptr char](dest.offset(pos + 1))[] = LF

proc encodeChunk*(
  source: pointer, 
  ssize: Natural, 
  dest: pointer, 
  dsize: Natural
) = 
  ## 
  ## 
  ## ..code-block::bnf
  ## 
  ##   chunk-ext = *( ";" chunk-ext-name [ "=" chunk-ext-val ] )
  ## 
  ## ``"abc" => "3\r\nabc\r\n"``  
  ## ``"abc", ";n1=v1;n2=v2" => "3;n1=v1;n2=v2\r\nabc\r\n"``
  if dsize - ssize - 4 < LimitChunkSizeLen:
    raise newException(OverflowError, "Dest size is not large enough")
  let chunkSizeStr = ssize.toHex()  
  assert chunkSizeStr.len <= LimitChunkSizeLen
  encodeChunkImpl(source, ssize, dest, dsize, void, chunkSizeStr)

proc encodeChunk*(
  source: pointer, 
  ssize: Natural, 
  dest: pointer, 
  dsize: Natural, 
  extensions = openarray[tuple[name: string, value: string]]
) = 
  ## 
  ## 
  ## ..code-block::bnf
  ## 
  ##   chunk-ext = *( ";" chunk-ext-name [ "=" chunk-ext-val ] )
  ## 
  ## ``"abc" => "3\r\nabc\r\n"``  
  ## ``"abc", ";n1=v1;n2=v2" => "3;n1=v1;n2=v2\r\nabc\r\n"``
  let extensionsStr = extensions.toChunkExtensions()
  if dsize - ssize - extensionsStr.len - 4 < LimitChunkSizeLen:
    raise newException(OverflowError, "Dest size is not large enough")
  let chunkSizeStr = ssize.toHex()  
  assert chunkSizeStr.len <= LimitChunkSizeLen
  encodeChunkImpl(source, ssize, dest, dsize, extensionsStr, chunkSizeStr)

proc encodeChunk*(source: string): string = 
  ## 
  ## 
  ## ..code-block::bnf
  ## 
  ##   chunk-ext = *( ";" chunk-ext-name [ "=" chunk-ext-val ] )
  ## 
  ## ``"abc" => "3\r\nabc\r\n"``
  ## ``"abc", ";n1=v1;n2=v2" => "3;n1=v1;n2=v2\r\nabc\r\n"``
  let chunkSizeStr = source.len.toHex()  
  assert chunkSizeStr.len <= LimitChunkSizeLen
  result = newString(chunkSizeStr.len + source.len + 4)
  encodeChunkImpl(source.cstring, source.len, result.cstring, result.len, void, chunkSizeStr)

proc encodeChunk*(source: string, extensions: openarray[tuple[name: string, value: string]]): string = 
  ## 
  ## 
  ## ..code-block::bnf
  ## 
  ##   chunk-ext = *( ";" chunk-ext-name [ "=" chunk-ext-val ] )
  ## 
  ## ``"abc" => "3\r\nabc\r\n"``
  ## ``"abc", ";n1=v1;n2=v2" => "3;n1=v1;n2=v2\r\nabc\r\n"``
  let extensionsStr = extensions.toChunkExtensions()
  let chunkSizeStr = source.len.toHex()  
  assert chunkSizeStr.len <= LimitChunkSizeLen
  result = newString(chunkSizeStr.len + extensionsStr.len + source.len + 4)
  encodeChunkImpl(source.cstring, source.len, result.cstring, result.len, extensionsStr, chunkSizeStr)

proc encodeChunkEnd*(): string = 
  ## 
  ## 
  ## ``=> "0\r\n\r\n"``
  ## ``("n1", "v1"), ("n2", "v2") => "0\r\nn1: v1\r\nn2: v2\r\n\r\n"``  
  result = "0\C\L\C\L"

proc encodeChunkEnd*(trailers: openarray[tuple[name: string, value: string]]): string = 
  ## 
  ## 
  ## ``=> "0\r\n\r\n"``
  ## ``("n1", "v1"), ("n2", "v2") => "0\r\nn1: v1\r\nn2: v2\r\n\r\n"``  
  result.add("0\C\L")
  for trailer in trailers:
    result.add(trailer.name)
    result.add(": ")
    result.add(trailer.value)
    result.add("\C\L")
  result.add("\C\L")
  