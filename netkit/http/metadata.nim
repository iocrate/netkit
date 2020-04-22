#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## HTTP messages support carrying metadata. Currently, there are two kinds of metadata. Both of them appear
## in messages encoded with ``Transfer-Encoding: chunked``. They are:
## 
## - Chunk Extensions
## - Trailer
## 
## This module defines a general object ``HttpMetadata`` to abstract these metadata in order to simplify 
## the use of metadata. 
## 
## Chunk Extensions
## -----------------
## 
## For a message encoded by ``Transfer-Encoding: chunked``, each data chunk is allowed to contain zero or more
## chunk-extensions. These extensions immediately follow the chunk-size,  for the sake of supplying per-chunk 
## metadata (such as a signature or hash), mid-message control information, or randomization of message body 
## size. 
## 
## Each extension is a name-value pair with ``=`` as a separator, such as ``language = en``; multiple extensions
## are combined with ``;`` as a separator, such as ``language=en; city=London``.
## 
## An example of carring block expansion:
## 
## ..code-block:http
## 
##   HTTP/1.1 200 OK 
##   Transfer-Encoding: chunked
##   
##   9; language=en; city=London\r\n 
##   Developer\r\n 
##   0\r\n 
##   \r\n
## 
## Trailers
## --------
## 
## Messages encoded with ``Transfer-Encoding: chunked`` are allowed to carry trailers at the end. Trailer is
## actually one or more HTTP response header fields, allowing the sender to add additional meta-information 
## at the end of a message. These meta-information may be dynamically generated with the sending of the message 
## body, such as message integrity check, message Digital signature, or the final state of the message after 
## processing, etc.
## 
## Note: Only when the client sets trailers in the request header ``TE`` (`` TE: trailers``),  the server can
## carry Trailer in the response.
## 
## An example of carring trailers:
## 
## ..code-block:http
## 
##   HTTP/1.1 200 OK 
##   Transfer-Encoding: chunked
##   Trailer: Expires
##   
##   9\r\n 
##   Developer\r\n 
##   0\r\n 
##   Expires: Wed, 21 Oct 2015 07:28:00 GMT\r\n
##   \r\n

type
  HttpMetadataKind* {.pure.} = enum  ## Kinds of metadata.
    None,                            ## Indicates no metadata.
    ChunkTrailers,                   ## Indicates that the metadata is trailers.
    ChunkExtensions                  ## Indicates that the metadata is chunk-extensions.

  HttpMetadata* = object ## Metadata object.
    case kind*: HttpMetadataKind
    of HttpMetadataKind.ChunkTrailers:
      trailes*: seq[string] ## Trailer collection. For performance reasons, ``HttpMetadata`` does not further 
                            ## parse the content of ``trailers``, but uses a string sequence to save them. You 
                            ## can use ``parseChunkTrailers`` of the chunk module to convert the sequence of 
                            ## strings into ``HeaderFileds`` to access every items.
    of HttpMetadataKind.ChunkExtensions:
      extensions*: string   ## Chunk Extensions. For performance reasons, ``HttpMetadata`` does not further 
                            ## parse the content of ``extensions``, but uses a string to save them. You can use 
                            ## ``parseChunkExtensions`` of the chunk module to convert the string into ``(name, value)`` 
                            ## pair array to access every items.
    of HttpMetadataKind.None:
      discard 
