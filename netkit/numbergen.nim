
import netkit/collections/deques
import netkit/allocmode

type
  NaturalGenerator* = object
    curr: Natural
    reclaims: Deque[Natural]

proc `=destroy`*(x: var NaturalGenerator) =
  `=destroy`(x.reclaims)

proc initNaturalGenerator*(x: var NaturalGenerator, initialSize: Natural = 4, mode = AllocMode.THREAD_LOCAL) =
  x.reclaims.initDeque(initialSize, mode)

proc acquire*(x: var NaturalGenerator): Natural =
  if x.reclaims.len > 0:
    result = Natural(x.reclaims.popFirst())
  else:
    result = Natural(x.curr)
    inc(x.curr)

proc release*(x: var NaturalGenerator, id: Natural) =
  when compileOption("boundChecks"): 
    if unlikely(x.curr <= Natural(id)): 
      raise newException(RangeDefect, "value out of range: " & $Natural(id) & " notin 0 .. " & $(x.curr - 1))
  x.reclaims.addLast(Natural(id))

when isMainModule:
  proc tBase = 
    var ng: NaturalGenerator
    ng.initNaturalGenerator()
    for i in 0..<10:
      discard ng.acquire()

    doAssert (ng.acquire() == Natural(10))

    for i in 0..<5:
      ng.release(Natural(i))
    
    doAssert ng.acquire() == Natural(0) 
    doAssert ng.acquire() == Natural(1)  
    doAssert ng.acquire() == Natural(2)  
    doAssert ng.acquire() == Natural(3)  
    doAssert ng.acquire() == Natural(4)  
    doAssert ng.acquire() == Natural(11)  
    doAssert ng.acquire() == Natural(12) 

  proc tCloseBound = 
    var ng: NaturalGenerator
    ng.initNaturalGenerator()
    discard ng.acquire()
    when compileOption("boundChecks"):
      try:
        ng.release(Natural(100))
        assert false
      except RangeDefect:
        discard

  tBase()
  tCloseBound()