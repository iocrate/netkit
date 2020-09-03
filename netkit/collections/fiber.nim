
import netkit/collections/spsc
import netkit/collections/mpsc
import netkit/collections/fibercounter

type
  FiberBase* = object of RootObj
    run*: FiberProc

  Fiber*[T] = object of FiberBase
    value*: T

  FiberProc* = proc (r: ref FiberBase) {.nimcall, gcsafe.}

  FiberRegistry* = object
    spscQueue: SpscQueue[ref FiberBase, cint]
    mpscQueue: MpscQueue[ref FiberBase, cint]

proc initFiberRegistry*(spscFd: cint, spscCap: Natural, mpscFd: cint, mpscCap: Natural): FiberRegistry =
  result.spscQueue = initSpscQueue[ref FiberBase, cint](initFiberCounter(spscFd), spscCap)
  result.mpscQueue = initMpscQueue[ref FiberBase, cint](initFiberCounter(mpscFd), mpscCap)

proc addSpsc*(r: var FiberRegistry, t: ref FiberBase) {.inline.} =
  r.spscQueue.add(t)

proc addMpsc*(r: var FiberRegistry, t: ref FiberBase) {.inline.} =
  r.mpscQueue.add(t)

proc runSpsc*(r: var FiberRegistry) =
  r.spscQueue.sync()
  while r.spscQueue.len > 0:
    let task = r.spscQueue.take()
    task.run(task)

proc runMpsc*(r: var FiberRegistry) =
  r.mpscQueue.sync()
  while r.mpscQueue.len > 0:
    let task = r.mpscQueue.take()
    task.run(task)

