#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import netkit/checks

const LimitStartLineLen* {.intdefine.}: Natural = 8*1024 ##  
const LimitHeaderFieldLen* {.intdefine.}: Natural = 8*1024 ##  
const LimitHeaderFieldCount* {.intdefine.}: Natural = 100 ##   
const LimitChunkedSizeLen* {.intdefine.}: Natural = 1*1024 ## ``Transfer-Encoding: chunked``  
const LimitChunkedDataLen* {.intdefine.}: Natural = 1*1024 ## ``Transfer-Encoding: chunked`` 

checkDefNatural LimitStartLineLen,     "LimitStartLineLen"
checkDefNatural LimitHeaderFieldLen,   "LimitHeaderFieldLen"
checkDefNatural LimitHeaderFieldCount, "LimitHeaderFieldCount"
checkDefNatural LimitChunkedSizeLen,   "LimitChunkedSizeLen"
checkDefNatural LimitChunkedDataLen,   "LimitChunkedDataLen"