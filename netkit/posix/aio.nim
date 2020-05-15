#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import std/selectors
import std/nativesockets

type
  FDEvent* {.pure.} = enum
    Read, Write, Error

  SelectFD* = distinct int
  SelectTimer* = distinct int
  SelectEvent* = selectors.SelectEvent

  SelectFDCb* = proc (disp: AioDispatcher, fd: SelectFD, events: set[FDEvent]) {.closure, gcsafe.}
  SelectTimerCb* = proc (disp: AioDispatcher, timer: SelectTimer) {.closure, gcsafe.}
  SelectEventCb* = proc (disp: AioDispatcher, event: SelectEvent) {.closure, gcsafe.}
  
  AioKind {.pure.} = enum
    SelectFD, SelectTimer, SelectEvent

  AioData* = object
    case kind: AioKind
    of AioKind.SelectFD:
      fdCb: SelectFDCb
    of AioKind.SelectTimer:
      timerCb: SelectTimerCb
    of AioKind.SelectEvent:
      eventCb: SelectEventCb
      eventPtr: SelectEvent
  
  AioDispatcher* = ref object of RootRef
    # timers*: HeapQueue[tuple[finishAt: MonoTime, fut: Future[void]]]
    # callbacks*: Deque[proc () {.gcsafe.}]
    selector: Selector[AioData]

## TODO: 参考 std/asyncdispatch 提供 windows IOCP API
## TODO：添加 timer， event，兼容 [poll, select]
## TODO：添加 pending 处理，参考 asyncdispatch
## 
## timers - pendings - io 

proc registerHandle*(disp: AioDispatcher, fd: SelectFD, cb: SelectFDCb) = 
  ## 为调度器注册一个描述符 ``fd`` 。当该描述符接收到感兴趣的事件时，运行回调函数 ``data`` 。这个函数仅仅
  ## 注册描述符，并不为描述符绑定感兴趣的事件。 TODO：“事件” 这个词需要推敲一下，看看网络上有没有合适的词语替代。
  disp.selector.registerHandle(fd.int, {}, AioData(kind: AioKind.SelectFD, fdCb: cb))

proc unregisterHandle*(disp: AioDispatcher, fd: SelectFD) = 
  ## 从调度器删除一个已经注册的描述符 ``fd`` 。
  disp.selector.unregister(fd.int)

proc advertiseHandle*(disp: AioDispatcher, fd: SelectFD, events: set[FDEvent]) = 
  ## 告诉调度器，描述符 ``fd`` 对事件 ``events`` 感兴趣。接下来，只通知 ``events`` 有关的事件。
  var evs: set[Event] = {}
  if FDEvent.Read in events: evs.incl(Event.Read)
  if FDEvent.Write in events: evs.incl(Event.Write)
  if FDEvent.Error in events: evs.incl(Event.Error)
  disp.selector.updateHandle(fd.int, evs)

proc registerTimer*(disp: AioDispatcher, timeout: int, oneshot: bool, cb: SelectTimerCb): SelectTimer {.discardable.} = 
  ## 为调度器注册一个描述符 ``fd`` 。当该描述符接收到感兴趣的事件时，运行回调函数 ``data`` 。这个函数仅仅
  ## 注册描述符，并不为描述符绑定感兴趣的事件。 TODO：“事件” 这个词需要推敲一下，看看网络上有没有合适的词语替代。
  result = disp.selector.registerTimer(timeout, oneshot, AioData(kind: AioKind.SelectTimer, timerCb: cb)).SelectTimer

proc unregisterTimer*(disp: AioDispatcher, timer: SelectTimer) = 
  ## 从调度器删除一个已经注册的描述符 ``fd`` 。
  disp.selector.unregister(timer.int)

proc registerEvent*(disp: AioDispatcher, event: SelectEvent, cb: SelectEventCb) = 
  ## 为调度器注册一个描述符 ``fd`` 。当该描述符接收到感兴趣的事件时，运行回调函数 ``data`` 。这个函数仅仅
  ## 注册描述符，并不为描述符绑定感兴趣的事件。 TODO：“事件” 这个词需要推敲一下，看看网络上有没有合适的词语替代。
  disp.selector.registerEvent(event, AioData(kind: AioKind.SelectEvent, eventCb: cb, eventPtr: event))

proc unregisterEvent*(disp: AioDispatcher, event: SelectEvent) = 
  ## 从调度器删除一个已经注册的描述符 ``fd`` 。
  disp.selector.unregister(event)

proc newAioDispatcher*(): AioDispatcher = 
  new(result)
  result.selector = newSelector[AioData]()

  # proc cb(fd: AsyncFD, events: set[Event]): bool =
  #   assert events == {Event.Read}
  #   asyncdispatch.poll(0)
  # result.register(asyncdispatch.getGlobalDispatcher().getIoHandler().getFd().AsyncFD, cb)
  # result.advertise(asyncdispatch.getGlobalDispatcher().getIoHandler().getFd().AsyncFD, {Event.Read})

proc poll*(disp: AioDispatcher, timeout = 500) =
  ## 
  var keys: array[64, ReadyKey]
  var count = disp.selector.selectInto(timeout, keys)
  for i in 0..<count:
    let fd = keys[i].fd
    let events = keys[i].events
    var data: ptr AioData = addr disp.selector.getData(fd)
    case data.kind
    of AioKind.SelectFD:
      var evs: set[FDEvent] = {}
      if Event.Read in events: evs.incl(FDEvent.Read)
      if Event.Write in events: evs.incl(FDEvent.Write)
      if Event.Error in events: evs.incl(FDEvent.Error)
      data.fdCb(disp, fd.SelectFD, evs)
    of AioKind.SelectTimer:
      data.timerCb(disp, fd.SelectTimer)
    of AioKind.SelectEvent:
      data.eventCb(disp, data.eventPtr)

  # if unlikely(asyncdispatch.getGlobalDispatcher().callbacks.len() > 0):
  #   asyncdispatch.poll(0)

when isMainModule:
  var disp = newAioDispatcher()

  proc timeoutCb(disp: AioDispatcher, timer: SelectTimer) =
    echo  "timeout"

  disp.registerTimer(10, false, timeoutCb)

  disp.poll()
  disp.poll()
  disp.poll()
  disp.poll()
  disp.poll()
  disp.poll()