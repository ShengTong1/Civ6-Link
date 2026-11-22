# civtrace v0.4.5 — 日志体量上限（修复"单轮 15.4 GB 爆盘"）

> 版本：v1.0（2026-11-16 23:30 +08:00）
> 范围：`CivLink-M0A-audit\civtrace\`（观测面 DLL，31 Hook）。**不涉及** `civlink\`（数据面 Hook/Agent/Relay）。
> 结论一句话：限流后同一载荷下日志从 **471,187,542 B / 10 s（47 MB/s）** 降到 **24,167 B / 10 s（2.4 KB/s）**，约 **19,500×**；同时 100 个发现广播**一条不丢**，跳过条数与总调用数**逐条对账**（delta=0）。

---

## 1 缺陷与根因

用户 2026-11-16 报告：日志把 C 盘写爆。

| 观察 | 数值 | 来源 |
|---|---|---|
| 单轮 E2-B（约 13 分钟）`_host` 日志 | **15.4 GB** | `%LOCALAPPDATA%\CivLink\M0A\logs\` |
| 同轮 B 机 `_client` 日志 | 82 MB | B 机同目录 |
| 根本高频源 | Civ6 数据面 socket 忙轮询 `WSARecvFrom` ≈ **1.6 M 次/秒** | F2 S5 观察 + 本轮 raw 日志 |

根因链：

1. `civtrace.dll` 的 31 个 Hook **无条件** `Emit()` 一行；
2. `Emit()` 只把行推进内存队列，刷盘线程每 150 ms 批量落盘；
3. 62056 数据面 socket 采用非阻塞忙轮询（`recvfrom`/`WSARecvFrom` 返回 `WSAEWOULDBLOCK` 后立刻重试），**每秒约 160 万次**；
4. 队列上限 65536 行，超出即 `g_drops++` —— 所以爆盘的同时**证据还在丢**（本轮实测 `drops=8,003,894`）。

即：旧行为既"写爆磁盘"又"丢关键行"，是最坏组合。

---

## 2 设计（v0.4.5）

### 2.1 分类：发现 socket 与其它

**发现 socket**（关注对象，必须全记录）：

- `bind()` 成功且端口落在 **62900–62999**（Civ6 发现广播区间）；或
- `sendto()` / `WSASendTo()` **成功**且目标是 `255.255.255.255` 或端口 62900–62999。

一旦判定，该 socket 在 `SockInfo.discovery` 上打标，**此后永不限流**。

**其它 socket**（数据面、Steam 心跳、无关进程）：读事件每 **200 ms** 至多记录 1 行。

### 2.2 为什么是 200 ms

- Civ6 数据面对端在 62056 上以指数退避（0.5→128 s）重发，事件密度远低于 5 Hz；200 ms 窗口不会漏掉"帧到达"这类状态变化，只是把同一状态的重复轮询折叠成 1 行。
- 10 s 窗口理论上限 `ceil(10000/200)+1 = 51` 行/socket（实测 50 行）。

### 2.3 无 socket 参数的高频 API

`WSAWaitForMultipleEvents` 没有 socket 参数（只有事件数组），无法按 socket 归因，改用**全局** 200 ms 窗口（`ThrottleGlobal()`）。`select` 用 `rset->fd_array[0]` 代表（空集不限），`WSAPoll` 用 `fds[0].fd` 代表。

### 2.4 可审计性

- 跳过行计入 `g_throttled`（原子），**不静默丢弃**；
- 会话结束行变为 `===== session end seq=%llu drops=%llu throttled=%llu =====`；
- 恒等式（断言 A11）：`throttled + recorded == total calls`。

---

## 3 实现落点（`civtrace\trace_dll.cpp`，1,583 行 / 79,923 B）

| 位置 | 内容 |
|---|---|
| L181 | `static std::atomic<unsigned long long> g_throttled{0}` |
| L189 | `static constexpr ULONGLONG kThrottleMs = 200` |
| L474–483 | `IsDiscoveryDst(to, tolen)`：`AF_INET && (port 62900–62999 || addr == INADDR_BROADCAST)` |
| L484–487 | `MarkDiscovery(s)` |
| L490–498 | `ThrottleRead(s)`：discovery 直接 false；否则 200 ms 窗口 |
| L500–507 | `g_lastGlobalLogMs`（`std::atomic<ULONGLONG>`，R-1 修复）+ `ThrottleGlobal()`（CAS 循环，失败者若窗口内则计数 throttled） |
| L465–472 | `MarkClosed()` 命中时额外复位 `discovery=false; lastLogMs=0` |
| L684 | `Hook_bind`：成功且目标是发现端口 → `MarkDiscovery` |
| L709 / L734 | `Hook_sendto` / `Hook_WSASendTo`：**仅 `r != SOCKET_ERROR`** 才 `MarkDiscovery` |
| L759 | `Hook_recvfrom` 限流 |
| L787 | `Hook_WSARecvFrom` 限流 |
| L804–812 | `Hook_select` 限流（`rset->fd_array[0]`） |
| L1040 | `Hook_WSAPoll` 限流（`fds[0].fd`） |
| L1065 | `Hook_WSASend` 限流 |
| L1086 | `Hook_WSARecv` 限流 |
| L1159 | `Hook_WSAWaitForMultipleEvents` 限流（全局窗口） |
| L347 | 会话结束行加 `throttled=%llu` |
| `civtrace_common.h` L7 | `CIVTRACE_VERSION "0.4.5"` |

限流语句统一形如（放在 `snprintf`/`Emit` **之前**，避免白算字符串）：

```cpp
if (ThrottleRead(s)) { tx.end(); g_inFlight.fetch_sub(1, std::memory_order_relaxed); g_tlsInHook = false; return r; }
```

---

## 4 实施中踩到的两个真 bug（都已修）

> **证据标注（审计 CIVTRACE-LOGBOUND-REVIEW R-2，2026-11-16）**：4.1 与 4.2 是**同一组 `run-20261116-231817` 计数（`throttled=0`、471 MB）的两种可替换解释**，且 231817 轮的 raw 日志未留存（现场清理），**机制本身无直接日志证据**。两处根因由代码审查确认（`MarkDiscovery` 不看返回值、`MarkClosed` 不复位），旁证为 REV-002 T15 日志中真实存在的 `socket … err=10093` 调用（`docs\reports\rev002\raw-233102-pid8072_host.log` 尾部 3 行）——即 `sendto(-1)` 失败调用确实会发生。修复后的行为已由 232727 轮机械证据直接证明（broadcast=100 全记录、throttled>0、delta=0）。

### 4.1 无条件 `MarkDiscovery` → 限流被整条旁路

第一版在 `Hook_sendto`/`Hook_WSASendTo` 里**不看返回值**就 `MarkDiscovery(s)`。Winsock 未初始化时游戏会以 `s = -1`（`INVALID_SOCKET`）调用 `sendto` 并得到 `10093 WSAENOTINITIALISED`，于是 `(SOCKET)-1` 这个句柄被永久标记为 discovery，而后续高频 `recvfrom` 恰恰发生在同一句柄上 → **全量写盘**。

实测（`run-20261116-231817`）：`busy_calls=11,608,214`、`log_bytes=471,187,542`、`throttled=0`、`drops=8,003,894`。

修法：只有 `r != SOCKET_ERROR` 才打标。

### 4.2 句柄复用继承 `discovery=true`

`MarkClosed()` 原先只置 `closed=true`，Winsock 句柄号会被复用，新 socket 一旦复用旧号即继承 `discovery=true` → 又变成全量写盘。

修法：关闭时同时复位 `discovery=false; lastLogMs=0`。

---

## 5 机械证据（`run-20261117-000112`，PASS 11/11，最终 DLL `ade54435…`）

自检脚本 `civtrace\run-logbound-selftest.ps1`（13,955 B / 287 行 / sha256 `E4544D81B439597875416B664D8A1D9D800D53A245033CFCA788038100D310C5`），自提权一次，载荷在**被注入的 powershell.exe 内**用裸 `ws2_32` P/Invoke 执行：

1. `WSAStartup(0x0202)`；
2. socket → `setsockopt(SO_BROADCAST)` → 向 `255.255.255.255:62900..62999` 各发 1 个 4 B datagram（`8D E8 FC 70`，与 Civ6 发现 magic 同字节）共 **100 个**；
3. 另开 socket `bind(0.0.0.0:0)` + `ioctlsocket(FIONBIO)`，**10 s 满速 `recvfrom` 忙轮询**（模拟 62056 数据面）。

### 5.1 结果

| 断言 | 实测 | 判据 |
|---|---|---|
| A1 注入退出码 | `0` | = 0 |
| A2 日志文件创建 | `civtrace_20261117_000125_pid35472_host.log` | 存在 |
| A3 `hooks installed ok=31 fail=0` | `matched=True len=712` | 日志内含 |
| A4 发现广播全记录 | `broadcast_lines=100` | = 100 |
| A5 忙轮询行数受限 | `recv_lines=50` | ≤ 55 |
| A6 日志体量 | `24,167 B` | ≤ 4 MiB |
| A8 卸载退出码 | `0` | = 0 |
| A9 会话行带 throttled | `found=True` | 含 `throttled=` |
| A10 限流计数为大数 | `13,935,201` | > 10,000 |
| A11 逐条对账 | `delta=0`（`13,935,201 + 50 == 13,935,251`） | = 0 |
| — 忙轮询次数 | `busy_calls=13,935,251`（10 s，≈1.39 M/s） | 与 Civ6 同量级 |

### 5.2 修复前后同一载荷

| | 修复前（`run-20261116-231817`，含 bug 4.1） | 修复后（`run-20261117-000112`，最终 DLL） |
|---|---|---|
| `busy_calls` | 11,608,214 | 13,935,251 |
| 会话期日志 | **471,187,542 B** | **24,167 B** |
| `throttled` | 0 | 13,935,201 |
| `drops` | 8,003,894 | 0 |
| 发现广播行 | 0（被爆盘挤掉） | **100（全保留）** |
| 字节/秒 | 47,118,754 | 2,416.7 |

降幅 ≈ **19,500×**（`471,187,542 / 24,167 = 19,497`）。

### 5.3 证据文件（`CivLink-M0A-audit\docs\reports\logbound\run-20261117-000112\`）

| 文件 | 字节 | sha256 |
|---|---|---|
| `raw-000113-pid35472.log` | 24,476 | `A347B502B86170864404EFA9B32FB2BB1D145EDD61215B1F3E249B7D6459126F` |
| `result.txt` | 6,314 | `309DB32BFD365E9F704C5CB7D912D72255416F8A2AE49BDB7114B78694F17916` |
| `sha256.txt` | 271 | `8080164683B400A8E7362067ED6AF29439A4D818BB81C6B77F037014D4C22B95` |

### 5.4 代码身份

| 文件 | 字节 | sha256 |
|---|---|---|
| `civtrace\civtrace.dll` | 247,296 | `ade54435fcc2af37d8d5c5731f7b3c3edbb0dbe98f15f22ac20731a7f79cea0e` |
| `civtrace\civinject.exe` | 171,520 | `eacde79727fca730fb04b29e1a0f173ea0a4e37f930b386cda7cfcd84d0aa71d` |
| `civtrace\civtrace_common.h` | 3,036 | （版本 0.4.5） |

> 历史构建均已作废，不得再分发：首个 v0.4.5 构建 `477E130B0891ED9D50069B3B0D17E8ABFD1BB6BAE401AAE2386F55D690C575E8`（含 4.1/4.2 两个 bug）、中间构建 `60232D932B110D52C017CE8206A95C59A91AE948EE728ACBA172992553A53843`（R-1 前，非原子全局窗口）。

---

### 5.5 REV-002 回归矩阵（最终 DLL `ade54435…`，2026-11-17 00:06–00:07）

限流只改日志行数，不改 Hook 行为，但按项目规矩仍须在**最终构建**上重跑 REV-002 的 T1–T15。

- 运行：`civtrace\test-rev002-elevated.cmd`（自提权 + Defender 排除），`docs\reports\rev002\done.txt` = `done 2026-11-17 00:07:19`。**教训（重要）**：`test-rev002.ps1` 自身**不自提权**，直接以普通权限运行会全部断言 FAIL（`EnableDebugPrivilege: NOT ALL ASSIGNED`）——必须经 `test-rev002-elevated.cmd`（cmd 内 UAC 自提权 + Defender 排除）；00:03–00:04 时间戳的 run-T*.txt 一轮为无效输出，须忽略。
- 断言：脚本输出 **39 条** `key=value (expect v)` 断言（脚本含 40 处 `(expect` 文本，其中 1 处为注释行 L166 `# baseline: read exact error…` 非断言输出），逐条比对 **39/39 一致**（其中 **4 条** expect 文本含分号或冒号+说明：T3 `unload_exit=0 (expect 0; second shutdown code=1 still confirms)`、T6 `inject_exit=0 (expect 0; DLL loads but no hooks)` 等，按分隔符前主值判对，属口径说明非不符）。注：比对为脚本产出 + **人工逐条核对**，脚本本身不内含自动比对代码（审计 CIVTRACE-LOGBOUND-REVIEW R-3 更正）。
- 关键值：T1 `dup_exit=0` / `unload_exit=0` / `module_left_mapped: True` / `hooks installed ok=31 fail=0` / `session end seq=124 drops=0 throttled=38`；T3 `unload_exit=0`（double-shutdown code=1 idempotent）；T4 `first_unload_exit=2` → `second_unload_exit=0`；T5 同；T8 `wrongdll_unload_exit=2` → `normal_unload_exit=0`；T9 `inject_exit=2`（ABORT, buffer left）；T10 `inject_exit=2` → `normal_inject_exit=0`；T13 `dumpbin_msvcp_vcruntime_lines=0`（/MT 静态 CRT 仍成立）、`g_inHook_residual=0`；T14 `first_unload_exit=2` → `second_unload_exit=0`、`timeout_line: 1`、`still_alive_after_timeout=True`、`blk_socket_done=True`；T15 `still_alive=True`、`mt_runs=6208`、`session_end: 1`。
- 版本证据：全部输出首行为 `civinject v0.4.5`；注入日志含 `throttled=`（v0.4.4 不存在该字段）。
- 旁证：`docs\reports\rev002\raw-233102-pid8072_host.log`（146,933 B）由 **T15** 产生；`raw-log-sha256.txt`（330 B）由 **T1/T2/T6** 产生并覆盖（T15 的 8072 日志不在哈希清单内，审计 CIVTRACE-LOGBOUND-REVIEW R-3 更正）。

---

## 6 证明与不证明

### 6.1 证明（限流使日志可长期运行）

1. 发现广播 100/100 全记录（A4）——**关注流量零损失**。
2. 同一时刻高频非发现 socket 被 200 ms 窗口折叠（A5），字节/秒降到 2.4 KB/s（A6）。
3. 折叠是**计数**而非静默丢弃（A10 + A11 delta=0）。**口径限定（审计 CIVTRACE-LOGBOUND-REVIEW R-4）**：A11 恒等式（`throttled + recorded == total calls`）仅对走 `ThrottleRead`/`ThrottleGlobal` 的 API（recvfrom/WSARecvFrom/select/WSAPoll/WSASend/WSARecv/WSAWaitForMultipleEvents）成立；`GetQueuedCompletionStatus`/`GQCSEx`（trace_dll.cpp L1284-1342）使用独立 `call#` 采样计数，**不计入 `throttled`**，不属于该恒等式覆盖范围。
4. 卸载链在限流后仍正常（A8 `unload_exit=0`，B2 审计运行模式日志行可见）。
5. 31 个 Hook 全部安装成功（A3）。

### 6.2 不证明

1. **不证明 Civ6 真实 62056 场景下的最终体积**——本自检用合成忙轮询（1.36 M/s）近似；真实对局中如有多个高频 socket 或 `select` 多路复用，行数按 socket 数线性增长（每 socket 200 ms 1 行）。
2. **不证明不会遗漏"状态变化"**：200 ms 窗口内若同一 socket 从 `WSAEWOULDBLOCK` 变为"收到数据"，窗口内**第一次**调用就被记录，因此转变可见；但若在同一窗口内连续出现两次不同结果，只有第一次被记录。
3. **不证明发现 socket 判定无假阴**：若某 socket 只 `recvfrom` 而不 `bind`/`sendto` 到发现端口（理论上不成立，发现 socket 必然先 bind 62900–62999），它会被当作普通 socket 限流。
4. **不证明 62056 数据面 Hook 观测路径不丢帧**（该问题属 M0-B 未验证项，F3-D 已登记）。
5. **不证明跨进程/多实例**：每个被注入进程各自限流、各自计数。

---

## 7 运行历史（同脚本，同 DLL 版本演进）

| 运行 | 结果 | 说明 |
|---|---|---|
| `run-20261116-231608` | FAIL | 首次冒烟，载荷侧 `Environment.TickCount64` 不存在（.NET 4.8），改用 `Stopwatch` |
| `run-20261116-231817` | FAIL 6/11 | 暴露 bug 4.1（471 MB、throttled=0）；A3 亦失败（见下） |
| `run-20261116-232318` | FAIL 10/11 | bug 4.1/4.2 已修；**唯一失败 A3**：脚本用 `[IO.File]::ReadAllText` 读正在被 DLL 持有的日志，抛异常后 `$ErrorActionPreference='Continue'` 使 `$t=$null`，`-match` 恒 False，白等 10 s |
| `run-20261116-232727` | PASS 11/11 | A3 改为 `FileShare.ReadWrite` 共享读并回显异常文本；一次通过（中间构建 `60232D93…`） |
| `run-20261117-000112` | **PASS 11/11** | **R-1 修复后最终轮**（`g_lastGlobalLogMs` 原子化，`ade54435…`）；A3 复用共享读；`delta=0`、`broadcast=100` |

A3 的教训已写进脚本注释：**读活日志必须共享读**，且断言失败信息要带 `len=` 与异常文本，否则"读失败"会被误读成"内容不符"。

---

## 8 关系

- 缺陷报告：用户 2026-11-16（"日志直接把我c盘爆了"）。
- 上游事实：F2 S5（62056 忙轮询、8 B 数据面帧）、E2-B 首轮（`M0A\captures\E2B-firstround-20261116\`）。
- 回归基线：`civtrace\test-rev002.ps1`（REV-002 T1–T15 矩阵，29,560 B）。该矩阵跑过三次：v0.4.5 首个（含 bug 的）构建 `477E130B…` 39/39；中间构建 `60232D93…` 2026-11-16 23:31:02 39/39；**最终构建 `ade54435…` 2026-11-17 00:07:19 39/39**（见 §5.5）。
- 下游：E2-B 重跑必须用本版 DLL。

---

## 9 下一步

1. ~~用最终 DLL `60232D93…` 重跑 REV-002 T1–T15~~ —— **已完成，39/39**；R-1 原子化后再跑最终轮 `ade54435…` 39/39（见 §5.5）。
2. 更新核验包二进制为 `ade54435…` / `eacde797…`：`M0A\pcb-kit\`、`C:\Users\dd\Desktop\pcb-kit\`、`C:\Users\dd\Desktop\pcb-kit.zip` 与 `MANIFEST-sha256.txt`。
3. 子代理独立审计本文件与本修复（机制/证据/表述边界）——R-1~R-4 落实确认（R-1 代码原子化、R-2 推断标注、R-3 断言口径 39/39、R-4 恒等式限定）。
4. E2-B 用限流后的 DLL 重跑，取 H6 发现窗口数据（`analyze-trace.ps1 -Discovery`、`analyze-h6-window.ps1 -RelayRttMs 50`）。
