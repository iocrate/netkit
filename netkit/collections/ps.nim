type
  OptionDemo {.pure.} = object
    val1: int
    val2: char

var queue: array[2, OptionDemo]

var w = 0
var r = 0

proc produceRun() {.thread.} =
  var newW: int
  for i in 0..60000:
    newW = (w + 1) and 1
    while newW == r:
      cpuRelax()
      
    queue[w] = OptionDemo(val1: i) 
    w = newW

  echo "produceRun() finished"

proc consumeRun() {.thread.} =
  var final = 0
  while final < 60000:
    while r == w:
      cpuRelax()
    
    final = queue[r].val1
    echo "[R] r=", r, " w=", $w, " val=", queue[r]   
    r = (r + 1) and 1
  
  echo "consumeRun() finished"
  doAssert final == 60000
    
proc main() = 
  var producer: Thread[void]
  var comsumer: Thread[void]
  createThread(producer, produceRun)
  createThread(comsumer, consumeRun)
  joinThread(producer)
  joinThread(comsumer)
  echo "main exit"

main()