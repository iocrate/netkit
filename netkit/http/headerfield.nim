#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module provides basic tools related to HTTP.
## 

# Multiple Header Fields with The Same Field Name
# -----------------------------------------------
#
# `RFC 7230-3.2.2 <https://tools.ietf.org/html/rfc7230#section-3.2.2>`_
#
# A sender MUST NOT generate multiple header fields with the same field name in a message unless either the entire 
# field value for that header field is defined as a comma-separated list [i.e., #(values)] or the header field is a
# well-known exception (as noted below).
#
# A recipient MAY combine multiple header fields with the same field name into one "field-name: field-value" pair, 
# without changing the semantics of the message, by appending each subsequent field value to the combined field value
# in order, separated by a comma. The order in which header fields with the same field name are received is therefore 
# significant to the interpretation of the combined field value; a proxy MUST NOT change the order of these field values 
# when forwarding a message.
#
# Note: In practice, the "Set-Cookie" header field ([RFC6265]) often appears multiple times in a response message and
#       does not use the list syntax, violating the above requirements on multiple header fields with the same name.
#       Since it cannot be combined into a single field-value, recipients ought to handle "Set-Cookie" as a special case 
#       while processing header fields. 
#
# ASCII
# -----
#
# - https://zh.wikipedia.org/wiki/ASCII 
# - https://zh.wikipedia.org/wiki/EASCII
#
# ASCII 0~255 一共 256 个字符。 0~31 和 127 是控制字符； 32~126 是可视字符； 128~255 是扩展字符。 一个 char 是 8 位， 可表示 0~255。 
#
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

import strutils
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

proc parseSingleRule(v: string, res: var seq[tuple[key: string, value: string]]) = 
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

proc parsMultiRule(v: string, res: var seq[seq[tuple[key: string, value: string]]]) = 
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

proc parseSingleRule*(fields: HeaderFields, name: string, default = ""): seq[tuple[key: string, value: string]] =
  if fields.contains(name):
    var v = fields[name]
    if v.len > 1:
        raise newHttpError(Http400, "Multiple values are not allowed")
    v[0].parseSingleRule(result)    

proc parsMultiRule*(fields: HeaderFields, name: string, default = ""): seq[seq[tuple[key: string, value: string]]] =
  if fields.contains(name):
    for v in fields[name]:
      v.parsMultiRule(result)
