
type
  DestructorState* {.pure, size: sizeof(uint8).} = enum
    PENDING, READY, COMPLETED