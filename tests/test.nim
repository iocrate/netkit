discard """
  cmd:      "nim c -r --styleCheck:hint --panics:on $options $file"
  matrix:   "--gc:arc"
  targets:  "c"
  nimout:   ""
  action:   "run"
  exitcode: 0
  timeout:  60.0
"""

#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

###############################################################
# import locks

# var count = 0
# var lock: Lock

# lock.initLock()

# proc threadFunc(i: int) {.thread.} =
#   for j in 0..<10000000:
#     # acquire(lock)
#     # count = count + 1            # 非原子操作，加锁 => 40000000
#     # release(lock)
#     discard atomicInc(count, 1)  # 原子操作，无锁 => 40000000

# proc main() = 
#   var threads: array[4, Thread[int]]

#   for i in 0..<4:
#     createThread(threads[i], threadFunc, i)

#   joinThreads(threads)
#   echo "count: ", count

# main()
###############################################################

# import os, volatile

# var a: int = 10
# var b: int

# echo "b:", b

# {.push stackTrace:off.}

# proc assign*(a: int, b: var int) {.asmNoStackFrame.} =
#   var c = b
#   asm """
#     mov %1, %%rax;
#     mov %%rax, %0;
#     :"=r"(`c`)
#     :"r"(`a`)
#     :"%rax"
#   """

#   b = c

# assign(a, b)

# {.pop.}

# echo "b:", b

# type
#   MpscQueue = object
#     data: ptr UncheckedArray[int]
#     len: int
#     cap: int
#     writeIdx: int
#     readIdx: int
#     tag: bool

# var counter = 0

# proc atomicWrite(mq: var MpscQueue, val: int) = 
#   var a = counter

#   counter.inc()
#   echo "a:", a
#   sleep(1)
#   counter.inc()

#   sleep(1)
#   var b = counter
#   echo "b:", b

#   # 1. 判断长度 = 容量，伸缩存储 (原子，一旦完成可以放开原子)
#   # 2. 添加值
#   # 3. 增加长度

#   var l = mq.len

#   # 考虑：
#   #
#   #   消费：
#   #   
#   #     readIdx++ .. [len]
#   #
#   #   生产：
#   #
#   #     [len]++ -> cap

#   var idx = atomicInc(mq.writeIdx)

#   # if idx >= mq.len:
#   #   let tag = mq.tag

#   #   if cas(mq.tag.addr, false, true):
#   #     discard
#   #     let r = cas(mq.tag.addr, true, false)
#   #     assert r
#   #   else:
#   #     echo "..."
#   #     while mq.tag:
#   #       cpuRelax()

#   #   discard

#   sleep(1)
#   # mq.data[idx] = val

#   # var i = atomicInc(mq.len)

# proc atomicRead(mq: var MpscQueue, val: int) = 
#   mq.data[0] = val

# var mq: MpscQueue
# mq.len = 4

# proc threadFunc(i: int) {.thread.} =
#   for j in 0..<1:
#     mq.atomicWrite(1)

# proc main() = 
#   var threads: array[4, Thread[int]]

#   for i in 0..<4:
#     createThread(threads[i], threadFunc, i)

#   joinThreads(threads)
#   echo "mq.writeIdx: ", mq.writeIdx

# main()


# var i = 0

# proc threadFunc0() {.thread.} =
#   sleep(10)
#   while i < 16:
#     i.inc()

# proc threadFunc1() {.thread.} =
#   while i < 8:
#     cpuRelax()
#   echo "i == 8"

# proc main() = 
#   var threads: array[2, Thread[void]]

#   createThread(threads[0], threadFunc0)
#   createThread(threads[1], threadFunc1)

#   joinThreads(threads)

# main()


# type
#   OptionDemo = object
#     val: int
#     has: bool

# var Test_demo = OptionDemo()
# var data = Test_demo.val
# echo "[R] ", data
# zeroMem(Test_demo.addr, 16) 

# import volatile

# var a: int = 1;
# var b: int = 2;
# var c: int;


# proc f() =
#   # a = b;
#   # c = 1;
#   volatileStore(a.addr, b)
#   volatileStore(c.addr, 1)

# f()

# var 
#   r: int = 0

# proc threadFunc1() {.thread.} =
#   while r != 1: 
#     continue
#   echo "Got r=2"

# proc threadFunc2() {.thread.} =
#   r = 1

# proc main() =
#   var
#     thread1: Thread[void]
#     thread2: Thread[void]

#   createThread(thread1, threadFunc1)
#   createThread(thread2, threadFunc2)

#   joinThread(thread1)
#   joinThread(thread2)

# main()


# type
#   Demo = ptr object
#     val: int
#     a: string
#     b: string
#     c: string

# proc testFunc(x: Demo): int = 
#   return x.val + 100

# proc setFunc(x: ptr Demo) = 
#   var a = testFunc(x[])
#   var b = a

# var demo = Demo()
# discard testFunc((demo.addr)[])
# setFunc(demo.addr)
