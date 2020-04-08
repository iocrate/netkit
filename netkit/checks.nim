#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

template checkDefNatural*(value: static[Natural], name: static[string]): untyped = 
  ## 检查 ``a`` 是否是自然数 (零和正整数) 。 如果不是，则停止编译。 
  when value < 0:
    {.fatal: "The value of '" & name & "' by ``--define`` must be greater than or equal to 0!".}