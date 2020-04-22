#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## TODO: 整理这篇文档
## 
## HTTP Specifition 对头字段的定义非常的 sucks， 有非常多的特例， 甚至有些混乱。 有些字段是单个值， 比如 content-type， 有些字段是多个
## 值， 比如 accept 。 单个值中， 有的有参数， 比如 content-length： 0， 有的没有参数， 比如 content-type： application/json; charset=utf8。
## 多个值中， 有的是名字值对， 比如 cookie: a=1; c=2， 有的是值和参数， 比如 accept： text/html;q=1;level=1, text/plain。 对于多个值，使用
## 多行或者 ``,`` 作为分隔符。 另外， ``"`` 作为引用字符串则会将内部的 ``,`` 排除。 对于单个值， ``,`` 则属于内容而非分隔符， 比如
## Date: Wed, 21 Oct 2015 07:28:00 GMT 。``;`` 在某些值里扮演参数的分隔符， 比如 content-type： application/json; charset=utf8， 在某些值
## 里则扮演名值对的分隔符， 比如 cookie: a=1; b=2 。
##
## 为了尽可能简化对这些负责情况的处理， netkit 提供了两个解码 procs， 一个用于处理单个值， 一个用户处理多个值。 在使用的时候， 您必须负责指定目标
## 是单值或者多值， 解码 procs 按照指定的方式进行解析， 而不管是否正确。 比如 ``Date: Wed, 21 Oct 2015 07:28:00 GMT``， 应该使用
## ``decodeSingle``， 但是如果您使用 ``decodeMulti``， 则会将其中的 ``,`` 作为分隔符， 输出多值 ``["Wed", "21 Oct 2015 07:28:00 GMT"]``
##
## 比如您在调用 ``decodeSingle(fields, "Content-Type")`` 得到的结果可能是 ``@[("application/json", ""), ("charset", "utf8")]``； 在调用
## ``decodeSingle(fields, "Content-Length")`` 得到的结果可能是 ``@[("0", "")]``； 在调用``decodeMulti(fields, "Cookie")`` 得到的结果可能是 
## ``@[("a", "1"), ("b", "2")]``。 
## 
## 请注意 Set-Cookie 是多行值； Cookie 是单行值， 和其他不一样的是， Cookie 使用 ``;`` 作为分隔符。 
## 
## - 多行 , 多值， 每个 , 一个值 
## - 多行 setcookie 特例 多值， 每个 field 一个值 (对象)
## - 单行 ; 多个值 cookie
## - 单行 单值 content-length 

import strutils
import netkit/http/base
import netkit/http/exception

proc decodeSingle*(fields: HeaderFields, name: string): seq[tuple[key: string, value: string]] = discard
  ## 

proc decodeMulti*(fields: HeaderFields, name: string): seq[seq[tuple[key: string, value: string]]] = discard 
  ## 