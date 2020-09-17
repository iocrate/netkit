type
  SimpleNode* = object of RootObj
    next: ref SimpleNode

  SimpleQueue* = object
    head*: ref SimpleNode
    tail*: ref SimpleNode

proc add*(Q: var SimpleQueue, node: ref SimpleNode) {.raises: [ValueError].} = 
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

proc pop*(Q: var SimpleQueue): ref SimpleNode = 
  result = Q.head
  if Q.head != nil:
    if result.next == nil:
      Q.head = nil
      Q.tail = nil
    else:
      Q.head = result.next
      result.next = nil

proc peek*(Q: var SimpleQueue): ref SimpleNode = 
  result = Q.head

iterator nodes*(Q: var SimpleQueue): ref SimpleNode = 
  var node {.cursor.} = Q.head
  while node != nil:
    var next {.cursor.} = node.next
    yield node
    node = next


