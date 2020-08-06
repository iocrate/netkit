
type
  Task = object of RootObj
    context: pointer
    run: proc (ctx: pointer) {.nimcall, gcsafe.}
    
  FeedBackTask = object of Task
    feedback: proc () {.nimcall, gcsafe.}

# spawn(task)

