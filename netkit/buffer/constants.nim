#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import netkit/checks

const BufferSize* {.intdefine.}: Natural = 8*1024  
checkDefNatural BufferSize, "BufferSize"