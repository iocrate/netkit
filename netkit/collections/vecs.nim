# PS: 这个模块实现了一个面向线程本地堆的向量，文档以后补充。

import netkit/allocmode

type
  Vec*[T] = object
    mode: AllocMode
    data: ptr UncheckedArray[T]
    cap: Natural

template checkMaxBounds[T](vec: Vec[T], i: Natural) =
  # ``-d:release`` should disable this.
  when compileOption("boundChecks"): 
    if unlikely(i >= vec.cap): 
      raise newException(IndexDefect, "value out of bounds: " & $i & " > " & $(vec.cap - 1))

template checkMinBounds[T](vec: Vec[T], i: Natural) =
  # ``-d:release`` should disable this.
  when compileOption("boundChecks"): 
    if unlikely(i < 0): 
      raise newException(IndexDefect, "value out of bounds: " & $i & " < 0")

proc `=destroy`*[T](vec: var Vec[T]) = 
  if vec.data != nil:
    for i in 0..<vec.cap: 
      `=destroy`(vec.data[i])
    case vec.mode
    of AllocMode.THREAD_SHARED:
      deallocShared(vec.data)
    of AllocMode.THREAD_LOCAL:
      dealloc(vec.data)
    vec.data = nil

proc `=sink`*[T](dest: var Vec[T], source: Vec[T]) = 
  `=destroy`(dest)
  dest.cap = source.cap
  dest.data = source.data

proc `=`*[T](dest: var Vec[T], source: Vec[T]) =
  if dest.data != source.data: 
    `=destroy`(dest)
    dest.cap = source.cap
    if source.data != nil:
      let blockLen = sizeof(T) * source.cap
      case dest.mode
      of AllocMode.THREAD_SHARED:
        dest.data = cast[ptr UncheckedArray[T]](allocShared0(blockLen))
      of AllocMode.THREAD_LOCAL:
        dest.data = cast[ptr UncheckedArray[T]](alloc0(blockLen))
      copyMem(dest.data, source.data, blockLen)

proc cap*[T](vec: Vec[T]): Natural {.inline.} = 
  vec.cap

proc `[]`*[T](vec: Vec[T], i: Natural): lent T {.inline.} =
  checkMaxBounds(vec, i)
  vec.data[i]

proc `[]`*[T](vec: var Vec[T], i: Natural): var T {.inline.} =
  checkMaxBounds(vec, i)
  vec.data[i]

proc `[]=`*[T](vec: var Vec[T], i: Natural, v: sink T) {.inline.} =
  checkMaxBounds(vec, i)
  vec.data[i] = v

proc `[]`*[T](vec: Vec[T], i: BackwardsIndex): lent T {.inline.} =
  ## `vec[^1]` is the last element.
  let j = int(vec.cap) - int(i)
  checkMinBounds(vec, j)
  vec.data[j]

proc `[]`*[T](vec: var Vec[T], i: BackwardsIndex): var T {.inline.} =
  ## `vec[^1]` is the last element.
  let j = int(vec.cap) - int(i)
  checkMinBounds(vec, j)
  vec.data[j]

proc `[]=`*[T](vec: var Vec[T], i: BackwardsIndex, v: sink T) {.inline.} =
  ## `vec[^1]` is the last element.
  let j = int(vec.cap) - int(i)
  checkMinBounds(vec, j)
  vec.data[j] = v

iterator items*[T](vec: Vec[T]): lent T = 
  for i in 0..<vec.cap: 
    yield vec.data[i]

iterator mitems*[T](vec: var Vec[T]): var T = 
  for i in 0..<vec.cap: 
    yield vec.data[i]

iterator itemsBackwards*[T](vec: Vec[T]): lent T = 
  for i in countdown(vec.cap-1, 0): 
    yield vec.data[i]

iterator mitemsBackwards*[T](vec: Vec[T]): var T = 
  for i in countdown(vec.cap-1, 0): 
    yield vec.data[i]

iterator pairs*[T](vec: Vec[T]): tuple[key: Natural, val: lent T] = 
  for i in 0..<vec.cap: 
    yield (Natural(i), vec.data[i])

iterator pairsBackwards*[T](vec: Vec[T]): tuple[key: Natural, val: lent T] = 
  for i in countdown(vec.cap-1, 0): 
    yield (Natural(i), vec.data[i])

iterator mpairs*[T](vec: var Vec[T]): tuple[key: Natural, val: var T] = 
  for i in 0..<vec.cap: 
    yield (Natural(i), vec.data[i])

iterator mpairsBackwards*[T](vec: Vec[T]): tuple[key: Natural, val: lent T] = 
  for i in countdown(vec.cap-1, 0): 
    yield (Natural(i), vec.data[i])

proc resize*[T](vec: var Vec[T], cap: Natural) =
  if vec.cap > cap: 
    for i in cap..<vec.cap: 
      `=destroy`(vec.data[i])
  vec.data = cast[ptr UncheckedArray[T]](realloc0(vec.data, sizeof(T) * vec.cap, sizeof(T) * cap))
  vec.cap = cap

proc initVec*[T](vec: var Vec[T], cap: Natural = 4, mode = AllocMode.THREAD_SHARED) = 
  `=destroy`(vec)
  vec.mode = mode
  vec.cap = cap
  case vec.mode
  of AllocMode.THREAD_SHARED:
    vec.data = cast[ptr UncheckedArray[T]](allocShared0(sizeof(T) * cap))
  of AllocMode.THREAD_LOCAL:
    vec.data = cast[ptr UncheckedArray[T]](alloc0(sizeof(T) * cap))

when isMainModule:
  proc testInt() = 
    var vec: Vec[int]

    vec.initVec(10, AllocMode.THREAD_LOCAL)
    for i in 0..<10: vec[i] = i

    block base:
      doAssert vec.cap == 10
      doAssert vec[1] == 1
      doAssert vec[8] == 8
      doAssert vec[^1] == 9

    block resize:
      vec.resize(2)
      doAssert vec.cap == 2
      doAssert vec[1] == 1

      vec.resize(4)
      doAssert vec.cap == 4
      doAssert vec[1] == 1
      doAssert vec[3] == 0

    block sink:
      var vec2: Vec[int]
      
      vec2.initVec(10, AllocMode.THREAD_LOCAL)
      vec2 = vec
      doAssert vec2.cap == 4
      doAssert vec2[1] == 1
  
  type
    MyObj = object
      value: int

  proc testObj() = 
    var vec: Vec[MyObj]
    
    vec.initVec(10)
    for key, val in vec.mpairs(): 
      val = MyObj(value: key)

    block base:
      doAssert vec.cap == 10
      doAssert vec[1].value == 1
      doAssert vec[8].value == 8

    block lent:
      vec[1].value = 2
      doAssert vec[1].value == 2

  testInt()
  testObj()
  