#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module provides basic tools related to HTTP.

type
  HttpMetaDataKind* {.pure.} = enum
    None, ChunkTrailer, ChunkExtensions

  HttpMetaData* = object
    case kind: HttpMetaDataKind
    of HttpMetaDataKind.ChunkTrailer:
      trailer: seq[string]
    of HttpMetaDataKind.ChunkExtensions:
      extensions: string
    of HttpMetaDataKind.None:
      discard 

proc initHttpMetaData*(): HttpMetaData =
  ## 
  result.kind = HttpMetaDataKind.None

proc initHttpMetaData*(trailer: seq[string]): HttpMetaData =
  ## 
  result.kind = HttpMetaDataKind.ChunkTrailer
  result.trailer = trailer

proc initHttpMetaData*(extensions: string): HttpMetaData =
  ## 
  result.kind = HttpMetaDataKind.ChunkExtensions
  result.extensions = extensions

proc kind*(D: HttpMetaData): HttpMetaDataKind {.inline.} = 
  D.kind

proc trailer*(D: HttpMetaData): seq[string] {.inline.} = 
  D.trailer

proc extensions*(D: HttpMetaData): string {.inline.} = 
  D.extensions