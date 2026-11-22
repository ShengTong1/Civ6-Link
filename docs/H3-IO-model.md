# H3 专项：文明6 I/O 模型五分类裁决指南

> 对应《CivLink 技术设计规范 v2.1》§2.2 H3、§4.1；工具：civtrace v0.3（31 API）+
> `scripts/analyze-trace.ps1 -H3`。审查 2.3 明确：**WSAPoll 属同步轮询，不与 Overlapped 混类**。

## 五分类定义与判据

| # | I/O 模型 | 观察接口 | 日志判据 |
|---|---------|---------|---------|
| ① | 同步阻塞 | `recvfrom`/`WSARecvFrom`（无非阻塞标记） | 无 `NB` 标记、无 `[WSAEWOULDBLOCK]`、调用返回即有数据 |
| ② | 非阻塞轮询 | `select` / `WSAPoll` / `ioctlsocket(FIONBIO)` + 循环收 | 大量 `[WSAEWOULDBLOCK]`；select/poll 调用密集；**无④⑤痕迹** |
| ③ | 事件通知 | `WSAEventSelect` / `WSAAsyncSelect` + `WSAWaitForMultipleEvents`/窗口消息 | `WSAEventSelect s=... event=... events=0x...` 或 `WSAAsyncSelect hwnd=... msg=...` |
| ④ | Overlapped I/O | `WSARecvFrom`/`WSARecv` 带 OVERLAPPED | `ov=yes`（仅证明传入了 OVERLAPPED，**不等于真异步**）→ 必须再验 `[WSA_IO_PENDING]`（真 Pending）→ 完成路径看 ③ 或 `WSAGetOverlappedResult` |
| ⑤ | IOCP | `CreateIoCompletionPort`（file 命中已知 socket）+ `GetQueuedCompletionStatus(Ex)` | `CreateIoCompletionPort ... (sock)` / `GQCS ... bytes=...`（GQCS 限流记录：前 50 次全记，之后每 1000 次 1 次） |

## 旁路路径（必须排除，否则裁决不完整）

`WSAIoctl(SIO_GET_EXTENSION_FUNCTION_POINTER)` 可取到 **ConnectEx / AcceptEx /
WSARecvMsg / WSASendMsg / DisconnectEx** 等扩展函数指针，之后直接通过指针调用——
**不再经过普通导出 API**，普通 API Hook 看不到收发。civtrace 会解码并记录 GUID 名称；
日志出现 `WSAIoctl ... SIO_GET_EXTENSION ... -> ConnectEx` 即宣告存在旁路路径，
M0-B Hook 设计必须覆盖（或证明该旁路未被游戏实际用于 62900-62999/62056 通道）。

## 裁决流程

1. `analyze-trace.ps1 -Log <log> -H3`：五段输出 + verdict 提示；
2. 全部五段为空 + 发现阶段 `[WSAEWOULDBLOCK]` 密集 → **②非阻塞轮询**（injciv6 同款，
   M0-B 前提最简，Design I/II 都按同步语义处理）；
3. 任一段非空 → 按命中最高编号归类；④必须区分"传入 OVERLAPPED / 立即完成 /
   IO_PENDING / 完成通知路径"四态后再下结论；
4. 结论写进报告 §2-H3，并标注对 M0-B 的影响：
   - ①② → Hook 接收队列只需同步返回路径；
   - ③④⑤ → Design II 的"队列注入 + 可读状态伪造"复杂度大增，M0-B 前需专项设计。

## 常见误判

- `ov=yes` ≠ 异步：同步 socket 也可传 OVERLAPPED 结构（立即完成）；
- `WSAEWOULDBLOCK` ≠ 异步：这是②的标志，不是④；
- GQCS 出现不代表游戏用 IOCP：可能是其它系统组件/运行库行为——看 `CreateIoCompletionPort`
  是否 `(sock)` 命中游戏 socket；
- 追踪 DLL 自身调用 socket（日志线程无网络）不会经过 Hook 记录（g_inHook 递归保险），
  日志里出现的都来自游戏或其库。
