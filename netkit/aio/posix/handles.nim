
type
  IoHandle* = distinct int

proc `==`*(a: IoHandle, b: IoHandle): bool {.borrow.}

