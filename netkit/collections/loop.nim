
import netkit/collections/mpsc
import netkit/collections/share/vecs
import netkit/posix/linux/selector
import netkit/aio/ident

type
  Poller[T] = object
    selector: Selector
    interests: SharedVec[InterestData[T]] # 散列 handle -> data
    identManager: IdentityManager

  InterestData[T] = object
    fd: cint
    interest: Interest
    val: T

proc register*[T](p: Poller[T], fd: cint, data: InterestData[T]): Identity =
  result = p.identManager.acquire()
  var interest = initInterest()
  p.interests[result.int] = InterestData(
    fd: fd,
    interest: interest,
    readReady: false,
    readQueue: initSimpleQueue[Runnable](),
    writeQueue: initSimpleQueue[Runnable]()
  )
  p.selector.register(fd, UserData(u64: result.uint64), interest)

proc unregister(ident: Identity) =
  let w = workersData[currentThreadId].addr
  if p.interests.len > ident.int:
    # TODO: 考虑边界
    var data = p.interests[ident.int].addr
    if data.fd <= 0:
      raise newException(ValueError, "File descriptor not registered")
    reset(p.interests[ident.int]) # TODO
    p.identManager.release(ident)
    p.selector.unregister(data.fd)
  else:
    raise newException(ValueError, "边界问题")
  # TODO: 考虑 p.interests[ident.int] 内部成员的内存问题

proc updateRead(ident: Identity, runnable: Runnable) =
  let w = workersData[currentThreadId].addr
  if p.interests.len > ident.int:
    # TODO: 考虑边界
    var data = p.interests[ident.int].addr
    if data.fd <= 0:
      raise newException(ValueError, "File descriptor not registered")
    data.interest.registerReadable()
    let node = createSimpleNode[Runnable](runnable)
    data.readQueue.addLast(node)
    p.selector.update(data.fd, UserData(u64: ident.uint64), data.interest)
  else:
    raise newException(ValueError, "边界问题")

proc updateWrite(ident: Identity, runnable: Runnable) =
  let w = workersData[currentThreadId].addr
  if p.interests.len > ident.int:
    # TODO: 考虑边界
    var data = p.interests[ident.int].addr
    if data.fd <= 0:
      raise newException(ValueError, "File descriptor not registered")
    data.interest.registerWritable()
    let node = createSimpleNode[Runnable](runnable)
    data.writeQueue.addLast(node)
    p.selector.update(data.fd, UserData(u64: ident.uint64), data.interest)
    echo "...", data.writeQueue.len, " ", currentThreadId
  else:
    raise newException(ValueError, "边界问题")

