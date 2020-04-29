#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块包含 HTTP 头部字段的定义。 ``HeaderFields`` 使用一个 distinct table 实现，表示头部字段的集合。
## 
## 概述
## ========================
## 
## HTTP 头字段是请求消息头部和响应消息头部的组件，负责定义 HTTP 传输的操作参数。
## 
## 头字段的名字忽略大小写。许多头字段的值，则使用空白或者特殊的分隔符拆分成多个组件。
## 
## .. container::r-fragment
## 
##   格式规则 
##   ----------------
## 
##   头字段的值，其格式差异很大。有五种不同的格式规则：
## 
##   1. 表示为单行；单个值；无参数
## 
##   .. container::r-ol
## 
##      例子：
##    
##      .. code-block::http
## 
##        Content-Length: 0
## 
##   2. 表示为单行；单个值；以 ``';'`` 分隔的可选参数
## 
##   .. container::r-ol
## 
##      例子：  
##    
##      .. code-block::http
## 
##        Content-Type: application/json
## 
##      或者：
##    
##      .. code-block::http
## 
##        Content-Type: application/json; charset=utf8
## 
##   3. 表示为单行；多个值，之间用 ``';'`` 分隔；无参数
## 
##   .. container::r-ol
## 
##      例子：
##    
##      .. code-block::http
## 
##        Cookie: SID=123abc; language=en
## 
##   4. 表示为单行或多行；多个值，之间用 ``';'`` 分隔；每个值具有可选参数，以 ``';'`` 分隔
## 
##   .. container::r-ol
## 
##      单行：
##    
##      .. code-block::http
## 
##        Accept: text/html; q=1; level=1, text/plain
## 
##      多行：
##    
##      .. code-block::http
## 
##        Accept: text/html; q=1; level=1
##        Accept: text/plain
## 
##   5. ``Set-Cookie`` 是一种特殊情况，用多行表示；每行都是以 ``';'`` 分隔的值；无参数
## 
##   .. container::r-ol
## 
##      .. code-block::http
## 
##        Set-Cookie: SID=123abc; path=/
##        Set-Cookie: language=en; path=/
## 
##   为了简化这些复杂的表示形式，该模块提供了两个特殊工具 ``parseSingleRule`` 和 ``parseMultiRule`` ，
##   将上述 5 条规则组合为 2 条规则 **single-line-rule** (SLR) 和 **multiple-lines-rule** (MLR)。
## 
## 用法
## ========================
## 
## .. container:: r-fragment
## 
##   访问头字段
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
##   基于 SLR 访问值
##   --------------------
## 
##   使用 ``parseSingleRule`` 解析头字段，该头字段遵循上面列出的 1,2,3 规则，并返回一组 ``(key, value)`` 对。
## 
##   1. 表示为单行；单个值；无参数
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
##      返回的结果最多包含一项，并且第一项的 ``key`` 表示头字段的值（如果有）。
##      
##      .. 
##      
##        注意：使用此 proc 时，必须确保这些值以单行表示。如果值可表示为多行（如 ``Accept``），则可能会丢失值。如果发现存在多个值，将引发异常。
## 
##   2. 表示为单行；单个值；以 ``';'`` 分隔的可选参数
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
##      如果返回的结果不为空，则第一项的 ``key`` 表示此头字段的值，其他项表示值的参数。
##      
##      .. 
##      
##        注意：使用此 proc 时，必须确保这些值以单行表示。如果值可表示为多行（如 ``Accept``），则可能会丢失值。如果发现存在多个值，将引发异常。
## 
##   3. 表示为单行；多个值，之间用 ``';'`` 分隔；无参数
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
##      如果返回的结果不为空，则每个项表示一个值。
##      
##      .. 
##      
##        注意：使用此 proc 时，必须确保这些值以单行表示。如果值可表示为多行（如 ``Accept``），则可能会丢失值。如果发现存在多个值，将引发异常。
## 
## .. container:: r-fragment
## 
##   基于 MLR 访问值
##   --------------------
## 
##   使用 ``parseMultiRule`` 解析头字段，该头字段遵循上面列出的 4,5 规则，并返回一组 ``seq[(key，value)]`` 。
## 
##   4. 表示为单行或多行；多个值，之间用 ``';'`` 分隔；每个值具有可选参数，以 ``';'`` 分隔
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
##      以下相同：
## 
##      .. code-block::nim
##      
##        let fields = initHeaderFields({
##          "Accept": @["text/html; q=1; level=1", "text/plain"]
##        })
##        let values = fields.parseMultiRule("Accept")
## 
##      如果返回的结果不为空，则每个项均指示一个值。每个项第一项的 ``key`` 表示值本身，其他项表示值的参数。
## 
##      ..
## 
##        注意：使用此 proc 时，必须确保值可表示为多行。如果值是那些诸如 ``Date`` 之类的单行值，则可能会得到错误的结果。 
##        因为 ``Date`` 将 ``,`` 视为值的一部分，例如 ``Date: Thu, 23 Apr 2020 07:41:15 GMT`` 。
## 
##   5. ``Set-Cookie`` 是一种特殊情况，用多行表示；每行都是以 ``';'`` 分隔的值；无参数
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
##      如果返回的结果不为空，则每个项均指示一个值。
## 
##      ..
## 
##        注意：使用此 proc 时，必须确保值可表示为多行。如果值是那些诸如 ``Date`` 之类的单行值，则可能会得到错误的结果。 
##        因为 ``Date`` 将 ``,`` 视为值的一部分，例如 ``Date: Thu, 23 Apr 2020 07:41:15 GMT`` 。

import tables
import strutils
import netkit/http/spec

type
  HeaderFields* = distinct Table[string, seq[string]] ## Represents the header fields of a HTTP message.

proc initHeaderFields*(): HeaderFields = discard
  ## 初始化一个 ``HeaderFields`` 。

proc initHeaderFields*(pairs: openarray[tuple[name: string, value: seq[string]]]): HeaderFields = discard
  ## 初始化一个 ``HeaderFields`` ， ``pairs`` 指定一组 ``(name, value)`` 对。
  ## 
  ## 下面的示例演示如何处理单值字段，例如 ``Content-Length`` ：
  ## 
  ## .. code-block::nim
  ## 
  ##   let fields = initHeaderFields({
  ##     "Content-Length": @["1"], 
  ##     "Content-Type": @["text/plain"]
  ##     "Cookie": @["SID=123; language=en"]
  ##   })
  ## 
  ## 下面的示例演示如何处理 Set-Cookie 或以逗号分隔的多值字段（例如 ``Accept`` ）：
  ## 
  ##   .. code-block::nim
  ## 
  ##     let fields = initHeaderFields({
  ##       "Set-Cookie": @["SID=123; path=/", "language=en"],
  ##       "Accept": @["audio/\*; q=0.2", "audio/basic"]
  ##     })

proc initHeaderFields*(pairs: openarray[tuple[name: string, value: string]]): HeaderFields = discard
  ## 初始化一个 ``HeaderFields``. ``pairs`` 指定一组 ``(name, value)`` 对。
  ## 
  ## 下面的示例演示如何处理单值字段，例如 ``Content-Length`` ：
  ## 
  ## .. code-block::nim
  ## 
  ##   let fields = initHeaderFields({
  ##     "Content-Length": "16", 
  ##     "Content-Type": "text/plain"
  ##     "Cookie": "SID=123; language=en"
  ##   })

proc clear*(fields: var HeaderFields) = discard
  ## 重置头字段，清空里面的数据。

proc `[]`*(fields: HeaderFields, name: string): seq[string] {.raises: [KeyError].} = discard
  ## 返回名字为 ``name`` 的字段值。如果此字段中没有 ``name`` ，则会引发 ``KeyError`` 异常。
  ## 
  ## 例子：
  ## 
  ## .. code-block::nim
  ## 
  ##   let fields = initHeaderFields({
  ##     "Content-Length": "16"
  ##   })
  ##   assert fields["Content-Length"][0] == "16"

proc `[]=`*(fields: var HeaderFields, name: string, value: seq[string]) = discard
  ## 设置名字为 ``name`` 的字段值。如果字段已经存在，则替换已有的值。
  ## 
  ## 例子：
  ## 
  ## .. code-block::nim
  ## 
  ##   let fields = initHeaderFields({
  ##     "Content-Length": "16"
  ##   })
  ##   fields["Content-Length"] == @["100"]

proc add*(fields: var HeaderFields, name: string, value: string) = discard
  ## 添加一个字段，名字为 ``name``，值为 ``value``。如果字段不存在，则创建一个。
  ## 
  ## 例子：
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
  ## 删除名字为 ``name`` 的字段。
  ## 
  ## 例子：
  ## 
  ## .. code-block::nim
  ## 
  ##   fields.del("Content-Length")
  ##   fields.del("Cookie")
  ##   fields.del("Accept")

proc hasKey*(fields: HeaderFields, name: string): bool = discard
  ## 判断是否含有名字为 ``name`` 的字段。
  ## 
  ## 例子：
  ## 
  ## .. code-block::nim
  ## 
  ##   let fields = initHeaderFields({
  ##     "Content-Length": "16"
  ##   })
  ##   assert fields.hasKey("Content-Length") == true
  ##   assert fields.hasKey("content-length") == true
  ##   assert fields.hasKey("ContentLength") == false
  ##   assert "content-length" in fields

proc contains*(fields: HeaderFields, name: string): bool = discard
  ## 判断是否含有名字为 ``name`` 的字段。
  ## 
  ## 例子：
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
  ## 返回包含的字段数量。

iterator pairs*(fields: HeaderFields): tuple[name, value: string] = discard
  ## 迭代所有字段。

iterator names*(fields: HeaderFields): string = discard
  ## 迭代所有字段的名字。

proc getOrDefault*(
  fields: HeaderFields, 
  name: string,
  default = @[""]
): seq[string] = discard
  ## 返回名字为 ``name`` 的字段值。如果字段不存在，则返回 ``default`` 。

proc `$`*(fields: HeaderFields): string = discard
  ## 把字段转换为一个遵循 HTTP 规范的字符串。

proc parseSingleRule*(fields: HeaderFields, name: string): seq[tuple[key: string, value: string]] {.raises: [ValueError].} = discard
  ## 解析名字为 ``name`` 的字段值，该值匹配 **single-line-rule** 规则。
    
proc parseMultiRule*(fields: HeaderFields, name: string, default = ""): seq[seq[tuple[key: string, value: string]]] = discard
  ## 解析名字为 ``name`` 的字段值，该值匹配 **multiple-lines-rule** 规则。 