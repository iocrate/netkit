type
  SimpleNode*[T] = object
    next: ref SimpleNode[T]
    prev: ref SimpleNode[T]
    value*: T

  SimpleQueue*[T] = object
    head: ref SimpleNode[T]
    len: Natural

proc newSimpleNode*[T](): ref SimpleNode[T] =
  new(result)
  result.next = result
  result.prev = result

proc newSimpleNode*[T](value: sink T): ref SimpleNode[T] =
  new(result)
  result.next = result
  result.prev = result
  result.value = value

proc initSimpleQueue*[T](): SimpleQueue[T] = 
  result.head = newSimpleNode[T]()

proc len*[T](Q: SimpleQueue[T]): Natural {.inline.} = 
  Q.len

proc addLast*[T](Q: var SimpleQueue[T], node: ref SimpleNode[T]) = 
  node.next = Q.head
  node.prev = Q.head.prev
  Q.head.prev.next = node
  Q.head.prev = node
  Q.len.inc()

proc addFirst*[T](Q: var SimpleQueue[T], node: ref SimpleNode[T]) = 
  node.next = Q.head.next
  node.prev = Q.head
  Q.head.next.prev = node
  Q.head.next = node
  Q.len.inc()

proc popLast*[T](Q: var SimpleQueue[T]): ref SimpleNode[T] = 
  if Q.len > 0:
    result = Q.head.prev
    Q.head.prev = result.prev
    result.prev.next = Q.head
    result.next = result
    result.prev = result
    Q.len.dec()

proc popFirst*[T](Q: var SimpleQueue[T]): ref SimpleNode[T] = 
  if Q.len > 0:
    result = Q.head.next
    Q.head.next = result.next
    result.next.prev = Q.head
    result.next = result
    result.prev = result
    Q.len.dec()

proc peekLast*[T](Q: var SimpleQueue[T]): ref SimpleNode[T] = 
  if Q.len > 0:
    Q.head.prev

proc peekFirst*[T](Q: var SimpleQueue[T]): ref SimpleNode[T] = 
  if Q.len > 0:
    Q.head.next

proc remove*[T](Q: var SimpleQueue[T], node: ref SimpleNode[T]) = 
  node.next.prev = node.prev
  node.prev.next = node.next
  node.next = node
  node.prev = node
  Q.len.dec()

iterator nodes*[T](Q: var SimpleQueue[T]): ref SimpleNode[T] = 
  var node = Q.head.next
  var next: ref SimpleNode[T]
  while node != Q.head:
    next = node.next
    yield node
    node = next

iterator nodesReverse*[T](Q: var SimpleQueue[T]): ref SimpleNode[T] = 
  var node = Q.head.prev
  var prev: ref SimpleNode[T]
  while node != Q.head:
    prev = node.prev
    yield node
    node = prev
