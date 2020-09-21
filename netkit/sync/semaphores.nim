
type
  Semaphore* = concept 
    proc signal(c: var Self) 
    proc wait(c: var Self): uint 
