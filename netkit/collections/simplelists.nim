type
  SimpleNode* = object of RootObj
    next: ref SimpleNode
    prev: ref SimpleNode

  SimpleList* = object
    head: ref SimpleNode

proc initSimpleNode*(node: ref SimpleNode) =
  node.next = node
  node.prev = node

proc initSimpleList*(L: var SimpleList) = 
  L.head = new(SimpleNode)
  L.head.initSimpleNode()

proc addLast*(L: var SimpleList, node: ref SimpleNode) = 
  node.next = L.head
  node.prev = L.head.prev
  L.head.prev.next = node
  L.head.prev = node

proc addFirst*(L: var SimpleList, node: ref SimpleNode) = 
  node.next = L.head.next
  node.prev = L.head
  L.head.next.prev = node
  L.head.next = node

proc popLast*(L: var SimpleList): ref SimpleNode = 
  if L.head.prev != L.head:
    result = L.head.prev
    L.head.prev = result.prev
    result.prev.next = L.head
    result.next = result
    result.prev = result

proc popFirst*(L: var SimpleList): ref SimpleNode = 
  if L.head.next != L.head:
    result = L.head.next
    L.head.next = result.next
    result.next.prev = L.head
    result.next = result
    result.prev = result

proc peekLast*(L: var SimpleList): ref SimpleNode = 
  if L.head.prev != L.head:
    result = L.head.prev

proc peekFirst*(L: var SimpleList): ref SimpleNode = 
  if L.head.next != L.head:
    result = L.head.next

proc remove*(L: var SimpleList, node: ref SimpleNode) = 
  node.next.prev = node.prev
  node.prev.next = node.next
  node.next = node
  node.prev = node

iterator nodes*(L: var SimpleList): ref SimpleNode = 
  var node = L.head.next
  var next: ref SimpleNode
  while node != L.head:
    next = node.next
    yield node
    node = next

iterator nodesBackwards*(L: var SimpleList): ref SimpleNode = 
  var node = L.head.prev
  var prev: ref SimpleNode
  while node != L.head:
    prev = node.prev
    yield node
    node = prev
