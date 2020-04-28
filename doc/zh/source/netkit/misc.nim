#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

template offset*(p: pointer, n: int): pointer = discard 
  ## 
   
template checkDefNatural*(value: static[Natural], name: static[string]): untyped = discard
  ## 检查 ``value`` 是否是自然数 (零和正整数) 。 如果不是，则停止编译。 ``name`` 指定其符号名字。 