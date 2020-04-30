#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块包含 HTTP 版本的定义。

type
  HttpVersion* = enum
    HttpVer10 = "HTTP/1.0", 
    HttpVer11 = "HTTP/1.1"
    HttpVer20 = "HTTP/2.0"


proc parseHttpVersion*(s: string): HttpVersion  {.raises: [ValueError].} = discard
  ## 将字符串转换为状态码。当 ``s`` 不是有效的 HTTP 版本时，引发 ``ValueError`` 。当前只有 `"HTTP/1.0"` 和 `"HTTP/1.1"`
  ## 是有效的。
  ## 
  ## 例子：
  ## 
  ## .. code-block::nim
  ## 
  ##   let version = parseHttpVersion("HTTP/1.1")
  ##   assert version == HttpVer11