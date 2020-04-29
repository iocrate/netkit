#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块定义了与 HTTP 操作相关的异常。

import netkit/http/status

type
  HttpError* = object of CatchableError ## 表示与 HTTP 协议相关的错误。
    code*: range[Http400..Http505] 
    
  ReadAbortedError* = object of CatchableError ## 读操作在完成前被中断。
  WriteAbortedError* = object of CatchableError ## 写操作在完成前被中断。

proc newHttpError*(
  code: range[Http400..Http505], 
  parentException: ref Exception = nil
): ref HttpError = discard
  ## 创建一个 ``ref HttpError``.

proc newHttpError*(
  code: range[Http400..Http505], 
  msg: string, 
  parentException: ref Exception = nil
): ref HttpError = discard
  ## 创建一个 ``ref HttpError``.
