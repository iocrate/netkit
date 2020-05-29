type
  FutureBase* = ref object of RootObj
    callback: CallbackFunc
    finished: bool
    error: ref Exception   

  Future*[T] = ref object of FutureBase
    value: T

  AioPromiseCode* {.pure.} = enum # TODO: size 优化，与 Promise 一致
    Send, Recv

  AioPromise* = ref object of RootObj
    code*: AioPromiseCode
    
  Promise*[T] = ref object of AioPromise
    future: Future[T]

  CallbackFunc* = proc () {.gcsafe.}

proc newPromise*[T](): Promise[T] =
  new(result)
  result.future = new(Future[T])
  result.future.finished = false

proc init*[T](promise: Promise[T], code: AioPromiseCode) =
  promise.code = code
  promise.future = new(Future[T])
  promise.future.finished = false

proc setValue*[T](promise: Promise[T], value: T) =
  let future = promise.future
  # checkFinished(future) TODO
  assert(future.error == nil)
  future.value = value
  future.finished = true
  if future.callback != nil:
    future.callback() # TODO: callSoon

proc setValue*[T](promise: Promise[T]) =
  let future = promise.future
  # checkFinished(future) TODO
  assert(future.error == nil)
  future.finished = true
  if future.callback != nil:
    future.callback() # TODO: callSoon

proc setError*[T](promise: Promise[T], error: ref Exception) =
  let future = promise.future
  # checkFinished(promise) TODO
  future.finished = true
  future.error = error
  if future.callback != nil:
    future.callback() # TODO: callSoon

proc future*[T](promise: Promise[T]): Future[T] =
  promise.future

proc `callback=`*(future: FutureBase, cb: CallbackFunc) =
  assert cb != nil
  future.callback = cb
  if future.finished:
    cb() # TODO: callSoon

proc finished*(future: FutureBase): bool =
  future.finished

proc failed*(future: FutureBase): bool =
  future.error != nil

proc getError*(future: FutureBase): ref Exception =
  if future.error == nil: 
    raise newException(ValueError, "No error in future.")
  future.error

proc getValue*[T](future: Future[T]): T =
  if future.finished:
    if future.error != nil:
      # injectStacktrace(future) TODO
      raise future.error
    when T isnot void:
      future.value
  else:
    # TODO: Make a custom exception type for this?
    raise newException(ValueError, "Future still in progress.")

proc asyncCheck*[T](future: Future[T]) =
  assert(not future.isNil, "Future is nil")
  # TODO: We can likely look at the stack trace here and inject the location
  # where the `asyncCheck` was called to give a better error stack message.
  future.callback = proc () =
    if future.failed:
      # injectStacktrace(future) TODO
      raise future.error