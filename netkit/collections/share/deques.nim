## Implementation of a `deque`:idx: (double-ended queue).
## The underlying implementation uses a ``seq``.
##
## None of the procs that get an individual value from the deque can be used
## on an empty deque.
## If compiled with `boundChecks` option, those procs will raise an `IndexDefect`
## on such access. This should not be relied upon, as `-d:release` will
## disable those checks and may return garbage or crash the program.
##
## As such, a check to see if the deque is empty is needed before any
## access, unless your program logic guarantees it indirectly.
##
## .. code-block:: Nim
##   import deques
##
##   var a: SharedDeque[int]
##   a.init()
##
##   doAssertRaises(IndexDefect, echo a[0])
##
##   for i in 1 .. 5:
##     a.addLast(10*i)
##   assert $a == "[10, 20, 30, 40, 50]"
##
##   assert a.peekFirst == 10
##   assert a.peekLast == 50
##   assert len(a) == 5
##
##   assert a.popFirst == 10
##   assert a.popLast == 50
##   assert len(a) == 3
##
##   a.addFirst(11)
##   a.addFirst(22)
##   a.addFirst(33)
##   assert $a == "[33, 22, 11, 20, 30, 40]"
##
##   a.shrink(fromFirst = 1, fromLast = 2)
##   assert $a == "[22, 11, 20]"
##
##
## **See also:**
## * `lists module <lists.html>`_ for singly and doubly linked lists and rings
## * `channels module <channels.html>`_ for inter-thread communication

import std/math
import netkit/misc

type
  SharedDeque*[T] = object
    ## A double-ended queue backed with a ringed seq buffer.
    ##
    ## To initialize an empty deque use `initSharedDeque proc <#initSharedDeque,int>`_.
    data: ptr UncheckedArray[T]
    head, tail, cap, len, mask: Natural

template checkMaxBounds[T](x: SharedDeque[T], i: Natural) =
  # ``-d:release`` should disable this.
  when compileOption("boundChecks"): 
    if unlikely(i >= x.len): 
      raise newException(IndexDefect, "Out of bounds: " & $i & " > " & $(x.len - 1))

template checkMinBounds[T](x: SharedDeque[T], i: Natural) =
  # ``-d:release`` should disable this.
  when compileOption("boundChecks"): 
    if unlikely(i < 0): 
      raise newException(IndexDefect, "Out of bounds: " & $i & " < 0")

template checkEmpty[T](x: SharedDeque[T]) =
  # Bounds check for the regular deque access.
  when compileOption("boundChecks"):
    if unlikely(x.len < 1):
      raise newException(IndexDefect, "Empty deque.")

proc `=destroy`*[T](x: var SharedDeque[T]) = 
  if x.data != nil:
    for i in 0..<x.len: 
      `=destroy`(x.data[i])
    deallocShared(x.data)
    x.data = nil

proc `=sink`*[T](dest: var SharedDeque[T], source: SharedDeque[T]) = 
  `=destroy`(dest)
  dest.data = source.data
  dest.head = source.head
  dest.tail = source.tail
  dest.cap = source.cap
  dest.len = source.len
  dest.mask = source.mask

proc `=`*[T](dest: var SharedDeque[T], source: SharedDeque[T]) =
  if dest.data != source.data: 
    `=destroy`(dest)
    dest.head = source.head
    dest.tail = source.tail
    dest.cap = source.cap
    dest.len = source.len
    dest.mask = source.mask
    if source.data != nil:
      let blockLen = sizeof(T) * source.len
      dest.data = cast[ptr UncheckedArray[T]](allocShared0(blockLen))
      copyMem(dest.data, source.data, blockLen)

proc len*[T](x: SharedDeque[T]): Natural {.inline.} =
  ## Return the number of elements of `deq`.
  x.len

proc init*[T](x: var SharedDeque[T], initialSize: Natural = 4) =
  ## Create a new empty deque.
  ##
  ## Optionally, the initial capacity can be reserved via `initialSize`
  ## as a performance optimization.
  ## The length of a newly created deque will still be 0.
  ##
  ## ``initialSize`` must be a power of two (default: 4).
  ## If you need to accept runtime values for this you could use the
  ## `nextPowerOfTwo proc<math.html#nextPowerOfTwo,int>`_ from the
  ## `math module<math.html>`_.
  assert isPowerOfTwo(initialSize)
  x.cap = initialSize
  x.mask = initialSize - 1
  x.data = cast[ptr UncheckedArray[T]](allocShared0(sizeof(T) * initialSize))

proc `[]`*[T](x: SharedDeque[T], i: Natural): lent T {.inline.} =
  ## Access the i-th element of `deq`.
  runnableExamples:
    var a: SharedDeque[int]
    a.init()
    for i in 1 .. 5:
      a.addLast(10*i)
    assert a[0] == 10
    assert a[3] == 40
    doAssertRaises(IndexDefect, echo a[8])

  checkMaxBounds(x, i)
  x.data[(x.head + i) and x.mask]

proc `[]`*[T](x: var SharedDeque[T], i: Natural): var T {.inline.} =
  ## Access the i-th element of `deq` and return a mutable
  ## reference to it.
  runnableExamples:
    var a: SharedDeque[int]
    a.init()
    for i in 1 .. 5:
      a.addLast(10*i)
    assert a[0] == 10
    assert a[3] == 40
    doAssertRaises(IndexDefect, echo a[8])

  checkMaxBounds(x, i)
  x.data[(x.head + i) and x.mask]

proc `[]=`*[T](x: var SharedDeque[T], i: Natural, val: sink T) {.inline.} =
  ## Change the i-th element of `deq`.
  runnableExamples:
    var a: SharedDeque[int]
    a.init()
    for i in 1 .. 5:
      a.addLast(10*i)
    a[0] = 99
    a[3] = 66
    assert $a == "[99, 20, 30, 66, 50]"

  checkMaxBounds(x, i)
  x.data[(x.head + i) and x.mask] = val

proc `[]`*[T](x: SharedDeque[T], i: BackwardsIndex): lent T {.inline.} =
  ## Access the backwards indexed i-th element.
  ##
  ## `deq[^1]` is the last element.
  runnableExamples:
    var a: SharedDeque[int]
    a.init()
    for i in 1 .. 5:
      a.addLast(10*i)
    assert a[^1] == 50
    assert a[^4] == 20
    doAssertRaises(IndexDefect, echo a[^9])

  let j = int(x.len) - int(i)
  checkMinBounds(x, j)
  x[j]

proc `[]`*[T](x: var SharedDeque[T], i: BackwardsIndex): var T {.inline.} =
  ## Access the backwards indexed i-th element.
  ##
  ## `deq[^1]` is the last element.
  runnableExamples:
    var a: SharedDeque[int]
    a.init()
    for i in 1 .. 5:
      a.addLast(10*i)
    assert a[^1] == 50
    assert a[^4] == 20
    doAssertRaises(IndexDefect, echo a[^9])

  let j = int(x.len) - int(i)
  checkMinBounds(x, j)
  x[j]

proc `[]=`*[T](x: var SharedDeque[T], i: BackwardsIndex, val: sink T) {.inline.} =
  ## Change the backwards indexed i-th element.
  ##
  ## `deq[^1]` is the last element.
  runnableExamples:
    var a: SharedDeque[int]
    a.init()
    for i in 1 .. 5:
      a.addLast(10*i)
    a[^1] = 99
    a[^3] = 77
    assert $a == "[10, 20, 77, 40, 99]"

  let j = int(x.len) - int(i)
  checkMinBounds(j)
  x[j] = val

iterator items*[T](x: SharedDeque[T]): lent T =
  ## Yield every element of `deq`.
  ##
  ## **Examples:**
  ##
  ## .. code-block::
  ##   var a: SharedDeque[int]
  ##   for i in 1 .. 3:
  ##     a.addLast(10*i)
  ##
  ##   for x in a:  # the same as: for x in items(a):
  ##     echo x
  ##
  ##   # 10
  ##   # 20
  ##   # 30
  ##
  var i = x.head
  for c in 0..<x.len:
    yield x.data[i]
    i = (i + 1) and x.mask

iterator mitems*[T](x: var SharedDeque[T]): var T =
  ## Yield every element of `deq`, which can be modified.
  runnableExamples:
    var a: SharedDeque[int]
    a.init()
    for i in 1 .. 5:
      a.addLast(10*i)
    assert $a == "[10, 20, 30, 40, 50]"
    for x in mitems(a):
      x = 5*x - 1
    assert $a == "[49, 99, 149, 199, 249]"

  var i = x.head
  for c in 0..<x.len:
    yield x.data[i]
    i = (i + 1) and x.mask

iterator pairs*[T](x: SharedDeque[T]): tuple[key: Natural, val: lent T] =
  ## Yield every (position, value) of `deq`.
  ##
  ## **Examples:**
  ##
  ## .. code-block::
  ##   var a: SharedDeque[int]
  ##   for i in 1 .. 3:
  ##     a.addLast(10*i)
  ##
  ##   for k, v in pairs(a):
  ##     echo "key: ", k, ", value: ", v
  ##
  ##   # key: 0, value: 10
  ##   # key: 1, value: 20
  ##   # key: 2, value: 30
  ##
  var i = x.head
  for c in 0..<x.len:
    yield (c, x.data[i])
    i = (i + 1) and x.mask

iterator mpairs*[T](x: var SharedDeque[T]): tuple[key: Natural, val: var T] =
  ## Yield every (position, value) of `deq`.
  ##
  ## **Examples:**
  ##
  ## .. code-block::
  ##   var a: SharedDeque[int]
  ##   for i in 1 .. 3:
  ##     a.addLast(10*i)
  ##
  ##   for k, v in pairs(a):
  ##     echo "key: ", k, ", value: ", v
  ##
  ##   # key: 0, value: 10
  ##   # key: 1, value: 20
  ##   # key: 2, value: 30
  ##
  var i = x.head
  for c in 0..<x.len:
    yield (c, x.data[i])
    i = (i + 1) and x.mask

proc contains*[T](x: SharedDeque[T], item: T): bool {.inline.} =
  ## Return true if `item` is in `x` or false if not found.
  ##
  ## Usually used via the ``in`` operator.
  ## It is the equivalent of ``x.find(item) >= 0``.
  ##
  ## .. code-block:: Nim
  ##   if a in x:
  ##     assert x.contains(a)
  for e in x: 
    if e == item: return true
  return false

proc expandIfNeeded[T](x: var SharedDeque[T]) =
  if unlikely(x.len >= x.cap):
    assert x.len == x.cap
    x.cap = x.cap shl 1
    var data = cast[ptr UncheckedArray[T]](allocShared0(sizeof(T) * x.cap))
    if x.head == 0:
      copyMem(data, x.data, sizeof(T) * x.len)
    else:
      let firstOffset = sizeof(T) * (x.len - x.head)
      let headOffset = sizeof(T) * x.head
      copyMem(data, x.data.offset(headOffset), firstOffset)
      copyMem(data.offset(firstOffset), x.data, headOffset)

    deallocShared(x.data)
    x.data = data
    x.mask = x.cap - 1
    x.tail = x.len
    x.head = 0

proc addFirst*[T](x: var SharedDeque[T], item: sink T) =
  ## Add an `item` to the beginning of the `deq`.
  ##
  ## See also:
  ## * `addLast proc <#addLast,SharedDeque[T],T>`_
  ## * `peekFirst proc <#peekFirst,SharedDeque[T]>`_
  ## * `peekLast proc <#peekLast,SharedDeque[T]>`_
  ## * `popFirst proc <#popFirst,SharedDeque[T]>`_
  ## * `popLast proc <#popLast,SharedDeque[T]>`_
  runnableExamples:
    var a: SharedDeque[int]
    a.init()
    for i in 1 .. 5:
      a.addFirst(10*i)
    assert $a == "[50, 40, 30, 20, 10]"

  expandIfNeeded(x)
  inc(x.len)
  x.head = (x.head - 1) and x.mask
  x.data[x.head] = item

proc addLast*[T](x: var SharedDeque[T], item: sink T) =
  ## Add an `item` to the end of the `deq`.
  ##
  ## See also:
  ## * `addFirst proc <#addFirst,SharedDeque[T],T>`_
  ## * `peekFirst proc <#peekFirst,SharedDeque[T]>`_
  ## * `peekLast proc <#peekLast,SharedDeque[T]>`_
  ## * `popFirst proc <#popFirst,SharedDeque[T]>`_
  ## * `popLast proc <#popLast,SharedDeque[T]>`_
  runnableExamples:
    var a: SharedDeque[int]
    a.init()
    for i in 1 .. 5:
      a.addLast(10*i)
    assert $a == "[10, 20, 30, 40, 50]"

  expandIfNeeded(x)
  inc(x.len)
  x.data[x.tail] = item
  x.tail = (x.tail + 1) and x.mask

proc peekFirst*[T](x: SharedDeque[T]): lent T {.inline.} =
  ## Returns the first element of `deq`, but does not remove it from the deque.
  ##
  ## See also:
  ## * `addFirst proc <#addFirst,SharedDeque[T],T>`_
  ## * `addLast proc <#addLast,SharedDeque[T],T>`_
  ## * `peekLast proc <#peekLast,SharedDeque[T]>`_
  ## * `popFirst proc <#popFirst,SharedDeque[T]>`_
  ## * `popLast proc <#popLast,SharedDeque[T]>`_
  runnableExamples:
    var a: SharedDeque[int]
    a.init()
    for i in 1 .. 5:
      a.addLast(10*i)
    assert $a == "[10, 20, 30, 40, 50]"
    assert a.peekFirst == 10
    assert len(a) == 5

  checkEmpty(x)
  result = x.data[x.head]

proc peekFirst*[T](x: var SharedDeque[T]): var T {.inline.} =
  ## Returns the first element of `deq`, but does not remove it from the deque.
  ##
  ## See also:
  ## * `addFirst proc <#addFirst,SharedDeque[T],T>`_
  ## * `addLast proc <#addLast,SharedDeque[T],T>`_
  ## * `peekLast proc <#peekLast,SharedDeque[T]>`_
  ## * `popFirst proc <#popFirst,SharedDeque[T]>`_
  ## * `popLast proc <#popLast,SharedDeque[T]>`_
  runnableExamples:
    var a: SharedDeque[int]
    a.init()
    for i in 1 .. 5:
      a.addLast(10*i)
    assert $a == "[10, 20, 30, 40, 50]"
    assert a.peekFirst == 10
    assert len(a) == 5

  checkEmpty(x)
  result = x.data[x.head]

proc peekLast*[T](x: SharedDeque[T]): lent T {.inline.} =
  ## Returns the last element of `deq`, but does not remove it from the deque.
  ##
  ## See also:
  ## * `addFirst proc <#addFirst,SharedDeque[T],T>`_
  ## * `addLast proc <#addLast,SharedDeque[T],T>`_
  ## * `peekFirst proc <#peekFirst,SharedDeque[T]>`_
  ## * `popFirst proc <#popFirst,SharedDeque[T]>`_
  ## * `popLast proc <#popLast,SharedDeque[T]>`_
  runnableExamples:
    var a: SharedDeque[int]
    a.init()
    for i in 1 .. 5:
      a.addLast(10*i)
    assert $a == "[10, 20, 30, 40, 50]"
    assert a.peekLast == 50
    assert len(a) == 5

  checkEmpty(x)
  result = x.data[(x.tail - 1) and x.mask]

proc peekLast*[T](x: var SharedDeque[T]): var T {.inline.} =
  ## Returns the last element of `deq`, but does not remove it from the deque.
  ##
  ## See also:
  ## * `addFirst proc <#addFirst,SharedDeque[T],T>`_
  ## * `addLast proc <#addLast,SharedDeque[T],T>`_
  ## * `peekFirst proc <#peekFirst,SharedDeque[T]>`_
  ## * `popFirst proc <#popFirst,SharedDeque[T]>`_
  ## * `popLast proc <#popLast,SharedDeque[T]>`_
  runnableExamples:
    var a: SharedDeque[int]
    a.init()
    for i in 1 .. 5:
      a.addLast(10*i)
    assert $a == "[10, 20, 30, 40, 50]"
    assert a.peekLast == 50
    assert len(a) == 5

  checkEmpty(x)
  result = x.data[(x.tail - 1) and x.mask]

proc popFirst*[T](x: var SharedDeque[T]): T {.inline, discardable.} =
  ## Remove and returns the first element of the `deq`.
  ##
  ## See also:
  ## * `addFirst proc <#addFirst,SharedDeque[T],T>`_
  ## * `addLast proc <#addLast,SharedDeque[T],T>`_
  ## * `peekFirst proc <#peekFirst,SharedDeque[T]>`_
  ## * `peekLast proc <#peekLast,SharedDeque[T]>`_
  ## * `popLast proc <#popLast,SharedDeque[T]>`_
  ## * `clear proc <#clear,SharedDeque[T]>`_
  ## * `shrink proc <#shrink,SharedDeque[T],int,int>`_
  runnableExamples:
    var a: SharedDeque[int]
    a.init()
    for i in 1 .. 5:
      a.addLast(10*i)
    assert $a == "[10, 20, 30, 40, 50]"
    assert a.popFirst == 10
    assert $a == "[20, 30, 40, 50]"

  checkEmpty(x)
  dec(x.len)
  result = x.data[x.head]
  reset(x.data[x.head])
  x.head = (x.head + 1) and x.mask

proc popLast*[T](x: var SharedDeque[T]): T {.inline, discardable.} =
  ## Remove and returns the last element of the `deq`.
  ##
  ## See also:
  ## * `addFirst proc <#addFirst,SharedDeque[T],T>`_
  ## * `addLast proc <#addLast,SharedDeque[T],T>`_
  ## * `peekFirst proc <#peekFirst,SharedDeque[T]>`_
  ## * `peekLast proc <#peekLast,SharedDeque[T]>`_
  ## * `popFirst proc <#popFirst,SharedDeque[T]>`_
  ## * `clear proc <#clear,SharedDeque[T]>`_
  ## * `shrink proc <#shrink,SharedDeque[T],int,int>`_
  runnableExamples:
    var a: SharedDeque[int]
    a.init()
    for i in 1 .. 5:
      a.addLast(10*i)
    assert $a == "[10, 20, 30, 40, 50]"
    assert a.popLast == 50
    assert $a == "[10, 20, 30, 40]"

  checkEmpty(deq)
  dec(x.len)
  x.tail = (x.tail - 1) and x.mask
  result = x.data[x.tail]
  reset(x.data[x.tail])

proc delFirst*[T](x: var SharedDeque[T]) {.inline.} =
  ## Remove the first element of the `deq`.
  ##
  ## See also:
  ## * `addFirst proc <#addFirst,SharedDeque[T],T>`_
  ## * `addLast proc <#addLast,SharedDeque[T],T>`_
  ## * `peekFirst proc <#peekFirst,SharedDeque[T]>`_
  ## * `peekLast proc <#peekLast,SharedDeque[T]>`_
  ## * `popLast proc <#popLast,SharedDeque[T]>`_
  ## * `clear proc <#clear,SharedDeque[T]>`_
  ## * `shrink proc <#shrink,SharedDeque[T],int,int>`_
  runnableExamples:
    var a: SharedDeque[int]
    a.init()
    for i in 1 .. 5:
      a.addLast(10*i)
    assert $a == "[10, 20, 30, 40, 50]"
    assert a.popFirst == 10
    assert $a == "[20, 30, 40, 50]"

  checkEmpty(x)
  dec(x.len)
  `=destroy`(x.data[x.head])
  reset(x.data[x.head])
  x.head = (x.head + 1) and x.mask

proc delLast*[T](x: var SharedDeque[T]) {.inline.} =
  ## Remove the last element of the `deq`.
  ##
  ## See also:
  ## * `addFirst proc <#addFirst,SharedDeque[T],T>`_
  ## * `addLast proc <#addLast,SharedDeque[T],T>`_
  ## * `peekFirst proc <#peekFirst,SharedDeque[T]>`_
  ## * `peekLast proc <#peekLast,SharedDeque[T]>`_
  ## * `popFirst proc <#popFirst,SharedDeque[T]>`_
  ## * `clear proc <#clear,SharedDeque[T]>`_
  ## * `shrink proc <#shrink,SharedDeque[T],int,int>`_
  runnableExamples:
    var a: SharedDeque[int]
    a.init()
    for i in 1 .. 5:
      a.addLast(10*i)
    assert $a == "[10, 20, 30, 40, 50]"
    assert a.popLast == 50
    assert $a == "[10, 20, 30, 40]"

  checkEmpty(deq)
  dec(x.len)
  x.tail = (x.tail - 1) and x.mask
  `=destroy`(x.data[x.tail])
  reset(x.data[x.tail])

proc clear*[T](x: var SharedDeque[T]) {.inline.} =
  ## Resets the deque so that it is empty.
  ##
  ## See also:
  ## * `clear proc <#clear,SharedDeque[T]>`_
  ## * `shrink proc <#shrink,SharedDeque[T],int,int>`_
  runnableExamples:
    var a: SharedDeque[int]
    a.init()
    for i in 1 .. 5:
      a.addFirst(10*i)
    assert $a == "[50, 40, 30, 20, 10]"
    clear(a)
    assert len(a) == 0

  for el in x.mitems(): 
    `=destroy`(el)
    reset(el)
  x.len = 0
  x.tail = x.head

proc shrink*[T](x: var SharedDeque[T], fromFirst = 0, fromLast = 0) =
  ## Remove `fromFirst` elements from the front of the deque and
  ## `fromLast` elements from the back.
  ##
  ## If the supplied number of elements exceeds the total number of elements
  ## in the deque, the deque will remain empty.
  ##
  ## See also:
  ## * `clear proc <#clear,SharedDeque[T]>`_
  runnableExamples:
    var a: SharedDeque[int]
    a.init()
    for i in 1 .. 5:
      a.addFirst(10*i)
    assert $a == "[50, 40, 30, 20, 10]"
    a.shrink(fromFirst = 2, fromLast = 1)
    assert $a == "[30, 20]"

  let n = fromFirst + fromLast

  if n > x.len:
    x.clear()
  else:
    for i in 0..<fromFirst:
      `=destroy`(x.data[x.head])
      reset(x.data[x.head])
      x.head = (x.head + 1) and x.mask

    for i in 0..<fromLast:
      `=destroy`(x.data[x.tail])
      reset(x.data[x.tail])
      x.tail = (x.tail - 1) and x.mask

    dec(x.len, n)

proc `$`*[T](x: SharedDeque[T]): string =
  ## Turn a deque into its string representation.
  result = "["
  for el in x: 
    if result.len > 1: 
      result.add(", ")
    result.addQuoted(el)
  result.add("]")

when isMainModule:
  var deq: SharedDeque[int]
  deq.init(1)
  deq.addFirst(4)
  deq.addFirst(9)
  deq.addFirst(123)

  var first = deq.popFirst()
  deq.addLast(56)
  assert(deq.peekLast() == 56)
  deq.addLast(6)
  assert(deq.peekLast() == 6)
  var second = deq.popFirst()
  deq.addLast(789)
  assert(deq.peekLast() == 789)

  assert first == 123
  assert second == 9
  assert($deq == "[4, 56, 6, 789]")

  assert deq[0] == deq.peekFirst and deq.peekFirst == 4
  assert deq[^1] == deq.peekLast and deq.peekLast == 789
  deq[0] = 42
  deq[deq.len - 1] = 7

  assert 6 in deq and 789 notin deq
  assert deq.find(6) >= 0
  assert deq.find(789) < 0

  block:
    var d: SharedDeque[int]
    d.init(1)
    d.addLast 7
    d.addLast 8
    d.addLast 10
    d.addFirst 5
    d.addFirst 2
    d.addFirst 1
    d.addLast 20
    d.shrink(fromLast = 2)
    doAssert($d == "[1, 2, 5, 7, 8]")
    d.shrink(2, 1)
    doAssert($d == "[5, 7]")
    d.shrink(2, 2)
    doAssert d.len == 0

  for i in -2 .. 10:
    if i in deq: 
      assert deq.contains(i) and deq.find(i) >= 0
    else:
      assert(not deq.contains(i) and deq.find(i) < 0)

  when compileOption("boundChecks"):
    try:
      echo deq[99]
      assert false
    except IndexDefect:
      discard

    try:
      assert deq.len == 4
      for i in 0 ..< 5: 
        deq.popFirst()
      assert false
    except IndexDefect:
      discard

  # grabs some types of resize error.
  deq = SharedDeque[int]()
  deq.init()
  for i in 1 .. 4: deq.addLast(i)
  deq.popFirst()
  deq.popLast()
  for i in 5 .. 8: deq.addFirst(i)
  assert $deq == "[8, 7, 6, 5, 2, 3]"

  # Similar to proc from the documentation example
  proc foo(a, b: Positive) = # assume random positive values for `a` and `b`.
    var deq: SharedDeque[int]
    deq.init()
    assert deq.len == 0
    for i in 1..a: 
      deq.addLast(i)

    if b < deq.len: 
      assert deq[b] == b + 1

    assert deq.peekFirst == 1
    assert deq.peekLast == a

    while deq.len > 0: 
      assert deq.popFirst() > 0

  foo(8, 5)
  foo(10, 9)
  foo(1, 1)
  foo(2, 1)
  foo(1, 5)
  foo(3, 2)

  # Stdlib Error: lib/system/syslocks.nim(177, 7) Error: cannot 'importc' variable at compile time; acquireSysAux
  # 
  # import sets
  # block t13310:
  #   proc main() =
  #     var q: SharedDeque[HashSet[int16]]
  #     q.init(2)
  #     q.addFirst([1'i16].toHashSet)
  #     q.addFirst([2'i16].toHashSet)
  #     q.addFirst([3'i16].toHashSet)
  #     assert $q == "[{3}, {2}, {1}]"

  #   static:
  #     main()


