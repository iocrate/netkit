客户端异步非阻塞 IO 新的流模式 Mostly Single Buffer 
===============================================

> PS: 最新更新，最多增加一个缓冲区，并支持自动伸缩，直到某个极限然后抛出异常并关闭连接。

> PS: 服务器的写操作将支持 MSB。

> PS: 这篇文章描述的是比较底层的内容，主要设计传输层，而不是应用层。我不打算对传输层的知识做过多讨论，然而，如果你只是对应用层感兴趣，你仍然可以读读，并在文章最后了解这个模式对应用层的收益。

Mostly Single Buffer 更精确点应该是 Mostly Single Buffer one connection，意思是：大多数时候，一个连接总是使用一个缓冲区。也就是说，会存在这样的情况，即一个连接使用两个甚至更多个缓冲区。

Mostly Single Buffer 的目标是提供绝对的 IO 一致性，并尽可能保证 IO 性能和减少内存占用，而最小化对用户编程效率的影响。

在对网络 IO 进行编程时，我们通常要处理各种各样的协议封装数据。拿 HTTP 来说，这些数据是以 “请求” (Request) 为单元进行封装的。对于同一个客户端连接，其发送 HTTP 数据包的过程类似这样：

    |---request 1---|---request 2---|---request 3---|

上面图中表示，客户端发送了 3 个请求。同一个客户端发送的 HTTP 请求总是连续的。站在服务器的视角，服务器会为每一个客户端创建一个 “缓冲区”，将请求数据读入缓冲区，进行处理，然后作出响应。通常，服务器对于缓冲区的态度是，对每个客户端连接创建一个独立的缓冲区。也就是说，如果同时有 2000 个客户端连接到服务器，服务器通常会有 2000 个缓冲区，分别对应每一个客户端。对于每一个客户端，服务器都使用一个完全独立的缓冲区处理，这就保证了 IO 一致性，即各个客户端的处理不会交叉在一起；同时，也意味着更多的内存占用，每一个缓冲区都要占用一块内存。

现在，把视角转回客户端。作为客户端，通常向服务器建立一个连接，然后不断发起请求。让我们谈谈 MySQL 连接，这会非常有代表性，特别是涉及到异步非阻塞 IO 时，其内部的操作过程会变得非常负载和不稳定。看看下面这段伪代码 (1)：

```nim
var mysql = newMysqlClient()

await mysql.query("select * from users") # 第一个请求
await mysql.query("select * from blogs") # 第二个请求
```

这段代码发起了两次查询请求，需要注意的是 ``await`` 适时地等待第一个请求完成，然后才发起第二个请求。请看下面伪代码(2)：

```nim
var mysql = newMysqlClient()

var req1 = mysql.query("select * from users") # 第一个请求
var req2 = mysql.query("select * from blogs") # 第二个请求

await req1
await req2
```

仍是发起两次查询请求，不同之处在于，第二个请求还没等第一个请求处理完成，就开始发起。相同的是，先等待第一个响应完成，然后等待第二个响应完成。再请看下面伪代码(3)：

```nim
var mysql = newMysqlClient()

var req1 = mysql.query("select * from users") # 第一个请求
var req2 = mysql.query("select * from blogs") # 第二个请求

await req2
await req1
```

这段代码先等待第二个响应完成，然后等待第一个响应完成。

以上三段伪代码执行了相同的操作，但是其涉及的影响却远远不同。上面说过，服务器会为每一个客户端连接创建一个缓冲区，那么客户端呢？通常的方法是，客户端为每一个连接创建一个缓冲区。创建多个缓冲区是没有必要的，因为每个连接一次只能处理一个问题，额外的缓冲区通常都是浪费。

然而，上面三段伪代码会牵扯出很多问题。我们现在假设 mysql 的客户端连接只有一个缓冲区，发出两个查询请求，那么返回来的结果则是这样的：

    |---response 1---|---response 2---|

结果是顺序排列在同一个缓冲区当中。

对于伪代码(1)，这不会产生问题，因为总是先等待第一个响应完成，再处理第二个响应；伪代码(2)，也构不成问题，因为其对响应的处理，类似伪代码(1)。然而，对于伪代码(3)，却产生了大问题，因为其先等待第二个响应完成，然后再处理第一个响应。这就表示，响应 2 不处理完成，响应 1 就不会处理。看看上图，因为响应 1 和响应 2 被顺序存储到同一个缓冲区，这就导致只有响应 1 从缓冲区提取后，响应 2 才会获得操作。“死锁” 产生了！

这有点像多线程编程中常常提到的 “死锁”，锁 A 先于锁 B 锁住，然而程序却先处理锁 B，导致 “死锁”。异步非阻塞 IO 并没有锁的概念，然而在此处却也产生了 “死锁” 的问题。这是因为 ``await`` 的问题。``await`` 将一行程序操作拆成了两行，将原来本可以一次处理变成了两次处理，“破坏了” 原子操作。然而，我们不能强制要求用户总是将 ``await`` 写作一行，而且，当处理大数据流的时候，我们还必须使用多次 ``await`` 来处理 “小块” 数据。看看这段伪代码：

```nim
var stream = mysql.queryLargeResult(...)

while stream.next():
  await stream.readRow()
```

然而，问题总要解决。回想起服务器对于缓冲区的态度，我们可以想要使用同样的思路，为每一次请求创建一块单独的缓冲区。好了，客户端 IO 的解决方法是，对于每一个客户端连接，不再是创建一个单独的缓冲区，而是每一个请求创建一个单独的缓冲区。看看下面的伪代码：

```nim
var mysql = newMysqlClient()

var req1 = mysql.query("select * from users") # 第一个请求
var req2 = mysql.query("select * from blogs") # 第二个请求
var req3 = mysql.query("select * from blogs") # 第二个请求
var req4 = mysql.query("select * from blogs") # 第二个请求

await req2
await req1
await req4
await req3
```

上面的代码创建 4 块独立的缓冲区，但是它们都是位于同一个客户端连接。

不过，这也同时带来问题，即内存被大量的占用，而且被浪费，因为在每一时刻，客户端只有一块缓冲区是有用的。特别是当你建立一个 Web Server，然后对 HTTP 请求进行一些 Mysql 查询时，你的服务器内存开始飙升。这可能不是你所想要的。

Mostly Single Buffer 期望解决这些问题。客户端建立网络 IO 时，对每一个连接，该方案尽可能只创建一块缓冲区，并使用一个标记，标记该缓冲区是处于 “忙” 状态，还是处于 “空闲” 状态。当处于 “忙”状态时，如果收到新的请求操作，则自动创建一块新的缓冲区。当一块 “忙” 缓冲区重新变为 “空闲” 的时候，自动将其回收。

倾倒：如果用户对同一连接申请了多个请求，当处理响应的时候，MSB 会查看用户提供的读操作。比如发起请求 [q1, q2, q3]，MSB 收到响应数据后，查看请求队列，先查询 q1 的读操作，然后使用读操作处理数据，如果 q1 的所有读操作都工作完，q1 的响应数据仍然未完全 “读” 完，那么 MSB 就进行 “倾倒”，将 q1 剩余的数据倒入一块新的缓冲区暂存起来，以便于后续 q1 的相关读操作进行处理。然后依次处理 q2，q3，... 这自然会形成一种情况，即 q1、q2、q3 剩余的数据及其引用会一直暂存在内存，直到内存溢出。``.clear(q1)`` 允许立刻清除 q1 相关响应数据。

使用 Mostly Single Buffer，如果你是经验丰富的程序员，总能合理安排你的程序，即在合理时刻 ``await`` 每一个请求，那么你总能最小化缓冲区的内存占用。比如 (只创建一块缓冲区) ：

```nim
var req1 = mysql.query("select * from users")    # 第一个请求
await req1

var req2 = mysql.query("select * from blogs")    # 第二个请求
await req2

var req3 = mysql.query("select * from comments") # 第三个请求
await req3
```

而如果你对 IO 编程掌握还不够熟练，或者编程的程序比较随意，Mostly Single Buffer 总能保证你的程序正确运行，但是会消耗一些内存。比如 (创建三块缓冲区)：

```nim
var req1 = mysql.query("select * from users")    # 第一个请求
var req2 = mysql.query("select * from blogs")    # 第二个请求
var req3 = mysql.query("select * from comments") # 第三个请求

await req3
await req1
await req2
```

这个 IO 缓冲区方案将会应用在 [netkit](https://github.com/iocrate/netkit) --- 一个正在积极开发的 Nim Network 工具包，以及其他的一些网络包中，比如 mysql connector。顺便一提的是，[asyncmysql](https://github.com/tulayang/asyncmysql) 使用了回调函数来处理 IO 一致性问题，但是却导致 API 调用比较难以使用，未来的连接器将会获得改善。

Enjoy yourself! :)