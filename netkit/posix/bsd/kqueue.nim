from posix import Timespec

const 
  DefFreeBSD = defined(freebsd)     # version >= 12.0
  DefOpenBSD = defined(openbsd)     # version >= 6.1
  DefNetBSD = defined(netbsd)       # version >= 6.0
  DefDragonfly = defined(dragonfly) # version >= 4.9 
  DefMacosx = defined(macosx)       # 

when DefNetBSD:
  const
    EVFILT_READ*     = 0
    EVFILT_WRITE*    = 1
    EVFILT_AIO*      = 2 
    EVFILT_VNODE*    = 3 
    EVFILT_PROC*     = 4 
    EVFILT_SIGNAL*   = 5 
    EVFILT_TIMER*    = 6 
else:
  const
    EVFILT_READ*     = -1
    EVFILT_WRITE*    = -2
    EVFILT_AIO*      = -3 
    EVFILT_VNODE*    = -4 
    EVFILT_PROC*     = -5 
    EVFILT_SIGNAL*   = -6 
    EVFILT_TIMER*    = -7 
    
when DefMacosx:
  const
    EVFILT_MACHPORT* = -8  
    EVFILT_FS*       = -9  
    EVFILT_USER*     = -10 
elif DefFreeBSD:
  const
    EVFILT_FS*       = -9  
    EVFILT_LIO*      = -10 
    EVFILT_USER*     = -11 
elif DefDragonfly:
  const
    EVFILT_EXCEPT*   = -8  
    EVFILT_USER*     = -9  
    EVFILT_FS*       = -10 

const
  EV_ADD*      = 0x0001 
  EV_DELETE*   = 0x0002 
  EV_ENABLE*   = 0x0004 
  EV_DISABLE*  = 0x0008 

const
  EV_ONESHOT*  = 0x0010 
  EV_CLEAR*    = 0x0020 
  EV_RECEIPT*  = 0x0040 
  EV_DISPATCH* = 0x0080 
  EV_SYSFLAGS* = 0xF000 
  EV_DROP*     = 0x1000 
  EV_FLAG1*    = 0x2000 

const
  EV_EOF*      = 0x8000 
  EV_ERROR*    = 0x4000 
  EV_NODATA*   = 0x1000 

when DefMacosx or DefFreeBSD or DefDragonfly:
  const
    NOTE_FFNOP*      = 0x00000000'u32 
    NOTE_FFAND*      = 0x40000000'u32 
    NOTE_FFOR*       = 0x80000000'u32 
    NOTE_FFCOPY*     = 0xc0000000'u32 
    NOTE_FFCTRLMASK* = 0xc0000000'u32 
    NOTE_FFLAGSMASK* = 0x00ffffff'u32
    NOTE_TRIGGER*    = 0x01000000'u32 
                                      
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
  NOTE_EXIT*         = 0x80000000'u32 
  NOTE_FORK*         = 0x40000000'u32 
  NOTE_EXEC*         = 0x20000000'u32 
  NOTE_PCTRLMASK*    = 0xf0000000'u32 
  NOTE_PDATAMASK*    = 0x000fffff'u32 

const
  NOTE_TRACK*        = 0x00000001'u32 
  NOTE_TRACKERR*     = 0x00000002'u32 
  NOTE_CHILD*        = 0x00000004'u32 

when DefMacosx or DefFreeBSD:
  const
    NOTE_SECONDS*    = 0x00000001'u32 
    NOTE_MSECONDS*   = 0x00000002'u32 
    NOTE_USECONDS*   = 0x00000004'u32 
    NOTE_NSECONDS*   = 0x00000008'u32 
else:
  const
    NOTE_MSECONDS*   = 0x00000000'u32

type Ident* = uint

when DefNetBSD: 
  type Filter* = uint32
  type Flags* = uint32
  type FFlags* = uint32
elif DefMacosx:
  type Filter* = int16
  type Flags* = uint16
  type FFlags* = uint32
else: 
  type Filter* = cshort
  type Flags* = cushort
  type FFlags* = cuint

when DefFreeBSD or DefOpenBSD or DefNetBSD:
  type Data* = int64
else: 
  type Data* = int

when DefNetBSD:
  type UData* = int
else: 
  type UData* = pointer

when DefNetBSD:
  type Count* = csize_t
else: 
  type Count* = cint

type
  KEvent* {.
    importc: "struct kevent",
    header: """#include <sys/types.h>
               #include <sys/event.h>
               #include <sys/time.h>""", 
    pure, 
    final
  .} = object
    ident*  : Ident     
    filter* : Filter   
    flags*  : Flags  
    fflags* : FFlags    
    data*   : Data      
    udata*  : UData  

proc kqueue*(): cint {.importc: "kqueue", header: "<sys/event.h>".}

proc kevent*(
  kq: cint,
  changelist: ptr KEvent, 
  nchanges: Count,
  eventlist: ptr KEvent, 
  nevents: Count, 
  timeout: ptr Timespec
): cint {.importc: "kevent", header: "<sys/event.h>".}

proc EV_SET*(
  kev: ptr KEvent, 
  ident: Ident, 
  filter: Filter, 
  flags: Flags,
  fflags: FFlags, 
  data: Data, 
  udata: UData
) {.importc: "EV_SET", header: "<sys/event.h>".}

