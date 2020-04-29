#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## 这个模块包含了一些其他功能，这些功能不属于任何其他模块。

template offset*(p: pointer, n: int): pointer = discard 
  ## Returns a new pointer, which is offset ``n`` bytes backwards from ``p``.
   
template checkDefNatural*(value: static[Natural], name: static[string]): untyped = discard
  ## 检查 ``value`` 是否是自然数 (零和正整数) 。 如果不是，则停止编译。 ``name`` 指定其符号名字。 