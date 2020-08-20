
type
  SimpleNode*[T] = object
    next: ref SimpleNode[T]
    val*: T

  SimpleQueue*[T] = object
    head: ref SimpleNode[T]
    tail: ref SimpleNode[T]
    len: Natural

proc newSimpleNode*[T](): ref SimpleNode[T] =
  new(result)

proc newSimpleNode*[T](val: sink T): ref SimpleNode[T] =
  new(result)
  result.val = val

proc initSimpleQueue*[T](): SimpleQueue[T] = 
  discard

proc len*[T](Q: SimpleQueue[T]): Natural {.inline.} = 
  Q.len

proc addLast*[T](Q: var SimpleQueue[T], node: ref SimpleNode[T]) = 
  # result = case[ref SimpleNode[T]](alloc0(sizeof(SimpleNode[T])))
  assert node != nil
  assert node.next == nil
  if Q.tail == nil:
    Q.head = node
  else:
    Q.tail.next = node
  Q.tail = node
  Q.len.inc()

proc popFirst*[T](Q: var SimpleQueue[T]): ref SimpleNode[T] = 
  if Q.head != nil:
    result = Q.head
    Q.head = Q.head.next
    result.next = nil
    Q.len.dec()

proc peekFirst*[T](Q: var SimpleQueue[T]): ref SimpleNode[T] {.inline.} = 
  Q.head

iterator nodes*[T](Q: var SimpleQueue[T]): ref SimpleNode[T] = 
  var node = Q.head
  while node != nil:
    yield node
    node = node.next

iterator nodesByPop*[T](Q: var SimpleQueue[T]): ref SimpleNode[T] = 
  while Q.head != nil:
    let node = Q.head
    let next = node.next
    node.next = nil
    Q.head = next
    Q.len.dec()
    yield node
