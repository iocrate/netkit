
type
  SigCounterBase* = object of RootObj
    signalImpl*: proc (c: var SigCounterBase) {.nimcall, gcsafe.}
    waitImpl*: proc (c: var SigCounterBase): uint64 {.nimcall, gcsafe.}
  
  SigCounter*[T] = object of SigCounterBase
    value*: T

proc signal*(c: var SigCounterBase) {.inline.} =
  c.signalImpl(c) 

proc wait*(c: var SigCounterBase): uint64 {.inline.} =
  c.waitImpl(c) 