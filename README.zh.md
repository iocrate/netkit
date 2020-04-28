Netkit 
==========

[![Build Status](https://travis-ci.org/iocrate/netkit.svg?branch=master)](https://travis-ci.org/iocrate/netkit)
[![Build Status](https://dev.azure.com/iocrate/netkit/_apis/build/status/iocrate.netkit?branchName=master)](https://dev.azure.com/iocrate/netkit/_build/latest?definitionId=1&branchName=master)

Netkit 希望作为一个多才多艺的网络开发基础套件，提供网络编程常用的工具。Netkit 应该是开箱即用并且稳定、安全的。Netkit 包含了大多数常用的网络编程工具，比如 TCP、UDP、TLS、HTTP、HTTPS、WebSocket 以及相关的一些实用工具。

Netkit 不打算成为高阶生产力开发工具，而是作为一个可靠效率的基础网络设施。Netkit 由多个子模块组成，每个子模块提供了一些网络工具。

**这个软件包正在积极开发中。**

- [文档 (英文) - PS:临时的，需要更友好的主页](https://iocrate.github.io/netkit.html)
- [文档 (中文) - PS:临时的，需要更友好的主页](https://iocrate.github.io/zh/netkit.html)

运行测试
---------

软件包提供了一个自动测试的脚本，查看 config.nims 了解详情。``$ nim test <测试文件名>`` 可以测试指定的文件，比如 ``$ nim test tbuffer`` 将测试 tests/tbuffer.nim 文件。``$ nimble test`` 将会测试所有 tests 目录内的测试文件。

制作文档
---------

软件包提供了一个自动制作文档的脚本，查看 config.nims 了解详情。``$ nim docs -d:lang=en`` 制作源代码的文档，即英文文档； ``$ nim docs -d:lang=zh`` 制作源代码的中文文档；``$ nim docs`` 制作源代码的中文文档和英文文档。

源代码的文档以英文书写。源代码的中文版文档放置在 ``${projectDir}/doc/zh/source`` 目录内。

开发列表
---------

- [x] buffer
    - [x] circular
    - [x] vector
- [ ] tcp
- [ ] udp
- [ ] http
    - [x] limits
    - [x] exception
    - [x] spec
    - [x] httpmethod
    - [x] version
    - [x] status
    - [x] headerfield
    - [x] header
    - [x] chunk
    - [x] metadata
    - [x] cookie
    - [x] parser
    - [x] connection
    - [x] reader
    - [x] writer
    - [x] server
    - [ ] client
    - [ ] clientpool
- [ ] websocket
- [ ] 编写文档主页，提供更加友好的文档管理
- [ ] 增强 docpolisher 的功能，为文档添加 github 链接和返回上一页、返回主页的功能

贡献项目
-----------

- 编写和制作更多的中文、英文文档
- 添加更严格的单元测试
- 添加基准测试或者压力测试
- 添加新的代码以支持新的功能
- 修复 bugs
- 修复文档错误
