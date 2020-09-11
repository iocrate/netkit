## This module contains a few possible errors associated with HTTP operations.

import netkit/http/status

type
  HttpError* = object of CatchableError ## Indicates an error associated with a HTTP operation.
    code*: range[Http400..Http505] 
    
  ReadAbortedError* = object of CatchableError ## Indicates that the read operation is aborted before completion. 
    timeout*: bool
  
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

proc newReadAbortedError*(
  msg: string, 
  timeout: bool = false, 
  parentException: ref Exception = nil
): ref ReadAbortedError = 
  ## Creates a new ``ref ReadAbortedError``.
  result = (ref ReadAbortedError)(msg: msg, timeout: timeout, parent: parentException)

proc newWriteAbortedError*(
  msg: string, 
  parentException: ref Exception = nil
): ref WriteAbortedError = 
  ## Creates a new ``ref ReadAbortedError``.
  result = (ref WriteAbortedError)(msg: msg, parent: parentException)