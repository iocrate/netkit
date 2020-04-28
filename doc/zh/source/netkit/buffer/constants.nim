#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import netkit/checks

const BufferSize* {.intdefine.}: Natural = 8*1024
  ## 描述缓冲区的字节数。 您可以在编译时通过开关选项 ``--define:BufferSize`` 重写这个
  ## 数值。 注意， 值必须是自然数， 即大于等于零的整数； 否则， 将会引起异常。 