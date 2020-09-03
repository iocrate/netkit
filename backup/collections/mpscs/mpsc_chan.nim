when isMainModule:
  type 
    Task = object
      val: int
      val1: int
      val2: int
      val3: int
      val4: int
      val5: int
      val6: int

  proc createTask(val: int): ptr Task =
    result = cast[ptr Task](allocShared0(sizeof(Task)))
    result.val = val

  proc destroy(t: ptr Task) =
    deallocShared(t)

  var counter = 0
  var sum = 0
  var chan: Channel[ptr Task]

  proc producer2Func() {.thread.} =
    for i in 1..1000000:
      chan.send(createTask(i)) 

  proc consumer2Func() {.thread.} =
    while counter < 4000000:
      var task = chan.recv()
      if task != nil:
        counter.inc()
        sum.inc(task.val)
        task.destroy()

  proc test() = 
    var producers: array[4, Thread[void]]
    var comsumer: Thread[void]
    chan.open(16384)
    for i in 0..<4:
      createThread(producers[i], producer2Func)
    createThread(comsumer, consumer2Func)
    joinThreads(producers)
    joinThreads(comsumer)
    chan.close()
    doAssert sum == ((1 + 1000000) * (1000000 div 2)) * 4 # (1 + n) * n / 2

  test()




  