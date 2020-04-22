#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    destribution, for details about the copyright.

## HTTP 1.1 protocol specification supports chunked encoding. By adding a ``Transfer-Encoding: chunked`` 
## field to the message header, the message body can be sent chunk by chunk without determining the total
## size of the message body. Each data chunk needs to be encoded and decoded when it is sent and received.
## This module provides tools for dealing with these types of encodings and decodings.
## 
## Data Chunk and Data Tail
## ------------------------
## 
## The entire message body was split into zero or more data chunks and one data tail.
## 
## Each data chunk include chunk-size (specify the size of the data chunk), chunk-extensions (optional, 
## specify the extensions), and chunk-data (the actual data). Generally, such a data chunk is represented 
## as a header and a body. The header include chunk-size and chunk-extensions, and the body is the chunk-data. 
## 
## The last part of the message body is the data tail, indicating the end of the message body. The data tail
## supports carring trailers to allow the sender to add additional meta-information.
## 
## HTTP Message Example
## ---------------------
## 
## The following example is a chunked HTTP message body:
## 
## ..code-block:http
## 
##   5;\r\n                                      # chunk-size and chunk-extensions
##   Hello\r\n                                   # chunk-data
##   9; language=en; city=London\r\n             # chunk-size and chunk-extensions
##   Developer\r\n                               # chunk-data
##   0\r\n                                       # data tail ----------------------
##   Expires: Wed, 21 Oct 2015 07:28:00 GMT\r\n  # trailer
##   \r\n                                        # --------------------------------
## 
## Usage - encoding
## -----------------------------------------
## 
## To implement the HTTP message body shown in the above example, you can use the following methods:
## 
## ..code-block:http
## 
##   var message = ""
## 
##   message.add(encodeChunk("Hello"))
##   message.add(encodeChunk("Developer", {
##     "language": "en",
##     "city": "London"
##   }))
##   message.add(encodeChunkEnd(initHeaderFields({
##     "Expires": "Wed, 21 Oct 2015 07:28:00 GM"
##   })))
## 
## This example demonstrates the "string version of encodeChunk", this module also provides other efficient 
## encoding functions, you can view the specific description.
## 
## Usage - parsing
## ----------------------------
## 
## To parse a character sequence that consisting of chunk-size and chunk-extensions: 
## 
## ..code-block::nim
## 
##   let header = parseChunkHeader("1A; a1=v1; a2=v2") 
##   assert header.size = 26
##   assert header.extensions = "; a1=v1; a2=v2"
## 
## To parse a character sequence related to chunk-extensions ： 
## 
## ..code-block::nim
## 
##   let extensions = parseChunkExtensions("; a1=v1; a2=v2") 
##   assert extensions[0].name = "a1"
##   assert extensions[0].value = "v1"
##   assert extensions[1].name = "a1"
##   assert extensions[1].value = "v1"
## 
## To parse a group of character sequence related to tailers： 
## 
## ..code-block::nim
## 
##   let tailers = parseChunkHeader(@["Expires: Wed, 21 Oct 2015 07:28:00 GMT"]) 
##   assert tailers["Expires"][0] == "Wed, 21 Oct 2015 07:28:00 GMT"
## 
## About \n and \L 
## -------------------
## 
## Since ``\n`` cannot be represented as a character (but a string) in Nim language, we use 
## ``'\L'`` to represent a newline character. 

import strutils
import strtabs
import netkit/misc
import netkit/http/base
import netkit/http/constants as http_constants

type
  ChunkHeader* = object ## Represents the header of a data chunk.
    size*: Natural      ## Size of the data chunk.
    extensions*: string ## Extensions of the data chunk.

  ChunkExtension* = tuple ## Represents a chunk-extension.
    name: string          ## The name of this extension.
    value: string         ## The value of this extension

template seek(r: string, v: string, start: Natural, stop: Natural) = 
  if stop > start:
    var s = v[start..stop-1]
    s.removePrefix(WSP)
    s.removeSuffix(WSP)
    if s.len > 0:
      r = move s
  start = stop + 1

proc parseChunkHeader*(s: string): ChunkHeader {.raises: [ValueError].} = 
  ## Converts a string representing size and extensions into a ``ChunkHeader``. 
  ##
  ## Examples:
  ## 
  ## ..code-block::nim
  ## 
  ##   parseChunkHeader("64") # => (100, "")
  ##   parseChunkHeader("64; name=value") # => (100, "name=value")
  result.size = 0
  var i = 0
  while i < s.len:
    case s[i]
    of '0'..'9':
      result.size = result.size shl 4 or (s[i].ord() - 48) # '0'.ord()
    of 'a'..'f':
      result.size = result.size shl 4 or (s[i].ord() - 87) # 'a'.ord() - 10
    of 'A'..'F':
      result.size = result.size shl 4 or (s[i].ord() - 55) # 'A'.ord() - 10
    of ';':
      result.extensions = s[i..^1]
      break
    else:
      raise newException(ValueError, "Invalid chunked data")
    i.inc()

proc parseChunkExtensions*(s: string): seq[tuple[name: string, value: string]] = 
  ## Converts a string representing extensions into a ``(name, value)`` pair seq. 
  ## 
  ## Examples: 
  ## 
  ## ..code-block::nim
  ## 
  ##   let extensions = parseChunkExtensions(";a1=v1;a2=v2") 
  ##                  # => ("a1", "v1"), ("a2", "v2")
  ##   assert extensions[0].name == "a1"
  ##   assert extensions[0].value == "v1"
  ##   assert extensions[1].name == "a2"
  ##   assert extensions[1].value == "v2"
  var start = 0
  var stop = 0
  var flag = '\x0'
  var flagQuote = '\x0'
  var flagPair = '\x0'
  var key: string
  var value: string
  while stop < s.len:
    case flag
    of '"':
      case flagQuote
      of '\\':
        flagQuote = '\x0'
      else:
        case value[stop] 
        of '\\':
          flagQuote = '\\'
        of '"':
          flag = '\x0'
        else:
          discard
    else:
      case s[stop] 
      of '"':
        flag = '"'
      of '=':
        case flagPair
        of '=':
          discard # traits as a value
        else:
          flagPair = '='
          key.seek(s, start, stop) 
      of ';':
        case flagPair
        of '=':
          value.seek(s, start, stop) 
          flagPair = '\x0'
        else:
          key.seek(s, start, stop) 
        if key.len > 0 or value.len > 0:
          result.add((key, value))
          key = ""
          value = ""
      else:
        discard
    stop.inc()
  if key.len > 0 or value.len > 0:
    result.add((key, value))

proc parseChunkTrailers*(ts: openarray[string]): HeaderFields = 
  ## Converts a string array representing Trailer into a ``HeaderFields``. 
  ## 
  ## Examples: 
  ## 
  ## ..code-block::nim
  ## 
  ##   let fields = parseChunkTrailers(@["Expires: Wed, 21 Oct 2015 07:28:00 GMT"]) 
  ##              # => ("Expires", "Wed, 21 Oct 2015 07:28:00 GMT")  
  ##   assert fields["Expires"][0] == "Wed, 21 Oct 2015 07:28:00 GMT"
  discard
  result = initHeaderFields()
  for s in ts:
    var start = 0
    var stop = 0
    var key: string
    var value: string
    while stop < s.len:
      if s[stop] == ':':
        key.seek(s, start, stop) 
        break
      stop.inc()
    stop = s.len
    value.seek(s, start, stop) 
    if key.len > 0 or value.len > 0:
      result.add(key, value)

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
  ## Uses ``Transfer-Encoding: chunked`` to encode a data chunk. ``source`` specifies the actual data, and ``ssize``
  ## specifies the length of ``source``. The encoded data is copied to `` dest``, and ``dsize`` specifies the length 
  ## of ``dest``. 
  ## 
  ## Note that ``dsize`` must be at least ``21 + extensions.len`` larger than ``ssize``, otherwise, there 
  ## will not be enough space to store the encoded data, causing an exception. 
  ## 
  ## This function uses two buffers ``source`` and ``dest`` to handle the encoding process. It is very useful if you 
  ## need to process a large amount of data frequently and pay attention to the performance consumption during 
  ## processing. By saving references to the two buffers, you don't need to create additional storage space to save 
  ## the encoded data.
  ## 
  ## If you do not pay attention to the performance consumption during processing, or the amount of data is not large, 
  ## it is recommended to use the following string version of ``encodeChunk``.
  ## 
  ## Examples:
  ## 
  ## ..code-block::nim
  ## 
  ##   let source = "Developer"
  ##   let dest = newString(source.len + 21)
  ##   encodeChunk(source.cstring, source.len, dest.cstring, dest.len)
  ##   assert dest == "9\r\LDeveloper\r\L"
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
  ## Uses ``Transfer-Encoding: chunked`` to encode a data chunk. ``source`` specifies the actual data, and ``ssize``
  ## specifies the length of ``source``. The encoded data is copied to `` dest``, and ``dsize`` specifies the length 
  ## of ``dest``. ``extensions`` specifies the chunk-extensions. 
  ## 
  ## Note that ``dsize`` must be at least ``21 + extensions.len`` larger than ``ssize``, otherwise, there 
  ## will not be enough space to store the encoded data, causing an exception. 
  ## 
  ## This function uses two buffers ``source`` and ``dest`` to handle the encoding process. It is very useful if you 
  ## need to process a large amount of data frequently and pay attention to the performance consumption during 
  ## processing. By saving references to the two buffers, you don't need to create additional storage space to save 
  ## the encoded data.
  ## 
  ## If you do not pay attention to the performance consumption during processing, or the amount of data is not large, 
  ## it is recommended to use the following string version of ``encodeChunk``.
  ## 
  ## Examples:
  ## 
  ## ..code-block::nim
  ## 
  ##   let source = "Developer"
  ##   let extensions = "language=en; city=London"
  ##   let dest = newString(source.len + 21 + extensions.len)
  ##   encodeChunk(source.cstring, source.len, dest.cstring, dest.len, extensions)
  ##   assert dest == "9; language=en; city=London\r\LDeveloper\r\L"
  let extensionsStr = extensions.toChunkExtensions()
  if dsize - ssize - extensionsStr.len - 4 < LimitChunkSizeLen:
    raise newException(OverflowError, "Dest size is not large enough")
  let chunkSizeStr = ssize.toHex()  
  assert chunkSizeStr.len <= LimitChunkSizeLen
  encodeChunkImpl(source, ssize, dest, dsize, extensionsStr, chunkSizeStr)

proc encodeChunk*(source: string): string =
  ## Returns a data chunk encoded with ``Transfer-Encoding: chunked``. ``source`` specifies the actual data. 
  ## This one has no metadata.
  ## 
  ## This is the string version of ``encodeChunk``, which is more convenient and simple to use.
  ## 
  ## Examples:
  ## 
  ## ..code-block::nim
  ## 
  ##   let out = encodeChunk("Developer")
  ##   assert out == "9\r\LDeveloper\r\L"
  let chunkSizeStr = source.len.toHex()  
  assert chunkSizeStr.len <= LimitChunkSizeLen
  result = newString(chunkSizeStr.len + source.len + 4)
  encodeChunkImpl(source.cstring, source.len, result.cstring, result.len, void, chunkSizeStr)

proc encodeChunk*(source: string, extensions: openarray[tuple[name: string, value: string]]): string = 
  ## Returns a data chunk encoded with ``Transfer-Encoding: chunked``. ``source`` specifies the actual data, 
  ## ``extensions`` specifies the chunk-extensions. 
  ## 
  ## This is the string version of ``encodeChunk``, which is more convenient and simple to use.
  ## 
  ## Examples:
  ## 
  ## ..code-block::nim
  ## 
  ##   let out = encodeChunk("Developer", {
  ##     "language": "en",
  ##     "city": "London"
  ##   })
  ##   assert out == "9; language=en; city=London\r\LDeveloper\r\L"
  let extensionsStr = extensions.toChunkExtensions()
  let chunkSizeStr = source.len.toHex()  
  assert chunkSizeStr.len <= LimitChunkSizeLen
  result = newString(chunkSizeStr.len + extensionsStr.len + source.len + 4)
  encodeChunkImpl(source.cstring, source.len, result.cstring, result.len, extensionsStr, chunkSizeStr)

proc encodeChunkEnd*(): string = 
  ## Returns a data tail encoded with ``Transfer-Encoding: chunked``. This one has no metadata.
  ## 
  ## Examples: 
  ## 
  ## ..code-block:nim
  ## 
  ##   let out = encodeChunkEnd()
  ##   assert out == "0\r\L\r\L"
  result = "0\C\L\C\L"

proc encodeChunkEnd*(trailers: openarray[tuple[name: string, value: string]]): string = 
  ## Returns a data tail encoded with ``Transfer-Encoding: chunked``. ``trailers`` specifies the carried metadata。
  ## 
  ## Examples: 
  ## 
  ## ..code-block:nim
  ## 
  ##   let out = encodeChunkEnd(initHeaderFields({
  ##     "Expires": "Wed, 21 Oct 2015 07:28:00 GM"
  ##   }))
  ##   assert out == "0\r\LExpires: Wed, 21 Oct 2015 07:28:00 GM\r\L\r\L"
  result.add("0\C\L")
  for trailer in trailers:
    result.add(trailer.name)
    result.add(": ")
    result.add(trailer.value)
    result.add("\C\L")
  result.add("\C\L")
  