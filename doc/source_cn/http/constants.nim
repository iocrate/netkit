#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 本模块定义了 HTTP 操作使用的一些常量。 其中的一部分， 支持编译时通过 ``--define`` 指令重定义。 这些常量影响
## HTTP 服务器和客户端的行为。 

import netkit/checks

const LimitStartLineLen* {.intdefine.}: Natural = 8*1024 
  ## 指定 HTTP start-line 允许的最大长度 (字节数) 。 这个限制同时影响 request-line and status-line 。 
  ## 
  ## 由于 request-line 由请求方法、 URI、 协议版本号组成， 这条指令为请求消息的 request-URI 设定了长度限制。 
    
const LimitHeaderFieldLen* {.intdefine.}: Natural = 8*1024 
  ## 指定一个 HTTP 头字段允许的最大长度 (字节数) 。 这个限制同时影响请求头和响应头。 

const LimitHeaderFieldCount* {.intdefine.}: Natural = 100 
  ## 指定一条 HTTP 消息允许出现的头字段的最大数量。 这个限制同时影响请求头和响应头。 
     
const LimitChunkSizeLen*: Natural = 16 
  ## 对于一个经过 ``Transfer-Encoding: chunked`` 编码的数据块， 指定其尺寸部分的最大长度。 
  
const LimitChunkHeaderLen* {.intdefine.}: Natural = 1*1024 
  ## 对于一个经过 ``Transfer-Encoding: chunked`` 编码的数据块， 指定其尺寸部分和扩展部分的最大长度。 
  ## 
  ## 根据 HTTP protocol， size 部分和扩展部分类似下面这种形式：
  ## 
  ## ..code-block:http
  ## 
  ##   7\r\n; foo=value1; bar=value2\r\n 
 
const LimitChunkDataLen* {.intdefine.}: Natural = 1*1024 
  ## 对于一个经过 ``Transfer-Encoding: chunked`` 编码的数据块， 指定其数据部分的最大长度。 
  ## 
  ## 根据 HTTP protocol， 数据部分类似下面这种形式：
  ## 
  ## ..code-block:http
  ## 
  ##   Hello World\r\n 

const LimitChunkTrailerLen* {.intdefine.}: Natural = 8*1024 
  ## 对于一个经过 ``Transfer-Encoding: chunked`` 编码的数据块， 指定其一个元数据的最大长度。 实际上，元数据是
  ## 一些 ``Trailer`` 头字段。 例子： 
  ## 
  ## ..code-block:http
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
  ## 对于一个经过 ``Transfer-Encoding: chunked`` 编码的消息， 指定其 ``Trailer`` 头字段允许出现的最大数量。 