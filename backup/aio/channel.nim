
import netkit/future
import netkit/aio/loop

type
  IoChannelObj* = object of RootObj
    # fd: cint
    loop: int # TODO: 使用 EventLoopId = distinct int
    token: int

  IoChannel* = ref IoChannelObj

proc bindEventLoop*(c: IoChannel, loop: Natural) = 
  if c.loop > -1:
    raise newException(ValueError, "只能绑定一次 Loop")
  c.loop = loop
  if c.loop == current():
    discard
  else:
    discard

proc read*(c: var IoChannel) = 
  discard

proc write*(c: var IoChannel) = 
  discard

proc readv*(c: var IoChannel) = 
  discard

proc writev*(c: var IoChannel) = 
  discard

proc recv*(c: var IoChannel) = 
  discard

proc send*(c: var IoChannel) = 
  discard

proc recvfrom*(c: var IoChannel) = 
  discard

proc sendto*(c: var IoChannel) = 
  discard

proc accept*(c: var IoChannel) = 
  discard


import loop
import task

proc bindEventLoop*(c: var IoChannel) = 
  if c.loop > -1:
    raise newException(ValueError, "只能绑定一次 Loop")
  c.loop = round()
  if c.loop == current():
    discard
  else:
    discard

var chl = IoChannel()
chl.bindEventLoop()