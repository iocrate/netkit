type
  SimpleNode* = object of RootObj
    next: ref SimpleNode
    prev: ref SimpleNode

  SimpleList* = object
    head: ref SimpleNode

proc initSimpleNode*(node: ref SimpleNode) =
  var n {.cursor.} = node
  node.next = n
  node.prev = n

proc initSimpleList*(L: var SimpleList) = 
  L.head = new(SimpleNode)
  L.head.initSimpleNode()

proc addLast*(L: var SimpleList, node: ref SimpleNode) = 
  assert node.next == node
  assert node.prev == node
  node.next = L.head
  node.prev = L.head.prev
  L.head.prev.next = node
  L.head.prev = node

proc addFirst*(L: var SimpleList, node: ref SimpleNode) = 
  assert node.next == node
  assert node.prev == node
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
  let n {.cursor.} = node
  node.next = n
  node.prev = n

iterator nodes*(L: var SimpleList): ref SimpleNode = 
  var node {.cursor.} = L.head
  while node.next != L.head:
    yield node.next
    node = node.next

iterator nodesBackwards*(L: var SimpleList): ref SimpleNode = 
  var node {.cursor.} = L.head
  while node.prev != L.head:
    yield node.prev
    node = node.prev

