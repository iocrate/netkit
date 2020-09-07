type
  SimpleNode* = object of RootObj
    next: ref SimpleNode
    prev: ref SimpleNode

  SimpleList* = object
    head: ref SimpleNode

proc initSimpleNode*(node: ref SimpleNode) =
  node.next = node
  node.prev = node

proc initSimpleList*(): SimpleList = 
  result.head = new(SimpleNode)
  result.head.initSimpleNode()

proc addLast*(Q: var SimpleList, node: ref SimpleNode) = 
  node.next = Q.head
  node.prev = Q.head.prev
  Q.head.prev.next = node
  Q.head.prev = node

proc addFirst*(Q: var SimpleList, node: ref SimpleNode) = 
  node.next = Q.head.next
  node.prev = Q.head
  Q.head.next.prev = node
  Q.head.next = node

proc popLast*(Q: var SimpleList): ref SimpleNode = 
  if Q.head.prev != Q.head:
    result = Q.head.prev
    Q.head.prev = result.prev
    result.prev.next = Q.head
    result.next = result
    result.prev = result

proc popFirst*(Q: var SimpleList): ref SimpleNode = 
  if Q.head.next != Q.head:
    result = Q.head.next
    Q.head.next = result.next
    result.next.prev = Q.head
    result.next = result
    result.prev = result

proc peekLast*(Q: var SimpleList): ref SimpleNode = 
  if Q.head.prev != Q.head:
    result = Q.head.prev

proc peekFirst*(Q: var SimpleList): ref SimpleNode = 
  if Q.head.next != Q.head:
    result = Q.head.next

proc remove*(Q: var SimpleList, node: ref SimpleNode) = 
  node.next.prev = node.prev
  node.prev.next = node.next
  node.next = node
  node.prev = node

iterator nodes*(Q: var SimpleList): ref SimpleNode = 
  var node = Q.head.next
  var next: ref SimpleNode
  while node != Q.head:
    next = node.next
    yield node
    node = next

iterator nodesBackwards*(Q: var SimpleList): ref SimpleNode = 
  var node = Q.head.prev
  var prev: ref SimpleNode
  while node != Q.head:
    prev = node.prev
    yield node
    node = prev
