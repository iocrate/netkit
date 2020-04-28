#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module contains a few information about HTTP Specification. 

# Tip
# ---
#
# The set type are implemented as high performance bit vectors:
# 
# ..code-block::nim
#   
#   Chars: set[char] = {...} # => Chars: array[0..255, bit] = [0,0,0,0,1,1,0,1,0,0,0,1,...] 
#   'A' in {...}             # => Chars[61] == 1

const 
  # [RFC5234](https://tools.ietf.org/html/rfc5234#appendix-B.1)
  COLON* = ':'
  COMMA* = ','
  SEMICOLON* = ';'
  CR* = '\x0D'
  LF* = '\x0A'
  CRLF* = "\x0D\x0A"
  SP* = '\x20'
  HTAB* = '\x09'
  WSP* = {SP, HTAB}

proc checkFieldName*(s: string) {.raises: [ValueError].} = discard
  ## Checks if ``s`` is a valid name of a HTTP header field. 
  ##
  ## `HTTP RFC 5234 <https://tools.ietf.org/html/rfc5234>`_
  ## 
  ## .. code-block::nim
  ## 
  ##   DIGIT          =  %x30-39            ; 0-9
  ##   ALPHA          =  %x41-5A / %x61-7A  ; A-Z / a-z
  ## 
  ## `HTTP RFC 7230 <https://tools.ietf.org/html/rfc7230>`_
  ## 
  ## .. code-block::nim
  ## 
  ##   field-name     =  token
  ##   token          =  1*tchar
  ##   tchar          =  "!" / "#" / "$" / "%" / "&" / "'" / "*"
  ##                  /  "+" / "-" / "." / "^" / "_" / "`" / "|" / "~"
  ##                  /  DIGIT 
  ##                  /  ALPHA
  ##                  ;  any VCHAR, except delimiters
  ## 

proc checkFieldValue*(s: string) {.raises: [ValueError].} = discard
  ## Checks if ``s`` is a valid value of a HTTP header field. 
  ## 
  ## `HTTP RFC 5234 <https://tools.ietf.org/html/rfc5234>`_
  ## 
  ## .. code-block::nim
  ## 
  ##   HTAB           =  %x09       ; horizontal tab
  ##   SP             =  %x20       ; ' '
  ##   VCHAR          =  %x21-7E    ; visible (printing) characters
  ## 
  ## `HTTP RFC 7230 <https://tools.ietf.org/html/rfc7230>`_
  ## 
  ## .. code-block::nim
  ## 
  ##   field-value    =  \*( field-content / obs-fold )
  ##   field-content  =  field-vchar [ 1\*( SP / HTAB ) field-vchar ]
  ##   field-vchar    =  VCHAR / obs-text
  ##   obs-text       =  %x80-FF
  ##   obs-fold       =  CRLF 1\*( SP / HTAB )  ; obsolete line folding  
  ## 
  
     