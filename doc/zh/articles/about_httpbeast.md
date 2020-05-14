# About httpbeast

我仔细研究后发现，httpbeast 不适合用于产品环境。Linux 环境也不行。httpbeast 强行把 IO 通知类型限定为 httpbeast 的 Server、Client、Dispatcher 三个。当 httpbeast 的 epoll_wait 执行时，只会检查这 3 个 IO 通知。这意味着，你无法使用其他 IO 库或者编写一些 httpbeast 无关联的 IO 函数。比如，你想在同一个线程同时运行 httpbeast server 和另一个 websocket server 或者 rpc server，是不可行的。

我写了一个简单的 disp.AsyncHttpServer，类似 httpbeast，也是直接使用 linux epoll 跑整个 IO，而不使用任何外置接口，吞吐量性能同样达到了 10 万每秒 （大概是 10.6 W Requests/sec，httpbeast 大概是 11.1 W Requests/sec -- 微小的差异仅仅在于解析的完整性 --- netkit 按照 RFC 对 SP HTAB CRLF 进行多符号解析）。看看 netkit/http/disp.AsyncHttpServer 。

将 epoll case kind(Server, Client, Dispatcher#timer#pending) 语句切换为 callback，吞吐量为 8 万每秒。