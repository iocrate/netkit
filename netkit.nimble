# Package

version       = "0.1.0"
author        = "Wang Tong"
description   = "A versatile network development kit, providing tools commonly used in network programming."
license       = "MIT"


# Dependencies

requires "nim >= 1.0.6"

task test, "Run all tests":
  exec "testament all"
