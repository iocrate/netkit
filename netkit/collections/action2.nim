
import std/os
import std/posix

import netkit/collections/simplequeue
import netkit/collections/future
import netkit/collections/vecs
import netkit/collections/runnable
import netkit/posix/linux/selector
import netkit/aio/ident

const
  MaxConcurrentEventCount* {.intdefine.} = 1024

type
  Action* = Runnable[bool]

  ActionRegistry* = object
    interests: ThreadLocalVec[InterestData] # 散列 handle -> data
    identManager: IdentityManager
    
  InterestData = object
    fd: cint
    interest: Interest
    readQueue: SimpleQueue[ref Action]
    writeQueue: SimpleQueue[ref Action]
    has: bool

proc initActionRegistry*(initialSize: int): ActionRegistry =
  result.interests.init(initialSize)
  result.identManager.init()

proc register*(r: var ActionRegistry, fd: cint): Identity =
  let data = r.interests[result.int].addr
  if data.has:
    raise newException(ValueError, "file descriptor has registered")
  let interest = initInterest()
  result = r.identManager.acquire()
  if r.interests.len <= result.int:
    r.interests.resize(r.interests.len * 2)
    assert r.interests.len > result.int
  data.fd = fd
  data.interest = interest
  data.readQueue = initSimpleQueue[ref Action]()
  data.writeQueue = initSimpleQueue[ref Action]()
  data.has = true

proc unregister*(r: var ActionRegistry, ident: Identity) =
  var data = r.interests[ident.int].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  r.identManager.release(ident)
  reset(data) 

proc unregister*(r: var ActionRegistry) =
  for i, data in r.interests.mpairs():
    if data.has:
      r.identManager.release(Identity(i))
      # r.selector.unregister(data.fd) TODO
      reset(data) 

proc unregisterReadable*(r: var ActionRegistry, ident: Identity) =
  let data = r.interests[ident.int].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  if data.interest.isReadable():
    data.interest.unregisterReadable()
    # r.selector.update(data.fd, UserData(u64: ident.uint64), data.interest) TODO

proc unregisterWritable*(r: var ActionRegistry, ident: Identity) =
  let data = r.interests[ident.int].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  if data.interest.isWritable():
    data.interest.unregisterWritable()
    r.selector.update(data.fd, UserData(u64: ident.uint64), data.interest)

proc updateRead*(r: var ActionRegistry, ident: Identity, action: ref Action) =
  let data = r.interests[ident.int].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  data.readQueue.addLast(newSimpleNode[ref Action](action))
  if not data.interest.isReadable():
    data.interest.registerReadable()
    r.selector.update(data.fd, UserData(u64: ident.uint64), data.interest)

proc updateWrite*(r: var ActionRegistry, ident: Identity, action: ref Action) =
  let data = r.interests[ident.int].addr
  if not data.has:
    raise newException(ValueError, "file descriptor not registered")
  data.writeQueue.addLast(newSimpleNode[ref Action](action))
  if not data.interest.isWritable():
    data.interest.registerWritable()
    r.selector.update(data.fd, UserData(u64: ident.uint64), data.interest)

proc shutdown*(r: var ActionRegistry) = 
  if r.state != ActionRegistryState.SHUTDOWN:
    r.state = ActionRegistryState.SHUTDOWN
    r.unregister()

proc runWait*(r: var ActionRegistry, timeout: cint) =
  template handleEvent(queue: SimpleQueue[ref Action]) =
    for node in queue.nodes():
      if node.value.run(node.value):
        queue.remove(node)
      else:
        break
  
  r.state = ActionRegistryState.RUNNING
  var events: array[MaxConcurrentEventCount, Event] 
  while true:
    let count = r.selector.select(events, timeout) 
    if r.state == ActionRegistryState.SHUTDOWN:
      return
    if count < 0:
      let errorCode = osLastError()
      if errorCode.int32 != EINTR:
        raiseOSError(errorCode) 
    else:
      for i in 0..<count:
        let event = events[i]
        let data = r.interests[event.data.u64].addr
        if event.isReadable or event.isError:
          data.readQueue.handleEvent()
        if event.isWritable or event.isError:
          data.writeQueue.handleEvent()
