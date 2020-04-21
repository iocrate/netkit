#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## HTTP 消息支持 ``Transfer-Encoding: chunked`` 编码， 将数据以流的形式逐块发送。 发送和接收的每一块数据
## 都需要进行一些编码和解码。 本模块提供了处理这些编码和解码相关的工具。 

# ==============  ==========  =====  ============================================
# Name            工具         用途    描述
# ==============  ==========  =====  ============================================
# Parsing         Parser      解析    将字符序列转换成一个对象树表示
# Serialization   Serializer  序列化   将一个对象树转换成一个字符序列
# Encoding        Encoder     编码    将一个字符序列进行扰码或者变换转换成另一个字符序列
# Decoding        Decoder     解码    将一个经过扰码或者变换的字符序列转换成原始的字符序列
# ==============  ==========  =====  ============================================

import strutils
import strtabs
import netkit/misc
import netkit/http/base
import netkit/http/constants as http_constants

type
  ChunkHeader* = tuple ## 
    size: Natural
    extensions: string

proc parseChunkHeader*(s: string): ChunkHeader = discard
  ## 解析一个字符串， 该字符串通过 ``Transfer-Encoding: chunked`` 编码， 表示块数据的大小和可选的块扩展。  
  ## 
  ## ``"64" => (100, "")``  
  ## ``"64; name=value" => (100, "name=value")``

proc parseChunkTrailer*(lines: openarray[string]): HeaderFields = 
  ## 解析一个字符串， 该字符串通过 ``Transfer-Encoding: chunked`` 编码， 表示块数据的一个 Trailer 。 
  ## 
  ## ``"Expires: Wed, 21 Oct 2015 07:28:00 GMT" => ("Expires", "Wed, 21 Oct 2015 07:28:00 GMT")``  

proc parseChunkExtensions*(s: string): StringTableRef = discard

proc encodeChunk*(
  source: pointer, 
  ssize: Natural, 
  dest: pointer, 
  dsize: Natural
) = discard
  ## 将 ``source`` 转换为一块经过 ``Transfer-Encoding: chunked`` 编码的数据块， 包括块大小行和数据行。 ``extensions`` 
  ## 指定块扩展。 ``sourceLen`` 指定原始数据的长度； ``dist`` 存储经过转换的数据块， ``distLen`` 指定该存储空间的长度。 
  ## 
  ## 注意， ``distLen`` 的长度必须比 ``sourceLen`` 的长度至少大 20 + extensions.len， 否则， 将会引起长度溢出异常。 
  ## 
  ## 根据 `RFC 7230 <https://tools.ietf.org/html/rfc7230#section-4.1.1>`_ 
  ## 
  ## ..code-block::bnf
  ## 
  ##   chunk-ext = *( ";" chunk-ext-name [ "=" chunk-ext-val ] )
  ## 
  ## ``"abc" => "3\r\nabc\r\n"``  
  ## ``"abc", ";a1=v1;a2=v2" => "3;a1=v1;a2=v2\r\nabc\r\n"``

proc encodeChunk*(
  source: pointer, 
  ssize: Natural, 
  dest: pointer, 
  dsize: Natural, 
  extensions = openarray[tuple[name: string, value: string]]
) = discard
  ## 将 ``source`` 转换为一块经过 ``Transfer-Encoding: chunked`` 编码的数据块， 包括块大小行和数据行。 ``extensions`` 
  ## 指定块扩展。 ``sourceLen`` 指定原始数据的长度； ``dist`` 存储经过转换的数据块， ``distLen`` 指定该存储空间的长度。 
  ## 
  ## 注意， ``distLen`` 的长度必须比 ``sourceLen`` 的长度至少大 20 + extensions.len， 否则， 将会引起长度溢出异常。 
  ## 
  ## 根据 `RFC 7230 <https://tools.ietf.org/html/rfc7230#section-4.1.1>`_ 
  ## 
  ## ..code-block::bnf
  ## 
  ##   chunk-ext = *( ";" chunk-ext-name [ "=" chunk-ext-val ] )
  ## 
  ## ``"abc" => "3\r\nabc\r\n"``  
  ## ``"abc", ";a1=v1;a2=v2" => "3;a1=v1;a2=v2\r\nabc\r\n"``

proc encodeChunk*(source: string): string = discard
  ## 将 ``source`` 转换为一块经过 ``Transfer-Encoding: chunked`` 编码的数据块， 包括块大小、块扩展行和数据行。 ``extensions``
  ## 指定块扩展。 
  ## 
  ## 根据 `RFC 7230 <https://tools.ietf.org/html/rfc7230#section-4.1.1>`_ 
  ## 
  ## ..code-block::bnf
  ## 
  ##   chunk-ext = *( ";" chunk-ext-name [ "=" chunk-ext-val ] )
  ## 
  ## ``"abc" => "3\r\nabc\r\n"``
  ## ``"abc", ";a1=v1;a2=v2" => "3;a1=v1;a2=v2\r\nabc\r\n"``

proc encodeChunk*(source: string, extensions: openarray[tuple[name: string, value: string]]): string = discard
  ## 将 ``source`` 转换为一块经过 ``Transfer-Encoding: chunked`` 编码的数据块， 包括块大小、块扩展行和数据行。 ``extensions``
  ## 指定块扩展。 
  ## 
  ## 根据 `RFC 7230 <https://tools.ietf.org/html/rfc7230#section-4.1.1>`_ 
  ## 
  ## ..code-block::bnf
  ## 
  ##   chunk-ext = *( ";" chunk-ext-name [ "=" chunk-ext-val ] )
  ## 
  ## ``"abc" => "3\r\nabc\r\n"``
  ## ``"abc", ";a1=v1;a2=v2" => "3;a1=v1;a2=v2\r\nabc\r\n"``

proc encodeChunkEnd*(): string = discard
  ## 生成一块经过 ``Transfer-Encoding: chunked`` 编码的数据块尾部。  ``trailers`` 是可选的， 指定挂载的 Trailer
  ## 首部。
  ## 
  ## ``=> "0\r\n\r\n"``
  
proc encodeChunkEnd*(trailers: openarray[tuple[name: string, value: string]]): string = discard
  ## 生成一块经过 ``Transfer-Encoding: chunked`` 编码的数据块尾部。  ``trailers`` 是可选的， 指定挂载的 Trailer
  ## 首部。
  ## 
  ## ``=> "0\r\n\r\n"``
  ## ``("a1", "v1"), ("a2", "v2") => "0\r\na1: v1\r\na2: v2\r\n\r\n"``  