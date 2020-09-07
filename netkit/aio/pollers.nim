
import std/os
import std/posix
import netkit/posix/linux/selector
import netkit/collections/simplelists
import netkit/collections/vecs
import netkit/aio/error
import netkit/numbergen
import netkit/options
import netkit/allocmode

const
  MaxConcurrentEventCount* {.intdefine.} = 1024

type
  PollableBase* = object of SimpleNode
    poll*: PollableProc

  Pollable*[T] = object of PollableBase
    value*: T

  PollableProc* = proc (p: ref PollableBase): bool {.nimcall, gcsafe.}

  InterestData = object
    fd: cint
    interest: Interest
    readList: SimpleList
    writeList: SimpleList

  InterestVec = object
    data: Vec[Option[InterestData]]
    len: Natural
    idGenerator: NaturalGenerator

  Poller* = object
    selector: Selector
    interests: InterestVec
    state: PollerState
    initialized: bool

  PollerState* {.pure.} = enum
    CREATED, RUNNING, SHUTDOWN, STOPPED, CLOSED

proc `=destroy`*(poller: var Poller) {.raises: [OSError].} = 
  if poller.initialized and poller.state != PollerState.CLOSED:
    poller.selector.close()
    poller.interests.data.`=destroy`()
    poller.interests.idGenerator.`=destroy`()
    poller.state = PollerState.CLOSED
    
proc initPoller*(poller: var Poller, initialSize: Natural = 256, mode = AllocMode.THREAD_LOCAL) {.raises: [OSError].} = 
  poller.selector = initSelector()
  poller.interests.data.initVec(initialSize, mode)
  poller.interests.idGenerator.initNaturalGenerator(initialSize, mode)
  poller.state = PollerState.CREATED
  poller.initialized = true

proc shutdown*(poller: var Poller) {.raises: [IllegalStateError].} = 
  case poller.state 
  of PollerState.CREATED:
    poller.state = PollerState.RUNNING
  of PollerState.RUNNING:
    poller.state = PollerState.SHUTDOWN
  of PollerState.SHUTDOWN:
    raise newException(IllegalStateError, "reactor still shutdowning")
  of PollerState.STOPPED:
    raise newException(IllegalStateError, "reactor already stopped")
  of PollerState.CLOSED:
    raise newException(IllegalStateError, "reactor already closed")

proc runBlocking*(poller: var Poller, timeout: cint) {.raises: [OSError, IllegalStateError, Exception].} =
  template handleEvents(list: SimpleList) =
    var listCopy = list
    for node in listCopy.nodes():
      if ((ref PollableBase)(node)).poll((ref PollableBase)(node)):
        listCopy.remove(node)
      else:
        break

  case poller.state 
  of PollerState.CREATED:
    poller.state = PollerState.RUNNING
  of PollerState.RUNNING:
    raise newException(IllegalStateError, "reactor already running")
  of PollerState.SHUTDOWN:
    raise newException(IllegalStateError, "reactor still shutdowning")
  of PollerState.STOPPED:
    poller.state = PollerState.RUNNING
  of PollerState.CLOSED:
    raise newException(IllegalStateError, "reactor already closed")
  
  var events: array[MaxConcurrentEventCount, Event] 
  while true:
    let count = poller.selector.select(events, timeout) 
    if count < 0:
      let errorCode = osLastError()
      if errorCode.int32 != EINTR:
        raiseOSError(errorCode) 
    else:
      for i in 0..<count:
        let event = events[i]
        let data = poller.interests.data[event.data.u64].addr
        if data.has:
          if event.isReadable or event.isError:
            data.value.readList.handleEvents()
          if event.isWritable or event.isError:
            data.value.writeList.handleEvents()
    if poller.state == PollerState.SHUTDOWN:
      poller.state = PollerState.STOPPED
      return
    # if poller.state == PollerState.SHUTDOWN and poller.interests.len == 0:
    #   poller.state = PollerState.STOPPED
    #   return

iterator interests*(poller: var Poller): Natural =
  for i, data in poller.interests.data.pairs():
    if data.has:
      yield i

proc register*(poller: var Poller, fd: cint): Natural =
  # if poller.state == PollerState.SHUTDOWN:
  #   raise newException(IllegalStateError, "reactor already shutdown")
  # if poller.state == PollerState.CLOSED:
  #   raise newException(IllegalStateError, "reactor already closed")  
  let interest = initInterest()
  result = poller.interests.idGenerator.acquire()
  poller.selector.register(fd, UserData(u64: result.uint64), interest)
  if poller.interests.data.cap <= result:
    poller.interests.data.resize(poller.interests.data.cap * 2)
    assert poller.interests.data.cap > result
  let data = poller.interests.data[result].addr
  data.value.fd = fd
  data.value.interest = interest
  data.value.readList = initSimpleList()
  data.value.writeList = initSimpleList()
  data.has = true
  poller.interests.len.inc()

proc unregister*(poller: var Poller, id: Natural) {.raises: [OSError, ValueError].} =
  let data = poller.interests.data[id].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  poller.selector.unregister(data.value.fd)
  poller.interests.idGenerator.release(id)
  poller.interests.len.dec()
  reset(data[]) 

proc unregisterReadable*(poller: var Poller, id: Natural) {.raises: [OSError, ValueError].} =
  let data = poller.interests.data[id].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  if data.value.interest.isReadable():
    data.value.interest.unregisterReadable()
    poller.selector.update(data.value.fd, UserData(u64: id.uint64), data.value.interest)

proc unregisterWritable*(poller: var Poller, id: Natural) {.raises: [OSError, ValueError].} =
  let data = poller.interests.data[id].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  if data.value.interest.isWritable():
    data.value.interest.unregisterWritable()
    poller.selector.update(data.value.fd, UserData(u64: id.uint64), data.value.interest)

proc updateRead*(poller: var Poller, id: Natural, p: ref PollableBase) {.raises: [OSError, ValueError].} =
  let data = poller.interests.data[id].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  data.value.readList.addLast(p)
  if not data.value.interest.isReadable():
    data.value.interest.registerReadable()
    poller.selector.update(data.value.fd, UserData(u64: id.uint64), data.value.interest)

proc updateWrite*(poller: var Poller, id: Natural, p: ref PollableBase) {.raises: [OSError, ValueError].} =
  let data = poller.interests.data[id].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  data.value.writeList.addLast(p)
  if not data.value.interest.isWritable():
    data.value.interest.registerWritable()
    poller.selector.update(data.value.fd, UserData(u64: id.uint64), data.value.interest)
