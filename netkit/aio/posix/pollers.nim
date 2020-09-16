
import std/os
import std/posix
import netkit/errors
import netkit/idgen
import netkit/options
import netkit/allocmode
import netkit/objects
import netkit/collections/simplelists
import netkit/collections/vecs

when defined(linux):
  import netkit/aio/posix/linux/interests
  import netkit/aio/posix/linux/selectors
elif defined(macosx) or defined(freebsd) or defined(netbsd) or defined(openbsd) or defined(dragonfly):
  discard
else:
  {.fatal: "Platform not supported!".}

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
    idGenerator: IdGenerator

  Poller* = object
    selector: Selector
    interests: InterestVec
    state: PollerState
    destructorState: DestructorState

  PollerState* {.pure.} = enum
    CREATED, RUNNING, SHUTDOWN, STOPPED, DESTROYED

proc `=destroy`*(poller: var Poller) {.raises: [OSError].} = 
  if poller.destructorState == DestructorState.READY:
    `=destroy`(poller.selector)
    `=destroy`(poller.interests.data)
    `=destroy`(poller.interests.idGenerator)
    poller.state = PollerState.DESTROYED
    poller.destructorState = DestructorState.COMPLETED

proc `=`*(dest: var Poller, source: Poller) {.error.} 
    
proc initPoller*(poller: var Poller, initialSize: Natural = 256, mode = AllocMode.THREAD_LOCAL) {.raises: [OSError].} = 
  poller.selector.initSelector()
  poller.interests.data.initVec(initialSize, mode)
  poller.interests.idGenerator.initIdGenerator(initialSize, mode)
  poller.state = PollerState.CREATED
  poller.destructorState = DestructorState.READY

proc shutdown*(poller: var Poller) {.raises: [IllegalStateError].} = 
  case poller.state 
  of PollerState.CREATED:
    poller.state = PollerState.RUNNING
  of PollerState.RUNNING:
    poller.state = PollerState.SHUTDOWN
  of PollerState.SHUTDOWN:
    raise newException(IllegalStateError, "poller still shutdowning")
  of PollerState.STOPPED:
    raise newException(IllegalStateError, "poller already stopped")
  of PollerState.DESTROYED:
    raise newException(IllegalStateError, "poller already destroyed")

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
    raise newException(IllegalStateError, "poller already running")
  of PollerState.SHUTDOWN:
    raise newException(IllegalStateError, "poller still shutdowning")
  of PollerState.STOPPED:
    poller.state = PollerState.RUNNING
  of PollerState.DESTROYED:
    raise newException(IllegalStateError, "poller already destroyed")
  
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

proc registerHandle*(poller: var Poller, fd: cint): Natural {.raises: [OSError].} =
  let interest = initInterest()
  result = poller.interests.idGenerator.acquire()
  poller.selector.register(fd, UserData(u64: result.uint64), interest)
  if poller.interests.data.cap <= result:
    poller.interests.data.resize(poller.interests.data.cap * 2)
    assert poller.interests.data.cap > result
  let data = poller.interests.data[result].addr
  data.value.fd = fd
  data.value.interest = interest
  data.value.readList.initSimpleList()
  data.value.writeList.initSimpleList()
  data.has = true
  poller.interests.len.inc()

proc unregisterHandle*(poller: var Poller, id: Natural) {.raises: [OSError, ValueError].} =
  let data = poller.interests.data[id].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  poller.selector.unregister(data.value.fd)
  poller.interests.idGenerator.release(id)
  poller.interests.len.dec()
  reset(data[]) 

proc registerReadable*(poller: var Poller, id: Natural, p: ref PollableBase) {.raises: [OSError, ValueError].} =
  let data = poller.interests.data[id].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  data.value.readList.addLast(p)
  if not data.value.interest.isReadable():
    data.value.interest.registerReadable()
    poller.selector.update(data.value.fd, UserData(u64: id.uint64), data.value.interest)

proc unregisterReadable*(poller: var Poller, id: Natural) {.raises: [OSError, ValueError].} =
  let data = poller.interests.data[id].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  if data.value.interest.isReadable():
    data.value.interest.unregisterReadable()
    poller.selector.update(data.value.fd, UserData(u64: id.uint64), data.value.interest)

proc registerWritable*(poller: var Poller, id: Natural, p: ref PollableBase) {.raises: [OSError, ValueError].} =
  let data = poller.interests.data[id].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  data.value.writeList.addLast(p)
  if not data.value.interest.isWritable():
    data.value.interest.registerWritable()
    poller.selector.update(data.value.fd, UserData(u64: id.uint64), data.value.interest)

proc unregisterWritable*(poller: var Poller, id: Natural) {.raises: [OSError, ValueError].} =
  let data = poller.interests.data[id].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  if data.value.interest.isWritable():
    data.value.interest.unregisterWritable()
    poller.selector.update(data.value.fd, UserData(u64: id.uint64), data.value.interest)

when isMainModule:
  import std/posix

  var poller: Poller
  poller.initPoller()

  var chan: array[2, cint]
  discard pipe(chan)
  
  let r1 = chan[0]
  let r2 = dup(chan[0])
  let id1 = poller.registerHandle(r1)
  let w = chan[1]
  echo "r1:", r1, ", r2:", r2, ", w:", w
  
  let p1 = new(Pollable[int])
  p1.poll = proc (p: ref PollableBase): bool =
    result = true
    var buf = newString(16)
    assert r2.read(buf.addr, sizeof(buf)) > 0
    echo buf
  p1.value = 1
  poller.registerReadable(id1, p1)

  let id2 = poller.registerHandle(w)
  let p2 = new(Pollable[int])
  p2.poll = proc (p: ref PollableBase): bool =
    result = true
    var buf = "abc"
    assert w.write(buf.addr, sizeof(buf)) > 0
  p2.value = 1
  poller.registerWritable(id2, p2)

  poller.runBlocking(500)
