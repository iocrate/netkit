
import std/os
import std/posix
import netkit/posix/linux/selector
import netkit/options
import netkit/collections/simplequeue
import netkit/collections/vecs
import netkit/aio/error
import netkit/numbergen

const
  MaxReactiveEventCount* {.intdefine.} = 1024

type
  ActionBase* = object of RootObj
    # future: ref Future
    run*: ActionProc

  Action*[T] = object of ActionBase
    value*: T

  ActionProc* = proc (action: ref ActionBase): bool {.nimcall, gcsafe.}

  Reactor* = object
    selector: Selector
    interests: InterestVec
    state: ReactorState

  ReactorState* {.pure.} = enum
    CREATING, RUNNING, SHUTDOWN, CLOSED

  InterestVec = object
    data: Vec[Option[InterestData]]
    len: Natural
    idGenerator: NaturalGenerator
    
  InterestData = object
    fd: cint
    interest: Interest
    readQueue: SimpleQueue[ref ActionBase]
    writeQueue: SimpleQueue[ref ActionBase]

proc open*(r: var Reactor, initialSize: int) = 
  r.selector = initSelector()
  r.interests.data.initVec(initialSize, VecKind.THREAD_LOCAL)
  r.interests.idGenerator.initNaturalGenerator(initialSize)
  r.state = ReactorState.CREATING

proc register*(r: var Reactor, fd: cint): Natural =
  # if r.state == ReactorState.SHUTDOWN:
  #   raise newException(IllegalStateError, "reactor already shutdown")
  # if r.state == ReactorState.CLOSED:
  #   raise newException(IllegalStateError, "reactor already closed")  
  let interest = initInterest()
  result = r.interests.idGenerator.acquire()
  r.selector.register(fd, UserData(u64: result.uint64), interest)
  if r.interests.data.cap <= result:
    r.interests.data.resize(r.interests.data.cap * 2)
    assert r.interests.data.cap > result
  let data = r.interests.data[result].addr
  data.value.fd = fd
  data.value.interest = interest
  data.value.readQueue = initSimpleQueue[ref ActionBase]()
  data.value.writeQueue = initSimpleQueue[ref ActionBase]()
  data.has = true
  r.interests.len.inc()

proc unregister*(r: var Reactor, id: Natural) =
  let data = r.interests.data[id].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  r.selector.unregister(data.value.fd)
  r.interests.idGenerator.release(id)
  r.interests.len.dec()
  reset(data[]) 

iterator idItems*(r: var Reactor): Natural =
  for i, data in r.interests.data.mpairs():
    if data.has:
      yield Natural(i)

proc unregisterReadable*(r: var Reactor, id: Natural) =
  let data = r.interests.data[id].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  if data.value.interest.isReadable():
    data.value.interest.unregisterReadable()
    r.selector.update(data.value.fd, UserData(u64: id.uint64), data.value.interest)

proc unregisterWritable*(r: var Reactor, id: Natural) =
  let data = r.interests.data[id].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  if data.value.interest.isWritable():
    data.value.interest.unregisterWritable()
    r.selector.update(data.value.fd, UserData(u64: id.uint64), data.value.interest)

proc updateRead*(r: var Reactor, id: Natural, action: ref ActionBase) =
  let data = r.interests.data[id].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  data.value.readQueue.addLast(newSimpleNode[ref ActionBase](action))
  if not data.value.interest.isReadable():
    data.value.interest.registerReadable()
    r.selector.update(data.value.fd, UserData(u64: id.uint64), data.value.interest)

proc updateWrite*(r: var Reactor, id: Natural, action: ref ActionBase) =
  let data = r.interests.data[id].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  data.value.writeQueue.addLast(newSimpleNode[ref ActionBase](action))
  if not data.value.interest.isWritable():
    data.value.interest.registerWritable()
    r.selector.update(data.value.fd, UserData(u64: id.uint64), data.value.interest)

proc shutdown*(r: var Reactor) = 
  if r.state == ReactorState.SHUTDOWN:
    raise newException(IllegalStateError, "reactor already shutdown")
  if r.state == ReactorState.CLOSED:
    raise newException(IllegalStateError, "reactor already closed")
  r.state = ReactorState.SHUTDOWN

proc runBlocking*(r: var Reactor, timeout: cint) =
  template handleEvent(queue: SimpleQueue[ref ActionBase]) =
    for node in queue.nodes():
      if node.value.run(node.value):
        queue.remove(node)
      else:
        break
  
  if r.state == ReactorState.CREATING:
    r.state = ReactorState.RUNNING
  else:
    case r.state 
    of ReactorState.RUNNING:
      raise newException(IllegalStateError, "reactor already running")
    of ReactorState.SHUTDOWN:
      raise newException(IllegalStateError, "reactor already shutdown")
    of ReactorState.CLOSED:
      raise newException(IllegalStateError, "reactor already closed")
    else:
      discard
  
  var events: array[MaxReactiveEventCount, Event] 
  while true:
    let count = r.selector.select(events, timeout) 
    if count < 0:
      let errorCode = osLastError()
      if errorCode.int32 != EINTR:
        raiseOSError(errorCode) 
    else:
      for i in 0..<count:
        let event = events[i]
        let data = r.interests.data[event.data.u64].addr
        if data.has:
          if event.isReadable or event.isError:
            data.value.readQueue.handleEvent()
          if event.isWritable or event.isError:
            data.value.writeQueue.handleEvent()
    if r.state == ReactorState.SHUTDOWN and r.interests.len == 0:
      r.selector.close()
      r.state = ReactorState.CLOSED
      return
