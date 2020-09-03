

type
  Runnable*[T] = object of RootObj
    run: RunnableProc[T]

  RunnableProc*[T] = proc (r: ref Runnable[T]): T {.nimcall, gcsafe.}

proc `run=`*[T](r: ref Runnable[T], cb: RunnableProc[T]) {.inline.} = 
  r.run = cb

proc run*[T](r: ref Runnable[T]) {.inline.} = 
  r.run(r)
