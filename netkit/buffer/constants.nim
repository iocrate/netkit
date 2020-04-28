#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

## This module contains constants related to the buffer.

import netkit/misc

const BufferSize* {.intdefine.}: Natural = 8*1024 
  ## Describes the number of bytes for a buffer. 
  ## 
  ## You can override this value at compile time with the switch option ``--define:BufferSize=<n>``. Note 
  ## that  the value must be a natural number, that is, an integer greater than or equal to zero. Otherwise, 
  ## an  exception will be raised.
  
checkDefNatural BufferSize, "BufferSize"