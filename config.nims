import strutils, strformat, os

const PROJECT_DIR = projectDir() 
const TEST_DIR = PROJECT_DIR / "tests"
const BUILD_DIR = PROJECT_DIR / "build"
const BUILD_TEST_DIR = BUILD_DIR / "tests"

task test, "Run my tests":
#  run the following command:
#
#    nim test a,b.c,d.e.f 
#
#  equivalent to:
# 
#    test tests/a.nim
#    test tests/b/c.nim
#    test tests/d/e/f.nim
#
  var targets: seq[string] = @[]
  var flag = false
  for i in 0..system.paramCount():
    if flag:
      targets.add(system.paramStr(i).replace('.', AltSep).split(','))
    elif system.paramStr(i) == "test":
      flag = true
  for t in targets:
    withDir PROJECT_DIR:
      var args: seq[string] = @["nim", "c"]
      args.add("--run")
      args.add("--verbosity:0")
      args.add("--hints:off")
      args.add(fmt"--out:{BUILD_TEST_DIR / t}")
      args.add(fmt"--path:{PROJECT_DIR}")
      args.add(TEST_DIR / t)
      mkDir(BUILD_TEST_DIR / t.parentDir())
      exec(args.join(" "))
  rmDir(BUILD_DIR)
  
task docs, "Gen docs":
#  run the following command:
#
#    nim test a,b.c,d.e.f 
#
#  equivalent to:
# 
#    test tests/a.nim
#    test tests/b/c.nim
#    test tests/d/e/f.nim
#
  withDir PROJECT_DIR:
    mkDir(BUILD_TEST_DIR)
    var args: seq[string] = @["nim", "doc2"]
    args.add("--project")
    args.add("--index:on")
    args.add("--git.url:https://github.com/iocrate/netkit")
    args.add(fmt"--out:{BUILD_TEST_DIR}")
    args.add("netkit/http/server.nim")
    exec(args.join(" "))