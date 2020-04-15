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
    case kind: HttpMetadataKind
    of HttpMetadataKind.ChunkTrailer:
      trailer: seq[string]
    of HttpMetadataKind.ChunkExtensions:
      extensions: string
    of HttpMetadataKind.None:
      discard 

proc initHttpMetadata*(): HttpMetadata =
  ## 
  result.kind = HttpMetadataKind.None

proc initHttpMetadata*(trailer: seq[string]): HttpMetadata =
  ## 
  result.kind = HttpMetadataKind.ChunkTrailer
  result.trailer = trailer

proc initHttpMetadata*(extensions: string): HttpMetadata =
  ## 
  result.kind = HttpMetadataKind.ChunkExtensions
  result.extensions = extensions

proc kind*(D: HttpMetadata): HttpMetadataKind {.inline.} = 
  D.kind

proc trailer*(D: HttpMetadata): seq[string] {.inline.} = 
  D.trailer

proc extensions*(D: HttpMetadata): string {.inline.} = 
  D.extensions