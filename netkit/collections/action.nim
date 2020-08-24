
import netkit/collections/simplequeue

type
  Future* = object
    publish: proc ()
    subscribe: proc ()
    finished: bool
    # error*: ref Exception
    # value: T   

  ActionBase* = object of RootObj
    future: ref Future
    run*: ActionProc

  Action*[T] = object of ActionBase
    value*: T

  ActionProc* = proc (c: ref ActionBase): bool {.nimcall, gcsafe.}

  ActionQueue* = SimpleQueue[ref ActionBase]