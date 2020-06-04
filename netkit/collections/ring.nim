
type 
  RingRecord* = object of RootObj
    size: Natural
    startPos: Natural                                #  0..n-1 
    endPos: Natural                                  #  0..n-1 
    endMirrorPos: Natural                            #  0..2n-1 

proc capacity*(r: RingRecord): Natural {.inline.} = 
  ## Returns the capacity of this buffer.
  r.size

proc len*(r: RingRecord): Natural {.inline.} = 
  ## Returns the length of the data stored in this buffer.
  r.endMirrorPos - r.startPos

proc isFull*(r: RingRecord): bool {.inline.} = 
  r.endMirrorPos - r.startPos == r.size

proc isEmpty*(r: RingRecord): bool {.inline.} = 
  r.endMirrorPos == 0

proc next*(r: var RingRecord): Natural {.inline.} = 
  r.endPos

proc write*(r: var RingRecord): Natural = 
  if r.endMirrorPos - r.startPos < r.size:
    result = 1
    r.endMirrorPos = r.endMirrorPos + 1
    r.endPos = r.endMirrorPos mod r.size

proc read*(r: var RingRecord): Natural = 
  if r.endMirrorPos > 0:
    result = 1
    r.startPos = r.startPos + 1
    if r.startPos == r.size:
      r.startPos = 0
      r.endMirrorPos = r.endPos
    elif r.startPos == r.endPos:
      r.startPos = 0
      r.endPos = 0
      r.endMirrorPos = 0  

proc nextBlock*(r: var RingRecord): (Natural, Natural) = 
  result[0] = r.endPos
  result[1] = if r.endMirrorPos < r.size: r.size - r.endPos
              else: r.startPos - r.endPos

proc writeBlock*(r: var RingRecord, size: Natural): Natural = 
  if r.endMirrorPos < r.size:
    result = min(size, r.size - r.endPos) 
    r.endMirrorPos = r.endMirrorPos + result
    r.endPos = r.endMirrorPos mod r.size
  else:
    result = min(size, r.startPos - r.endPos) 
    r.endMirrorPos = r.endMirrorPos + result
    r.endPos = r.endMirrorPos mod r.size

proc readBlock*(r: var RingRecord, size: Natural): Natural = 
  if r.endMirrorPos > r.endPos:
    result = min(size, r.size - r.startPos)
    r.startPos = r.startPos + result
    if r.startPos == r.size:
      r.startPos = 0
      r.endMirrorPos = r.endPos
  else:
    result = min(size, r.endPos - r.startPos)
    r.startPos = r.startPos + result
    if r.startPos == r.endPos:
      r.startPos = 0
      r.endPos = 0
      r.endMirrorPos = 0

iterator items*(r: RingRecord): Natural =
  ## Iterates over the stored data. 
  var i = r.startPos
  while i < r.endMirrorPos:
    yield i mod r.size
    i.inc()
