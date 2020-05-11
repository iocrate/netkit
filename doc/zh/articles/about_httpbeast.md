# About httpbeast

我仔细研究后发现，httpbeast 不适合用于产品环境。Linux 环境也不行。httpbeast 强行把 IO 通知类型限定为 httpbeast 的 Server、Client、Dispatcher 三个。当 httpbeast 的 epoll_wait 执行时，只会检查这 3 个 IO 通知。这意味着，你无法使用其他 IO 库或者编写一些 httpbeast 无关联的 IO 函数。比如，你想在同一个线程同时运行 httpbeast server 和另一个 websocket server 或者 rpc server，是不可行的。


