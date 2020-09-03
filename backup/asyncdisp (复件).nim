#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import std/selectors
import std/nativesockets, os, net, asyncdispatch, deques

type
  AsyncFD* = distinct int
  AsyncData* = proc (fd: AsyncFD, events: set[Event]): bool {.closure.}

  AsyncDispatcher* = ref object of RootRef
    # timers*: HeapQueue[tuple[finishAt: MonoTime, fut: Future[void]]]
    # callbacks*: Deque[proc () {.gcsafe.}]
    selector: Selector[AsyncData]

## TODO: 参考 std/asyncdispatch 提供 windows IOCP API

proc register*(disp: AsyncDispatcher, fd: AsyncFD, data: AsyncData) = 
  ## 为调度器注册一个描述符 ``fd`` 。当该描述符接收到感兴趣的事件时，运行回调函数 ``data`` 。这个函数仅仅
  ## 注册描述符，并不为描述符绑定感兴趣的事件。 TODO：“事件” 这个词需要推敲一下，看看网络上有没有合适的词语替代。
  disp.selector.registerHandle(fd.SocketHandle, {}, data)

proc unregister*(disp: AsyncDispatcher, fd: AsyncFD) = 
  ## 从调度器删除一个已经注册的描述符 ``fd`` 。
  disp.selector.unregister(fd.SocketHandle)

proc advertise*(disp: AsyncDispatcher, fd: AsyncFD, events: set[Event]) = 
  ## 告诉调度器，描述符 ``fd`` 对事件 ``events`` 感兴趣。接下来，只通知 ``events`` 有关的事件。
  disp.selector.updateHandle(fd.SocketHandle, events)

proc newAsyncDispatcher*(): AsyncDispatcher = 
  new(result)
  result.selector = newSelector[AsyncData]()

  proc cb(fd: AsyncFD, events: set[Event]): bool =
    assert events == {Event.Read}
    asyncdispatch.poll(0)
  result.register(asyncdispatch.getGlobalDispatcher().getIoHandler().getFd().AsyncFD, cb)
  result.advertise(asyncdispatch.getGlobalDispatcher().getIoHandler().getFd().AsyncFD, {Event.Read})

proc poll*(disp: AsyncDispatcher) =
  ## 
  var keys: array[64, ReadyKey]
  var count = disp.selector.selectInto(-1, keys)
  for i in 0..<count:
    let fd = keys[i].fd.AsyncFD
    let events = keys[i].events
    let cb: AsyncData = disp.selector.getData(fd.SocketHandle)
    discard cb(fd, events)

  if unlikely(asyncdispatch.getGlobalDispatcher().callbacks.len() > 0):
    asyncdispatch.poll(0)

import net

var socket1 = newSocket(buffered=false)
var socket2 = newSocket(buffered=false)

socket1.bindAddr(Port(8080))
socket1.listen()
socket1.getFd().setSockOptInt(SOL_SOCKET, SO_REUSEADDR, 1)
socket1.getFd().setSockOptInt(SOL_SOCKET, SO_REUSEPORT, 1)
socket1.getFd().setBlocking(false)

socket2.getFd().setBlocking(false)
# socket2.bindAddr(Port(8081))
# socket2.listen()

var disp = newAsyncDispatcher()

proc cb1(fd: AsyncFD, events: set[Event]): bool =
  var client: Socket
  socket1.accept(client)
  echo "cb1:", events, " ", repr client.getPeerAddr()
  # sleep(10)
  # disp.advertise(socket1.getFd().AsyncFD, {Event.Read})

proc cb2(fd: AsyncFD, events: set[Event]): bool =
  echo "cb2:", repr events

disp.register(socket1.getFd().AsyncFD, cb1)
disp.register(socket2.getFd().AsyncFD, cb2)

## Tip：有意思，我发现 socket 没有进行 bind listen，于是使用 epoll 监听 socket 时立马触发 EPOLLRDHUP {Error} 事件
## 并且，由于 std/ioselectors 实现 updateHandle 时采用的水平触发，导致该事件在每次 selectInto 时都会触发。
## 如果 std/ioselectors.updateHandle 修改为 var epv = EpollEvent(events: EPOLLRDHUP or EPOLLET) 则只触发一次
## 考虑：标准库的 asynchttpserver 有没有可能因为此导致效率问题？
disp.advertise(socket1.getFd().AsyncFD, {Event.Read})
disp.advertise(socket2.getFd().AsyncFD, {Event.Write})

import posix
try:
  socket2.connect("127.0.0.1", Port(8080))
except:
  assert osLastError().cint == EINPROGRESS ## TODO: 发现 nonblocking connect 非常复杂，特别是 windows 版本，有必要封装一个函数

disp.poll()
# disp.poll()
# disp.poll()