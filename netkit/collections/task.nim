
import netkit/collections/spsc
import netkit/collections/mpsc
import netkit/collections/taskcounter

type
  TaskBase* = object of RootObj
    run*: TaskProc

  Task*[T] = object of TaskBase
    value*: T

  TaskProc* = proc (task: ref TaskBase) {.nimcall, gcsafe.}

  TaskRegistry* = object
    spscQueue: SpscQueue[ref TaskBase, cint]
    mpscQueue: MpscQueue[ref TaskBase, cint]

proc initTaskRegistry*(spscFd: cint, spscCap: Natural, mpscFd: cint, mpscCap: Natural): TaskRegistry =
  result.spscQueue = initSpscQueue[ref TaskBase, cint](initTaskCounter(spscFd), spscCap)
  result.mpscQueue = initMpscQueue[ref TaskBase, cint](initTaskCounter(mpscFd), mpscCap)

proc addSpsc*(r: var TaskRegistry, task: ref TaskBase) {.inline.} =
  r.spscQueue.add(task)

proc addMpsc*(r: var TaskRegistry, task: ref TaskBase) {.inline.} =
  r.mpscQueue.add(task)

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

