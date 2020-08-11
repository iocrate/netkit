
type
  SimpleNode*[T] = object
    next: ptr SimpleNode[T]
    val*: T

  SimpleQueue*[T] = object
    head: ptr SimpleNode[T]
    tail: ptr SimpleNode[T]
    len: Natural

proc createSimpleNode*[T](): ptr SimpleNode[T] =
  cast[ptr SimpleNode[T]](alloc0(sizeof(SimpleNode[T])))

proc createSimpleNode*[T](val: sink T): ptr SimpleNode[T] =
  result = cast[ptr SimpleNode[T]](alloc0(sizeof(SimpleNode[T])))
  result.val = val

proc destroy*[T](node: ptr SimpleNode[T]) {.inline.} =
  dealloc(node)

proc initSimpleQueue*[T](): SimpleQueue[T] = 
  discard

proc len*[T](Q: SimpleQueue[T]): Natural {.inline.} = 
  Q.len

proc addLast*[T](Q: var SimpleQueue[T], node: ptr SimpleNode[T]) = 
  # result = case[ptr SimpleNode[T]](alloc0(sizeof(SimpleNode[T])))
  assert node != nil
  assert node.next == nil
  if Q.tail == nil:
    Q.head = node
  else:
    Q.tail.next = node
  Q.tail = node
  Q.len.inc()

proc popFirst*[T](Q: var SimpleQueue[T]): ptr SimpleNode[T] = 
  if Q.head != nil:
    result = Q.head
    Q.head = Q.head.next
    result.next = nil
    Q.len.dec()

proc peekFirst*[T](Q: var SimpleQueue[T]): ptr SimpleNode[T] {.inline.} = 
  Q.head

iterator nodes*[T](Q: var SimpleQueue[T]): ptr SimpleNode[T] = 
  var node = Q.head
  while node != nil:
    yield node
    node = node.next

iterator nodesByPop*[T](Q: var SimpleQueue[T]): ptr SimpleNode[T] = 
  while Q.head != nil:
    let node = Q.head
    let next = node.next
    node.next = nil
    Q.head = next
    Q.len.dec()
    yield node
