import netkit/misc

type
  SharedVec*[T] = object
    data: ptr UncheckedArray[T]
    len: Natural

proc `=destroy`*[T](x: var SharedVec[T]) = 
  if x.data != nil:
    for i in 0..<x.len: 
      `=destroy`(cast[ptr T](x.data.offset(sizeof(T) * i))[])
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

proc `[]`*[T](x: SharedVec[T], i: Natural): var T {.inline.} =
  when not defined(release):
    if i >= x.len: 
      raise newException(IndexDefect, "index out of bounds")
  x.data[i]

proc `[]=`*[T](x: var SharedVec[T], i: Natural, v: sink T) {.inline.} =
  when not defined(release):
    if i >= x.len: 
      raise newException(IndexDefect, "index out of bounds")
  x.data[i] = v

proc len*[T](x: SharedVec[T]): Natural {.inline.} = 
  x.len

proc resize*[T](x: var SharedVec[T], len: Natural) =
  if x.len > len: 
    for i in len..<x.len: 
      `=destroy`(cast[ptr T](x.data.offset(sizeof(T) * i))[])
  x.data = cast[ptr UncheckedArray[T]](reallocShared0(x.data, sizeof(T) * x.len, sizeof(T) * len))
  x.len = len

proc createSharedVec*[T](len: Natural): SharedVec[T] = 
  result.len = len
  result.data = cast[ptr UncheckedArray[T]](allocShared0(sizeof(T) * result.len))

when isMainModule:
  proc testInt() = 
    var vec = createSharedVec[int](10)
    for i in 0..<10: vec[i] = i

    block:
      doAssert vec.len == 10
      doAssert vec[1] == 1
      doAssert vec[8] == 8

    block resize:
      vec.resize(2)
      doAssert vec.len == 2
      doAssert vec[1] == 1

      vec.resize(4)
      doAssert vec.len == 4
      doAssert vec[1] == 1
      doAssert vec[3] == 0

    block sink:
      var vec2 = createSharedVec[int](10)
      vec2 = vec
      doAssert vec2.len == 4
      doAssert vec2[1] == 1

  type
    MyObj = object
      value: int

  proc testObj() = 
    var vec = createSharedVec[MyObj](10)
    for i in 0..<10: vec[i] = MyObj(value: i)

    block:
      doAssert vec.len == 10
      doAssert vec[1].value == 1
      doAssert vec[8].value == 8

    block lent:
      vec[1].value = 2
      doAssert vec[1].value == 2

  testInt()
  testObj()