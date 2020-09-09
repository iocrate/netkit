
import std/os
import std/posix
import netkit/locks
import netkit/collections/spsc
import netkit/collections/mpsc
import netkit/collections/simplelists
import netkit/aio/eventcounter
import netkit/aio/pollers
import netkit/aio/errors
import netkit/objects

type
  FiberBase* = object of RootObj
    run*: FiberProc

  Fiber*[T] = object of FiberBase
    value*: T

  FiberProc* = proc (fiber: ref FiberBase) {.nimcall, gcsafe.}

  Executor* = object
    poller: Poller
    spscCounterId: Natural
    spscCounterFd: cint
    spscQueue: SpscQueue[ref FiberBase, cint]
    mpscCounterId: Natural
    mpscCounterFd: cint
    mpscQueue: MpscQueue[ref FiberBase, cint]
    destructorState: DestructorState

proc openEventFd(): cint {.raises: [OSError], inline.} = 
  result = eventfd(0, 0)
  if result < 0:
    raiseOSError(osLastError())

proc closeEventFd(fd: cint) {.raises: [OSError], inline.} = 
  if close(fd) < 0:
    raiseOSError(osLastError())

proc pollSpscQueue(pollable: ref PollableBase): bool =
  result = false
  let e = (ref Pollable[ptr Executor])(pollable).value
  e.spscQueue.sync()
  while e.spscQueue.len > 0:
    let runnable = e.spscQueue.take()
    runnable.run(runnable)

proc pollMpscQueue(pollable: ref PollableBase): bool =
  result = false
  let e = (ref Pollable[ptr Executor])(pollable).value
  e.mpscQueue.sync()
  while e.mpscQueue.len > 0:
    let runnable = e.mpscQueue.take()
    runnable.run(runnable)

proc `=destroy`*(e: var Executor) {.raises: [OSError].} = 
  if e.destructorState == DestructorState.READY:
    e.poller.`=destroy`()
    e.spscQueue.`=destroy`()
    e.spscCounterFd.closeEventFd()
    e.mpscQueue.`=destroy`()
    e.mpscCounterFd.closeEventFd()
    e.destructorState = DestructorState.COMPLETED

proc initExecutor*(e: var Executor, initialSize: Natural = 256) {.raises: [OSError, ValueError].} =
  initPoller(e.poller, initialSize)

  e.spscCounterFd = openEventFd()
  e.spscQueue = initSpscQueue[ref FiberBase, cint](initEventCounter(e.spscCounterFd), initialSize)
  e.spscCounterId = e.poller.register(e.spscCounterFd)
  let spscPollable = new(Pollable[ptr Executor])
  spscPollable.initSimpleNode()
  spscPollable.poll = pollSpscQueue
  spscPollable.value = e.addr
  e.poller.updateRead(e.spscCounterId, spscPollable)

  e.mpscCounterFd = openEventFd()
  e.mpscQueue = initMpscQueue[ref FiberBase, cint](initEventCounter(e.mpscCounterFd), initialSize)
  e.mpscCounterId = e.poller.register(e.mpscCounterFd)
  let mpscPollable = new(Pollable[ptr Executor])
  mpscPollable.initSimpleNode()
  mpscPollable.poll = pollMpscQueue
  mpscPollable.value = e.addr
  e.poller.updateRead(e.mpscCounterId, mpscPollable)

  e.destructorState = DestructorState.READY

proc shutdown*(e: var Executor) {.inline, raises: [IllegalStateError].} = 
  e.poller.shutdown()

proc execSpsc*(e: var Executor, fiber: ref FiberBase) {.inline, raises: [IllegalStateError, Exception].} = 
  e.spscQueue.add(fiber)

proc execMpsc*(e: var Executor, fiber: ref FiberBase) {.inline, raises: [IllegalStateError, Exception].} = 
  e.mpscQueue.add(fiber)

iterator interests*(e: var Executor): Natural {.inline.} =
  for i in e.poller.interests:
    yield i

proc registerHandle*(e: var Executor, fd: cint): Natural {.inline.} = 
  e.poller.register(fd)

proc unregisterHandle*(e: var Executor, id: Natural) {.inline.} =
  e.poller.unregister(id)
 
proc unregisterReadable*(e: var Executor, id: Natural) {.inline.} =
  e.poller.unregisterReadable(id)

proc unregisterWritable*(e: var Executor, id: Natural) {.inline.} =
  e.poller.unregisterWritable(id)

proc updateRead*(e: var Executor, id: Natural, pollable: ref PollableBase) {.inline.} =
  e.poller.updateRead(id, pollable)

proc updateWrite*(e: var Executor, id: Natural, pollable: ref PollableBase) {.inline.} =
  e.poller.updateWrite(id, pollable)

proc runBlocking*(e: var Executor, timeout: cint) {.inline, raises: [OSError, IllegalStateError, Exception].} =
  e.poller.runBlocking(timeout)
