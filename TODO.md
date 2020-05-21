
2020-04-09

- [x] 添加中文文档目录 doc/source_cn，中文注释写在该目录内。该目录内的文件对应源代码目录 netkit/ 
      内的文件，翻译后的注释追加到源代码文件
- [x] 修订 netkit/buffer/circular 模块，使得 CircularBuffer API 更加完善和稳定
- [x] 修订 netkit/buffer/circular 模块，使得 MarkableCircularBuffer API 更加完善和稳定
- [x] 移动各源码文件的中文注释到中文文档目录 doc/source_cn
- [x] 添加异步锁模块 locks
- [x] 使用异步锁重写 Request
- [x] 优化 HTTP Server Request 的读操作
- [x] 优化 HTTP Server Request 的写操作
- [x] 考虑统一抽象编码解码相关的内容，比如 chunked 解码、编码；HTTP version、method HTTP header 
      编码解码；等等
- [x] 考虑 socket recv/write 异常如何处理，是否关闭连接
- [x] 整理 HTTP Server 源码文件
- [x] 添加 chunk Trailer 支持
- [x] 添加 chunk Extensions 支持
- [x] 优化 HTTP chunked 解码和编码
- [x] 添加 HTTP 服务器单元测试，包含多种规则和不规则请求的模拟测试
- [ ] 添加 HTTP server benchmark tests
- [ ] 添加 CompactBuffer MarkableCompactBuffer （MarkableBuffer 统一标记缓冲区？） 优化 HTTP Parser -> 大多数 header field 都很小，并且通常是完整的，所以缓冲区很少会留下不完全的 header field part，这样就无需总是对缓冲区左右进行判断 (MarkableCircularBuffer)
- [ ] 添加 --define:benchgame 标识位，为基准测试跑分添加专门的优化 - 跳过 HTTP Header 解析，代替的是，仅仅保存到内存，直接查找 CRLFCRLF，以提升 CPU 计算时间 
- [ ] 优化 write(statusCode, header) 和 write(data)，在 benchmark 中影响性能达到 6 倍 --> 
      考虑将 statusCode, header 和第一块数据合并到一个缓冲区发送
- [ ] 修复 parseSingleRule, parseMultiRule
- [ ] 4 个线程，1000 个连接，30 秒持续请求的吞吐量测试，以优化 asyncdispatcher 的 io
- [ ] 创建 selector 分支，posix 环境使用 selector 优化 HTTP IO
- [ ] response.writeEnd 支持 Connection: keepalive 控制
- [ ] 添加 HTTP server 多线程支持
- [ ] 添加 HTTP 客户端和 HTTP 客户端连接池
- [ ] 修订各源码文件留下的 TODOs
- [ ] 考虑使用 {.noInit.} 优化已经写的 procs iterators vars lets
