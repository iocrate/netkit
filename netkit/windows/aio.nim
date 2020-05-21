#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import std/winlean
import std/nativesockets
import std/os
import std/sets
import std/hashes
import std/deques
import std/heapqueue
import std/times
import std/monotimes
import std/tables

type
  AioFDEvent* {.pure.} = enum
    Read, Write, Error

  AioFD* = distinct Handle
  AioTimer* = distinct Handle
  
  AioEventObj = object
    hEvent: Handle
    hWaiter: Handle
    pcd: PostCallbackData
  AioEvent* = ptr AioEventObj

  CompletionKey = ULONG_PTR
  CompletionData = object
    fd: AioFD          
    cb: owned(proc (fd: Handle, bytesTransferred: DWORD, errcode: OSErrorCode) {.closure, gcsafe.})
    cell: ForeignCell  # we need this `cell` to protect our `cb` environment,
                       # when using RegisterWaitForSingleObject, because
                       # waiting is done in different thread.

  CustomObj = object of OVERLAPPED
    data: CompletionData
  CustomRef = ref CustomObj

  PostCallbackData = object
    ioPort: Handle
    handleFd: AioFD
    waitFd: Handle
    ovl: CustomObj

  AioFDCb* = proc (disp: AioDispatcher, fd: AioFD, events: set[AioFDEvent]) {.closure, gcsafe.}
  AioTimerCb* = proc (disp: AioDispatcher, timer: AioTimer) {.closure, gcsafe.}
  AioEventCb* = proc (disp: AioDispatcher, event: AioEvent) {.closure, gcsafe.}

  AioKind {.pure.} = enum
    FileHandle, Timer, Event

  AioData* = object
    case kind: AioKind
    of AioKind.FileHandle:
      fdPcd: PostCallbackData
      fdEvent: Handle
    of AioKind.Timer:
      timerPcd: PostCallbackData
      timerEvent: Handle
    of AioKind.Event:
      eventCb: AioEventCb
      eventPtr: AioEvent
  
  AioDispatcher* = ref object of RootRef
    # timers*: HeapQueue[tuple[finishAt: MonoTime, fut: Future[void]]]
    callbacks*: Deque[proc () {.gcsafe.}]
    ioPort: Handle
    handles: Table[int, ref AioData]

## TODO: 参考 std/asyncdispatch 提供 windows IOCP API
## TODO：添加 timer， event，兼容 [poll, select]
## TODO：添加 pending 处理，参考 asyncdispatch
## 
## timers - pendings - io 
## 
proc newCustom*(): CustomRef =
  result = CustomRef() # 0
  GC_ref(result) # 1  prevent destructor from doing a premature free.
  # destructor of newCustom's caller --> 0. This means
  # Windows holds a ref for us with RC == 0 (single owner).
  # This is passed back to us in the IO completion port.

{.push stackTrace: off.}
proc waitableCallback(pcd: pointer, timerOrWaitFired: WINBOOL) {.stdcall.} =
  var p = cast[ptr PostCallbackData](pcd)
  discard postQueuedCompletionStatus(
    p.ioPort, 
    timerOrWaitFired.DWORD,
    ULONG_PTR(p.handleFd), 
    cast[pointer](p.ovl.addr)
  )
{.pop.}

proc registerHandle*(disp: AioDispatcher, fd: AioFD, cb: AioFDCb) = 
  ## 为调度器注册一个描述符 ``fd`` 。当该描述符接收到感兴趣的事件时，运行回调函数 ``data`` 。这个函数仅仅
  ## 注册描述符，并不为描述符绑定感兴趣的事件。 TODO：“事件” 这个词需要推敲一下，看看网络上有没有合适的词语替代。
  if createIoCompletionPort(fd.Handle, disp.ioPort, cast[CompletionKey](fd), 1) == 0:
    raiseOSError(osLastError())
  let data = new(AioData)
  data.kind = AioKind.AioFD

  var hEvent = wsaCreateEvent()
  if hEvent == 0:
    raiseOSError(osLastError())
  data.fdEvent = hEvent

  proc cdataCb(fd: AioFD, bytesCount: DWORD, errcode: OSErrorCode) {.gcsafe.} =
    # unregisterWait() is called before callback, because appropriate
    # winsockets function can re-enable event.
    # https://msdn.microsoft.com/en-us/library/windows/desktop/ms741576(v=vs.85).aspx
    if unregisterWait(data.fdPcd.waitFd) == 0:
      let err = osLastError()
      if err.int32 != ERROR_IO_PENDING:
        raiseOSError(err)
    cb(disp, fd, {})

  data.fdPcd.ioPort = disp.ioPort
  data.fdPcd.handleFd = fd
  data.fdPcd.ovl = CustomObj()
  # We need to protect our callback environment value, so GC will not free it
  # accidentally.
  data.fdPcd.ovl.data = CompletionData(fd: fd, cb: cdataCb, cell: system.protect(rawEnv(data.fdPcd.ovl.data.cb)))
  
  disp.handles[fd.int] = data

proc unregisterHandle*(disp: AioDispatcher, fd: AioFD) = 
  ## 从调度器删除一个已经注册的描述符 ``fd`` 。
  if not wsaCloseEvent(disp.handles[fd.int].fdEvent):
    raiseOSError(osLastError())
  disp.handles.del(fd.int)

proc advertiseHandle*(disp: AioDispatcher, fd: AioFD, events: set[AioFDEvent]) = 
  ## 告诉调度器，描述符 ``fd`` 对事件 ``events`` 感兴趣。接下来，只通知 ``events`` 有关的事件。
  var mask: DWORD = 0
  if AioFDEvent.Read in events: mask = FD_READ or FD_ACCEPT or FD_OOB or FD_CLOSE
  if AioFDEvent.Write in events: mask = FD_WRITE or FD_CONNECT or FD_CLOSE
  if AioFDEvent.Error in events: mask = 0

  # doAssert disp.handles.contains(fd.int)
  let data = disp.handles[fd.int]
  let flags: DWORD = WT_EXECUTEINWAITTHREAD or WT_EXECUTEONLYONCE

  # This is main part of `hacky way` is using WSAEventSelect, so `hEvent`
  # will be signaled when appropriate `mask` events will be triggered.
  if wsaEventSelect(fd.SocketHandle, data.fdEvent, mask) != 0:
    raiseOSError(osLastError())

  if not registerWaitForSingleObject(
    data.fdPcd.waitFd.addr, 
    data.fdEvent, 
    cast[WAITORTIMERCALLBACK](waitableCallback),
    data.fdPcd.addr, 
    INFINITE, 
    flags
  ):
    raiseOSError(osLastError())

proc registerTimer*(disp: AioDispatcher, timeout: int, oneshot: bool, cb: AioTimerCb): AioTimer {.discardable.} = 
  ## 为调度器注册一个描述符 ``fd`` 。当该描述符接收到感兴趣的事件时，运行回调函数 ``data`` 。这个函数仅仅
  ## 注册描述符，并不为描述符绑定感兴趣的事件。 TODO：“事件” 这个词需要推敲一下，看看网络上有没有合适的词语替代。
  var hEvent = createEvent(nil, 1, 0, nil)
  if hEvent == INVALID_HANDLE_VALUE:
    raiseOSError(osLastError())
  
  let data = new(AioData)
  data.kind = AioKind.AioTimer
  data.timerEvent = hEvent
  
  proc cdataCb(fd: AioFD, bytesCount: DWORD, errcode: OSErrorCode) {.gcsafe.} =
    # unregisterWait() is called before callback, because appropriate
    # winsockets function can re-enable event.
    # https://msdn.microsoft.com/en-us/library/windows/desktop/ms741576(v=vs.85).aspx
    cb(disp, fd.AioTimer)
    if oneshot:
      let waitFd = data.fdPcd.waitFd
      if unregisterWait(waitFd) == 0:
        let err = osLastError()
        if err.int32 != ERROR_IO_PENDING:
          discard closeHandle(data.timerEvent)
          raiseOSError(err)
      if closeHandle(data.timerEvent) == 0:
        raiseOSError(osLastError())

  data.fdPcd.ioPort = disp.ioPort
  data.fdPcd.handleFd = hEvent.AioFD
  data.fdPcd.ovl = CustomObj()
  # We need to protect our callback environment value, so GC will not free it
  # accidentally.
  data.fdPcd.ovl.data = CompletionData(fd: hEvent.AioFD, cb: cdataCb, cell: system.protect(rawEnv(data.fdPcd.ovl.data.cb)))
  var flags = WT_EXECUTEINWAITTHREAD.DWORD
  if oneshot: flags = flags or WT_EXECUTEONLYONCE
  if not registerWaitForSingleObject(data.fdPcd.waitFd.addr, hEvent,
                                     cast[WAITORTIMERCALLBACK](waitableCallback),
                                     data.fdPcd.addr, timeout.DWORD, flags):
    let err = osLastError()
    discard closeHandle(hEvent)
    raiseOSError(err)
  disp.handles[hEvent.int] = data

proc unregisterTimer*(disp: AioDispatcher, timer: AioTimer) = 
  ## 从调度器删除一个已经注册的描述符 ``fd`` 。
  if closeHandle(disp.handles[timer.int].timerEvent) == 0:
    raiseOSError(osLastError())
  disp.handles.del(timer.int)

proc registerEvent*(disp: AioDispatcher, event: AioEvent, cb: AioEventCb) = 
  ## 为调度器注册一个描述符 ``fd`` 。当该描述符接收到感兴趣的事件时，运行回调函数 ``data`` 。这个函数仅仅
  ## 注册描述符，并不为描述符绑定感兴趣的事件。 TODO：“事件” 这个词需要推敲一下，看看网络上有没有合适的词语替代。
  let hEvent = event.hEvent

  let data = new(AioData)
  data.kind = AioKind.AioEvent

  proc cdataCb(fd: AioFD, bytesCount: DWORD, errcode: OSErrorCode) =
    if event.hWaiter != 0:
      cb(disp, event)
      if event.hWaiter != 0:
        disp.handles.del(event.hEvent.int)
        if unregisterWait(event.hWaiter) == 0:
          let err = osLastError()
          if err.int32 != ERROR_IO_PENDING:
            raiseOSError(err)
        event.hWaiter = 0

  data.fdPcd.ioPort = disp.ioPort
  data.fdPcd.handleFd = hEvent.AioFD
  data.fdPcd.ovl = CustomObj()
  # We need to protect our callback environment value, so GC will not free it
  # accidentally.
  data.fdPcd.ovl.data = CompletionData(fd: hEvent.AioFD, cb: cdataCb, cell: system.protect(rawEnv(data.fdPcd.ovl.data.cb)))
  
  var flags = WT_EXECUTEINWAITTHREAD.DWORD
  if not registerWaitForSingleObject(data.fdPcd.waitFd.addr, hEvent,
                                     cast[WAITORTIMERCALLBACK](waitableCallback),
                                     data.fdPcd.addr, INFINITE, flags):
    let err = osLastError()
    discard closeHandle(hEvent)
    raiseOSError(err)
  disp.handles[hEvent.int] = data
  
  event.hWaiter = data.fdPcd.waitFd

proc unregisterEvent*(disp: AioDispatcher, event: AioEvent) = 
  ## 从调度器删除一个已经注册的描述符 ``fd`` 。
  disp.handles.del(event.hEvent.int)
  if unregisterWait(event.hWaiter) == 0:
    let err = osLastError()
    if err.int32 != ERROR_IO_PENDING:
      raiseOSError(err)
  event.hWaiter = 0

proc newAioEvent*(): AioEvent =
  ## Creates a new thread-safe ``AioEvent`` object.
  ##
  ## New ``AioEvent`` object is not automatically registered with
  ## dispatcher like ``AsyncSocket``.
  var sa = SECURITY_ATTRIBUTES(
    nLength: sizeof(SECURITY_ATTRIBUTES).cint,
    bInheritHandle: 1
  )
  var event = createEvent(addr(sa), 0'i32, 0'i32, nil)
  if event == INVALID_HANDLE_VALUE:
    raiseOSError(osLastError())
  result = cast[AioEvent](allocShared0(sizeof(AioEventImpl)))
  result.hEvent = event

proc trigger*(event: AioEvent) =
  ## Set event ``ev`` to signaled state.
  if setEvent(event.hEvent) == 0:
    raiseOSError(osLastError())

proc close*(event: AioEvent) =
  ## Closes event ``ev``.
  let res = closeHandle(event.hEvent)
  deallocShared(cast[pointer](event))
  if res == 0:
    raiseOSError(osLastError())



# proc newAioDispatcher*(): AioDispatcher = 
#   new(result)
#   result.ioPort = createIoCompletionPort(INVALID_HANDLE_VALUE, 0, 0, 1)
#   result.handles = initHashSet[AioFD]()
#   # result.timers.newHeapQueue()
#   result.callbacks = initDeque[proc () {.closure, gcsafe.}](64)

#   # proc cb(fd: AsyncFD, events: set[Event]): bool =
#   #   assert events == {Event.Read}
#   #   asyncdispatch.poll(0)
#   # result.register(asyncdispatch.getGlobalDispatcher().getIoHandler().getFd().AsyncFD, cb)
#   # result.advertise(asyncdispatch.getGlobalDispatcher().getIoHandler().getFd().AsyncFD, {Event.Read})

# proc poll*(disp: AioDispatcher, timeout = 500) =
#   ## 
#   var keys: array[64, ReadyKey]
#   var count = disp.selector.selectInto(timeout, keys)
#   for i in 0..<count:
#     let fd = keys[i].fd
#     let events = keys[i].events
#     var data: ptr AioData = addr disp.selector.getData(fd)
#     case data.kind
#     of AioKind.AioFD:
#       var evs: set[AioFDEvent] = {}
#       if Event.Read in events: evs.incl(AioFDEvent.Read)
#       if Event.Write in events: evs.incl(AioFDEvent.Write)
#       if Event.Error in events: evs.incl(AioFDEvent.Error)
#       data.fdCb(disp, fd.AioFD, evs)
#     of AioKind.AioTimer:
#       data.timerCb(disp, fd.AioTimer)
#     of AioKind.AioEvent:
#       data.eventCb(disp, data.eventPtr)

#   # if unlikely(asyncdispatch.getGlobalDispatcher().callbacks.len() > 0):
#   #   asyncdispatch.poll(0)