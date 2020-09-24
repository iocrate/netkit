
import netkit/objects
import netkit/errors
import netkit/sync/xpsc
import netkit/aio/posix/pollers

when defined(linux):
  import netkit/aio/posix/linux/semaphores
elif defined(macosx) or defined(freebsd) or defined(netbsd) or defined(openbsd) or defined(dragonfly):
  import netkit/aio/posix/semaphores
else:
  {.fatal: "Platform not supported!".}

type
  Executor* = object
    poller: Poller
    spscSemaphoreId: Natural
    spscQueue: XpscQueue[Runnable, PollableSemaphore]
    mpscSemaphoreId: Natural
    mpscQueue: XpscQueue[Runnable, PollableSemaphore]
    destructorState: DestructorState
    
  Runnable* = proc () {.gcsafe.}

proc `=destroy`*(e: var Executor) = 
  if e.destructorState == DestructorState.READY:
    `=destroy`(e.poller)
    `=destroy`(e.spscQueue)
    `=destroy`(e.mpscQueue)
    e.destructorState = DestructorState.COMPLETED

proc `=`*(dest: var Executor, source: Executor) {.error.}

proc initExecutor*(e: var Executor, initialSize: Natural = 1024) =
  let eAddr = e.addr
  e.poller.initPoller(initialSize)

  var spscSemaphore: PollableSemaphore
  spscSemaphore.initPollableSemaphore()
  e.spscSemaphoreId = e.poller.register(spscSemaphore)
  e.poller.registerReadable(e.spscSemaphoreId) do () -> bool:
    result = false
    for run in eAddr.spscQueue.popAll():
      run()
  e.spscQueue.initXpscQueue(spscSemaphore, XpscMode.SPSC, initialSize)

  var mpscSemaphore: PollableSemaphore
  mpscSemaphore.initPollableSemaphore()
  e.mpscSemaphoreId = e.poller.register(mpscSemaphore)
  e.poller.registerReadable(e.mpscSemaphoreId) do () -> bool:
    result = false
    for run in eAddr.mpscQueue.popAll():
      run()
  e.mpscQueue.initXpscQueue(mpscSemaphore, XpscMode.MPSC, initialSize)

  e.destructorState = DestructorState.READY

proc shutdown*(e: var Executor) {.inline, raises: [IllegalStateError].} = 
  e.poller.shutdown()

proc execSpsc*(e: var Executor, r: Runnable) {.inline.} = 
  e.spscQueue.add(r)

proc execMpsc*(e: var Executor, r: Runnable) {.inline.} = 
  e.mpscQueue.add(r)

iterator interests*(e: var Executor): Natural {.inline.} =
  for i in e.poller.interests:
    yield i

proc registerHandle*(e: var Executor, fd: cint): Natural {.inline.} = 
  e.poller.registerHandle(fd)

proc unregisterHandle*(e: var Executor, id: Natural) {.inline.} =
  e.poller.unregisterHandle(id)

proc registerReadable*(e: var Executor, id: Natural, p: Pollable) {.inline.} =
  e.poller.registerReadable(id, p)
 
proc unregisterReadable*(e: var Executor, id: Natural) {.inline.} =
  e.poller.unregisterReadable(id)

proc registerWritable*(e: var Executor, id: Natural, p: Pollable) {.inline.} =
  e.poller.registerWritable(id, p)

proc unregisterWritable*(e: var Executor, id: Natural) {.inline.} =
  e.poller.unregisterWritable(id)

proc runBlocking*(e: var Executor, timeout: cint) {.inline.} =
  e.poller.runBlocking(timeout)

