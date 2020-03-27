Netkit
==========

> PS: 请在有时间的时候将文档翻译成英文；这篇文档还在修改中，还不着急。

Netkit 希望作为一个多才多艺的网络开发基础套件，提供网络编程常用的工具。希望 Netkit 是开箱即用并且稳定、安全的，当拿到 Netkit 能够获得大多数可用的网络编程工具，比如 TCP、UDP、HTTP、WebSocket、MQTT 的基本客户端和服务器以及相关的一些工具。

Netkit 不打算成为高阶生产力开发工具，而是作为一个可靠效率的网络设施基础。Netkit 由多个子模块组成，每个子模块提供了一些网络工具。

这个软件包正在开发初期，还有很多事情要做。现在可以确定的第一个任务是：

- [ ] (支持增量模式) 可标记的环形缓冲区。用来作为 TCP、HTTP 通信时底层需要的读写缓冲区
- [ ] 一个 HTTP Parser，提供 HTTP 流量包的解析功能
- [ ] 一个 HTTP Server，作为测试第一个版本的网络性能的样本

关于测试
---------

现在，已经提供了一个子模块：

- buffer 内部实现了 ``MarkableCircularBuffer``，下一步的计划是对该模块进行更多严格的单元测试和基准测试 (性能比较)；另一个计划是开始编写 HTTP Parser

[Circular buffer Wiki](https://en.wikipedia.org/wiki/Circular_buffer)  
[Circular buffer Wiki-中文](https://zh.wikipedia.org/wiki/%E7%92%B0%E5%BD%A2%E7%B7%A9%E8%A1%9D%E5%8D%80)

运行测试：软件包提供了一个自动测试脚本，查看 config.nims 了解详情。``$ nim test <测试文件名>`` 可以测试指定的文件，比如 ``$ nim test tbuffer`` 将测试 tests/tbuffer.nim 文件。``$ nimble test`` 将会测试所有 tests 目录内的测试文件。