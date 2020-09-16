
import netkit/objects
import netkit/errors
import netkit/sync/xpsc
import netkit/collections/simplelists
import netkit/aio/posix/pollers

when defined(linux):
  import netkit/aio/posix/linux/semaphores
elif defined(macosx) or defined(freebsd) or defined(netbsd) or defined(openbsd) or defined(dragonfly):
  import netkit/aio/posix/semaphores
else:
  {.fatal: "Platform not supported!".}

type
  FiberBase* = object of RootObj
    run*: FiberProc

  Fiber*[T] = object of FiberBase
    value*: T

  FiberProc* = proc (fiber: ref FiberBase) {.nimcall, gcsafe.}

  Executor* = object
    poller: Poller
    spscSemaphoreId: Natural
    spscQueue: XpscQueue[ref FiberBase, PollableCounter]
    mpscSemaphoreId: Natural
    mpscQueue: XpscQueue[ref FiberBase, PollableCounter]
    destructorState: DestructorState

proc `=destroy`*(e: var Executor) {.raises: [OSError].} = 
  if e.destructorState == DestructorState.READY:
    `=destroy`(e.poller)
    `=destroy`(e.spscQueue)
    `=destroy`(e.mpscQueue)
    e.destructorState = DestructorState.COMPLETED

proc `=`*(dest: var Executor, source: Executor) {.error.}

proc pollSpscQueue(pollable: ref PollableBase): bool =
  result = false
  for fiber in (ref Pollable[ptr Executor])(pollable).value.spscQueue.popAll():
    fiber.run(fiber)

proc pollMpscQueue(pollable: ref PollableBase): bool =
  result = false
  for fiber in (ref Pollable[ptr Executor])(pollable).value.mpscQueue.popAll():
    fiber.run(fiber)

proc initExecutor*(e: var Executor, initialSize: Natural = 1024) {.raises: [OSError, ValueError].} =
  e.poller.initPoller(initialSize)

  var spscSemaphore: PollableSemaphore
  spscSemaphore.initPollableSemaphore()
  e.spscSemaphoreId = e.poller.register(spscSemaphore)
  let spscPollable = new(Pollable[ptr Executor])
  spscPollable.initSimpleNode()
  spscPollable.poll = pollSpscQueue
  spscPollable.value = e.addr
  e.poller.registerReadable(e.spscSemaphoreId, spscPollable)
  e.spscQueue.initXpscQueue(spscSemaphore, XpscMode.SPSC, initialSize)

  var mpscSemaphore: PollableSemaphore
  mpscSemaphore.initPollableSemaphore()
  e.mpscSemaphoreId = e.poller.register(mpscSemaphore)
  let mpscPollable = new(Pollable[ptr Executor])
  mpscPollable.initSimpleNode()
  mpscPollable.poll = pollMpscQueue
  mpscPollable.value = e.addr
  e.poller.registerReadable(e.mpscSemaphoreId, mpscPollable)
  e.mpscQueue.initXpscQueue(mpscSemaphore, XpscMode.MPSC, initialSize)

  e.destructorState = DestructorState.READY

proc shutdown*(e: var Executor) {.inline, raises: [IllegalStateError].} = 
  e.poller.shutdown()

proc execSpsc*(e: var Executor, fiber: ref FiberBase) {.inline.} = 
  e.spscQueue.add(fiber)

proc execMpsc*(e: var Executor, fiber: ref FiberBase) {.inline.} = 
  e.mpscQueue.add(fiber)

iterator interests*(e: var Executor): Natural {.inline.} =
  for i in e.poller.interests:
    yield i

proc registerHandle*(e: var Executor, fd: cint): Natural {.inline, raises: [OSError].} = 
  e.poller.registerHandle(fd)

proc unregisterHandle*(e: var Executor, id: Natural) {.inline, raises: [OSError, ValueError].} =
  e.poller.unregisterHandle(id)

proc registerReadable*(e: var Executor, id: Natural, pollable: ref PollableBase) {.inline, raises: [OSError, ValueError].} =
  e.poller.registerReadable(id, pollable)
 
proc unregisterReadable*(e: var Executor, id: Natural) {.inline, raises: [OSError, ValueError].} =
  e.poller.unregisterReadable(id)

proc registerWritable*(e: var Executor, id: Natural, pollable: ref PollableBase) {.inline, raises: [OSError, ValueError].} =
  e.poller.registerWritable(id, pollable)

proc unregisterWritable*(e: var Executor, id: Natural) {.inline, raises: [OSError, ValueError].} =
  e.poller.unregisterWritable(id)

proc runBlocking*(e: var Executor, timeout: cint) {.inline, raises: [OSError, IllegalStateError, Exception].} =
  e.poller.runBlocking(timeout)

