


type
  EventLoopHandle* = distinct int
  ChannelHandle* = distinct int

const 
  InvalidEventLoopHandle* = EventLoopHandle(-1)
  InvalidChannelHandle* = ChannelHandle(-1)
