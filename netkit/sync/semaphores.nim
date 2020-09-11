
type
  Semaphore*[T] = object 
    value*: T
    signalImpl*: proc (c: var Semaphore[T]) {.nimcall, gcsafe.}
    waitImpl*: proc (c: var Semaphore[T]): uint {.nimcall, gcsafe.}

proc signal*[T](c: var Semaphore[T]) {.inline.} =
  c.signalImpl(c) 

proc wait*[T](c: var Semaphore[T]): uint {.inline.} =
  c.waitImpl(c) 