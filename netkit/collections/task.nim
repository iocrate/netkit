
import netkit/collections/spsc
import netkit/collections/taskcounter

type
  TaskBase* = object of RootObj
    run*: TaskProc

  Task*[T] = object of TaskBase
    value*: T

  TaskProc* = proc (r: ptr TaskBase) {.nimcall, gcsafe.}

  TaskRegistry* = object
    taskQueue: SpscQueue[ptr TaskBase, cint]

proc initTaskRegistry*(fd: cint, cap: int): TaskRegistry =
  result.taskQueue = initSpscQueue[ptr TaskBase, cint](initTaskCounter(fd), cap)

proc add*(r: var TaskRegistry, t: ptr TaskBase) {.inline.} =
  r.taskQueue.add(t)

proc run*(r: var TaskRegistry) =
  r.taskQueue.sync()
  while r.taskQueue.len > 0:
    let task = r.taskQueue.take()
    task.run(task)

