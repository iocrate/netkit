import strutils 
import strformat
import os except getCurrentDir

const ProjectDir = projectDir() 
const TestDir = ProjectDir / "tests"
const BuildDir = ProjectDir / "build"
const TestBuildDir = BuildDir / "tests"
const DocBuildEnDir = BuildDir / "doc/en"
const DocBuildZhDir = BuildDir / "doc/zh"
const DocCodeZhDir = ProjectDir / "doc/zh/code"
const DocPolisher = ProjectDir / "tools/docplus/polish.js"

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
    withDir ProjectDir:
      var args: seq[string] = @["nim", "c"]
      args.add("--run")
      args.add("--verbosity:0")
      args.add("--hints:off")
      args.add(fmt"--out:{TestBuildDir / t}")
      args.add(fmt"--path:{ProjectDir}")
      args.add(TestDir / t)
      rmDir(BuildDir / t.parentDir())
      mkDir(TestBuildDir / t.parentDir())
      exec(args.join(" "))
  
task docs, "Gen docs":
  # **netkit.nim** is the entry file of this project. This task starts with **netkit.nim** to generate 
  # the documentation of this project, and the output directory is **${projectDir}/build/doc**.
  #
  # run the following command:
  #
  #   nim docs [-d:lang=zh|en] [-d:module=netkit/buffer/constants]
  #
  # Note: nodejs is required, and ``$ npm install`` should be done in **${projectDir}/tools/docplus**.
  const lang {.strdefine.} = ""
  const module {.strdefine.} = ""
  var dirs: seq[tuple[build: string, source: string]] = @[]
  case lang
  of "":
    dirs.add((DocBuildEnDir, ProjectDir))
    dirs.add((DocBuildZhDir, DocCodeZhDir))
  of "en":
    dirs.add((DocBuildEnDir, ProjectDir))
  of "zh":
    dirs.add((DocBuildZhDir, DocCodeZhDir))
  else:
    discard
  for dir in dirs:  
    withDir dir.source:
      rmDir(dir.build)
      mkDir(dir.build)
      var args: seq[string] = @["nim", "doc2"]
      args.add("--verbosity:0")
      args.add("--hints:off")
      args.add(fmt"--path:.")
      if module.len == 0:
        args.add("--project")
        args.add("--index:on")
        args.add("--git.url:https://github.com/iocrate/netkit")
        args.add("--git.commit:master")
        args.add(fmt"--out:{dir.build}")
        args.add(dir.source / "netkit.nim")
      else:
        args.add(fmt"--out:{dir.build / module}.html")
        args.add(dir.source / module)
      exec(args.join(" "))
      exec(fmt"DOC_PLUS_ROOT={dir.build} {DocPolisher}")
