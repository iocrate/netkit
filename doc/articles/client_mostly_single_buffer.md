### A new streaming mode of asynchronous non blocking IO for Nim

**Mostly Single Buffer**, more accurately **Mostly Single Buffer one connection**, means that most of the time, a connection always uses one buffer. In other words, there will be a situation where one connection uses two or more buffers.

The goal of Mostly Single Buffer is to provide absolute IO consistency, as much as possible to ensure IO performance and reduce memory footprint, while minimizing the impact on user programming efficiency.

When programming network IO, we usually have to deal with various protocol encapsulated data. In the case of HTTP, these data are encapsulated in "Request" (Request) units. For the same client connection, the process of sending HTTP packets is similar to this:

    |---request 1---|---request 2---|---request 3---|

The figure above shows that the client has sent 3 requests. HTTP requests sent by the same client are always continuous. From the server's perspective, the server creates a "buffer" for each client, reads the requested data into the buffer, processes it, and then responds. Generally, the server's attitude towards the buffer is to create a separate buffer for each client connection. In other words, if there are 2000 clients connected to the server at the same time, the server usually has 2000 buffers, corresponding to each client. For each client, the server uses a completely independent buffer processing, which ensures IO consistency, that is, the processing of each client will not cross together; at the same time, it also means more memory consumption, each buffer must occupy a piece of memory.

Now, turn the perspective back to the client. As a client, it usually establishes a connection to the server, and then continue to initiate requests. Let's talk about MySQL connection, which will be very representative, especially when it comes to asynchronous non-blocking IO, its internal operation process will become very heavy load and unstable. Look at the following pseudo code (1):

```nim
var mysql = newMysqlClient()

await mysql.query("select * from users") # first request
await mysql.query("select * from blogs") # second request
```

This code initiates two query requests. It should be noted that `` await`` waits for the completion of the first request before initiating the second request. Please see the pseudocode (2) below:

```nim
var mysql = newMysqlClient()

var req1 = mysql.query("select * from users") # first request
var req2 = mysql.query("select * from blogs") # second request

await req1
await req2
```

Now, we still initiates two query requests. The difference is that the second request starts before the first request is processed. The same is to wait for the first response to complete first, then wait for the second response to complete. Again, let’s look at the following pseudocode (3):

```nim
var mysql = newMysqlClient()

var req1 = mysql.query("select * from users") # first request
var req2 = mysql.query("select * from blogs") # second request

await req2
await req1
```

This code first waits for the second response to complete, then waits for the first response to complete.

The three pseudocodes above perform the same operation, but the impact involved is far different. As mentioned above, the server will create a buffer for each client connection, so what about the client? The usual method is that the client creates a buffer for each connection. It is unnecessary to create multiple buffers, because each connection can only handle one problem at a time, and additional buffers are usually wasted.

However, the above three pseudo-codes will involve many problems. We now assume that there is only one buffer in the client connection of MySQL, and two query requests are issued, then the returned result is this:

    |---response 1---|---response 2---|

The result is that they are sequentially arranged in the same buffer.

For the pseudocode (1), this will not cause a problem, because it always waits for the first response to complete before processing the second response; the pseudocode (2) also does not constitute a problem, because its processing of the response is similar to Pseudo code (1). However, for the pseudocode (3), a big problem arises because it waits for the second response to complete before processing the first response. This means that response 2 will not be processed and response 1 will not be processed. Looking at the picture above, because response 1 and response 2 are stored in the same buffer in sequence, this causes response 2 to get the operation only after response 1 is fetched from the buffer. "Deadlock" has occurred!

This is a bit like the "deadlock" often mentioned in multi-threaded programming. Lock A is locked before lock B, but the program handles lock B first, resulting in a "deadlock." Asynchronous non-blocking IO does not have the concept of locks, but there is also a "deadlock" problem here. This is because of the problem of `` await``. ` await`  splits one line of program operation into two lines, turning the original one-time processing into two processing, "destroying" the atomic operation. However, we can’t force users to always write `` await`` as a line, and when dealing with large data streams, we must also use `` await`` multiple times to process "small blocks" of data. Take a look at this pseudo code:

```nim
var stream = mysql.queryLargeResult(...)

while stream.next():
  await stream.readRow()
```

However, the problem always has to be solved. Recalling the server's attitude towards buffers, we may want to use the same idea to create a separate buffer for each request. Well, the solution for client IO is that for each client connection, instead of creating a separate buffer, each request creates a separate buffer. Look at the following pseudo code:

```nim
var mysql = newMysqlClient()

var req1 = mysql.query("select * from users") # first request
var req2 = mysql.query("select * from blogs") # second request
var req3 = mysql.query("select * from blogs") # third request
var req4 = mysql.query("select * from blogs") # fourth reequest

await req2
await req1
await req4
await req3
```

The above code creates 4 independent buffers, but they are all located on the same client connection.

However, this also brings a problem, that is, the memory is heavily occupied and wasted, because at each moment, the client has only one buffer is useful. Especially when you build a Web Server and then perform some MySQL queries on HTTP requests, your server memory starts to soar. This may not be what you want.

Mostly Single Buffer expects to solve these problems. When the client establishes network IO, for each connection, the solution creates only one buffer as much as possible, and uses a tag to mark whether the buffer is in the "busy" state or in the "free" state. When in the "busy" state, if a new request operation is received, a new buffer is automatically created. When a "busy" buffer becomes "free" again, it is automatically recovered.

Dump: If the user applies for multiple requests for the same connection, when processing the response, the `MSB`(Mostly Single Buffer) will view the read operation provided by the user. For example, to initiate a request [q1, q2, q3], after the `MSB` receives the response data, check the request queue, first query the read operation of q1, and then use the read operation to process the data. If all the read operations of q1 are completed, the response data of q1 If it is still not completely "read", then the `MSB` will "dump" and pour the remaining data of q1 into a new buffer for temporary storage, so that the subsequent q1 related read operations can be processed. Then process q2, q3, ... in turn, which will naturally form a situation where the remaining data and references of q1, q2, q3 will be temporarily stored in memory until the memory overflows. `` .clear (q1) `` allows immediate clearing of q1 related response data.

With **Mostly Single Buffer**, if you are an experienced programmer, you can always arrange your program reasonably, that is, `` await '' every request at a reasonable time, then you can always minimize the memory usage of the buffer. For example only create a buffer.

```nim
var req1 = mysql.query("select * from users")    # first request
await req1

var req2 = mysql.query("select * from blogs")    # second request
await req2

var req3 = mysql.query("select * from comments") # third request
await req3
```

And if you are not skilled enough in IO programming, or the programming program is more casual, Mostly Single Buffer can always ensure that your program runs correctly, but it will consume some memory. For example (create three buffers):

```nim
var req1 = mysql.query("select * from users")    # first request
var req2 = mysql.query("select * from blogs")    # second request
var req3 = mysql.query("select * from comments") # third request

await req3
await req1
await req2
```

This IO buffer solution will be applied to [netkit](https://github.com/iocrate/netkit) Nim Network toolkit that is actively being developed, as well as some other network packages, such as MySQL connector. By the way, [asyncmysql](https://github.com/tulayang/asyncmysql) uses a callback function to deal with IO consistency issues, but it makes API calls more difficult to use, and future connectors will be changed.

Enjoy yourself! :)
