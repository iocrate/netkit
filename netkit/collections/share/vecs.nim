# PS: 这个模块实现了一个面向共享堆的向量，用在多线程环境，文档以后补充。

type
  SharedVec*[T] = object
    data: ptr UncheckedArray[T]
    len: Natural

template checkMaxBounds[T](x: SharedVec[T], i: Natural) =
  # ``-d:release`` should disable this.
  when compileOption("boundChecks"): 
    if unlikely(i >= x.len): 
      raise newException(IndexDefect, "value out of bounds: " & $i & " > " & $(x.len - 1))

template checkMinBounds[T](x: SharedVec[T], i: Natural) =
  # ``-d:release`` should disable this.
  when compileOption("boundChecks"): 
    if unlikely(i < 0): 
      raise newException(IndexDefect, "value out of bounds: " & $i & " < 0")

proc `=destroy`*[T](x: var SharedVec[T]) = 
  if x.data != nil:
    for i in 0..<x.len: 
      `=destroy`(x.data[i])
    deallocShared(x.data)
    x.data = nil

proc `=sink`*[T](dest: var SharedVec[T], source: SharedVec[T]) = 
  `=destroy`(dest)
  dest.data = source.data
  dest.len = source.len

proc `=`*[T](dest: var SharedVec[T], source: SharedVec[T]) =
  if dest.data != source.data: 
    `=destroy`(dest)
    dest.len = source.len
    if source.data != nil:
      let blockLen = sizeof(T) * source.len
      dest.data = cast[ptr UncheckedArray[T]](allocShared0(blockLen))
      copyMem(dest.data, source.data, blockLen)

proc len*[T](x: SharedVec[T]): Natural {.inline.} = 
  x.len

proc `[]`*[T](x: SharedVec[T], i: Natural): lent T {.inline.} =
  checkMaxBounds(x, i)
  x.data[i]

proc `[]`*[T](x: var SharedVec[T], i: Natural): var T {.inline.} =
  checkMaxBounds(x, i)
  x.data[i]

proc `[]=`*[T](x: var SharedVec[T], i: Natural, v: sink T) {.inline.} =
  checkMaxBounds(x, i)
  x.data[i] = v

proc `[]`*[T](x: SharedVec[T], i: BackwardsIndex): lent T {.inline.} =
  ## `x[^1]` is the last element.
  let j = int(x.len) - int(i)
  checkMinBounds(x, j)
  x.data[j]

proc `[]`*[T](x: var SharedVec[T], i: BackwardsIndex): var T {.inline.} =
  ## `x[^1]` is the last element.
  let j = int(x.len) - int(i)
  checkMinBounds(x, j)
  x.data[j]

proc `[]=`*[T](x: var SharedVec[T], i: BackwardsIndex, v: sink T) {.inline.} =
  ## `x[^1]` is the last element.
  let j = int(x.len) - int(i)
  checkMinBounds(x, j)
  x.data[j] = v

iterator items*[T](x: SharedVec[T]): lent T = 
  for i in 0..<x.len: 
    yield x.data[i]

iterator mitems*[T](x: var SharedVec[T]): var T = 
  for i in 0..<x.len: 
    yield x.data[i]

iterator pairs*[T](x: SharedVec[T]): tuple[key: Natural, val: lent T] = 
  for i in 0..<x.len: 
    yield (i, x.data[i])

iterator mpairs*[T](x: var SharedVec[T]): tuple[key: Natural, val: var T] = 
  for i in 0..<x.len: 
    yield (Natural(i), x.data[i])

proc resize*[T](x: var SharedVec[T], len: Natural) =
  if x.len > len: 
    for i in len..<x.len: 
      `=destroy`(x.data[i])
  x.data = cast[ptr UncheckedArray[T]](reallocShared0(x.data, sizeof(T) * x.len, sizeof(T) * len))
  x.len = len

proc init*[T](x: var SharedVec[T], len: Natural = 4) = 
  `=destroy`(x)
  x.len = len
  x.data = cast[ptr UncheckedArray[T]](allocShared0(sizeof(T) * len))

when isMainModule:
  proc testInt() = 
    var vec: SharedVec[int]

    vec.init(10)
    for i in 0..<10: vec[i] = i

    block base:
      doAssert vec.len == 10
      doAssert vec[1] == 1
      doAssert vec[8] == 8
      doAssert vec[^1] == 9

    block resize:
      vec.resize(2)
      doAssert vec.len == 2
      doAssert vec[1] == 1

      vec.resize(4)
      doAssert vec.len == 4
      doAssert vec[1] == 1
      doAssert vec[3] == 0

    block sink:
      var vec2: SharedVec[int]
      
      vec2.init(10)
      vec2 = vec
      doAssert vec2.len == 4
      doAssert vec2[1] == 1
  
  type
    MyObj = object
      value: int

  proc testObj() = 
    var vec: SharedVec[MyObj]
    
    vec.init(10)
    for key, val in vec.mpairs(): 
      val = MyObj(value: key)

    block base:
      doAssert vec.len == 10
      doAssert vec[1].value == 1
      doAssert vec[8].value == 8

    block lent:
      vec[1].value = 2
      doAssert vec[1].value == 2

  testInt()
  testObj()