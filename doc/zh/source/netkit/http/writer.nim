#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 

import strutils
import asyncdispatch
import nativesockets
import netkit/locks 
import netkit/http/base 
import netkit/http/exception
import netkit/http/connection

type
  HttpWriter* = ref object of RootObj ##
    conn: HttpConnection
    lock: AsyncLock
    onEnd: proc () {.gcsafe, closure.}
    writable: bool

  ServerResponse* = ref object of HttpWriter ## 
  ClientRequest* = ref object of HttpWriter ## 

proc newServerResponse*(conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}): ServerResponse = discard
  ##

proc newClientRequest*(conn: HttpConnection, onEnd: proc () {.gcsafe, closure.}): ClientRequest = discard
  ##

proc ended*(writer: HttpWriter): bool {.inline.} = discard
  ## 

proc write*(writer: HttpWriter, buf: pointer, size: Natural): Future[void] = discard
  ## Writes ``size`` bytes from ``buf`` to the request ``req``.
  ## 
  ## If the return future is failed, ``OsError`` or ``WriteAbortedError`` may be raised.

proc write*(writer: HttpWriter, data: string): Future[void] = discard
  ## 

proc write*(
  writer: HttpWriter, 
  statusCode: HttpCode,
  fields: openArray[tuple[name: string, value: string]]
): Future[void]  = discard
  ## 

proc write*(
  writer: HttpWriter, 
  statusCode: HttpCode,
  fields: openArray[tuple[name: string, value: seq[string]]]
): Future[void] = discard
  ## 

proc writeEnd*(writer: HttpWriter) = discard
  ## 