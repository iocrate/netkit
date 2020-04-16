#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import netkit/http/base

type
  HttpError* = ref object of CatchableError
    code*: range[Http400..Http505]
    
  ReadAbortedError* = object of CatchableError
  WriteAbortedError* = object of CatchableError

proc newHttpError*(
  code: range[Http400..Http505], 
  parentException: ref Exception = nil
): HttpError = 
  result = HttpError(msg: $code, code: code, parent: parentException)

proc newHttpError*(
  code: range[Http400..Http505], 
  msg: string, 
  parentException: ref Exception = nil
): HttpError = 
  result = HttpError(msg: msg, code: code, parent: parentException)
