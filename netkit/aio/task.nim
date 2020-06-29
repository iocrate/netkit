
type
  Task* = object
    code: TaskCode
    channel: int # TODO: ChannelId token
    sourceLoop: int # TODO: EventLoopId
    destLoop: int # TODO: EventLoopId
    next*: ptr Task

  TaskCode* {.pure, size: sizeof(uint8).} = enum
    AddChannel,
    DelChannel,
    Read, 
    Write, 
    ReadV, 
    WriteV, 
    Recv, 
    Send, 
    RecvFrom, 
    SendTo, 
    Accept

