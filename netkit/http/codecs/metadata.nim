#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module provides basic tools related to HTTP.

type
  HttpMetadataKind* {.pure.} = enum
    None, ChunkTrailer, ChunkExtensions

  HttpMetadata* = object
    case kind*: HttpMetadataKind
    of HttpMetadataKind.ChunkTrailer:
      trailer*: seq[string]
    of HttpMetadataKind.ChunkExtensions:
      extensions*: string
    of HttpMetadataKind.None:
      discard 
