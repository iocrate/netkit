type
  SimpleNode*[T] = object
    next: ref SimpleNode[T]
    value*: T

  SimpleQueue*[T] = object
    head*: ref SimpleNode[T]
    tail*: ref SimpleNode[T]

proc add*[T](Q: var SimpleQueue[T], node: ref SimpleNode[T]) {.raises: [ValueError].} = 
  if node.next != nil:
    raise newException(ValueError, "node already in a list")
  if Q.tail == nil:
    assert Q.head == nil
    Q.head = node
    Q.tail = node
  else:
    if Q.tail == node:
      raise newException(ValueError, "node already in a list")
    Q.tail.next = node
    Q.tail = node

proc add*[T](Q: var SimpleQueue[T], value: T) = 
  var node = new(SimpleNode[T])
  node.value = value
  if Q.tail == nil:
    assert Q.head == nil
    Q.head = node
    Q.tail = node
  else:
    Q.tail.next = node
    Q.tail = node

proc pop*[T](Q: var SimpleQueue[T]): ref SimpleNode[T] = 
  result = Q.head
  if Q.head != nil:
    if result.next == nil:
      Q.head = nil
      Q.tail = nil
    else:
      Q.head = result.next
      result.next = nil

proc peek*[T](Q: var SimpleQueue[T]): ref SimpleNode[T] = 
  result = Q.head

iterator nodes*[T](Q: var SimpleQueue): ref SimpleNode[T] = 
  var node {.cursor.} = Q.head
  while node != nil:
    var next {.cursor.} = node.next
    yield node
    node = next

iterator values*[T](Q: var SimpleQueue): ref T = 
  var node {.cursor.} = Q.head
  while node != nil:
    var next {.cursor.} = node.next
    yield node.value
    node = next


