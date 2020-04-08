#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

import netkit/checks

const LimitStartLineLen* {.intdefine.}: Natural = 8*1024 ## HTTP 起始行的最大长度。 
const LimitHeaderFieldLen* {.intdefine.}: Natural = 8*1024 ## HTTP 头字段的最大长度。 
const LimitHeaderFieldCount* {.intdefine.}: Natural = 100 ## HTTP 头字段的最大个数。  
const LimitChunkedSizeLen* {.intdefine.}: Natural = 1*1024 ## ``Transfer-Encoding: chunked`` 编码尺寸的最大长度。 
const LimitChunkedDataLen* {.intdefine.}: Natural = 1*1024 ## ``Transfer-Encoding: chunked`` 编码数据块的最大长度。  

checkDefNatural LimitStartLineLen,     "LimitStartLineLen"
checkDefNatural LimitHeaderFieldLen,   "LimitHeaderFieldLen"
checkDefNatural LimitHeaderFieldCount, "LimitHeaderFieldCount"
checkDefNatural LimitChunkedSizeLen,   "LimitChunkedSizeLen"
checkDefNatural LimitChunkedDataLen,   "LimitChunkedDataLen"