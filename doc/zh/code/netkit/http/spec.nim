#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块包含 HTTP 规范相关的一些信息。

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
  ## 检查 ``s`` 是否为有效的 HTTP 头字段名称。
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
  ## 检查 ``s`` 是否为有效的 HTTP 头字段值。
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
  
     