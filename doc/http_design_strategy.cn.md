HTTP 设计策略
=====================

关于请求解析
---------------------

1. 定义解析 HTTP Method 策略: 以 SP 结尾的字符序列(区分大小写)，只支持 8 个常规请求方法；start line 长度不超过边界

2. 定义解析 HTTP URL 策略: 以 SP 结尾的字符序列，进行 URI 字符转义 (%符号)；start line 长度不超过边界

3. 定义解析 HTTP Version 策略: 以 LF 或 CRLF 结尾的字符序列，只允许 HTTP/1.1 和 HTTP/1.0 两个字符串 (区分大小写)，否则认为是请求错误；start line 长度不超过边界

4. 定义解析 Field Name 策略: 以 : 结尾的字符序列 (不区分大小写)；前后不能有空白 (SP, HTAB)；长度 >0；field line 长度不超过边界

5. 定义解析 Field Value 策略: 解析以 , 分割，解析以多个行分割，统一放置到 seq[string]，每个 item 一定只表示一个值，即 "SET-COOKIE": @["...", "…"]；前后允许有零到多个可选空白 (SP, HTAB)；每个值的长度 >0；field line 长度不超过边界；以 LF 或 CRLF 结尾

6. 定义解析 HTTP Body 策略: 以 CRLF 作为边界；对 Field values 关键字段进行规范化

关于 incoming 请求读
---------------------

1. 定义 request header 自动解析，body 需要 read 手动读，直到 readEnded，以支持流式操作。当 contentLen=0 或者 chunked tail 时，readEnded <可以确定，read 总能保证正确的顺序，不会受到 API 调用顺序影响，因为 http1 的请求是串行的，软件库能控制 request 的读前进和安全>

2. 支持 chunked 读自动解析3. 自动处理特定 fields

关于 outgoing 响应写
---------------------

1. 定义写操作由 write writeEnd 两个 API 组成，write 写入 http 数据，writeEnd 发送写的结尾信号。以使写操作通用灵活，支持流操作；不猜测用户写的数据，包括写的 header，相反，由用户在 write 时明确指出写 flag，比如 chunked

2. 定义一条响应由 

    1 write([header]) 
    * write([body])
    1 writeEnd()

组成。当第一次 writeEnd时，writeEnded，request 不再允许任何进一步写 <无法保证 write 顺序的正确性，为此，需要应用 MSB 策略，为错序的 write 提供缓存功能>

3. 定义 MSB write 缓存功能，确保错序的同一连接多个请求的响应 write 按照正确的顺序写到网络

4. 提供 chunked 工具函数

关于下一条请求的触发条件
---------------------

1. 定义 readedEnd 和 writeEnded，自动开始下一条 request

2. 查看 version 1.1 和 1.0 的支持情况，并根据请求 Connection 和写操作 flag 确定是关闭连接还是开始下一个请求

关于错误处理
---------------------

1. 解析的时候，会遇到各种错误问题 (比如，溢出边界，格式错误，其他)，需要提供一套一致的 HttpError 表示 http 的各种错误问题

关于优化
---------------------

1. 优化 write / read call (async)，尽可能减少 macro async 的层级，采用 future 封装，并且尽可能直接调用底层 socket api，减少消耗