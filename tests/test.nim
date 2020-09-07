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


# type
#   PromiseKind* {.pure.} = enum
#     RUNNABLE, CALLABLE

#   Promise* = object
#     context: pointer
#     case kind: PromiseKind
#     of PromiseKind.RUNNABLE:
#       run: proc (context: pointer) {.nimcall, gcsafe.}
#     of PromiseKind.CALLABLE:
#       result: pointer
#       call: proc (context: pointer): pointer {.nimcall, gcsafe.}
#       then: proc (result: pointer) {.nimcall, gcsafe.}

# echo sizeof(PromiseKind)
# echo sizeof(Promise)

# type 
#   Runnable* = object of RootObj
#     run*: proc (x: ptr Runnable) {.nimcall, gcsafe.}

#   Runnable2*[T] = object
#     value: T
#     run*: proc (x: ptr Runnable) {.nimcall, gcsafe.}
  
#   Opt = object
#     a: int
#     b: int8

# var a: Runnable
# var b: Runnable2[int]
# var c: Runnable2[string]

# echo sizeof(Runnable2[Opt])

# type 
#   Runnable* = object of RootObj
#     run*: proc (x: ptr Runnable) {.nimcall, gcsafe.}

#   Test = object of Runnable
#     val: int

# proc f(r: ptr Runnable) =
#   echo "..."
#   deallocShared(cast[ptr Test](r))

# proc main() =
#   var test = cast[ptr Test](allocShared0(sizeof(Test)))
#   test.val = 100
#   # test.run = f
#   f(test)

# main()

# import cpuinfo

# var gCpus: Natural = countProcessors()
# echo gCpus

# var a: uint64 = high(uint64)
# var b: int64 = high(int64)

# echo "a:", a
# echo "b:", b

# var m = 0
# for i in b.uint64..<a:
#   m.inc()
#   if m > 10:
#     echo "c:", i
#     break

# import os 

# type
#   Obj = object
#     val: int

# proc threadFunc1(o: pointer) {.thread.} =
#   sleep(100)
#   echo "v1:", cast[ref Obj](o).val

# proc threadFunc2(o: ref Obj) {.thread.} =
#   sleep(100)
#   echo "v2:", o.val

# var thread1: Thread[pointer]
# var thread2: Thread[ref Obj]

# proc run1() =
#   var o = new(Obj)
#   o.val = 100
#   createThread(thread1, threadFunc1, cast[pointer](o))

# proc run2() =
#   var o = new(Obj)
#   o.val = 100
#   createThread(thread2, threadFunc2, o)

# proc main() = 
#   run1()
#   run2()
#   GC_fullCollect()

#   var o1 = new(Obj)
#   o1.val = 1
#   var o2 = new(Obj)
#   o2.val = 2

#   joinThread(thread1)
#   joinThread(thread2)

# main()

# type
#   Obj = object
#     val: int

# proc f() =
#   var a = Obj(val: 100)
#   var b = a.addr
#   reset(b[])
#   echo b.val
#   echo a.val

# f()

# type
#   Obj = object
#     val: int

# var container: pointer = alloc0(sizeof(pointer))

# proc f() =
#   var obj1: ref Obj = new(Obj)
#   obj1.val = 100
#   (cast[ref ref Obj](container))[] = obj1

#   # GC_ref(obj) # still necessary? If not, can arc collect garbage correctly?

# proc main() =
#   f()
#   GC_fullCollect()

#   var obj2 = new(Obj)
#   obj2.val = 1000

#   echo cast[ref ref Obj](container)[].val # Output: 100? 1000? unknown?

# main()

type
  A = object of RootObj
    val1: int
    val2: int
    val3: int16
    val4: int

echo sizeof(A)


var a: A
a.val1 = 100
echo repr offsetOf(A, val3)

echo cast[ptr A](cast[ByteAddress](a.val3.addr) - offsetOf(A, val3))[]