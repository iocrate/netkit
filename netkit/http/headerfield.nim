#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module provides basic tools related to HTTP.
## 

# `RFC 7230-3.2.2 <https://tools.ietf.org/html/rfc7230#section-3.2.2>`_
# A recipient MAY combine multiple header fields with the same field name into one "field-name: field-value" pair, 
# without changing the semantics of the message, by appending each subsequent field value to the combined field 
# value in order, separated by a comma. The order in which header fields with the same field name are received 
# is therefore significant to the interpretation of the combined field value; a proxy MUST NOT change the order of 
# these field values when forwarding a message.

import tables
import strtabs
import strutils
import macros
import netkit/http/base
import netkit/http/exception

type
  HeaderFieldValueKind* {.pure.} = enum
    Single, SingleUseParams, Multi, MultiUseParams

  HeaderFieldParam* = tuple
    name: string
    value: string

  HeaderFieldValue* = object
    case kind: HeaderFieldValueKind
    of HeaderFieldValueKind.Single:
      sValue: string
    of HeaderFieldValueKind.SingleUseParams:
      spValue: string
      spParams: seq[HeaderFieldParam]
    of HeaderFieldValueKind.Multi:
      mValue: seq[string]
    of HeaderFieldValueKind.MultiUseParams:
      mpValue: seq[string]
      mpParams: seq[seq[HeaderFieldParam]]

iterator tokens(s: string, sep: char): string = 
  var token = ""
  for c in s:
    if c == sep:
      token.removePrefix(WS)
      token.removeSuffix(WS)
      yield token
      token = ""
    else:
      token.add(c)

proc toPair(s: string, sep: char): HeaderFieldParam = 
  let i = s.find(sep)
  if i >= 0:
    result.name = s[0..i-1]
    result.value = s[i+1..s.len-1]

proc initHeaderFieldValue*(fields: HeaderFields, name: string, kind: HeaderFieldValueKind): HeaderFieldValue =
  template parseParams(s: string, value: string, params: seq[tuple[name: string, value: string]]) = 
    var tokened = false
    for item in s.tokens(SEMICOLON):
      if tokened:
        if item.len > 0:
          let pair = item.toPair('=')
          if pair.name.len > 0:
            params.add(pair)
      else:
        tokened = true
        if item.len > 0:
          value = item
        else:
          break

  result = HeaderFieldValue(kind: kind)
  let value = fields[name]
  if value.len > 0:
    case kind
    of HeaderFieldValueKind.Single:
      if value.len > 1:
        raise newHttpError(Http400)
      result.sValue = value[0]
    of HeaderFieldValueKind.SingleUseParams:
      if value.len > 1:
        raise newHttpError(Http400)
      value[0].parseParams(result.spValue, result.spParams)
    of HeaderFieldValueKind.Multi:
      for x in value:
        for valuePart in x.tokens(COMMA):
          if valuePart.len > 0:
            result.mValue.add(valuePart)
    of HeaderFieldValueKind.MultiUseParams:
      for x in value:
        for valuePart in x.tokens(COMMA):
          if valuePart.len > 0:
            var value: string
            var params: seq[tuple[name: string, value: string]]
            valuePart.parseParams(value, params)
            if value.len > 0:
              result.mpValue.add(value)
              result.mpParams.add(params)

macro kindDst*(pair: static[tuple[name: string, kinds: set[HeaderFieldValueKind]]], prc: untyped) =
  template compose(oneProc) = 
    var assertsList = newStmtList()
    for i in 1..<oneProc.params.len:
      if oneProc.params[i][0].eqIdent(pair.name) and oneProc.params[i][1].eqIdent("HeaderFieldValue"):
        var asserts: seq[string]
        for kind in pair.kinds.items():
          asserts.add(pair.name & ".kind == " & $kind)
        assertsList.add(("assert " & asserts.join(" or ")).parseStmt())
    oneProc.body = newStmtList(assertsList, oneProc.body) 

  if prc.kind == nnkStmtList:
    result = newStmtList()
    for oneProc in prc:
      oneProc.compose()
      result.add(oneProc)
  else:
    prc.compose()
    result = prc

proc getSingleValue*(v: HeaderFieldValue): string {.kindDst: ("v", {HeaderFieldValueKind.Single, HeaderFieldValueKind.SingleUseParams}).} = 
  case v.kind
  of HeaderFieldValueKind.Single:
    result = v.sValue
  of HeaderFieldValueKind.SingleUseParams:
    result = v.spValue
  else:
    discard

proc getMultiValue*(v: HeaderFieldValue): seq[string] {.kindDst: ("v", {HeaderFieldValueKind.Multi, HeaderFieldValueKind.MultiUseParams}).} = 
  case v.kind
  of HeaderFieldValueKind.Multi:
    result = v.mValue
  of HeaderFieldValueKind.MultiUseParams:
    result = v.mpValue
  else:
    discard
  
iterator pairs*(v: HeaderFieldValue): tuple[value: string, params: seq[HeaderFieldParam]] {.
  kindDst: ("v", {HeaderFieldValueKind.SingleUseParams, HeaderFieldValueKind.MultiUseParams})
.} = 
  case v.kind
  of HeaderFieldValueKind.SingleUseParams:
    yield (v.spValue, v.spParams)
  of HeaderFieldValueKind.MultiUseParams:
    var i = 0
    var len = v.mpValue.len
    while i < len:
      yield (v.mpValue[0], v.mpParams[0])
  else:
    discard
  
proc contans*(v: var HeaderFieldValue, value: string): bool {.
  kindDst: ("v", {
    HeaderFieldValueKind.Single, 
    HeaderFieldValueKind.SingleUseParams,
    HeaderFieldValueKind.Multi,
    HeaderFieldValueKind.MultiUseParams
  })
.} = 
  case v.kind
  of HeaderFieldValueKind.Single:
    result = v.sValue == value
  of HeaderFieldValueKind.SingleUseParams:
    result = v.spValue == value
  of HeaderFieldValueKind.Multi:
    for item in v.mValue:
      if item == value:
        return true
    return false
  of HeaderFieldValueKind.MultiUseParams:
    for item in v.mpValue:
      if item == value:
        return true
    return false

proc add*(v: var HeaderFieldValue, value: string) {.
  kindDst: ("v", {
    HeaderFieldValueKind.Single, 
    HeaderFieldValueKind.SingleUseParams,
    HeaderFieldValueKind.Multi,
    HeaderFieldValueKind.MultiUseParams
  })
.} = 
  if not v.contans(value):
    case v.kind
    of HeaderFieldValueKind.Single:
      v.sValue = value
    of HeaderFieldValueKind.SingleUseParams:
      v.spValue = value
      v.spParams = @[]
    of HeaderFieldValueKind.Multi:
      v.mValue.add(v.mValue)
    of HeaderFieldValueKind.MultiUseParams:
      v.mpValue.add(v.mpValue)
      v.mpParams.add(@[])
 
proc add*(v: var HeaderFieldValue, value: string, param: HeaderFieldParam) {.
  kindDst: ("v", {
    HeaderFieldValueKind.SingleUseParams,
    HeaderFieldValueKind.MultiUseParams
  })
.} = 
  case v.kind
  of HeaderFieldValueKind.SingleUseParams:
    if v.spValue == value:
      v.spParams.add(param)
    else:
      v.spValue = value
      v.spParams = @[param]
  of HeaderFieldValueKind.MultiUseParams:
    var i = 0
    var len = v.mpValue.len
    while i < len:
      if v.mpValue[i] == value:
        v.mpParams[i].add(param)
        return
    v.mpValue.add(value)
    v.mpParams.add(@[param])
  else:
    discard

proc del*(v: var HeaderFieldValue, value: string) {.
  kindDst: ("v", {
    HeaderFieldValueKind.Multi,
    HeaderFieldValueKind.MultiUseParams
  })
.} = 
  case v.kind
  of HeaderFieldValueKind.Multi:
    var i = 0
    var len = v.mValue.len
    while i < len:
      if v.mValue[i] == value:
        v.mValue.delete(i)
        break
  of HeaderFieldValueKind.MultiUseParams:
    var i = 0
    var len = v.mpValue.len
    while i < len:
      if v.mpValue[i] == value:
        v.mpValue.delete(i)
        v.mpParams.delete(i)
        break
  else:
    discard

proc del*(v: var HeaderFieldValue) {.
  kindDst: ("v", {
    HeaderFieldValueKind.Single, 
    HeaderFieldValueKind.SingleUseParams,
    HeaderFieldValueKind.Multi,
    HeaderFieldValueKind.MultiUseParams
  })
.} = 
  case v.kind
  of HeaderFieldValueKind.Single:
    v.sValue = ""
  of HeaderFieldValueKind.SingleUseParams:
    v.spValue = ""
    v.spParams = @[]
  of HeaderFieldValueKind.Multi:
    v.mValue = @[]
  of HeaderFieldValueKind.MultiUseParams:
    v.mpValue = @[]
    v.mpParams = @[]
