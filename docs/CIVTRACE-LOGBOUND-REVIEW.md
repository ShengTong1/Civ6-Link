# CIVTRACE-LOGBOUND-REVIEW — civtrace v0.4.5 日志限流修复审计裁定

- 审计角色：独立 codex 审计员（只出裁定，未改动任何文件）
- 审计对象：`docs\CIVTRACE-LOGBOUND-20261116.md`（12,811 B / sha256=8CA7F8DBE7EB7B41870AB35E9B3167684F2CA5C78CA9A6E48E3EC241CEE3DD98 / 225 行）
- 审计方法：逐行读代码（`civtrace\trace_dll.cpp` 全 1,577 行、`civtrace_common.h`）、实测全部声称哈希（Get-FileHash SHA256）、实测全部声称计数（result.txt/run-*.txt/raw 日志逐行核对）、复核分发点（civtrace\、M0A\pcb-kit、Desktop\pcb-kit、pcb-kit.zip）
- 裁定日期：2026-11-16（审计时点 23:5x，+08:00）
- 上一版失败审计的同名文件在此前已删除/不存在，本文件为全新裁定（同名覆盖完成）

---

## 一、裁定：**有条件通过（CONDITIONAL PASS）**

限流修复本身**通过核验**：机制按文档实现（落点逐行确认）、PASS 轮证据链全部吻合（哈希 100%、计数 100%、A11 delta=0）、REV-002 回归 39/39 实测一致、两个 bug 的修复代码（`r!=SOCKET_ERROR` 才打标 / MarkClosed 复位 discovery+lastLogMs）均确认存在且正确、分发点全部为最终版 60232D93。

不构成阻断，但发布前必须完成 3 项修正：

1. **中/必改**：`trace_dll.cpp:501` 的 `g_lastGlobalLogMs` 是**非原子** `ULONGLONG`，`ThrottleGlobal`（L502-507）无锁读改写 → 新引入的数据竞争（详见 B1）。
2. **中/必改**：文档 §4 把 4.1/4.2 表述为已证实，但二者是同一组计数证据的两种可替换解释，且 231817 的 raw 日志未留存 → 直接证据缺口需在文档标注（详见 D1）。
3. **低/必改**：文档 4 处表述与磁盘/脚本事实不符：§3 字节数（79,168→79,373）、§5.5 计数口径（39→40、"自动比对"不存在、分号 2→4、raw-log-sha256.txt 归因错误）。

---

## 二、分级清单

### 阻断（Blocking）
无。

### 高（High）
无。

### 中（Medium）

**B1 — `g_lastGlobalLogMs` 数据竞争（新引入，v0.4.5 特有）**
- 位置：`civtrace\trace_dll.cpp:501-507`（`static ULONGLONG g_lastGlobalLogMs = 0;` + `ThrottleGlobal()` 读改写，**不持 g_mu、非原子**）。
- 问题：多线程并发调用 `WSAWaitForMultipleEvents`（该 hook 在 L1159-1160 直接调 `ThrottleGlobal()`）时，两个线程可同时通过 200ms 窗口检查 → 全局窗口"至多 1 条/200ms"不是硬保证；可能双记录、`g_throttled` 双计数。x64 下对齐的 8 字节读写实际表现为原子（无撕裂），故现实影响有界（窗口内偶发多 1 行），但按 C++ 标准是数据竞争（UB），TSAN 会报。
- 改法（二选一）：
  - `static std::atomic<ULONGLONG> g_lastGlobalLogMs{0};`，`ThrottleGlobal` 用 CAS 循环：`ULONGLONG prev = g_lastGlobalLogMs.load(relaxed); if (now - prev < kThrottleMs) { g_throttled.fetch_add(1, relaxed); return true; } else if (g_lastGlobalLogMs.compare_exchange_weak(prev, now, relaxed, relaxed)) return false;`（失败则重试）；
  - 或直接持 `g_mu` 包住整个函数体（与 `ThrottleRead` 一致）。
- 注意 `g_throttled`（L181）本身是 `std::atomic` + `fetch_add(relaxed)`，**无问题**；`ThrottleRead`（L491-499）持 `g_mu`，**无问题**。竞争仅在全局窗口一处。

**D1 — §4 两个"真 bug"的直接证据缺口（文档表述问题）**
- 事实：run-20261116-231817（477E130B 时代）`throttled=0 / log_bytes=471,187,542 / A11 delta=8,003,894` 与"忙句柄被 discovery 豁免"方向一致，但：
  1. 4.1（INVALID_SOCKET 被无条件 MarkDiscovery 豁免）与 4.2（句柄复用继承 discovery）是**同一组计数证据的两种可替换解释**，文档未拆分归因；
  2. 231817 的 **raw 日志未留存**（result.txt 在、raw 不在），"sendto(s=-1)→10093→MarkDiscovery(-1)" 机制链条**无直接日志证据**；
  3. 无针对任一 bug 的专门复现 run（232318 已通过 → 4.2 在 232318 前已修，但 4.1/4.2 各自"未修时爆日志"未被分别演示）。
- 支持性旁证：REV-002 T15 日志（raw-233102-pid8072_host.log）有大量 `socket … ret=0xffffffffffffffff err=10093`（WSAENOTINITIALISED）行，证明本环境真实存在 Winsock 未初始化即调 socket 的代码路径 → 4.1 所述场景**现实可能**，但不等同于证实。
- 改法：文档 §4 补注"计数一致但未直接复现，属合理推断"；或补一次针对性复现（在 WSAStartup 前以 s=INVALID_SOCKET 调 sendto 制造 10093 → 忙循环 → 观察 throttled=0），留存 raw 日志与哈希。

### 低（Low）

**A1 — select / WSAPoll 代表 fd 的边界漏限（近似，文档已声明但仍有两处缺口）**
- `trace_dll.cpp:812-813`：select 只对 `rset->fd_array[0]` 判 `ThrottleRead`，**wset/eset 的忙 socket 完全不被限流**；且若首 fd 恰是 discovery socket，整行豁免（不限流）。
- `trace_dll.cpp:1040`：WSAPoll 以 `fds[0].fd` 代表，同理。
- 影响：Civ6 实际以单 socket 调 select/WSAPoll 为主，罕见；但文档 §2.2 的"每 200ms 至多 1 条"在 wset 热 socket 上不成立。
- 改法（可选，不阻断）：wset/eset 也各取首 fd 检查；或对 fd_array 全表取"任一非 discovery 者"作代表。

**C1 — §3 字节数错误**：文档标题声称 trace_dll.cpp "1,577 行 / 79,168 B"，实测 **79,373 B**（差 205 B；行数 1,577 正确；sha256=45AD7C75529027AD1BD5917F7CD250E3BE9BD9FB1D028EDE60F2136E8727F635，mtime 23:20:16 早于 DLL 构建 23:22:57，与最终 DLL 一致）。

**C2 — §5.5 "39 条 key=value (expect v)，自动比对 39/39" 口径错误**：`civtrace\test-rev002.ps1`（29,560 B）实测含 **40** 条 `(expect` 标注行（T1×3、T3×2、T4×3、T5×3、T6×2、T7×2、T8×3、T9×1、T10×3、T11×2、T12×2、T13×4、T14×7、T15×3），且**脚本内不存在自动比对代码**（仅输出带 expect 标注的 key=value 行，无比较循环）。"自动比对"表述不成立；39 vs 40 差 1。实质性结论不受影响：审计抽查 run-T1/T3/T4/T5/T8/T9/T10/T13/T14/T15 输出，全部 key=value 与 expect 一致。

**C3 — §5.5 "2 条 expect 文本含分号" 计数错误**：脚本实测 **4 条**含分号 expect：L223（T1）、L254（T3）、L286（T6）、L345（T11）。文档举的例（T3 "expect 0; second shutdown code=1 still confirms"）正确存在，但少算 2 条。

**C4 — §5.5 "raw-log-sha256.txt（330 B）由 T15 产生" 归因错误**：该文件由 `test-rev002.ps1:428-430` 生成，覆盖 **T1/T2/T6** 三个日志（`civtrace_20261116_232927_pid31900_host.log` d9aa7e08…、`…232939_pid16084…` 8934d0f4…、`…232959_pid20496…` 963e3802…），**不含 T15（8072）日志**。T15 日志本身存在（rev002\raw-233102-pid8072_host.log 146,933 B / sha256=78FCC6EF19E5444BB87BFC5673ED3512D699EC97D387649CB83D58C834D0996A，即 %LOCALAPPDATA%\…\civtrace_20261116_233059_pid8072_host.log 的副本），但未被该哈希清单覆盖。

**E1 — A11 恒等式口径未标注适用范围**：`throttled + recorded == total calls` 仅对走 `ThrottleRead`/`ThrottleGlobal` 的 API 成立；GQCS/GQCSEx（`trace_dll.cpp:1284-1342`）用独立 `++g_gqcsCalls` 采样（`n<=50 || n%1000==0` 才 Emit），**跳过行不计入 g_throttled** → 存在 GQCS 热循环时，会话行 `throttled` 会低估被折叠的调用数。自检载荷无 GQCS，故 delta=0 成立。文档应在 §6"不证明"中补该口径（见 §五-E）。

### 信息（Info）

**F1** — run-20261116-231817 的 raw 日志未留存（该 run 是 4.1 唯一计数证据来源；471,187,542 B 日志本体已不在磁盘，logs 目录现 116 文件共 4,523,746 B，无残留大文件）。文档 §1 的 "drops=8,003,894" 只能对应 result.txt 的 A11 delta 字段（会话行 drops 无法交叉验证）。

**F2** — 作废构建 477E130B0891ED9D50069B3B0D17E8ABFD1BB6BAE401AAE2386F55D690C575E8 在检索到的所有分发点（civtrace\、M0A\pcb-kit、Desktop\pcb-kit、pcb-kit.zip）均不存在（全部为 60232D93）——与"已作废、不得再分发"一致，但"含 4.1/4.2"的断言不可再对实物独立验证。REV-002 首轮（23:11，477E130B 时代）的 run-*.txt 已被二轮覆盖，仅 raw 日志留存（raw-231111…raw-231237 共 15 个）。

**G1** — Defender 排除状态当前不可复核：本审计会话非管理员，`Get-MpPreference` 返回占位符（"Must be an administrator to view exclusions"）。脚本行为已核：`run-logbound-selftest.ps1:54-55` 加排除、L284 移除；`test-rev002-elevated.cmd` 对 civtrace 与 rev002 目录添加排除且**不删除**（按设计保留）。建议在文档记录这两条永久排除，便于日后审计清理。

**G2** — 日志累积卫生：%LOCALAPPDATA%\CivLink\M0A\logs 累积 116 个历史日志（每次测试遗留多个）；rev002 目录累积约 90+ 个历史 raw 副本（raw-01xx/10xx/11xx/12xx/21xx/22xx/23xx，含 2,583,913 B 的 raw-215723-pid36020.log 与 455,961 B 的 raw-220305-pid29336.log）。建议引入清理策略（保留最后 N 轮）。

**A2** — `NoteSock`（L446-452）句柄复用 `gen++` 时**不复位 discovery/lastLogMs**，仅依赖 `MarkClosed`（L468 复位）。因 `closesocket` 已挂钩（L823-834 调 MarkClosed），正常关闭路径安全；仅当关闭绕过 hook（进程崩溃等）时复用可能继承旧 discovery。低概率，可顺手在 NoteSock 复位。

---

## 三、必改位置与改法汇总

| # | 位置 | 改法 | 级别 |
|---|---|---|---|
| 1 | `civtrace\trace_dll.cpp:501-507` | `g_lastGlobalLogMs` 改 `std::atomic<ULONGLONG>` + CAS 循环，或持 `g_mu` | 中/必改 |
| 2 | 文档 §4 | 4.1/4.2 标注"计数一致但未直接复现（231817 raw 缺失）"；或补针对性复现 run 留 raw | 中/必改 |
| 3 | 文档 §3 | `79,168 B` → `79,373 B` | 低/必改 |
| 4 | 文档 §5.5 | 39→40 条；删除"自动比对"（改注"比对口径为作者人工核验"）；"2 条分号"→"4 条分号"（L223/L254/L286/L345）；raw-log-sha256.txt 归因改"T1/T2/T6" | 低/必改 |
| 5 | 文档 §2.4/§6 | A11 适用范围补注 GQCS/GQCSEx 例外 | 低/必改 |
| 6 | `trace_dll.cpp:812-813, 1040`（可选） | wset/eset 检查、全表代表 | 低/可选 |
| 7 | `trace_dll.cpp:446-452`（可选） | NoteSock 复位 discovery/lastLogMs | 低/可选 |

---

## 四、证据逐项核验表（全部实测，非采信文档断言）

| 工件 | 文档声称 | 实测 | 结论 |
|---|---|---|---|
| CIVTRACE-LOGBOUND-20261116.md | 12,811 B / 8CA7F8DB… / 225 行 | 12,811 B / 8CA7F8DB… / 225 行 | ✓ |
| civtrace.dll | 247,296 B / 60232D93… | civtrace\、M0A\pcb-kit、Desktop\pcb-kit、pcb-kit.zip 四处均 247,296 B / 60232D93… | ✓ |
| civinject.exe | 171,520 B / 4C1E1D0D… | 同上四处均一致 | ✓ |
| civtrace_common.h | 3,036 B | 3,036 B，L7 `CIVTRACE_VERSION "0.4.5"` | ✓ |
| trace_dll.cpp | §3：1,577 行 / **79,168 B** | 1,577 行 / **79,373 B**（sha 45AD7C75…，mtime 23:20:16 < DLL 23:22:57） | ✗ 字节数差 205 B |
| run-logbound-selftest.ps1 | 13,955 B / 287 行 / E4544D81… | 13,955 B / 287 行 / E4544D81… / mtime 23:27:02 | ✓ |
| run-232727\raw-232729-pid12256.log | 24,476 B / 2DAB1D9A… | 24,476 B / 2DAB1D9A…；165 行逐行核对：seq#10-109 100 条 sendto dst=255.255.255.255:62900-62999 len=4 ret=4 data=8d e8 fc 70、#113-162 50 条 recvfrom WSAEWOULDBLOCK 间隔≈200ms、末尾 `session end seq=164 drops=0 throttled=13647844` | ✓ |
| run-232727\result.txt | 6,626 B / 62ED0B06… | 6,626 B / 62ED0B06…（UTF-16LE）；busy_calls=13,647,894 / throttled=13,647,844 / recorded=50 / A11 delta=0（tol=272,958）/ bytes_per_second=2416.7 / broadcast_lines=100 / recv_lines=50 / A3 matched=True len=712 / unload_exit=0 / checks=11 failures=0 | ✓ |
| run-232727\sha256.txt | 271 B / E2DAFFDA… | 271 B / E2DAFFDA…；3 行内容一致 | ✓ |
| §5.2 降幅 | 471,187,542→24,167 ≈ 19,497× | 471,187,542÷24,167=19,497.07；47,118,754.2→2,416.7 B/s | ✓ |
| run-231817\result.txt | busy_calls=11,608,214 / 471,187,542 B / throttled=0 | 全吻合（A11 delta=8,003,894、recorded=3,604,320）；**raw 日志缺失** | ✓值 / ✗缺 raw |
| run-232318\result.txt | FAIL 10/11，唯一失败 A3 | 吻合（throttled=11,701,239 / delta=0 / broadcast=100 / recv=50 / session end seq=164 throttled=11,701,239） | ✓ |
| run-232727 | PASS 11/11 | 吻合 | ✓ |
| REV-002 done.txt | "done 2026-11-16 23:31:02" | 29 B 同文本（sha 679708FA…，mtime 23:31:02） | ✓ |
| REV-002 raw-233102-pid8072_host.log | 146,933 B（T15） | 146,933 B / 1,225 行 / sha 78FCC6EF…；尾 `session end seq=1224 drops=0 throttled=0`；头 civtrace 0.4.5 + hooks ok=31 fail=0 + socket err=10093 行 | ✓ |
| REV-002 raw-log-sha256.txt | 330 B（称由 T15 产生） | 330 B，3 行 = T1/T2/T6 日志哈希（d9aa7e08…/8934d0f4…/963e3802…）；**不含 8072** | ✗ 归因错 |
| REV-002 run-T1 | dup_exit=0 / unload_exit=0 / module_left_mapped True / ok=31 fail=0 / seq=124 drops=0 throttled=38 | 全吻合 | ✓ |
| REV-002 run-T4/T5 | first_unload_exit=2 → second_unload_exit=0 | 全吻合 | ✓ |
| REV-002 run-T8 | wrongdll_unload_exit=2 → normal_unload_exit=0 | 全吻合 | ✓ |
| REV-002 run-T9 | inject_exit=2 | 吻合（"not confirmed -> ABORT, buffer left"） | ✓ |
| REV-002 run-T10 | inject_exit=2 → normal_inject_exit=0 | 全吻合 | ✓ |
| REV-002 run-T13 | g_inHook_residual=0 / dumpbin_msvcp_vcruntime_lines=0 | 全吻合（t_socket_decl=1 / findpids_dynamic=1） | ✓ |
| REV-002 run-T14 | first_unload_exit=2 → second_unload_exit=0 / timeout_line:1 / still_alive_after_timeout=True / session_end:1 | 全吻合 | ✓ |
| REV-002 run-T15 | still_alive=True / mt_runs=6208 / session_end:1 / unload_exit=0 | 全吻合 | ✓ |
| 作废构建 477E130B… | "已作废，不得再分发" | 检索 4 个分发点均不存在（全为 60232D93） | ✓（不可再验"含两 bug"） |
| M0A\pcb-kit / Desktop\pcb-kit / pcb-kit.zip | §9 更新 TODO | 均存在且含最终版；MANIFEST 生成 23:33、zip 23:34:37（晚于文档 23:32:05，TODO 已实际完成） | ✓ |
| test-rev002.ps1（civtrace\） | §8：29,560 B | 29,560 B / 435 行 / sha 3243A61D…；40 条 (expect 行；无自动比对代码 | ✓大小 / ✗§5.5 口径 |
| 限流实现落点 | §3 表 | 逐行确认：L181/L189/L191-199/L341-360/L465-472/L476-507/L684/L709/L734/L759/L787/L811-814/L1040/L1065/L1086/L1160/L1284-1342/L1485 | ✓ |

---

## 五、审计要求 A–G 逐项结论

**A 机制审查**：限流设计（200ms 折叠、发现判定、全局窗口）在代码中如文档所述实现，落点全部逐行确认（bind L684 需 `r==0`、sendto/WSASendTo L709/L734 需 `r!=SOCKET_ERROR`、recvfrom/WSARecvFrom/WSASend/WSARecv 走 ThrottleRead、select/WSAPoll 代表 fd、WSAWaitForMultipleEvents 走 ThrottleGlobal）。边界漏限 2 处（A1，低）：select 仅 rset 首 fd、wset/eset 不限；代表 fd 为 discovery 时整行豁免。句柄复用复位仅依赖 MarkClosed（A2，低，可选加固）。

**B 并发审查**：`g_throttled`（L181）为 `std::atomic` + relaxed fetch_add，**正确**；`ThrottleRead`/SockInfo 访问持 `g_mu`，**正确**；**新引入数据竞争 1 处**：`g_lastGlobalLogMs`（L501）非原子、`ThrottleGlobal`（L502-507）无锁读改写（B1，中，必改）。无其它新竞争（g_inFlight/g_tlsInHook/g_gqcsCalls 均为原子或线程局部/单写者）。

**C 证据一致性**：§5.1 证据表、§5.2 前后对比（19,497× 及 bytes/s）、§5.3 哈希、§5.4 代码身份、§5.5 REV-002 全部关键值与磁盘一致（核验表见上）。4 处表述级出入（C1-C4，低）：§3 字节数 79,168→79,373；§5.5 "39 条/自动比对/2 条分号"（实为 40 条/无自动比对代码/4 条分号）；§5.5 raw-log-sha256.txt 归因（实为 T1/T2/T6，非 T15）。

**D 两真 bug 叙述**：两处修复在代码中确认存在且正确（L709/L734 `r!=SOCKET_ERROR` 条件打标；L468 MarkClosed 复位 `discovery=false; lastLogMs=0`），closesocket 已挂钩保证 MarkClosed 必达。但文档 §4 的"证实"语气超出证据：4.1 与 4.2 是同一组 231817 计数的可替换解释、231817 raw 缺失、无分 bug 复现（D1，中）。旁证：T15 日志含真实 socket err=10093 行，场景现实存在。

**E 表述边界**：未发现"限流不丢发现流量 = E2-B 双机成功"式混淆——§6 明确把"真实 62056 体积、E2-B 重跑、发现判定假阴、跨进程各自限流"列为不证明项；§5.2 对比为同一自检载荷前后对比（471,187,542 B vs 24,167 B，可比）。需补：A11 恒等式适用范围（GQCS/GQCSEx 不参与计数，E1，低）；另 231817 的 "drops=8,003,894" 应注明取自 result.txt A11 delta，而非会话行 drops（会话行无法交叉验证）。

**F 缺失证据**：① run-231817 raw 日志缺失（4.1 机制不可直接证实）；② 作废构建 477E130B 全盘分发点不存在（"含两 bug"不可对实物验证）；③ REV-002 首轮（477E130B）的 run-*.txt 被二轮覆盖，仅 raw 留存；④ T15 日志未进 raw-log-sha256.txt（但本体存在）。

**G 安全运维**：日志路径 %LOCALAPPDATA%\CivLink\M0A\logs 正确（会话行回显 + A2 实测）；当前 116 文件共 4.5 MB，无失控日志（15.4GB 已清理）；A3 文件句柄共享读（FileShare.ReadWrite）修复有效（232727 PASS，232318 的 $t=$null 教训已解决）；Defender 排除策略行为正确（selftest 自加自删；elevated cmd 保留 2 条目录排除），当前状态非管理员会话不可复核（G1）；日志累积卫生建议清理（G2）；分发点全部为最终版、作废版不在流通（G3，正向）。

---

## 六、结论

功能修复真实、有效、可复现（PASS 11/11 + REV-002 39/39 + 哈希全对 + 两 bug 修复在代码中确认），**有条件通过**。阻断项为零；发布前完成 B1 数据竞争修复与文档 4 处修正（C1-C4、D1、E1）即可转正式通过。可选加固：A1（select/WSAPoll 代表 fd）、A2（NoteSock 复位）、G2（日志清理）。
