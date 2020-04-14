#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import netkit/http/base

type
  HttpError* = object of Exception
    code*: range[Http400..Http505]
    
  ReadAbortedError* = object of Exception
  WriteAbortedError* = object of Exception

proc newHttpError*(
  code: range[Http400..Http505], 
  parentException: ref Exception = nil
): ref HttpError = 
  result = newException(HttpError, $code, parentException)
  result.code = code

proc newHttpError*(
  code: range[Http400..Http505], 
  msg: string, 
  parentException: ref Exception = nil
): ref HttpError = 
  result = newException(HttpError, msg, parentException)
  result.code = code


