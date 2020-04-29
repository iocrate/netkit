#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块包含 HTTP 版本的定义。

type
  HttpVersion* = tuple 
    ## HTTP 版本。 ``orig`` 表示原始字符串形式，比如 ``"HTTP/1.1"`` 。 ``major`` 表示主版本号， 
    ## ``minor`` 表示次版本号。
    orig: string
    major: Natural
    minor: Natural

const 
  HttpVersion10* = "HTTP/1.0"
  HttpVersion11* = "HTTP/1.1"
  HttpVersion20* = "HTTP/2.0"

proc parseHttpVersion*(s: string): HttpVersion  {.raises: [ValueError].} = discard
  ## 将字符串转换为状态码。当 ``s`` 不是有效的 HTTP 版本时，引发 ``ValueError`` 。当前只有 `"HTTP/1.0"` 和 `"HTTP/1.1"`
  ## 是有效的。
  ## 
  ## 例子：
  ## 
  ## .. code-block::nim
  ## 
  ##   let version = parseHttpVersion("HTTP/1.1")
  ##   assert version.orig == "HTTP/1.1"
  ##   assert version.major == 1
  ##   assert version.minor == 1