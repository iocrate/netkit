# 这个文件只是一个参考策略，请忽略 !!!!!!!!!!!!!!!!!!!!!!!!!!!

import asyncdispatch

# proc do1Async() {.async.} =
#   await sleepAsync(1000)
#   echo 1000

# proc do2Async() {.async.} =
#   await sleepAsync(2000)
#   echo 2000

# proc main = 
#   var f1 = do1Async()
#   var f2 = do2Async()

#   f2.callback = proc () =
#     echo "f2 end"
#     sleepAsync(2000).callback = proc() =
#       f1.callback = proc () =
#         echo "f1 end"

var buffer = @[1, 2, 3, 4, 5, 6, 7, 8]

type 
  Reader = ref object
    buffer: seq[int]
    queryLen: int

  QueryResult = ref object
    data: seq[int]
    futures: seq[Future[int]]
    hasData: bool

var reader: Reader = new(Reader)
reader.buffer = @[]
reader.queryLen = 0

proc notify(r: QueryResult) =
  if r.hasData:      # 判断是否进行数据处理，有必要
    for fut in r.futures:
      fut.complete(1)
    r.futures = @[]

proc query(r: Reader): QueryResult = 
  var a = new(QueryResult)
  a.futures = @[]
  a.hasData = false
  result = a
  var f = sleepAsync(1000)
  f.callback = proc () = 
    r.buffer = @[1,2,3,4,5,6,7,8]
    r.queryLen = 1
    a.data = r.buffer
    a.hasData = true # 使用一个字段判断数据是否填充，以避免 notify 时重复操作
    a.notify()       # 通知，开始处理数据

proc read(r: QueryResult): Future[int] =
  var future = newFuture[int]()
  result = future
  r.futures.add(future)
  r.notify()         # 每次都要 notify 一下，以防止 await 顺序混乱导致没有回调被处理  

proc main() {.async.} = 
  var stream1 = reader.query()
  var stream2 = reader.query()

  var f2 = stream2.read()
  var f3 = stream2.read()

  var r2 = await f2
  var r3 = await f3

  var r1 = await stream1.read()

  echo "r1:", r1
  echo "r2:", r2
  echo "r3:", r3

# proc read(r: QueryResult): Future[int] {.async.} = 


# proc query(buffer: seq[int]): Stream =
#   result = new(Stream)
#   result.buffer = buffer
#   result.startPos = startPos

# proc read(s: Stream): Future[int] = 
#   var future = newFuture[int]()

#   if buffer.len 

#   sleepAsync(2000).callback = proc() =
#     result = s.buffer[s.startPos]
#     s.startPos.inc()

# proc main() {.async.} = 
#   var stream1 = buffer.query()
#   var stream2 = buffer.query()

#   var r1 = await stream2.read() # 5
#   var r2 = await stream2.read() # 6

#   echo r1
#   echo r2

#   var r3 = await stream1.read() # 1
#   var r4 = await stream1.read() # 2

#   echo r3
#   echo r4


asyncCheck main()
runForever()
