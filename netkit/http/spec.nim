#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块里实现一些 HTTP 规范相关的校验工具， 以验证 HTTP 消息的合法性。 请注意， 添加这些 checks， benchmark 将会随之有所下降。 

# Tip
# ---
#
# The set type are implemented as high performance bit vectors:
# 
# ..code-block::nim
#   
#   Chars: set[char] = {...} # => Chars: array[0..255, bit] = [0,0,0,0,1,1,0,1,0,0,0,1,...] 
#   'A' in {...}             # => Chars[61] == 1

import netkit/http/base

proc checkFieldName*(s: string) {.raises: [ValueError].} = 
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
  ##   field-name     =  token
  ##   token          =  1*tchar
  ##   tchar          =  "!" / "#" / "$" / "%" / "&" / "'" / "*"
  ##                  /  "+" / "-" / "." / "^" / "_" / "`" / "|" / "~"
  ##                  /  DIGIT 
  ##                  /  ALPHA
  ##                  ;  any VCHAR, except delimiters
  ## 
  const TokenChars = {
    '!', '#', '$', '%', '&', '\'', '*',
    '+', '-', '.', '^', '_', '`', '|', '~',
    '0'..'9',
    'a'..'z',
    'A'..'Z'
  }
  if s.len == 0:
    raise newException(ValueError, "Invalid field name")
  for c in s:
    if c notin TokenChars:
      raise newException(ValueError, "Invalid field name")

proc checkFieldValue*(s: string) {.raises: [ValueError].} = 
  ## `RFC5234 <https://tools.ietf.org/html/rfc5234>`_
  ## 
  ## ..code-block::nim
  ## 
  ##   HTAB           =  %x09       ; horizontal tab
  ##   SP             =  %x20       ; ' '
  ##   VCHAR          =  %x21-7E    ; visible (printing) characters
  ## 
  ## `RFC7230 <https://tools.ietf.org/html/rfc7230>`_
  ## 
  ## ..code-block::nim
  ## 
  ##   field-value    =  *( field-content / obs-fold )
  ##   field-content  =  field-vchar [ 1*( SP / HTAB ) field-vchar ]
  ##   field-vchar    =  VCHAR / obs-text
  ##   obs-text       =  %x80-FF
  ##   obs-fold       =  CRLF 1*( SP / HTAB )  ; obsolete line folding  
  ## 
  const ValueChars = { HTAB, SP, '\x21'..'\x7E', '\x80'..'\xFF' }
  for c in s:
    if c notin ValueChars:
      raise newException(ValueError, "Invalid field value")