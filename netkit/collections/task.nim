
import netkit/collections/spsc
import netkit/collections/mpsc
import netkit/collections/taskcounter

type
  TaskBase* = object of RootObj
    run*: TaskProc

  Task*[T] = object of TaskBase
    value*: T

  TaskProc* = proc (r: ptr TaskBase) {.nimcall, gcsafe.}

  TaskRegistry* = object
    spscQueue: SpscQueue[ptr TaskBase, cint]
    mpscQueue: MpscQueue[ptr TaskBase, cint]

proc initTaskRegistry*(spscFd: cint, spscCap: Natural, mpscFd: cint, mpscCap: Natural): TaskRegistry =
  result.spscQueue = initSpscQueue[ptr TaskBase, cint](initTaskCounter(spscFd), spscCap)
  result.mpscQueue = initMpscQueue[ptr TaskBase, cint](initTaskCounter(mpscFd), mpscCap)

proc addSpsc*(r: var TaskRegistry, t: ptr TaskBase) {.inline.} =
  r.spscQueue.add(t)

proc addMpsc*(r: var TaskRegistry, t: ptr TaskBase) {.inline.} =
  r.mpscQueue.add(t)

proc runSpsc*(r: var TaskRegistry) =
  r.spscQueue.sync()
  while r.spscQueue.len > 0:
    let task = r.spscQueue.take()
    task.run(task)

proc runMpsc*(r: var TaskRegistry) =
  r.mpscQueue.sync()
  while r.mpscQueue.len > 0:
    let task = r.mpscQueue.take()
    task.run(task)

