#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块实现了一个哈希表 ``StrValuesTable``， 每一个键。

import tables
import strutils

type
  ValuesTable* = distinct Table[string, seq[string]] ## 表示一条 HTTP 消息的头字段集合。 

proc initValuesTable*(): ValuesTable = discard
  ## 初始化一个 HTTP 头字段集合对象。 

proc initValuesTable*(pairs: openArray[tuple[name: string, value: seq[string]]]): ValuesTable = discard
  ## 初始化一个 HTTP 头字段集合对象。 ``pairs`` 指定初始字段集合，每个字段可以有多个值。 
  ## 
  ## 下面的例子说明了如何处理单一值的头字段：
  ## 
  ## ..code-block::nim
  ## 
  ##   let vt = initValuesTable({
  ##     "Content-Length": @["1"], 
  ##     "Content-Type": @["text/plain"]
  ##     "Cookie": @["SID=123; language=en"]
  ##   })
  ## 
  ## 下面的例子说明了如何处理 ``Set-Cookie`` 或者使用逗号分隔的多值的头字段 (比如 ``Accept``)：
  ## 
  ## ..code-block::nim
  ## 
  ##   let vt = initValuesTable({
  ##     "Set-Cookie": @["SID=123; path=/", "language=en"],
  ##     "Accept": @["audio/*; q=0.2", "audio/basic"]
  ##   })

proc initValuesTable*(pairs: openArray[tuple[name: string, value: string]]): ValuesTable = discard
  ## 初始化一个 HTTP 头字段集合对象。``pairs`` 指定初始字段集合，每个字段只有一个值。 
  ## 
  ## 下面的例子说明了如何处理单一值的头字段：
  ## 
  ## ..code-block::nim
  ## 
  ##   let vt = initValuesTable({
  ##     "Content-Length": @["1"], 
  ##     "Content-Type": @["text/plain"]
  ##     "Cookie": @["SID=123; language=en"]
  ##   })

proc clear*(vt: var ValuesTable) = discard
  ## 清空所有字段。 

proc `[]`*(vt: ValuesTable, name: string): seq[string] = discard
  ## 获取名字为 ``name`` 的字段值， 可能是零到多个。 
  ## 
  ## 例子：  
  ## 
  ## ..code-block::nim
  ## 
  ##   let vt = initValuesTable({
  ##     "Content-Length": "16"
  ##   })
  ##   assert vt["Content-Length"][0] == "16"

proc `[]=`*(vt: var ValuesTable, name: string, value: seq[string]) = discard
  ## 设置名字为 ``name`` 的字段值。 这会清除所有 ``name`` 已经设置的值。 
  ## 
  ## 例子： 
  ## 
  ## ..code-block::nim
  ## 
  ##   let vt = initValuesTable({
  ##     "Content-Length": "16"
  ##   })
  ##   vt["Content-Length"] == @["100"]

proc add*(vt: var ValuesTable, name: string, value: string) = discard
  ## 为名字为 ``name`` 的字段添加一个值。 
  ## 
  ## 例子： 
  ## 
  ## ..code-block::nim
  ## 
  ##   let vt = initValuesTable()
  ##   vt.add("Content-Length", "16")
  ##   vt.add("Cookie", "SID=123")
  ##   vt.add("Cookie", "language=en")
  ##   vt.add("Accept", "audio/*; q=0.2")
  ##   vt.add("Accept", "audio/basic")

proc del*(vt: var ValuesTable, name: string) = discard
  ## 删除名字为 ``name`` 的字段。 
  ## 
  ## 例子： 
  ## 
  ## ..code-block::nim
  ## 
  ##   vt.del("Content-Length")
  ##   vt.del("Cookie")
  ##   vt.del("Accept")

proc contains*(vt: ValuesTable, name: string): bool = discard
  ## 判断是否包含 ``name`` 字段。 
  ## 
  ## 例子： 
  ## 
  ## ..code-block::nim
  ## 
  ##   let vt = initValuesTable({
  ##     "Content-Length": "16"
  ##   })
  ##   assert vt.contains("Content-Length") == true
  ##   assert vt.contains("content-length") == true
  ##   assert vt.contains("ContentLength") == false

proc len*(vt: ValuesTable): int = discard
  ## 获取字段数量。 

iterator pairs*(vt: ValuesTable): tuple[name, value: string] = discard
  ## 迭代每一个 ``(name, value)`` 对。 

iterator names*(vt: ValuesTable): string = discard
  ## 迭代每一个字段名。 
    
proc getOrDefault*(vt: ValuesTable, name: string, default = @[""]): seq[string] = discard
  ## 获取名为 ``name`` 的字段值， 如果不存在则返回 ``default``。 

proc `$`*(vt: ValuesTable): string = discard
  ## 把 ``vt`` 转换为遵循 HTTP 协议规范的字符串。 
