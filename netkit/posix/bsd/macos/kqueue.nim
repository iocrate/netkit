from posix import Timespec

const
  EVFILT_READ*       = -1
  EVFILT_WRITE*      = -2
  EVFILT_AIO*        = -3 
  EVFILT_VNODE*      = -4 
  EVFILT_PROC*       = -5 
  EVFILT_SIGNAL*     = -6 
  EVFILT_TIMER*      = -7 
    
const
  EVFILT_MACHPORT*   = -8  
  EVFILT_FS*         = -9  
  EVFILT_USER*       = -10 

const
  EV_ADD*            = 0x0001 
  EV_DELETE*         = 0x0002 
  EV_ENABLE*         = 0x0004 
  EV_DISABLE*        = 0x0008 

const
  EV_ONESHOT*        = 0x0010 
  EV_CLEAR*          = 0x0020 
  EV_RECEIPT*        = 0x0040 
  EV_DISPATCH*       = 0x0080 
  EV_SYSFLAGS*       = 0xF000 
  EV_DROP*           = 0x1000 
  EV_FLAG1*          = 0x2000 

const
  EV_EOF*            = 0x8000 
  EV_ERROR*          = 0x4000 
  EV_NODATA*         = 0x1000 

const
  NOTE_FFNOP*        = 0x00000000
  NOTE_FFAND*        = 0x40000000
  NOTE_FFOR*         = 0x80000000
  NOTE_FFCOPY*       = 0xC0000000
  NOTE_FFCTRLMASK*   = 0xC0000000
  NOTE_FFLAGSMASK*   = 0x00FFFFFF
  NOTE_TRIGGER*      = 0x01000000
                                      
const
  NOTE_LOWAT*        = 0x0001 

const
  NOTE_DELETE*       = 0x0001 
  NOTE_WRITE*        = 0x0002 
  NOTE_EXTEND*       = 0x0004 
  NOTE_ATTRIB*       = 0x0008 
  NOTE_LINK*         = 0x0010 
  NOTE_RENAME*       = 0x0020 
  NOTE_REVOKE*       = 0x0040 

const
  NOTE_EXIT*         = 0x80000000
  NOTE_FORK*         = 0x40000000
  NOTE_EXEC*         = 0x20000000
  NOTE_PCTRLMASK*    = 0xF0000000
  NOTE_PDATAMASK*    = 0x000FFFFF

const
  NOTE_TRACK*        = 0x00000001
  NOTE_TRACKERR*     = 0x00000002
  NOTE_CHILD*        = 0x00000004

const
  NOTE_SECONDS*      = 0x00000001
  NOTE_MSECONDS*     = 0x00000002
  NOTE_USECONDS*     = 0x00000004
  NOTE_NSECONDS*     = 0x00000008

type 
  Filter* = int16
  Flags* = uint16
  FFlags* = uint32
  Data* = int
  UData* = pointer

type
  KEvent* {.
    importc: "struct kevent",
    header: """#include <sys/types.h>
               #include <sys/event.h>
               #include <sys/time.h>""", 
    pure, 
    final
  .} = object
    ident*  : uint     
    filter* : Filter   
    flags*  : Flags  
    fflags* : FFlags    
    data*   : Data      
    udata*  : UData  

proc kqueue*(): cint {.importc: "kqueue", header: "<sys/event.h>".}

proc kevent*(
  kq: cint,
  changelist: ptr KEvent, 
  nchanges: cint,
  eventlist: ptr KEvent, 
  nevents: cint, 
  timeout: ptr Timespec
): cint {.importc: "kevent", header: "<sys/event.h>".}

proc EV_SET*(
  kev: ptr KEvent, 
  ident: uint, 
  filter: Filter, 
  flags: Flags,
  fflags: FFlags, 
  data: Data, 
  udata: UData
) {.importc: "EV_SET", header: "<sys/event.h>".}