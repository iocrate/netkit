# Package

version       = "0.1.0"
author        = "Wang Tong"
description   = "一个多才多艺的网络开发基础套件，提供网络编程常用的工具 --> 请后面有时间的时候翻译成英文"
license       = "MIT"


# Dependencies

requires "nim >= 1.0.6"

task test, "Run all tests":
  exec "testament cat /"
