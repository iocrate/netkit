#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module contains a few possible errors associated with HTTP operations.

import netkit/http/status

type
  HttpError* = object of CatchableError ## Indicates a error associated with a HTTP operation.
    code*: range[Http400..Http505] 
    
  ReadAbortedError* = object of CatchableError ## Indicates that the read operation is aborted before completion. 
  WriteAbortedError* = object of CatchableError ## Indicates that the write operation is aborted before completion.

proc newHttpError*(
  code: range[Http400..Http505], 
  parentException: ref Exception = nil
): ref HttpError = discard
  ## Creates a new ``ref HttpError``.

proc newHttpError*(
  code: range[Http400..Http505], 
  msg: string, 
  parentException: ref Exception = nil
): ref HttpError = discard
  ## Creates a new ``ref HttpError``.
