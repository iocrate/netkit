#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module contains a definition of HTTP header fields. A distinct table, ``HeaderFields``, which 
## represents the set of header fields of a message.
## 
## Overview
## ========================
## 
## HTTP header fields are components of the header section of request and response messages. They define 
## the operating parameters of an HTTP transaction. 
## 
## Header field names are case-insensitive. Most HTTP header field values are defined using common syntax 
## components (token, quoted-string, and comment) separated by whitespace or specific delimiting characters. 
## 
## .. container::r-fragment
## 
##   Formatting rules 
##   ----------------
## 
##   The format of the value of each header field varies widely. There are five different formatting rules:
## 
##   1. Represented as a single line, a single value, no-parameters
## 
##   .. container::r-ol
## 
##      For example:
##    
##      .. code-block::http
## 
##        Content-Length: 0
## 
##   2. Represented as a single line, a single value, optional parameters separated by ``';'``
## 
##   .. container::r-ol
## 
##      For example:  
##    
##      .. code-block::http
## 
##        Content-Type: application/json
## 
##      or: 
##    
##      .. code-block::http
## 
##        Content-Type: application/json; charset=utf8
## 
##   3. Represented as a single line, multiple values separated by ``';'``, no-parameters 
## 
##   .. container::r-ol
## 
##      For example:
##    
##      .. code-block::http
## 
##        Cookie: SID=123abc; language=en
## 
##   4. Represented as a single line or multiple lines, multiple values separated by ``','``, each value has
##   optional parameters separated by ``';'``
## 
##   .. container::r-ol
## 
##      A single line:
##    
##      .. code-block::http
## 
##        Accept: text/html; q=1; level=1, text/plain
## 
##      Multiple lines:
##    
##      .. code-block::http
## 
##        Accept: text/html; q=1; level=1
##        Accept: text/plain
## 
##   5. ``Set-Cookie`` is a special case, represented as multiple lines, each line is a value that separated by ``';'``, 
##   no-parameters
## 
##   .. container::r-ol
## 
##      .. code-block::http
## 
##        Set-Cookie: SID=123abc; path=/
##        Set-Cookie: language=en; path=/
## 
##   To simplify these complex representations, this module provides two special tools, ``parseSingleRule`` and 
##   ``parseMultiRule``, which combine the above 5 rules into 2 rules: **single-line-rule** (SLR) and 
##   **multiple-lines-rule** (MLR).
## 
## Usage
## ========================
## 
## .. container:: r-fragment
## 
##   Access fields
##   -------------------------
## 
##   .. code-block::nim
## 
##     import netkit/http/headerfield  
##      
##     let fields = initHeaderFields({
##       "Host": @["www.iocrate.com"],
##       "Content-Length": @["16"],
##       "Content-Type": @["application/json; charset=utf8"],
##       "Cookie": @["SID=123; language=en"],
##       "Accept": @["text/html; q=1; level=1", "text/plain"]
##     })
##     
##     fields.add("Connection", "keep-alive")
##     fields.add("Accept", "text/*")
## 
##     assert fields["Content-Length"][0] = "16"
##     assert fields["content-length"][0] = "16"
##     assert fields["Accept"][0] = "text/html; q=1; level=1"
##     assert fields["Accept"][1] = "text/plain"
##     assert fields["Accept"][2] = "text/*"
## 
## .. container:: r-fragment
## 
##   Access values by SLR
##   --------------------
## 
##   Uses ``parseSingleRule`` to parse the header fields, which follows the 1,2,3 rules listed above, and returns a set of 
##   ``(key, value)`` pairs.  
## 
##   1. Represented as a single line, a single value, no-parameters
## 
##   .. container::r-ol
## 
##      .. code-block::nim
##      
##        let fields = initHeaderFields({
##          "Content-Length": @["0"]
##        })
##        let values = fields.parseSingleRule("Content-Length")
##        assert values[0].key = "0"
## 
##      The returned result should have at most one item, and the ``key`` of the first item indicates the value of this
##      header field, if any.
##      
##      .. 
##      
##        Note: When using this proc, you must ensure that the values is represented as a single line. If the values is represented 
##        as multiple-lines like ``Accept``, there may lose values. If more than one value is found, an exception will be raised.
## 
##   2. Represented as a single line, a single value, optional parameters separated by ``';'``
## 
##   .. container::r-ol
## 
##      .. code-block::nim
##      
##        let fields = initHeaderFields({
##          "Content-Type": @["application/json; charset=utf8"]
##        })
##        let values = fields.parseSingleRule("Content-Type")
##        assert values[0].key = "application/json"
##        assert values[1].key = "charset"
##        assert values[1].value = "utf8"
## 
##      If the returned result is not empty, the ``key`` of the first item indicates the value of this header field, and the 
##      other items indicates the parameters of this value.
##      
##      .. 
##      
##        Note: When using this proc, you must ensure that the values is represented as a single line. If the values is represented 
##        as multiple-lines like ``Accept``, there may lose values. If more than one value is found, an exception will be raised.
## 
##   3. Represented as a single line, multiple values separated by ``';'``, no-parameters 
## 
##   .. container::r-ol
## 
##      .. code-block::nim
##      
##        let fields = initHeaderFields({
##          "Cookie": @["SID=123abc; language=en"]
##        })
##        let values = fields.parseSingleRule("Cookie")
##        assert values[0].key = "SID"
##        assert values[0].value = "123abc"
##        assert values[1].key = "language"
##        assert values[1].value = "en"
## 
##      If the returned result is not empty, then each item indicates a value, that mean a ``(key, value)`` pair.
##      
##      .. 
##      
##        Note: When using this proc, you must ensure that the values is represented as a single line. If the values is represented 
##        as multiple-lines like ``Accept``, there may lose values. If more than one value is found, an exception will be raised.
## 
## .. container:: r-fragment
## 
##   Access values by MLR
##   --------------------
## 
##   Uses ``parseMultiRule`` to parse the header fields, which follows the 4,5 rules listed above, and returns a set of ``seq[(key, value)]``.  
## 
##   4. Represented as a single line or multiple lines, multiple values separated by ``','``, each value has
##   optional parameters separated by ``';'``
## 
##   .. container::r-ol
## 
##      .. code-block::nim
##      
##        let fields = initHeaderFields({
##          "Accept": @["text/html; q=1; level=1, text/plain"]
##        })
##        let values = fields.parseMultiRule("Accept")
##        assert values[0][0].key = "text/html"
##        assert values[0][1].key = "q"
##        assert values[0][1].value = "1"
##        assert values[0][2].key = "level"
##        assert values[0][2].value = "1"
##        assert values[1][0].key = "text/plain"
## 
##      the same below：
## 
##      .. code-block::nim
##      
##        let fields = initHeaderFields({
##          "Accept": @["text/html; q=1; level=1", "text/plain"]
##        })
##        let values = fields.parseMultiRule("Accept")
## 
##      If the returned result is not empty, then each item indicates a value. The ``key`` of the first 
##      item of each seq indicates the value itself, and the other items indicate parameters of that value.
## 
##      ..
## 
##        Note: When using this proc, you must ensure that the values is represented as multiple lines. 
##        If the values is represented as a single-line field like ``Date``, you may get wrong results. Because ``Date`` 
##        takes ``','`` as part of its value, for example, ``Date: Thu, 23 Apr 2020 07:41:15 GMT``.
## 
##   5. ``Set-Cookie`` is a special case, represented as multiple lines, each line is a value that separated by ``';'``, 
##   no-parameters
## 
##   .. container::r-ol
## 
##      .. code-block::nim
##      
##        let fields = initHeaderFields({
##          "Set-Cookie": @["SID=123abc; path=/", "language=en; path=/"]
##        })
##        let values = fields.parseMultiRule("Content-Type")
##        assert values[0][0].key = "SID"
##        assert values[0][0].value = "123abc"
##        assert values[0][1].key = "path"
##        assert values[0][1].value = "/"
##        assert values[1][0].key = "language"
##        assert values[1][0].value = "en"
##        assert values[1][1].key = "path"
##        assert values[1][1].value = "/"
##    
##      If the returned result is not empty, then each item indicates a value.
## 
##      ..
## 
##        Note: When using this proc, you must ensure that the values is represented as multiple lines. 
##        If the values is represented as a single-line field like ``Date``, you may get wrong results. Because ``Date`` 
##        takes ``','`` as part of its value, for example, ``Date: Thu, 23 Apr 2020 07:41:15 GMT``.

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
#   .. code-block::nim
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
#   .. code-block::nim
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
import strutils
import netkit/http/spec

type
  HeaderFields* = distinct Table[string, seq[string]] ## Represents the header fields of a HTTP message.

proc initHeaderFields*(): HeaderFields = discard
  ## Initializes a ``HeaderFields``.

proc initHeaderFields*(pairs: openarray[tuple[name: string, value: seq[string]]]): HeaderFields = discard
  ## Initializes a ``HeaderFields``. ``pairs`` is a container consisting of ``(key, value)`` tuples.
  ## 
  ## The following example demonstrates how to deal with a single value, such as ``Content-Length``:
  ## 
  ## .. code-block::nim
  ## 
  ##   let fields = initHeaderFields({
  ##     "Content-Length": @["1"], 
  ##     "Content-Type": @["text/plain"]
  ##     "Cookie": @["SID=123; language=en"]
  ##   })
  ## 
  ## The following example demonstrates how to deal with ``Set-Cookie`` or a comma-separated list of values
  ## such as ``Accept``: 
  ## 
  ##   .. code-block::nim
  ## 
  ##     let fields = initHeaderFields({
  ##       "Set-Cookie": @["SID=123; path=/", "language=en"],
  ##       "Accept": @["audio/\*; q=0.2", "audio/basic"]
  ##     })

proc initHeaderFields*(pairs: openarray[tuple[name: string, value: string]]): HeaderFields = discard
  ## Initializes a ``HeaderFields``. ``pairs`` is a container consisting of ``(key, value)`` tuples.
  ## 
  ## The following example demonstrates how to deal with a single value, such as ``Content-Length``:
  ## 
  ## .. code-block::nim
  ## 
  ##   let fields = initHeaderFields({
  ##     "Content-Length": "16", 
  ##     "Content-Type": "text/plain"
  ##     "Cookie": "SID=123; language=en"
  ##   })

proc clear*(fields: var HeaderFields) = discard
  ## Resets this fields so that it is empty.

proc `[]`*(fields: HeaderFields, name: string): seq[string] {.raises: [KeyError].} = discard
  ## Returns the value of the field associated with ``name``. If ``name`` is not in this fields, the 
  ## ``KeyError`` exception is raised. 
  ## 
  ## Examples: 
  ## 
  ## .. code-block::nim
  ## 
  ##   let fields = initHeaderFields({
  ##     "Content-Length": "16"
  ##   })
  ##   assert fields["Content-Length"][0] == "16"

proc `[]=`*(fields: var HeaderFields, name: string, value: seq[string]) = discard
  ## Sets ``value`` to the field associated with ``name``. Replaces any existing value.
  ## 
  ## Examples: 
  ## 
  ## .. code-block::nim
  ## 
  ##   let fields = initHeaderFields({
  ##     "Content-Length": "16"
  ##   })
  ##   fields["Content-Length"] == @["100"]

proc add*(fields: var HeaderFields, name: string, value: string) = discard
  ## Adds ``value`` to the field associated with ``name``. If ``name`` does not exist then create a new one.
  ## 
  ## Examples: 
  ## 
  ## .. code-block::nim
  ## 
  ##   let fields = initHeaderFields()
  ##   fields.add("Content-Length", "16")
  ##   fields.add("Cookie", "SID=123")
  ##   fields.add("Cookie", "language=en")
  ##   fields.add("Accept", "audio/\*; q=0.2")
  ##   fields.add("Accept", "audio/basic")

proc del*(fields: var HeaderFields, name: string) = discard
  ## Deletes the field associated with ``name``. 
  ## 
  ## Examples: 
  ## 
  ## .. code-block::nim
  ## 
  ##   fields.del("Content-Length")
  ##   fields.del("Cookie")
  ##   fields.del("Accept")

proc contains*(fields: HeaderFields, name: string): bool = discard
  ## Returns true if this fields contains the specified ``name``. 
  ## 
  ## Examples: 
  ## 
  ## .. code-block::nim
  ## 
  ##   let fields = initHeaderFields({
  ##     "Content-Length": "16"
  ##   })
  ##   assert fields.contains("Content-Length") == true
  ##   assert fields.contains("content-length") == true
  ##   assert fields.contains("ContentLength") == false

proc len*(fields: HeaderFields): int = discard
  ## Returns the number of names in this fields.

iterator pairs*(fields: HeaderFields): tuple[name, value: string] = discard
  ## Yields each ``(name, value)`` pair.

iterator names*(fields: HeaderFields): string = discard
  ## Yields each field name.

proc getOrDefault*(
  fields: HeaderFields, 
  name: string,
  default = @[""]
): seq[string] = discard
  ## Returns the value of the field associated with ``name``. If ``name`` is not in this fields, then 
  ## ``default`` is returned.

proc `$`*(fields: HeaderFields): string = discard
  ## Converts this fields to a string that follows the HTTP Protocol.

proc parseSingleRule*(fields: HeaderFields, name: string): seq[tuple[key: string, value: string]] {.raises: [ValueError].} = discard
  ## Parses the field value that matches **single-line-rule**. 
    
proc parseMultiRule*(fields: HeaderFields, name: string, default = ""): seq[seq[tuple[key: string, value: string]]] = discard
  ## Parses the field value that matches **multiple-lines-rule**. 