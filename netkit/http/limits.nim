## This module defines some constants associated with HTTP operations. Some of them support redefinition 
## through the ``--define`` instruction during compilation. 

import netkit/misc

const LimitStartLineLen* {.intdefine.}: Natural = 8*1024 
  ## Specifies the maximum number of bytes that will be allowed on the HTTP start-line. This limitation
  ## affects both request-line and status-line.
  ## 
  ## Since the request-line consists of the HTTP method, URI, and protocol version, this directive places 
  ## a restriction on the length of a request-URI allowed for a request on the server. 
    
const LimitHeaderFieldLen* {.intdefine.}: Natural = 8*1024 
  ## Specifies the maximum number of bytes that will be allowed on an HTTP header field. This limitation 
  ## affects both request and response header fields.
  ## 
  ## The size of a normal HTTP header field will vary greatly among different implementations, often  
  ## depending upon the extent to which a user has configured their browser to support detailed content 
  ## negotiation.

const LimitHeaderFieldCount* {.intdefine.}: Natural = 100 
  ## Specifies the maximum number of HTTP header fields that will be allowed. This limitation affects both 
  ## request and response header fields.
     
const LimitChunkSizeLen*: Natural = 16 
  ## Specifies the maximum number of bytes that will be allowed on the size part of an chunk data that is 
  ## encoded by ``Transfer-Encoding: chunked``.
  
const LimitChunkHeaderLen* {.intdefine.}: Natural = 1*1024 
  ## Specifies the maximum number of bytes that will be allowed on the size and extensions parts of an chunk 
  ## data that is encoded by ``Transfer-Encoding: chunked``.
  ## 
  ## According to the HTTP protocol, the size and extensions parts of this kind of data are in this form:
  ## 
  ## .. code-block::http
  ## 
  ##   7\r\n; foo=value1; bar=value2\r\n 
 
const LimitChunkDataLen* {.intdefine.}: Natural = 1*1024 
  ## Specifies the maximum number of bytes that will be allowed on the data part of an chunk data that is encoded 
  ## by ``Transfer-Encoding: chunked``.
  ## 
  ## According to the HTTP protocol, the data part of this kind of data are in this form:
  ## 
  ## .. code-block::http
  ## 
  ##   Hello World\r\n 

const LimitChunkTrailerLen* {.intdefine.}: Natural = 8*1024 
  ## Specifies the maximum number of bytes that will be allowed on the medatada part of a message that is encoded 
  ## by ``Transfer-Encoding: chunked``. In fact, these metadata are some ``Trailer``. 
  ## 
  ## Examples:
  ## 
  ## .. code-block::http
  ## 
  ##   HTTP/1.1 200 OK 
  ##   Transfer-Encoding: chunked
  ##   Trailer: Expires
  ##   
  ##   9\r\n 
  ##   Developer\r\n 
  ##   0\r\n 
  ##   Expires: Wed, 21 Oct 2015 07:28:00 GMT\r\n
  ##   \r\n
  
const LimitChunkTrailerCount* {.intdefine.}: Natural = 100 
  ## Specifies the maximum number of the medatada ``Trailer`` that will be allowed. 

checkDefNatural LimitStartLineLen, "LimitStartLineLen"
checkDefNatural LimitHeaderFieldLen, "LimitHeaderFieldLen"
checkDefNatural LimitHeaderFieldCount, "LimitHeaderFieldCount"
checkDefNatural LimitChunkHeaderLen, "LimitChunkHeaderLen"
checkDefNatural LimitChunkDataLen, "LimitChunkDataLen"
checkDefNatural LimitChunkTrailerLen, "LimitChunkTrailerLen"
checkDefNatural LimitChunkTrailerCount, "LimitChunkTrailerCount"