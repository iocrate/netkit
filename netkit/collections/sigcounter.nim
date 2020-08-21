
type
  SigCounter* = object of RootObj
    signalImpl*: proc (c: ptr SigCounter) {.nimcall, gcsafe.}
    waitImpl*: proc (c: ptr SigCounter): uint64 {.nimcall, gcsafe.}

proc signal*(c: ptr SigCounter) {.inline.} =
  c.signalImpl(c) 

proc wait*(c: ptr SigCounter): uint64 {.inline.} =
  c.waitImpl(c) 