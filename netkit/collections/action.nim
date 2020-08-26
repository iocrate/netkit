
import std/os
import std/posix

import netkit/collections/simplequeue
import netkit/collections/future
import netkit/collections/share/vecs
import netkit/posix/linux/selector
import netkit/aio/ident

const
  MaxEventCount* {.intdefine.} = 128

type
  ActionBase* = object of RootObj
    future: ref Future
    run*: ActionProc

  Action*[T] = object of ActionBase
    value*: T

  ActionProc* = proc (c: ref ActionBase): bool {.nimcall, gcsafe.}

  ActionRegistry* = object
    selector: Selector
    interests: SharedVec[InterestData] # 散列 handle -> data
    identManager: IdentityManager
    
  InterestData = object
    fd: cint
    interest: Interest
    readQueue: SimpleQueue[ref ActionBase]
    writeQueue: SimpleQueue[ref ActionBase]
    has: bool

proc initActionRegistry*(cap: int): ActionRegistry =
  result.selector = initSelector()
  result.interests.init(cap)
  result.identManager.init()

proc register*(r: var ActionRegistry, fd: cint): Identity =
  let interest = initInterest()
  result = r.identManager.acquire()
  if r.interests.len <= result.int:
    r.interests.resize(r.interests.len * 2)
    assert r.interests.len > result.int
  let data = r.interests[result.int].addr
  data.fd = fd
  data.interest = interest
  data.readQueue = initSimpleQueue[ref ActionBase]()
  data.writeQueue = initSimpleQueue[ref ActionBase]()
  data.has = true
  r.selector.register(fd, UserData(u64: result.uint64), interest)

proc unregister*(r: var ActionRegistry, ident: Identity) =
  let data = r.interests[ident.int].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  reset(r.interests[ident.int]) 
  r.selector.unregister(data.fd)
  r.identManager.release(ident)

proc unregisterReadable*(r: var ActionRegistry, ident: Identity) =
  let data = r.interests[ident.int].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  if data.interest.isReadable():
    data.interest.unregisterReadable()
    r.selector.update(data.fd, UserData(u64: ident.uint64), data.interest)

proc unregisterWritable*(r: var ActionRegistry, ident: Identity) =
  let data = r.interests[ident.int].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  if data.interest.isWritable():
    data.interest.unregisterWritable()
    r.selector.update(data.fd, UserData(u64: ident.uint64), data.interest)

proc updateRead*(r: var ActionRegistry, ident: Identity, c: ref ActionBase) =
  let data = r.interests[ident.int].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  data.readQueue.addLast(newSimpleNode[ref ActionBase](c))
  if not data.interest.isReadable():
    data.interest.registerReadable()
    r.selector.update(data.fd, UserData(u64: ident.uint64), data.interest)

proc updateWrite*(r: var ActionRegistry, ident: Identity, c: ref ActionBase) =
  let data = r.interests[ident.int].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  data.writeQueue.addLast(newSimpleNode[ref ActionBase](c))
  if not data.interest.isWritable():
    data.interest.registerWritable()
    r.selector.update(data.fd, UserData(u64: ident.uint64), data.interest)

proc poll*(r: var ActionRegistry, timeout: cint) =
  template handleIoEvent(queue: SimpleQueue[ref ActionBase]) =
    for node in queue.nodes():
      if node.value.run(node.value):
        queue.remove(node)
      else:
        break
  
  var events: array[MaxEventCount, Event] 
  while true:
    let count = r.selector.select(events, timeout) 
    # if currentThreadPoolState == ThreadPoolState.SHUTDOWN:
    #   return
    if count < 0:
      let errorCode = osLastError()
      if errorCode.int32 != EINTR:
        raiseOSError(errorCode) 
    else:
      for i in 0..<count:
        let event = events[i]
        let data = r.interests[event.data.u64].addr
        if event.isReadable or event.isError:
          data.readQueue.handleIoEvent()
        if event.isWritable or event.isError:
          data.writeQueue.handleIoEvent()

        # if event.data.u64 == taskCounterIdent.uint64:
        #   if event.isReadable: 
        #     w.taskQueue.handleTaskEvent()
        #   else:
        #     raise newException(Defect, "bug， 不应该遇到这个错误")
        # else:
        #   let data = w.ioInterests[event.data.u64].addr
        #   if event.isReadable or event.isError:
        #     echo "isReadable or isError...", data.readQueue.len, " [", currentThreadId, "]"
        #     data.readQueue.handleIoEvent()
        #   if event.isWritable or event.isError:
        #     echo "isWritable or isError...", data.writeQueue.len, " [", currentThreadId, "]"
        #     data.writeQueue.handleIoEvent()

