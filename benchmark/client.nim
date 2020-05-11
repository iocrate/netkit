import asyncnet
import asyncdispatch

proc main() {.async.} =
  let client = await asyncnet.dial("127.0.0.1", Port(8080))

  for i in 1..1000:
    echo $i
    await client.send("""
GET /iocrate/netkit HTTP/1.1
Host: iocrate.com
Content-Length: 6

foobar

GET /iocrate/netkit HTTP/1.1
Host: iocrate.com
Content-Length: 12

foobarfoobar""")
    await sleepAsync(10)
  client.close()

waitFor main()