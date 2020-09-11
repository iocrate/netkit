
import netkit/platforms/posix/linux/epoll

type
  Interest* = object # 兼容 
    value: uint32

proc initInterest*(): Interest = 
  result.value = EPOLLET.uint32 # TODO: 考虑 EPOLLET 的利弊

proc value*(interest: Interest): uint32 {.inline.} = 
  interest.value 

proc registerReadable*(interest: var Interest) {.inline.} = 
  interest.value = interest.value or EPOLLIN or EPOLLRDHUP

proc registerWritable*(interest: var Interest) {.inline.} = 
  interest.value = interest.value or EPOLLOUT

proc registerAio*(interest: var Interest) {.inline.} = 
  discard

proc registerLio*(interest: var Interest) {.inline.} = 
  discard

proc unregisterReadable*(interest: var Interest) {.inline.} = 
  interest.value = interest.value and not EPOLLIN.uint32 and not EPOLLRDHUP.uint32

proc unregisterWritable*(interest: var Interest) {.inline.} = 
  interest.value = interest.value and not EPOLLOUT.uint32 

proc unregisterAio*(interest: var Interest) {.inline.} = 
  discard

proc unregisterLio*(interest: var Interest) {.inline.} = 
  discard

proc unregister*(interest: var Interest) {.inline.} = 
  interest.value = EPOLLET.uint32

proc isReadable*(interest: Interest): bool {.inline.} =
  (interest.value and EPOLLIN) != 0 

proc isWritable*(interest: Interest): bool {.inline.} =
  (interest.value and EPOLLOUT) != 0 

proc isAio*(interest: Interest): bool {.inline.} =
  false

proc isLio*(interest: Interest): bool {.inline.} =
  false

