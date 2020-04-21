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

# https://zh.wikipedia.org/wiki/ASCII 
# https://zh.wikipedia.org/wiki/EASCII
#
# ASCII 0~255 一共 256 个字符。0~31 和 127 是控制字符；32~126 是可视字符；128~255 是扩展字符。
# 
# 
# 一个 char 是 8 位，可表示 -127~127。

# HTTP Specifition 对头字段的定义非常的 sucks， 有非常多的特例， 甚至有些混乱。 有些字段是单个值， 比如 content-type， 有些字段是多个
# 值， 比如 accept 。 单个值中， 有的有参数， 比如 content-length： 0， 有的没有参数， 比如 content-type： application/json; charset=utf8。
# 多个值中， 有的是名字值对， 比如 cookie: a=1; c=2， 有的是值和参数， 比如 accept： text/html;q=1;level=1, text/plain。 对于多个值，使用
# 多行或者 ``,`` 作为分隔符。 另外， ``"`` 作为引用字符串则会将内部的 ``,`` 排除。 对于单个值， ``,`` 则属于内容而非分隔符， 比如
# Date: Wed, 21 Oct 2015 07:28:00 GMT 。``;`` 在某些值里扮演参数的分隔符， 比如 content-type： application/json; charset=utf8， 在某些值
# 里则扮演名值对的分隔符， 比如 cookie: a=1; b=2 。

# 为了尽可能简化对这些负责情况的处理， netkit 提供了两个解码 procs， 一个用于处理单个值， 一个用户处理多个值。 在使用的时候， 您必须负责指定目标
# 是单值或者多值， 解码 procs 按照指定的方式进行解析， 而不管是否正确。 比如 ``Date: Wed, 21 Oct 2015 07:28:00 GMT``， 应该使用
# ``decodeSingle``， 但是如果您使用 ``decodeMulti``， 则会将其中的 ``,`` 作为分隔符， 输出多值 ``["Wed", "21 Oct 2015 07:28:00 GMT"]``

# 比如您在调用 ``decodeSingle(fields, "Content-Type")`` 得到的结果可能是 ``@[("application/json", ""), ("charset", "utf8")]``； 在调用
# ``decodeSingle(fields, "Content-Length")`` 得到的结果可能是 ``@[("0", "")]``； 在调用``decodeMulti(fields, "Cookie")`` 得到的结果可能是 
# ``@[("a", "1"), ("b", "2")]``。 

# Field Value Components
# ----------------------
# 
# ..
# 
#   `RFC7230 <https://tools.ietf.org/html/rfc7230>`_
# 
#   Most HTTP header field values are defined using common syntax components (token, quoted-string, and comment) 
#   separated by whitespace or specific delimiting characters. Delimiters are chosen from the set of US-ASCII
#   visual characters not allowed in a token (DQUOTE and "(),/:;<=>?@[\]{}").
# 
# ..
#
#   `RFC5234 <https://tools.ietf.org/html/rfc5234>`_
# 
#   ..code-block::nim
# 
#     DIGIT          =  %x30-39            ; 0-9
#     ALPHA          =  %x41-5A / %x61-7A  ; A-Z / a-z
#     DQUOTE         =  %x22       ; '"'
#     HTAB           =  %x09       ; horizontal tab
#     SP             =  %x20       ; ' '
#     VCHAR          =  %x21-7E    ; visible (printing) characters
# 
# ..
#
#   `RFC7230 <https://tools.ietf.org/html/rfc7230>`_
# 
#   ..code-block::nim
# 
#     field-value    =  *( field-content / obs-fold )
#     field-content  =  field-vchar [ 1*( SP / HTAB ) field-vchar ]
#     field-vchar    =  VCHAR / obs-text
#     obs-text       =  %x80-FF
#     obs-fold       =  CRLF 1*( SP / HTAB )  ; obsolete line folding  
# 
#     token          =  1*tchar
#     tchar          =  "!" / "#" / "$" / "%" / "&" / "'" / "*"
#                    /  "+" / "-" / "." / "^" / "_" / "`" / "|" / "~"
#                    /  DIGIT / ALPHA
#                    ;  any VCHAR, except delimiters
#
#     quoted-pair    =  "\" ( HTAB / SP / VCHAR / obs-text )
# 
#     quoted-string  =  DQUOTE *( qdtext / quoted-pair ) DQUOTE
#     qdtext         =  HTAB / SP /%x21 / %x23-5B / %x5D-7E / obs-text
# 
#     comment        = "(" *( ctext / quoted-pair / comment ) ")"
#     ctext          = HTAB / SP / %x21-27 / %x2A-5B / %x5D-7E / obs-text

import tables
import strtabs
import strutils
import macros
import netkit/http/base
import netkit/http/exception

template seek(a: string, v: string, start: Natural, stop: Natural) = 
  if stop > start:
    var s = v[start..stop-1]
    s.removePrefix(WSP)
    s.removeSuffix(WSP)
    if s.len > 0:
      a = move s
  start = stop + 1

proc decodeSingle(v: string, res: var seq[tuple[key: string, value: string]]) = 
  # delemeters: ``= ; "``
  var start = 0
  var stop = 0
  var flag = '\x0'
  var flagQuote = '\x0'
  var flagPair = '\x0'
  var key: string
  var value: string
  while stop < v.len:
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
      case v[stop] 
      of '"':
        flag = '"'
      of '=':
        case flagPair
        of '=':
          discard # traits as a value
        else:
          flagPair = '='
          key.seek(v, start, stop) 
      of ';':
        case flagPair
        of '=':
          value.seek(v, start, stop) 
          flagPair = '\x0'
        else:
          key.seek(v, start, stop) 
        if key.len > 0 or value.len > 0:
          res.add((key, value))
          key = ""
          value = ""
      else:
        discard
    stop.inc()
  if key.len > 0 or value.len > 0:
    res.add((key, value))

proc decodeMulti(v: string, res: var seq[seq[tuple[key: string, value: string]]]) = 
  # delemeters: ``= ; " ,``
  var start = 0
  var stop = 0
  var flag = '\x0'
  var flagQuote = '\x0'
  var flagPair = '\x0'
  var key: string
  var value: string
  var item: seq[tuple[key: string, value: string]]
  while stop < v.len:
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
      case v[stop] 
      of '"':
        flag = '"'
      of '=':
        case flagPair
        of '=':
          discard # traits as a value
        else:
          flagPair = '='
          key.seek(v, start, stop) 
      of ';':
        case flagPair
        of '=':
          value.seek(v, start, stop) 
          flagPair = '\x0'
        else:
          key.seek(v, start, stop) 
        if key.len > 0 or value.len > 0:
          item.add((key, value))
          key = ""
          value = ""
      of ',':
        case flagPair
        of '=':
          value.seek(v, start, stop) 
          flagPair = '\x0'
        else:
          key.seek(v, start, stop) 
        if key.len > 0 or value.len > 0:
          item.add((key, value))
          key = ""
          value = ""
        if item.len > 0:
          res.add(item)
      else:
        discard
    stop.inc()
  if key.len > 0 or value.len > 0:
    item.add((key, value))
    key = ""
    value = ""
  if item.len > 0:
    res.add(item)

proc decodeSingle*(fields: HeaderFields, name: string, default = ""): seq[tuple[key: string, value: string]] =
  if fields.contains(name):
    var v = fields[name]
    if v.len > 1:
        raise newHttpError(Http400, "Multiple values are not allowed")
    v[0].decodeSingle(result)    

proc decodeMulti*(fields: HeaderFields, name: string, default = ""): seq[seq[tuple[key: string, value: string]]] =
  if fields.contains(name):
    for v in fields[name]:
      v.decodeMulti(result)

type
  HeaderFieldParam* = tuple
    name: string
    value: string

proc skipOWS(s: string): Natural =
  result = 0
  while result < s.len:
    if s[result] != SP and s[result] != HTAB:
      break
    result.inc()

proc decodeTransferEncoding*(
  fields: HeaderFields,  
  default = ""
): seq[string] =  
  ## `RFC5234 <https://tools.ietf.org/html/rfc5234>`_
  ## 
  ## ..code-block::nim
  ## 
  ##   HTAB           =  %x09       ; horizontal tab
  ##   SP             =  %x20       ; ' '
  ##   DIGIT          =  %x30-39            ; 0-9
  ##   ALPHA          =  %x41-5A / %x61-7A  ; A-Z / a-z
  ## 
  ## `RFC7230 <https://tools.ietf.org/html/rfc7230>`_
  ## 
  ## ..code-block::nim
  ##  
  ##   Transfer-Encoding   =  1#transfer-coding
  ##   transfer-coding     =  "chunked" / "compress" / "deflate" / "gzip" / transfer-extension
  ##   transfer-extension  =  token *( OWS ";" OWS transfer-parameter )
  ##   transfer-parameter  =  token BWS "=" BWS ( token / quoted-string )
  ##   token               =  1*tchar
  ##   tchar               =  "!" / "#" / "$" / "%" / "&" / "'" / "*"
  ##                       /  "+" / "-" / "." / "^" / "_" / "`" / "|" / "~"
  ##                       /  DIGIT 
  ##                       /  ALPHA
  ##   OWS                 =  *( SP / HTAB )
  ##   BWS                 =  OWS
  ## 
  ##   1#element           = element *( OWS "," OWS element )
  ## 
  const TextChars = { HTAB, SP, '\x21', '\x23'..'\x5B', '\x5D'..'\x7E', '\x80'..'\xFF' }
  const PairChars = { HTAB, SP, '\x21'..'\x7E', '\x80'..'\xFF' }
  if fields.contains("Transfer-Encoding"):
    var v = fields["Transfer-Encoding"]
    var res: seq[string]
    for line in v:
      var start = 0
      var stop = 0
      var flag = '\x0'
      var flag2 = '\x0'
      while stop < line.len:
        case flag
        of '"':
          case flag2
          of '\\':
            flag2 = '\x0'
          else:
            case line[stop] 
            of '\\':
              flag2 = '\\'
            of '"':
              flag = '\x0'
              flag2 = '\x0'
            else:
              discard
        else:
          case line[stop] 
          # of '\\':
          #   flag = '\\'
          of '"':
            flag = '"'
          of ',':
            if stop > start:
              var s = line[start..stop-1]
              s.removePrefix(WSP)
              s.removeSuffix(WSP)
              if s.len > 0:
                s.shallow()
                res.add(s)
            start = stop + 1
          else:
            # if line[stop] notin TextChars:
            #   return
            discard
        stop.inc()

proc checkoutToken(s: string, start: Natural): int = 
  ## `RFC5234 <https://tools.ietf.org/html/rfc5234>`_
  ## 
  ## ..code-block::nim
  ## 
  ##   DIGIT          =  %x30-39            ; 0-9
  ##   ALPHA          =  %x41-5A / %x61-7A  ; A-Z / a-z
  ## 
  ## `RFC7230 <https://tools.ietf.org/html/rfc7230>`_
  ## 
  ## ..code-block::nim
  ## 
  ##   token          =  1*tchar
  ##   tchar          =  "!" / "#" / "$" / "%" / "&" / "'" / "*"
  ##                  /  "+" / "-" / "." / "^" / "_" / "`" / "|" / "~"
  ##                  /  DIGIT / ALPHA
  ##                  ;  any VCHAR, except delimiters
  ## 
  const TokenChars = {
    '!', '#', '$', '%', '&', '\'', '*',
    '+', '-', '.', '^', '_', '`', '|', '~',
    '0'..'9',
    'a'..'z',
    'A'..'Z'
  }
  result = -1
  if s.len == 0:
    return
  for c in s:
    if c notin TokenChars:
      return
  return s.len

proc decodeSingleValue*(fields: HeaderFields, name: string, default = ""): string = 
  if fields.contains(name):
    var v = fields[name]
    if v.len > 1:
        raise newHttpError(Http400)
    result = move v[0]

proc decodeSingleValueUseParams*(
  fields: HeaderFields, 
  name: string, 
  default = ""
): tuple[value: string, params: string] = 
  if fields.contains(name):
    var v = fields[name]
    if v.len > 1:
        raise newHttpError(Http400)
    result = move v[0].parseParams(result.spValue, result.spParams)

proc decodeMultiValue*(): seq[string] = 
  discard

proc decodeMultiValueUseParams*(): seq[tuple[value: string, params: seq[HeaderFieldParam]]] = 
  discard

proc decodeSetCookie*(): seq[tuple[value: string, params: seq[HeaderFieldParam]]] = 
  discard

type
  HeaderFieldKind* {.pure.} = enum
    Single, SingleUseParams, Multi, MultiUseParams, SetCookie

  HeaderFieldDescriptor* = object
    case kind: HeaderFieldKind
    of HeaderFieldKind.Single:
      sValue: string
    of HeaderFieldKind.SingleUseParams:
      spValue: string
      spParams: seq[HeaderFieldParam]
    of HeaderFieldKind.Multi:
      mValue: seq[string]
    of HeaderFieldKind.MultiUseParams:
      mpValue: seq[string]
      mpParams: seq[seq[HeaderFieldParam]]

iterator tokens(s: string, sep: char): string = 
  var token = ""
  for c in s:
    if c == sep:
      token.removePrefix(WSP)
      token.removeSuffix(WSP)
      yield token
      token = ""
    else:
      token.add(c)

proc toPair(s: string, sep: char): HeaderFieldParam = 
  let i = s.find(sep)
  if i >= 0:
    result.name = s[0..i-1]
    result.value = s[i+1..s.len-1]

# parse     | decode    解码 解析（反序列化）
# stringify | encode    编码 字符（序列化）
proc toHeaderFieldDescriptor*(value: seq[string], kind: HeaderFieldKind): HeaderFieldDescriptor =
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

  result = HeaderFieldDescriptor(kind: kind)
  if value.len > 0:
    case kind
    of HeaderFieldKind.Single:
      if value.len > 1:
        raise newHttpError(Http400)
      result.sValue = value[0]
    of HeaderFieldKind.SingleUseParams:
      if value.len > 1:
        raise newHttpError(Http400)
      value[0].parseParams(result.spValue, result.spParams)
    of HeaderFieldKind.Multi:
      for x in value:
        for valuePart in x.tokens(COMMA):
          if valuePart.len > 0:
            result.mValue.add(valuePart)
    of HeaderFieldKind.MultiUseParams:
      for x in value:
        for valuePart in x.tokens(COMMA):
          if valuePart.len > 0:
            var value: string
            var params: seq[tuple[name: string, value: string]]
            valuePart.parseParams(value, params)
            if value.len > 0:
              result.mpValue.add(value)
              result.mpParams.add(params)

macro kindDst*(pair: static[tuple[name: string, kinds: set[HeaderFieldKind]]], prc: untyped) =
  template compose(oneProc) = 
    var assertsList = newStmtList()
    for i in 1..<oneProc.params.len:
      if oneProc.params[i][0].eqIdent(pair.name) and oneProc.params[i][1].eqIdent("HeaderFieldDescriptor"):
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

proc getSingleValue*(v: HeaderFieldDescriptor): string {.kindDst: ("v", {HeaderFieldKind.Single, HeaderFieldKind.SingleUseParams}).} = 
  case v.kind
  of HeaderFieldKind.Single:
    result = v.sValue
  of HeaderFieldKind.SingleUseParams:
    result = v.spValue
  else:
    discard

proc getMultiValue*(v: HeaderFieldDescriptor): seq[string] {.kindDst: ("v", {HeaderFieldKind.Multi, HeaderFieldKind.MultiUseParams}).} = 
  case v.kind
  of HeaderFieldKind.Multi:
    result = v.mValue
  of HeaderFieldKind.MultiUseParams:
    result = v.mpValue
  else:
    discard
  
iterator pairs*(v: HeaderFieldDescriptor): tuple[value: string, params: seq[HeaderFieldParam]] {.
  kindDst: ("v", {HeaderFieldKind.SingleUseParams, HeaderFieldKind.MultiUseParams})
.} = 
  case v.kind
  of HeaderFieldKind.SingleUseParams:
    yield (v.spValue, v.spParams)
  of HeaderFieldKind.MultiUseParams:
    var i = 0
    var len = v.mpValue.len
    while i < len:
      yield (v.mpValue[0], v.mpParams[0])
  else:
    discard
  
proc contans*(v: var HeaderFieldDescriptor, value: string): bool {.
  kindDst: ("v", {
    HeaderFieldKind.Single, 
    HeaderFieldKind.SingleUseParams,
    HeaderFieldKind.Multi,
    HeaderFieldKind.MultiUseParams
  })
.} = 
  case v.kind
  of HeaderFieldKind.Single:
    result = v.sValue == value
  of HeaderFieldKind.SingleUseParams:
    result = v.spValue == value
  of HeaderFieldKind.Multi:
    for item in v.mValue:
      if item == value:
        return true
    return false
  of HeaderFieldKind.MultiUseParams:
    for item in v.mpValue:
      if item == value:
        return true
    return false

proc add*(v: var HeaderFieldDescriptor, value: string) {.
  kindDst: ("v", {
    HeaderFieldKind.Single, 
    HeaderFieldKind.SingleUseParams,
    HeaderFieldKind.Multi,
    HeaderFieldKind.MultiUseParams
  })
.} = 
  if not v.contans(value):
    case v.kind
    of HeaderFieldKind.Single:
      v.sValue = value
    of HeaderFieldKind.SingleUseParams:
      v.spValue = value
      v.spParams = @[]
    of HeaderFieldKind.Multi:
      v.mValue.add(v.mValue)
    of HeaderFieldKind.MultiUseParams:
      v.mpValue.add(v.mpValue)
      v.mpParams.add(@[])
 
proc add*(v: var HeaderFieldDescriptor, value: string, param: HeaderFieldParam) {.
  kindDst: ("v", {
    HeaderFieldKind.SingleUseParams,
    HeaderFieldKind.MultiUseParams
  })
.} = 
  case v.kind
  of HeaderFieldKind.SingleUseParams:
    if v.spValue == value:
      v.spParams.add(param)
    else:
      v.spValue = value
      v.spParams = @[param]
  of HeaderFieldKind.MultiUseParams:
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

proc del*(v: var HeaderFieldDescriptor, value: string) {.
  kindDst: ("v", {
    HeaderFieldKind.Multi,
    HeaderFieldKind.MultiUseParams
  })
.} = 
  case v.kind
  of HeaderFieldKind.Multi:
    var i = 0
    var len = v.mValue.len
    while i < len:
      if v.mValue[i] == value:
        v.mValue.delete(i)
        break
  of HeaderFieldKind.MultiUseParams:
    var i = 0
    var len = v.mpValue.len
    while i < len:
      if v.mpValue[i] == value:
        v.mpValue.delete(i)
        v.mpParams.delete(i)
        break
  else:
    discard

proc del*(v: var HeaderFieldDescriptor) {.
  kindDst: ("v", {
    HeaderFieldKind.Single, 
    HeaderFieldKind.SingleUseParams,
    HeaderFieldKind.Multi,
    HeaderFieldKind.MultiUseParams
  })
.} = 
  case v.kind
  of HeaderFieldKind.Single:
    v.sValue = ""
  of HeaderFieldKind.SingleUseParams:
    v.spValue = ""
    v.spParams = @[]
  of HeaderFieldKind.Multi:
    v.mValue = @[]
  of HeaderFieldKind.MultiUseParams:
    v.mpValue = @[]
    v.mpParams = @[]
