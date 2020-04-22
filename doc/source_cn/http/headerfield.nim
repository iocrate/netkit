#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## HTTP 协议定义了各种各样的头字段， 这些头字段的值有着独特的格式： 
## 
## 1. 使用单行表示。 表示单个值， 没有参数
## 
##    比如：
##    
##    ..code-block::http
## 
##      Content-Length: 0
## 
## 2. 使用单行表示。 表示单个值， 有参数， 参数之间使用 ``;`` 作为分隔符
## 
##    比如：
##    
##    ..code-block::http
## 
##      Content-Type: application/json
## 
##    或者
##    
##    ..code-block::http
## 
##      Content-Type: application/json; charset=utf8
## 
## 3. 使用单行表示。 表示多个值， 没有参数， 值之间使用 ``;`` 作为分隔符
## 
##    比如：
##    
##    ..code-block::http
## 
##      Cookie: SID=123abc; language=en
## 
## 4. 使用单行或多行表示。 表示多个值。 使用单行时，值之间使用 ``,`` 作为分隔符。 值的参数使用``;`` 作为分隔符
## 
##    单行表示：
##    
##    ..code-block::http
## 
##      Accept: text/html; q=1; level=1, text/plain
## 
##    多行表示：
##    
##    ..code-block::http
## 
##      Accept: text/html; q=1; level=1
##      Accept: text/plain
## 
## 5. ``Set-Cookie`` 是一个特例， 使用多行表示， 表示多个值
## 
##    ..code-block::http
## 
##      Set-Cookie: SID=123abc; path=/
##      Set-Cookie: language=en; path=/
## 
## 为了简化这些复杂的表示方式， 这个模块提供了一些特殊的工具。 这些工具将上面 5 种表示方式合并为 2 种： 允许单行和允许多行。
## 
## 使用指南 - 允许单行
## -----------------
## 
## 使用 ``parseSingleRule`` 以解析那些允许单行的头字段， 也就是上面列出的 1,2,3 规则。 返回的结果是一组 
## ``(key, value)`` 对。 每一对表示一个值或者值的参数 (如果支持参数的话) 。 以下是各个规则的使用例子： 
## 
## 1. 使用单行表示。 表示单个值， 没有参数
## 
##    ..code-block::nim
##      
##      let fields = initHeaderFields({
##        "Content-Length": @["0"]
##      })
##      let values = fields.parseSingleRule("Content-Length")
##      assert values[0].key = "0"
## 
##    返回结果应该最多只有一项， 并且第一项的 ``key`` 表示头字段的值。 
## 
##    注意：使用时， 您必须确定该字段确实是单行表示。 如果您使用该函数处理类似 ``Accept`` 这样的多行字段， 有可能会丢失值； 如果
##         发现 ``fields`` 中该字段超过了一个值， 将抛出异常。  
## 
## 2. 使用单行表示。 表示单个值， 有参数， 参数之间使用 ``;`` 作为分隔符
## 
##    ..code-block::nim
##      
##      let fields = initHeaderFields({
##        "Content-Type": @["application/json; charset=utf8"]
##      })
##      let values = fields.parseSingleRule("Content-Type")
##      assert values[0].key = "application/json"
##      assert values[1].key = "charset"
##      assert values[1].value = "utf8"
## 
##    返回结果不为空时， 则第一项的 ``key`` 表示头字段的值， 剩余项表示值的参数。 
## 
##    注意：使用时， 您必须确定该字段确实是单行表示。 如果您使用该函数处理类似 ``Accept`` 这样的多行字段， 有可能会丢失值； 如果
##         发现 ``fields`` 中该字段超过了一个值， 将抛出异常。  
## 
## 3. 使用单行表示。 表示单个值， 有参数， 参数之间使用 ``;`` 作为分隔符
## 
##    ..code-block::nim
##      
##      let fields = initHeaderFields({
##        "Cookie": @["SID=123abc; language=en"]
##      })
##      let values = fields.parseSingleRule("Cookie")
##      assert values[0].key = "SID"
##      assert values[0].value = "123abc"
##      assert values[1].key = "language"
##      assert values[1].value = "en"
## 
##    返回结果不为空时， 则每个项表示其中一个值， 以 ``(key, value)`` 表示。 
## 
##    注意：使用时， 您必须确定该字段确实是单行表示。 如果您使用该函数处理类似 ``Accept`` 这样的多行字段， 有可能会丢失值； 如果
##         发现 ``fields`` 中该字段超过了一个值， 将抛出异常。  
## 
## 使用指南 - 允许多行
## -----------------
## 
## 使用 ``parseMultiRule`` 以解析那些允许多行的头字段， 也就是上面列出的 4,5 规则。 返回的结果是一组 
## ``seq[(key, value)]`` 。 每一个 ``seq[(key, value)]`` 表示一个值和值的参数 (如果支持参数的话) 。 以下是各个规则的使用例子： 
## 
## 4. 使用单行或多行表示。 表示多个值。 使用单行时，值之间使用 ``,`` 作为分隔符。 值的参数使用``;`` 作为分隔符
## 
##    ..code-block::nim
##      
##      let fields = initHeaderFields({
##        "Accept": @["text/html; q=1; level=1, text/plain"]
##      })
##      let values = fields.parsMultiRule("Accept")
##      assert values[0][0].key = "text/html"
##      assert values[0][1].key = "q"
##      assert values[0][1].value = "1"
##      assert values[0][2].key = "level"
##      assert values[0][2].value = "1"
##      assert values[1][0].key = "text/plain"
## 
##    以下方式也是同样的结果：
## 
##    ..code-block::nim
##      
##      let fields = initHeaderFields({
##        "Accept": @["text/html; q=1; level=1", "text/plain"]
##      })
##      let values = fields.parsMultiRule("Accept")
## 
##    返回结果不为空时， 则每个项表示其中一个值， 以 ``seq[(key, value)]`` 表示， 该 seq 的第一项的 ``key`` 表示值本身， 其他项表示
##    值的参数。 
## 
##    注意：使用时， 您必须确定该字段确实是多行表示。 如果您使用该函数处理类似 ``Date`` 这样的单行字段， 有可能会得到错误的结果。  
## 
## 5. ``Set-Cookie`` 是一个特例， 使用多行表示， 表示多个值
## 
##    ..code-block::nim
##      
##      let fields = initHeaderFields({
##        "Set-Cookie": @["SID=123abc; path=/", "language=en; path=/"]
##      })
##      let values = fields.parsMultiRule("Content-Type")
##      assert values[0][0].key = "SID"
##      assert values[0][0].value = "123abc"
##      assert values[0][1].key = "path"
##      assert values[0][1].value = "/"
##      assert values[1][0].key = "language"
##      assert values[1][0].value = "en"
##      assert values[1][1].key = "path"
##      assert values[1][1].value = "/"
## 
##    返回结果不为空时， 则每个项表示其中一行， 每行以 ``(key, value)`` 表示名值对。  
## 
##    注意：使用时， 您必须确定该字段确实是单行表示。 如果您使用该函数处理类似 ``Date`` 这样的单行字段， 有可能会得到错误的结果。   

import strutils
import netkit/http/base
import netkit/http/exception

proc parseSingleRule*(fields: HeaderFields, name: string): seq[tuple[key: string, value: string]] = discard
  ## 

proc parsMultiRule*(fields: HeaderFields, name: string): seq[seq[tuple[key: string, value: string]]] = discard 
  ## 