
import netkit/collections/deques
import netkit/allocmode

type
  IdGenerator* = object
    curr: Natural
    buckets: Deque[Natural]

proc `=destroy`*(G: var IdGenerator) =
  `=destroy`(G.buckets)

proc initIdGenerator*(G: var IdGenerator, initialSize: Natural = 4, mode = AllocMode.THREAD_LOCAL) =
  G.buckets.initDeque(initialSize, mode)

proc acquire*(G: var IdGenerator): Natural =
  if G.buckets.len > 0:
    result = G.buckets.popFirst()
  else:
    result = G.curr
    inc(G.curr)

proc release*(G: var IdGenerator, id: Natural) =
  when compileOption("boundChecks"): 
    if unlikely(G.curr <= id): 
      raise newException(RangeDefect, "value out of range: " & $id & " notin 0 .. " & $(G.curr - 1))
  G.buckets.addLast(id)

when isMainModule:
  proc testBase() = 
    var idgen: IdGenerator
    idgen.initIdGenerator()
    for i in 0..<10:
      discard idgen.acquire()

    doAssert (idgen.acquire() == Natural(10))

    for i in 0..<5:
      idgen.release(Natural(i))
    
    doAssert idgen.acquire() == Natural(0) 
    doAssert idgen.acquire() == Natural(1)  
    doAssert idgen.acquire() == Natural(2)  
    doAssert idgen.acquire() == Natural(3)  
    doAssert idgen.acquire() == Natural(4)  
    doAssert idgen.acquire() == Natural(11)  
    doAssert idgen.acquire() == Natural(12) 

  proc testReleaseBound() = 
    var idgen: IdGenerator
    idgen.initIdGenerator()
    discard idgen.acquire()
    when compileOption("boundChecks"):
      try:
        idgen.release(Natural(100))
        assert false
      except RangeDefect:
        discard

  testBase()
  testReleaseBound()