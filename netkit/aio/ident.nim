
import netkit/collections/share/deques

type
  Identity* = distinct Natural

  IdentityManager* = object
    curr: Natural
    reclaimed: SharedDeque[Natural]

proc `==`*(a: Identity, b: Identity): bool {.borrow.}

proc `=destroy`*(x: var IdentityManager) =
  `=destroy`(x.reclaimed)

proc init*(x: var IdentityManager) =
  x.reclaimed.init()

proc acquire*(x: var IdentityManager): Identity =
  if x.reclaimed.len > 0:
    result = Identity(x.reclaimed.popFirst())
  else:
    result = Identity(x.curr)
    inc(x.curr)

proc release*(x: var IdentityManager, id: Identity) =
  when compileOption("boundChecks"): 
    if unlikely(x.curr <= Natural(id)): 
      raise newException(RangeDefect, "value out of range: " & $Natural(id) & " notin 0 .. " & $(x.curr - 1))
  x.reclaimed.addLast(Natural(id))

when isMainModule:
  proc tBase = 
    var im: IdentityManager
    im.init()
    for i in 0..<10:
      discard im.acquire()

    doAssert (im.acquire() == Identity(10))

    for i in 0..<5:
      im.release(Identity(i))
    
    doAssert im.acquire() == Identity(0) 
    doAssert im.acquire() == Identity(1)  
    doAssert im.acquire() == Identity(2)  
    doAssert im.acquire() == Identity(3)  
    doAssert im.acquire() == Identity(4)  
    doAssert im.acquire() == Identity(11)  
    doAssert im.acquire() == Identity(12) 

  proc tCloseBound = 
    var im: IdentityManager
    im.init()
    discard im.acquire()
    when compileOption("boundChecks"):
      try:
        im.release(Identity(100))
        assert false
      except RangeDefect:
        discard

  tBase()
  tCloseBound()