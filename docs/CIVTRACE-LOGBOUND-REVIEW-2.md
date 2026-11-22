# CivLink M0-A civtrace v0.4.5 日志限流修复 复审（REVIEW-2）

- 复审对象：civtrace v0.4.5 日志限流修复（per-socket 200ms 限流，发现 socket 全记录、其余折叠计数 g_throttled）
- 复审依据：CIVTRACE-LOGBOUND-REVIEW.md（首轮审计，必改项 R-1~R-4）
- 被审文档：docs\CIVTRACE-LOGBOUND-20261116.md（228 行，UTF-8）
- 复审时间：2026-11-17 00:22 +08:00
- 检查方法：只读核验；源码/文档用 read 工具逐行读取并记录行号；哈希用 Get-FileHash -Algorithm SHA256（大写）；断言口径用 grep 实测；zip 用 System.IO.Compression.ZipFile 解压后逐文件 SHA256 比对。所有断言均附实测值。

## A. 代码核验（R-1）：通过

实测文件：`civtrace\trace_dll.cpp`（1,583 行，79,923 B；read 工具确认 "of 1583"）。

1. **原子化 + CAS 已落实**：
   - L503：`static std::atomic<ULONGLONG> g_lastGlobalLogMs{0};` —— 已由非原子 ULONGLONG 改为 `std::atomic<ULONGLONG>`（原缺陷位于首轮审计 B1 所指的 trace_dll.cpp:501-507 非原子读写）。
   - L504-513 `ThrottleGlobal()`：
     - L505 `ULONGLONG now = GetTickCount64();`
     - L506 `ULONGLONG prev = g_lastGlobalLogMs.load(std::memory_order_relaxed);`
     - L507 `if (now - prev < kThrottleMs) { g_throttled.fetch_add(1, relaxed); return true; }`
     - L509 `while (!g_lastGlobalLogMs.compare_exchange_weak(prev, now, std::memory_order_relaxed)) {`
     - L510 `if (now - prev < kThrottleMs) { g_throttled.fetch_add(1, relaxed); return true; } }`
     - L512 `return false;`（CAS 成功、窗口内判定通过 → 放行记日志）
     - L508 注释「失败者计入 throttled（与读侧一致）」。
   - **CAS 语义核验**：CAS 失败者若仍超窗（now-prev ≥ kThrottleMs），并不直接计 throttled，而是由 compare_exchange_weak 的副作用将 prev 更新为他人写入的新值后重试循环，直至 CAS 成功（return false 放行）或落入窗口（计 throttled return true）。GetTickCount64 单调递增保证终止，无活锁；计数只统计实际被抑制的行，无双计。该语义正确实现 R-1 要求。
2. **无新死锁/竞态**：ThrottleGlobal 只用原子变量、不持 g_mu；ThrottleRead（L491-499）维持原状，持 g_mu 访问 `SockInfo.lastLogMs`（struct SockInfo L191-198，含 `bool discovery=false; ULONGLONG lastLogMs=0;`）。两路径无嵌套锁、无锁序反转 → 未引入新死锁。relaxed 内存序对单调时间戳窗口启发已足够，无数据竞争残留（g_lastGlobalLogMs 的所有读写均经 atomic load/store/CAS）。
3. **配套调用点确认（旁证 R-1 覆盖范围）**：ThrottleRead 调用点 L765(recvfrom)、L793(WSARecvFrom)、L819(select rset->fd_array[0])、L1046(WSAPoll fds[0].fd)、L1071(WSASend)、L1092(WSARecv)；ThrottleGlobal 调用点 L1166(WSAWaitForMultipleEvents)。发现 socket 打标：L690 `if (r == 0 && IsDiscoveryDst(name, namelen)) MarkDiscovery(s);`（bind）；L715/L740 `if (r != SOCKET_ERROR && IsDiscoveryDst(to, tolen)) MarkDiscovery(s);`（sendto/WSASendTo，仅成功调用打标）；L468 MarkClosed 复位 `discovery=false; lastLogMs=0`。R-4 相关代码：L180 `static std::atomic<unsigned long long> g_gqcsCalls{0};`，Hook_GetQueuedCompletionStatus（L1291-1320）/Hook_GetQueuedCompletionStatusEx（L1322-1340）用 `unsigned long long n = ++g_gqcsCalls; if (n <= 50 || n % 1000 == 0)` 独立采样，不调 ThrottleRead/ThrottleGlobal、不增 g_throttled。

**A 项裁定：通过。**

## B. 文档核验（R-2/R-3/R-4）：逐项通过

被审文档：`docs\CIVTRACE-LOGBOUND-20261116.md`（228 行；首轮审计时为 225 行/12,811 B/8CA7F8DB…）。

1. **R-2（§4 证据标注）——通过**。L93 存在标注块，原文要点：4.1 与 4.2 是**同一组 run-20261116-231817 计数（throttled=0、471 MB）的两种可替换解释**，且 231817 轮 raw 日志未留存（现场清理），**机制本身无直接日志证据**；两处根因由代码审查确认；旁证为 REV-002 T15 日志中真实存在的 `socket … err=10093` 调用（docs\reports\rev002\raw-233102-pid8072_host.log 尾部 3 行）；修复后行为已由 232727 轮机械证据直接证明（broadcast=100 全记录、throttled>0、delta=0）。「推断/未直接复现」措辞准确。
2. **R-3（§5.5 断言口径）——通过**。L173 写：脚本输出 **39 条** key=value (expect v) 断言（脚本含 40 处 `(expect` 文本，其中 1 处为注释行 L166 `# baseline: read exact error…` 非断言输出），逐条比对 **39/39 一致**（其中 **4 条** expect 文本含分号或冒号+说明，按分隔符前主值判对，属口径说明非不符），并注明比对为脚本产出 + **人工逐条核对**、脚本本身不内含自动比对代码。实测：test-rev002.ps1 grep `(expect` 恰好 40 处，L166 确为注释行；含分号 4 条 = L223(T1)/L254(T3)/L286(T6)/L345(T11)；脚本内无自动比对代码（仅输出 key=value 行）。
3. **R-3（§5.5 旁证归因）——通过**。L176 写：raw-233102-pid8072_host.log（146,933 B）由 **T15** 产生；raw-log-sha256.txt（330 B）由 **T1/T2/T6** 产生并覆盖（T15 的 8072 日志不在哈希清单内）。实测：raw-233102 文件 146,933 B；raw-log-sha256.txt 330 B，内容 3 行 = civtrace_20261117_000544_pid19688 / _000556_pid32436 / _000616_pid30136（无 8072）；脚本 test-rev002.ps1 L428-430 的 `Get-FileHash $la.FullName, $lb.FullName, $lf.FullName` 中 $la=Get-LogFor $A.Id(L213,T1)、$lb=Get-LogFor $B.Id(L237,T2)、$lf=Get-LogFor $F.Id(L288,T6)。
4. **R-4（§6.1 第 3 条限定）——通过**。L186 写：A11 恒等式（throttled + recorded == total calls）仅对走 ThrottleRead/ThrottleGlobal 的 API（recvfrom/WSARecvFrom/select/WSAPoll/WSASend/WSARecv/WSAWaitForMultipleEvents）成立；GetQueuedCompletionStatus/GQCSEx（引用 trace_dll.cpp L1284-1342）使用独立 call# 采样计数，**不计入 throttled**，不属于该恒等式覆盖范围。代码实测 GQCS/GQCSEx 实际位于 L1291-1340，引用的区间为近似描述，但限定语义正确。
5. **R-3（§3 标题）——通过**。L60 写「1,583 行 / 79,923 B」；实测 trace_dll.cpp = 79,923 B、1,583 行（首轮审计时 1,577 行/79,373 B 的错误已修正）。
6. **§5.4 哈希与旁证（配套抽查）——通过**。L160-161 声明的 civtrace.dll 247,296 B / ade54435…、civinject.exe 171,520 B / eacde797…、civtrace_common.h 3,036 B（L7 CIVTRACE_VERSION "0.4.5"）均与实测一致；run-logbound-selftest.ps1 13,955 B / E4544D81B439597875416B664D8A1D9D800D53A245033CFCA788038100D310C5、test-rev002.ps1 29,560 B / 3243A61D82E77767093B232558537D277A0025452DFCC48E6C738CB52EADF929、done.txt「done 2026-11-17 00:07:19」均与实测一致。

**B 项裁定：通过。**

## C. 证据一致性：逐项通过（实测哈希，SHA256 大写）

1. `civtrace\civtrace.dll`：247,296 B，SHA256 = `ADE54435FCC2AF37D8D5C5731F7B3C3EDBB0DBE98F15F22AC20731A7F79CEA0E`，与预期 `ade54435fcc2af37d8d5c5731f7b3c3edbb0dbe98f15f22ac20731a7f79cea0e` 一致 ✓
2. `civtrace\civinject.exe`：171,520 B，SHA256 = `EACDE79727FCA730FB04B29E1A0F173EA0A4E37F930B386CDA7CFCD84D0AA71D`，与预期 `eacde79727fca730fb04b29e1a0f173ea0a4e37f930b386cda7cfcd84d0aa71d` 一致 ✓
3. `docs\reports\logbound\run-20261117-000112\` 三文件：
   - raw-000113-pid35472.log：24,476 B，SHA256 = `A347B502B86170864404EFA9B32FB2BB1D145EDD61215B1F3E249B7D6459126F` ✓
   - result.txt：6,314 B，SHA256 = `309DB32BFD365E9F704C5CB7D912D72255416F8A2AE49BDB7114B78694F17916` ✓
   - sha256.txt：271 B，SHA256 = `8080164683B400A8E7362067ED6AF29439A4D818BB81C6B77F037014D4C22B95` ✓
   - result.txt 关键值实测：busy_calls=13935251、log_bytes_during_session=24167、throttled=13935201、broadcast_lines=100 recv_lines=50、A3~A11 全 PASS（A11：delta=0 tol=278706 calls=13935251 throttled=13935201 recorded=50）、bytes_per_second=2416.7、checks=11 failures=0、unload_exit=0、session end seq=164 drops=0 throttled=13935201。
4. `docs\reports\rev002\done.txt` = 「done 2026-11-17 00:07:19」✓；rev002 目录 15 个 run-T*.txt 全部存在；抽查关键行与文档一致：run-T1（dup_exit=0、unload_exit=0、module_left_mapped: True、hooks installed ok=31 fail=0、session end seq=124 drops=0 throttled=38）、run-T4（first_unload_exit=2 → second_unload_exit=0）、run-T14（first_unload_exit=2 → second_unload_exit=0、still_alive_after_timeout=True、blk_socket_done=True、timeout_line: 1、session_end: 1）、run-T15（still_alive=True、mt_runs=6208、session_end: 1、inject_exit=0、unload_exit=0）。raw-233102-pid8072_host.log 尾部 3 行实测存在 `err=10093` 行（`23:31:02.157 … socket af=2 type=2 proto=17 ret=0xffffffffffffffff caller=? err=10093`）及 `session end seq=1224 drops=0 throttled=0` 行。

**C 项裁定：通过。**

## D. 表述边界（R-2 配套）：通过

- grep 文档「复现|直接证据|直接证明|推断|未直接」仅命中 2 处：L93（标注块，明确「机制本身无直接日志证据」，仅 232727 轮称「直接证明」）与 L227（下一步审计 TODO）。文档未宣称 231817 轮直接复现了 bug 机制 ✓
- 限流降幅算术：471,187,542 / 24,167 = 19,497.1466（PowerShell 实测）；文档 §5.2 L146「≈19,500×（471,187,542 / 24,167 = 19,497）」正确 ✓

**D 项裁定：通过。**

## E. 核验包：逐项通过

1. 三处二进制一致：`M0A\pcb-kit\`、`C:\Users\dd\Desktop\pcb-kit\`、`C:\Users\dd\Desktop\civlink-run\` 的 civtrace.dll 全部 = ADE54435…、civinject.exe 全部 = EACDE797…（与 civtrace\ 构建目录一致）✓
2. `C:\Users\dd\Desktop\pcb-kit.zip`（481,836 B，mtime 2026-11-17 00:14:24）与 M0A\pcb-kit 顶层一致：zip 条目 = 25，与 M0A 顶层 25 文件（不含 captures 子目录）同名、同尺寸、无缺失、无多余；解压到临时目录后 25/25 SHA256 全等（diff=0）✓。另 M0A\pcb-kit 与 Desktop\pcb-kit 逐文件（名/尺寸/SHA256）对比 25/25 diff=0 ✓
3. `M0A\pcb-kit\MANIFEST-sha256.txt` = 2,659 B；24 行哈希（25 顶层文件除 MANIFEST 自身外）自校验 checked=24 **mismatched=0** ✓；Desktop 副本文件哈希相同（`068EC1F5EE22EC71F0EC1060D00668FFD5494C568D9A42FC387FA2E93533DA79`）且自校验 mismatched=0 ✓；MANIFEST 头注「generated: 2026-11-17 00:13 (civtrace v0.4.5 log-bound fix, R-1 atomic final)」，civtrace.dll=ade54435…、civinject.exe=eacde797…，并注明 superseded 版本 60232D93…/4C1E1D0D…（pre-R-1）✓

**E 项裁定：通过。**

## 结论

**裁定：通过（无必改项）。**

R-1~R-4 四项必改全部落实且经实测验证：
- R-1：`g_lastGlobalLogMs` 已为 `std::atomic<ULONGLONG>`（L503），CAS 循环窗口判定（L509-511），失败者落入窗口计 throttled（L510），无新死锁/竞态。
- R-2：§4 L93 证据标注块准确（推断/未直接复现措辞到位）。
- R-3：§5.5 L173 断言口径（39 条/39/39 一致/4 条含分号说明/人工逐条注明）、L176 旁证归因（T15 与 T1/T2/T6）、§3 L60 行数/字节数全部更正正确。
- R-4：§6.1 L186 GQCS/GQCSEx 恒等式限定正确。

可选审计观察（不影响裁定，不构成必改）：
1. 文档 L186 引用 GQCS/GQCSEx 代码区间「trace_dll.cpp L1284-1342」为近似（实际 L1291-1340），建议后续修订时改精确。
2. raw-log-sha256.txt 第三行哈希与首轮审计 C4 记载的旧第三行哈希相同但对应文件名不同（000616_pid30136 vs 旧 232959_pid20496）——不可解析的微小观察，不影响任何文档断言。

检查方法简述：只读核验。源码（trace_dll.cpp 1,583 行）与文档（228 行）用 read 工具逐段读取并记录行号；哈希一律 Get-FileHash -Algorithm SHA256 实测（大写输出）；脚本断言口径用 grep `(expect` 实测 40 处与 L166 注释行；zip 用 System.IO.Compression.ZipFile 解压至临时目录后 25 文件 SHA256 全比；MANIFEST 自校验按行解析哈希重算。未修改任何被审文件；仅产出本报告。

（报告时间戳：2026-11-17 00:22 +08:00）
