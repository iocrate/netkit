#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 该模块定义了一些与 HTTP 操作相关的常量。其中一些支持在编译时通过 ``--define`` 指令重定义。

import netkit/misc

const LimitStartLineLen* {.intdefine.}: Natural = 8*1024 
  ## 指定 HTTP 起始行的最大字节数。此限制同时影响请求行和状态行。
  ## 
  ## 由于请求行由 HTTP 请求方法、URL 和版本号组成，因此该指令对服务器端允许请求的 URL 长度进行了限制。
  ## 
  ## 您可以在编译时通过开关选项 ``--define:BufferSize=<n>`` 重写这个数值。
  ## 注意，值必须是自然数，即大于等于零的整数；否则，将会引起异常。 
    
const LimitHeaderFieldLen* {.intdefine.}: Natural = 8*1024 
  ## 指定 HTTP 头字段的最大长度。此限制同时影响请求头字段和响应头字段。
  ## 
  ## HTTP 头字段的大小在不同的实现中会有很大的不同，通常取决于用户对其浏览器配置支持内容协商的程度。
  ## 
  ## 您可以在编译时通过开关选项 ``--define:BufferSize=<n>`` 重写这个数值。
  ## 注意，值必须是自然数，即大于等于零的整数；否则，将会引起异常。 

const LimitHeaderFieldCount* {.intdefine.}: Natural = 100 
  ## 指定 HTTP 头字段的最大数量。此限制同时影响请求头字段和响应头字段。
  ## 
  ## 您可以在编译时通过开关选项 ``--define:BufferSize=<n>`` 重写这个数值。
  ## 注意，值必须是自然数，即大于等于零的整数；否则，将会引起异常。 
     
const LimitChunkSizeLen*: Natural = 16 
  ## 指定通过 chunked 编码的块数据其 size 部分的最大字节数。
  
const LimitChunkHeaderLen* {.intdefine.}: Natural = 1*1024 
  ## 指定通过 chunked 编码的块数据其 size 和扩展部分的最大字节数。
  ## 
  ## 您可以在编译时通过开关选项 ``--define:BufferSize=<n>`` 重写这个数值。
  ## 注意，值必须是自然数，即大于等于零的整数；否则，将会引起异常。 
  ## 
  ## 根据 HTTP 协议，数据的大小和扩展部分采用以下形式：
  ## 
  ## .. code-block::http
  ## 
  ##   7\r\n; foo=value1; bar=value2\r\n 
 
const LimitChunkDataLen* {.intdefine.}: Natural = 1*1024 
  ## 指定通过 chunked 编码的块数据的数据部分的最大字节数。
  ## 
  ## 您可以在编译时通过开关选项 ``--define:BufferSize=<n>`` 重写这个数值。
  ## 注意，值必须是自然数，即大于等于零的整数；否则，将会引起异常。 
  ## 
  ## 根据 HTTP 协议，数据部分采用以下形式：
  ## 
  ## .. code-block::http
  ## 
  ##   Hello World\r\n 

const LimitChunkTrailerLen* {.intdefine.}: Natural = 8*1024 
  ## 指定通过 chunked 编码的消息其元数据部分的最大字节数。实际上，这些元数据是一些 ``trailers`` 。
  ## 
  ## 您可以在编译时通过开关选项 ``--define:BufferSize=<n>`` 重写这个数值。
  ## 注意，值必须是自然数，即大于等于零的整数；否则，将会引起异常。 
  ## 
  ## 例子：
  ## 
  ## .. code-block::http
  ## 
  ##   HTTP/1.1 200 OK 
  ##   Transfer-Encoding: chunked
  ##   Trailer: Expires
  ##   
  ##   9\r\n 
  ##   Developer\r\n 
  ##   0\r\n 
  ##   Expires: Wed, 21 Oct 2015 07:28:00 GMT\r\n
  ##   \r\n
  
const LimitChunkTrailerCount* {.intdefine.}: Natural = 100 
  ## 指定通过 chunked 编码的消息其元数据部分的最大数量。实际上，这些元数据是一些 ``trailers`` 。
  ## 
  ## 您可以在编译时通过开关选项 ``--define:BufferSize=<n>`` 重写这个数值。
  ## 注意，值必须是自然数，即大于等于零的整数；否则，将会引起异常。 
  ## 
  ## 