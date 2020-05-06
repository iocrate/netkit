import asyncnet
import asyncdispatch

proc main() {.async.} =
  let client = await asyncnet.dial("127.0.0.1", Port(8080))
  await client.send("""
GET /iocrate/netkit HTTP/1.1
Host: iocrate.com
Content-Length: 12

foobarfoobar""")
  # let statusLine = await client.recvLine()
  # let contentLenLine = await client.recvLine()
  # let crlfLine = await client.recvLine()
  # let body = await client.recv(12)
  # client.close()

waitFor main()