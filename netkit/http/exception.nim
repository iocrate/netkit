#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module defines exceptions related to HTTP operations.

import netkit/http/base

type
  HttpError* = object of CatchableError ## Indicates a error related to HTTP protocol.
    code*: range[Http400..Http505] 
    
  ReadAbortedError* = object of CatchableError ## Indicates that the read operation is aborted before completion. 
  WriteAbortedError* = object of CatchableError ## Indicates that the write operation is aborted before completion.

proc newHttpError*(
  code: range[Http400..Http505], 
  parentException: ref Exception = nil
): ref HttpError = 
  ## Creates a new ``ref HttpError``.
  result = (ref HttpError)(msg: $code, code: code, parent: parentException)

proc newHttpError*(
  code: range[Http400..Http505], 
  msg: string, 
  parentException: ref Exception = nil
): ref HttpError = 
  ## Creates a new ``ref HttpError``.
  result = (ref HttpError)(msg: msg, code: code, parent: parentException)
