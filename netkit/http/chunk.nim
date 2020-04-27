#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    destribution, for details about the copyright.

## HTTP 1.1 supports chunked encoding, which allows HTTP messages to be broken up into several parts. 
## Chunking is most often used by the server for responses, but clients can also chunk large requests.
## By adding ``Transfer-Encoding: chunked`` to a message header, this message can be sent chunk by chunk. 
## Each data chunk requires to be encoded and decoded when it is sent and received. This module provides 
## tools for dealing with these types of encodings and decodings.
## 
## Overview
## ========================
## 
## .. container:: r-fragment
## 
##   Format
##   ------------------------
## 
##   If a ``Transfer-Encoding`` field with a value of ``"chunked"`` is specified in an HTTP message (either a 
##   request sent by a client or the response from the server), the body of the message consists of an 
##   unspecified number of chunks, a terminating chunk, trailer, and a final CRLF sequence (i.e. carriage 
##   return followed by line feed).
## 
##   Each chunk starts with the number of octets of the data it embeds expressed as a hexadecimal number in 
##   ASCII followed by optional parameters (chunk extension) and a terminating CRLF sequence, followed by 
##   the chunk data. The chunk is terminated by CRLF.
## 
##   If chunk extensions are provided, the chunk size is terminated by a semicolon and followed by the parameters, 
##   each also delimited by semicolons. Each parameter is encoded as an extension name followed by an optional 
##   equal sign and value. These parameters could be used for a running message digest or digital signature, or to 
##   indicate an estimated transfer progress, for instance.
## 
##   The terminating chunk is a regular chunk, with the exception that its length is zero. It is followed by the
##   trailer, which consists of a (possibly empty) sequence of entity header fields. Normally, such header fields  
##   would be sent in the message's header; however, it may be more efficient to determine them after processing   
##   the entire message entity. In that case, it is useful to send those headers in the trailer.
##
##   Header fields that regulate the use of trailers are ``TE`` (used in requests), and ``Trailers`` (used in 
##   responses).
## 
##   ..
## 
##     See `Chunked transfer encoding <https://en.wikipedia.org/wiki/Chunked_transfer_encoding>`_ for more information. 
## 
## .. container:: r-fragment
## 
##   Example
##   ------------------------
## 
##   Here is an example of a body of a chunked message:
## 
##   .. code-block::http
## 
##     5;\r\n                                      # chunk-size and chunk-extensions (empty)
##     Hello\r\n                                   # data
##     9; language=en; city=London\r\n             # chunk-size and chunk-extensions
##     Developer\r\n                               # data
##     0\r\n                                       # terminating chunk ---------------------
##     Expires: Wed, 21 Oct 2015 07:28:00 GMT\r\n  # trailer
##     \r\n                                        # final CRLF-----------------------------
## 
## .. container:: r-fragment
## 
##   About \\n and \\L 
##   ------------------------
## 
##   Since ``\n`` cannot be represented as a character (but a string) in Nim language, we use 
##   ``'\L'`` to represent a newline character here. 
## 
## Usage
## ========================
## 
## .. container:: r-fragment
## 
##   Encoding
##   ------------------------
## 
##   To implement a chunked body shown in the above example:
## 
##   .. code-block::nim
## 
##     import netkit/http/chunk
##     import netkit/http/headerfield
## 
##     assert encodeChunk("Hello") == "5;\r\nHello\r\n"
## 
##     assert encodeChunk("Developer", {
##       "language": "en",
##       "city": "London"
##     }) == "9; language=en; city=London\r\nDeveloper\r\n"
## 
##     assert encodeChunkEnd(initHeaderFields({
##       "Expires": "Wed, 21 Oct 2015 07:28:00 GMT"
##     })) == "0\r\nExpires: Wed, 21 Oct 2015 07:28:00 GMT\r\n\r\n"
## 
##   This example demonstrates the string version of the encoding procs. However, there is also a 
##   more efficient solution.
## 
##   Encoding with pointer buffer
##   --------------------------------
## 
##   Continuously reads data from a file and then encodes the data:
## 
##   .. code-block::nim
## 
##     import netkit/http/chunk
##     import netkit/http/headerfield
##     
##     var source: array[64, byte]
##     var dest: array[128, byte]
##     
##     # open a large file
##     var file = open("test.blob") 
##     
##     while true:
##       let readLen = file.readBuffer(source.addr, 64)
## 
##       if readLen > 0:
##         let encodeLen = encodeChunk(source.addr, readLen, dest.addr, 128)
##         # handle dest, encodeLen ...
## 
##       # read EOF
##       if readLen < 64: 
##         echo encodeChunkEnd(initHeaderFields({
##           "Expires": "Wed, 21 Oct 2015 07:28:00 GMT"
##         }))
##         break
## 
##   ..
## 
##     Consider using pointer buffer when you are dealing with large amounts of data and are very  
##     concerned about memory consumption. 
## 
## .. container:: r-fragment
## 
##   Decoding
##   ------------------------
## 
##   To parse a char sequence consisting of chunk-size and chunk-extensions: 
## 
##   .. code-block::nim
## 
##     import netkit/http/chunk
## 
##     let header = parseChunkHeader("1A; a1=v1; a2=v2") 
##     assert header.size = 26
##     assert header.extensions = "; a1=v1; a2=v2"
## 
##   To parse a char sequence associated with chunk-extensions ： 
## 
##   .. code-block::nim
## 
##     import netkit/http/chunk
## 
##     let extensions = parseChunkExtensions("; a1=v1; a2=v2") 
##     assert extensions[0].name = "a1"
##     assert extensions[0].value = "v1"
##     assert extensions[1].name = "a2"
##     assert extensions[1].value = "v2"
## 
##   To parse a set of char sequence associated with tailers： 
## 
##   .. code-block::nim
## 
##     import netkit/http/chunk
## 
##     let tailers = parseChunkTrailers(@["Expires: Wed, 21 Oct 2015 07:28:00 GMT"]) 
##     assert tailers["Expires"][0] == "Wed, 21 Oct 2015 07:28:00 GMT"

import strutils
import strtabs
import netkit/misc
import netkit/http/spec
import netkit/http/limits
import netkit/http/headerfield

type
  ChunkHeader* = object ## Represents the header of a chunk.
    size*: Natural      
    extensions*: string 

  ChunkExtension* = tuple ## Represents a chunk extension.
    name: string          
    value: string  

template seek(r: string, v: string, start: Natural, stop: Natural) = 
  if stop > start:
    var s = v[start..stop-1]
    s.removePrefix(WSP)
    s.removeSuffix(WSP)
    if s.len > 0:
      r = move(s)
  start = stop + 1

proc parseChunkHeader*(s: string): ChunkHeader {.raises: [ValueError].} = 
  ## Converts a string to a ``ChunkHeader``. 
  ##
  ## Examples:
  ## 
  ## .. code-block::nim
  ## 
  ##   parseChunkHeader("64") # => (100, "")
  ##   parseChunkHeader("64; name=value") # => (100, "; name=value")
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

proc parseChunkExtensions*(s: string): seq[ChunkExtension] = 
  ## Converts a string representing extensions to a set of ``(name, value)`` pair. 
  ## 
  ## Examples: 
  ## 
  ## .. code-block::nim
  ## 
  ##   let extensions = parseChunkExtensions(";a1=v1;a2=v2") 
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

proc parseChunkTrailers*(ts: openArray[string]): HeaderFields = 
  ## Converts a string array representing trailers to a ``HeaderFields``. 
  ## 
  ## Examples: 
  ## 
  ## .. code-block::nim
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

proc toChunkExtensions(args: openArray[ChunkExtension]): string = 
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
  dest: pointer, 
  size: Natural, 
  extensionsStr: untyped, 
  chunkSizeStr: string
): Natural = 
  copyMem(dest, chunkSizeStr.cstring, chunkSizeStr.len)
  var pos = chunkSizeStr.len
  when extensionsStr is string:
    if extensionsStr.len > 0:
      copyMem(dest.offset(pos), extensionsStr.cstring, extensionsStr.len)
      pos = pos + extensionsStr.len
  cast[ptr char](dest.offset(pos))[] = CR
  cast[ptr char](dest.offset(pos + 1))[] = LF
  copyMem(dest.offset(pos + 2), source, size)
  pos = pos + 2 + size
  cast[ptr char](dest.offset(pos))[] = CR
  cast[ptr char](dest.offset(pos + 1))[] = LF
  pos = pos + 2
  pos

proc encodeChunk*(
  source: pointer, 
  dest: pointer, 
  size: Natural
): Natural = 
  ## Encodes ``size`` bytes from the buffer ``source``, storing the results in the buffer ``dest``. The return 
  ## value is the number of bytes of the results.
  ## 
  ## **Note:** the length of ``dest`` must be at least ``21`` bytes larger than ``source`` to hold the results. 
  ## 
  ## Examples:
  ## 
  ## .. code-block::nim
  ## 
  ##   let source = "Developer"
  ##   let dest = newString(source.len + 21)
  ##   encodeChunk(source.cstring, source.len, dest.cstring, dest.len)
  ##   assert dest == "9\r\nDeveloper\r\n"
  let chunkSizeStr = size.toHex()  
  assert chunkSizeStr.len <= LimitChunkSizeLen
  result = encodeChunkImpl(source, dest, size, void, chunkSizeStr)

proc encodeChunk*(
  source: pointer, 
  dest: pointer, 
  size: Natural,
  extensions = openArray[ChunkExtension]
): Natural = 
  ## Encodes ``size`` bytes from the buffer ``source``, storing the results in the buffer ``dest``. ``extensions`` 
  ## specifies chunk extensions. The return value is the number of bytes of the results.
  ## 
  ## **Note:** the length of ``dest`` must be at least ``21 + extensions.len`` bytes larger than ``source`` to 
  ## hold the results. 
  ## 
  ## Examples:
  ## 
  ## .. code-block::nim
  ## 
  ##   let source = "Developer"
  ##   let extensions = "language=en; city=London"
  ##   let dest = newString(source.len + 21 + extensions.len)
  ##   encodeChunk(source.cstring, source.len, dest.cstring, dest.len, extensions)
  ##   assert dest == "9; language=en; city=London\r\nDeveloper\r\n"
  let extensionsStr = extensions.toChunkExtensions()
  let chunkSizeStr = size.toHex()  
  assert chunkSizeStr.len <= LimitChunkSizeLen
  result = encodeChunkImpl(source, dest, size, extensionsStr, chunkSizeStr)

proc encodeChunk*(source: string): string =
  ## Encodes ``source`` into a chunk. 
  ## 
  ## Examples:
  ## 
  ## .. code-block::nim
  ## 
  ##   let dest = encodeChunk("Developer")
  ##   assert dest == "9\r\nDeveloper\r\n"
  let chunkSizeStr = source.len.toHex()  
  assert chunkSizeStr.len <= LimitChunkSizeLen
  result = newString(chunkSizeStr.len + source.len + 4)
  discard encodeChunkImpl(source.cstring, result.cstring, source.len, void, chunkSizeStr)

proc encodeChunk*(source: string, extensions: openArray[ChunkExtension]): string = 
  ## Encodes ``source`` into a chunk. ``extensions`` specifies chunk extensions. 
  ## 
  ## Examples:
  ## 
  ## .. code-block::nim
  ## 
  ##   let dest = encodeChunk("Developer", {
  ##     "language": "en",
  ##     "city": "London"
  ##   })
  ##   assert dest == "9; language=en; city=London\r\nDeveloper\r\n"
  let extensionsStr = extensions.toChunkExtensions()
  let chunkSizeStr = source.len.toHex()  
  assert chunkSizeStr.len <= LimitChunkSizeLen
  result = newString(chunkSizeStr.len + extensionsStr.len + source.len + 4)
  discard encodeChunkImpl(source.cstring, result.cstring, source.len, extensionsStr, chunkSizeStr)

proc encodeChunkEnd*(): string = 
  ## Returns a string consisting of a terminating chunk and a final CRLF sequence.
  ## 
  ## Examples: 
  ## 
  ## .. code-block::nim
  ## 
  ##   let dest = encodeChunkEnd()
  ##   assert dest == "0\r\n\r\n"
  result = "0\C\L\C\L"

proc encodeChunkEnd*(trailers: HeaderFields): string = 
  ## Returns a string consisting of a terminating chunk, trailer and a final CRLF sequence. ``trailers`` specifies 
  ## the metadata carried.
  ## 
  ## Examples: 
  ## 
  ## .. code-block::nim
  ## 
  ##   let dest = encodeChunkEnd(initHeaderFields({
  ##     "Expires": "Wed, 21 Oct 2015 07:28:00 GM"
  ##   }))
  ##   assert dest == "0\r\nExpires: Wed, 21 Oct 2015 07:28:00 GM\r\n\r\n"
  result.add("0\C\L")
  result.add($trailers)
  result.add("\C\L")
