
import os, tables, strutils, times, heapqueue, options, deques, cstrutils
import netkit/collections/simplequeues

type
  FutureBase* = ref object of RootObj
    callback: CallbackProc
    finished: bool
    error*: ref Exception               ## Stored exception
    errorStackTrace*: string
    when not defined(release):
      stackTrace: seq[StackTraceEntry]  ## For debugging purposes only.
      id: int
      fromProc: string

  Future*[T] = ref object of FutureBase     ## Typed future.
    value: T                            ## Stored value

  FutureVar*[T] = distinct Future[T]

  FutureError* = object of Defect
    cause*: FutureBase

  CallbackProc* = proc () {.gcsafe.}

when not defined(release):
  var currentID = 0

const isFutureLoggingEnabled* = defined(futureLogging)

const
  NimAsyncContinueSuffix* = "NimAsyncContinue" ## For internal usage. Do not use.

template setupFutureBase(fromProc: string) =
  new(result)
  result.finished = false
  when not defined(release):
    result.stackTrace = getStackTraceEntries()
    result.id = currentID
    result.fromProc = fromProc
    currentID.inc()

proc newFuture*[T](fromProc: string = "unspecified"): owned Future[T] =
  setupFutureBase(fromProc)
  when isFutureLoggingEnabled: 
    logFutureStart(result)

proc checkFinished[T](future: Future[T]) =
  ## Checks whether `future` is finished. If it is then raises a
  ## ``FutureError``.
  when not defined(release):
    if future.finished:
      var msg = ""
      msg.add("An attempt was made to complete a Future more than once. ")
      msg.add("Details:")
      msg.add("\n  Future ID: " & $future.id)
      msg.add("\n  Created in proc: " & future.fromProc)
      msg.add("\n  Stack trace to moment of creation:")
      msg.add("\n" & indent(($future.stackTrace).strip(), 4))
      when T is string:
        msg.add("\n  Contents (string): ")
        msg.add("\n" & indent($future.value, 4))
      msg.add("\n  Stack trace to moment of secondary completion:")
      msg.add("\n" & indent(getStackTrace().strip(), 4))
      var err = newException(FutureError, msg)
      err.cause = future
      raise err

proc complete*[T](future: Future[T], value: T) =
  checkFinished(future)
  assert(future.error == nil)
  future.value = value
  future.finished = true
  future.callback()
  when isFutureLoggingEnabled: 
    logFutureFinish(future)

proc complete*(future: Future[void]) =
  checkFinished(future)
  assert(future.error == nil)
  future.finished = true
  future.callback()
  when isFutureLoggingEnabled: 
    logFutureFinish(future)

proc fail*[T](future: Future[T], error: ref Exception) =
  checkFinished(future)
  future.finished = true
  future.error = error
  future.errorStackTrace = if getStackTrace(error) == "": getStackTrace() else: getStackTrace(error)
  future.callback()
  when isFutureLoggingEnabled: 
    logFutureFinish(future)

proc `callback=`*[T](future: Future[T], cb: CallbackProc) =
  future.callback = cb
  if future.finished:
    cb()
  # TODO: callSoon
  
proc injectStacktrace[T](future: Future[T]) =
  when not defined(release):
    const header = "\nAsync traceback:\n"

    var exceptionMsg = future.error.msg
    if header in exceptionMsg:
      # This is messy: extract the original exception message from the msg
      # containing the async traceback.
      let start = exceptionMsg.find(header)
      exceptionMsg = exceptionMsg[0..<start]


    var newMsg = exceptionMsg & header

    let entries = getStackTraceEntries(future.error)
    newMsg.add($entries)

    newMsg.add("Exception message: " & exceptionMsg & "\n")
    newMsg.add("Exception type:")

    # # For debugging purposes
    # for entry in getStackTraceEntries(future.error):
    #   newMsg.add "\n" & $entry
    future.error.msg = newMsg

proc read*[T](future: Future[T] | ref FutureVar[T]): T =
  {.push hint[ConvFromXtoItselfNotNeeded]: off.}
  let fut = (Future[T])(future)
  {.pop.}
  if fut.finished:
    if fut.error != nil:
      injectStacktrace(fut)
      raise fut.error
    when T isnot void:
      result = fut.value
  else:
    # TODO: Make a custom exception type for this?
    raise newException(ValueError, "Future still in progress.")

proc readError*[T](future: Future[T]): ref Exception =
  if future.error != nil: 
    return future.error
  else:
    raise newException(ValueError, "No error in future.")

proc mget*[T](future: FutureVar[T]): var T =
  result = Future[T](future).value

proc finished*(future: FutureBase | FutureVar): bool =
  when future is FutureVar:
    result = (FutureBase(future)).finished
  else:
    result = future.finished

proc failed*(future: FutureBase): bool =
  ## Determines whether ``future`` completed with an error.
  return future.error != nil

proc asyncCheck*[T](future: Future[T]) =
  assert(not future.isNil, "Future is nil")
  # TODO: We can likely look at the stack trace here and inject the location
  # where the `asyncCheck` was called to give a better error stack message.
  proc asyncCheckCallback() =
    if future.failed:
      injectStacktrace(future)
      raise future.error
  future.callback = asyncCheckCallback