
type
  PurePointer* = ptr | pointer 

  Alloctor*[T] = object
    allocImpl: AllocFunc[T]
    deallocImpl: DeallocFunc[T]

  AllocFunc*[T] = proc (): T {.nimcall, gcsafe.}
  DeallocFunc*[T] = proc (p: T) {.nimcall, gcsafe.}

proc initAlloctor*[T: PurePointer](allocImpl: AllocFunc[T], deallocImpl: DeallocFunc[T]): Alloctor[T] =
  result.allocImpl = allocImpl
  result.deallocImpl = deallocImpl

proc alloc*[T: PurePointer](a: var Alloctor[T]): T {.inline.} =
  a.allocImpl() 

proc dealloc*[T: PurePointer](a: var Alloctor[T], p: T) {.inline.} =
  a.deallocImpl(p) 
