#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块包含 HTTP 请求方法的定义。
## 
## 概述
## ========================
## 
## HTTP 定义了请求方法，以标识对资源执行的操作。资源代表什么，是预先存在的数据还是动态生成的数据，取决于服务器的实现。
## 通常，资源与服务器上驻留的文件或可执行文件的输出相对应。
## 
## .. 
## 
##   看看 `Hypertext Transfer Protocol <https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol>`_ 了解更多。

type
  HttpMethod* = enum ## HTTP 请求方法。
    HttpHead = "HEAD",        
    HttpGet = "GET",         
    HttpPost = "POST",        
    HttpPut = "PUT", 
    HttpDelete = "DELETE", 
    HttpTrace = "TRACE", 
    HttpOptions = "OPTIONS", 
    HttpConnect = "CONNECT", 
    HttpPatch = "PATCH" 

proc parseHttpMethod*(s: string): HttpMethod {.raises: [ValueError].} = discard
  ## 将字符串转换为 HTTP 请求方法。如果 ``s`` 不是有效的请求方法，则会引发 ``ValueError`` 。
  ## 
  ## 例子：
  ## 
  ## .. code-block::nim
  ## 
  ##   assert parseHttpMethod("GET") == HttpGet
  ##   assert parseHttpMethod("POST") == HttpPost