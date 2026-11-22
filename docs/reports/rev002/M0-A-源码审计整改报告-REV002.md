# M0-A 源码审计整改报告（REV-002）

- **任务编号**：CIVLINK-M0A-REV-002
- **验收人**：CivLink 技术审批员
- **整改对象**：civtrace v0.4 → **v0.4.4**（trace_dll.cpp / injector.cpp / civtrace_common.h）
- **执行依据**：REV-002-CODE-AUDIT.md（111 行审计）+ REV-002-REMEDIATION-TASK.md（65 行整改任务书，R1-R7）+ REV-002-ACCEPTANCE-REVIEW.md（首轮复核：B1/B2 阻断项 + C1 注释更正）+ **REV-002-ACCEPTANCE-REVIEW-v0.4.3.md（补充复核：B1/C1 通过、B2 未达确定性 → 三选一收敛方式）**
- **协作模式**：codex 负责审计规划（生成 MD 报告），本执行端负责编辑与构建
- **报告日期**：2026-11-11
- **阶段声明**：本报告仅覆盖工具级（civtrace）整改与测试；真实文明6 E1-E5 实验另行执行，未在此声称完成。31/31 装钩成功 ≠ 完整协议审计。不修改 v2.1 稳定性阈值与架构决策。

---

## 0. 本轮（v0.4.4）核心变更：B2 按审查方方案②收敛

补充验收复核（REV-002-ACCEPTANCE-REVIEW-v0.4.3.md）判定 B2 未达确定性，并给出三选一收敛方式。本轮选择**方案②「无需卸载的审计运行模式」**：

| 项 | v0.4.3（被否） | v0.4.4（本轮） |
|---|---|---|
| DLL 关闭成功路径 | `MH_Uninitialize()` + `DrainAndClose()` | **去掉 `MH_Uninitialize()`**，仅 `DrainAndClose()`；MinHook 保持初始化 |
| 模块映射 | 注入器确认后远程 `FreeLibrary` | **不执行 `FreeLibrary`**，模块保持映射至目标进程退出 |
| 残余入口竞态 | 理论上可在已卸载代码上执行 → UAF | **无害化**：trampoline/detour 代码永久有效，最坏只安全走完 `Real_*` 并递减计数 |
| 注入器 `-u` 退出码 | 0=unloaded / 2=refcount>1 | **0** + 打印 "intentionally LEFT MAPPED until pid=N exits" |

**为何方案②可关闭 B2**：审查方指出的漏洞本质是"活动进程内 `FreeLibrary` + `MH_Uninitialize` 时，可能存在未被冻结的线程恰在 detour 入口窄窗口内，其 IP 未被 MinHook 重定向，计数器为 0 → 关闭线程越过排空检查 → 之后该线程恢复执行已被释放的 DLL 代码"。方案②**消除了该漏洞成立的前提**（不再释放 DLL 代码页、不再销毁 trampoline），因此无需证明 MinHook 的线程冻结完备性。方案①（严格同步安全）需要对 pin 的 MinHook v1.3.4 做库级改写或全库证明，与本项目"MinHook pin 不可改"约束冲突，未采用；方案③（代码级同步证明+故障注入）无法覆盖 `OpenThread`/`SuspendThread` 失败的真实组合，未采用。

**代价（如实披露）**：注入器 `-u` 不再能把 DLL 从活动进程中移除，模块映射保留至进程退出。对 M0-A 审计用途（观测、不驻留生产）无影响；若将来生产版需要热卸载，必须在方案①上另做专项证明——本报告不声称已解决该问题。

---

## 1. 交付物清单

| 交付物 | 路径 | 说明 |
|---|---|---|
| trace_dll.cpp | `CivLink-M0A-audit\civtrace\trace_dll.cpp` | v0.4.4，1516 行 / 75055 B |
| injector.cpp | `CivLink-M0A-audit\civtrace\injector.cpp` | v0.4.4，522 行 / 25303 B |
| civtrace_common.h | `CivLink-M0A-audit\civtrace\civtrace_common.h` | v0.4.4，38 行 / 3036 B，契约注释改为审计运行模式 |
| 构建脚本 | `CivLink-M0A-audit\civtrace\build-msvc.cmd` | 自动定位 vcvars（D:\MSVC\BuildTools） |
| MinHook pin 证据 | `deps\MinHook`（HEAD=8af6b4acae5a9388fd742b56fa79ece89d96f823，2026-09-08，--branch v1.3.4） | 固定版本，本轮未改动 |
| v0.4→v0.4.4 差异补丁 | `docs\reports\rev002\patch-*-v0.4-to-v0.4.4.diff` ×3 | 本轮 |
| 干净构建日志 | `docs\reports\rev002\build-v0.4.4.log` | 0 error 0 warning |
| 测试脚本 | `CivLink-M0A-audit\civtrace\test-rev002.ps1`（435 行，15 项：T1-T13 + T14 B1 超时重试 + T15 B2 并发关闭）+ `test-rev002-elevated.cmd` | 期望已按审计运行模式更新 |
| 每项测试原始日志 | `docs\reports\rev002\run-T*.txt` ×15 + `raw-*.log`（原始 DLL 日志副本）+ `raw-log-sha256.txt` | 全部为原始输出 |
| 测试环境记录 | `docs\reports\rev002\environment.txt` | Admin: True、构建哈希绑定 |
| 最终二进制 SHA256 | 见 §2 | |
| 本报告 | `docs\reports\rev002\M0-A-源码审计整改报告-REV002.md` | |

## 2. 构建与二进制身份

- 构建时间：**2026-11-11 11:44:58**（build-msvc.cmd，0 error 0 warning，exit 0）
- 构建命令：`cmd /c build-msvc.cmd`（cwd = `CivLink-M0A-audit\civtrace`；vcvars64.bat 来自 D:\MSVC\BuildTools；`/utf-8 /O2 /MT /EHsc`；MinHook v1.3.4 pin）

| 二进制 | 大小 | SHA256 |
|---|---|---|
| civtrace.dll | 246272 B | `19196ff7a6ce36ad49c00af7fca74efde868f87a6bfb49bab342f4cadf4bfede` |
| civinject.exe | 171520 B | `4dcc95578a5e0d85f0f6d4ba3c5ebed24ca0ee34d5ebf50a80f70c7faa99ec72` |

- 上述 SHA256 与 `environment.txt` 中记录一致（测试运行由同一对二进制产生）。
- dumpbin /dependents：civtrace.dll → WS2_32 + KERNEL32；civinject.exe → ADVAPI32 + KERNEL32；两者均无 MSVCP*/VCRUNTIME（`/MT` 静态 CRT 确认，T13 `dumpbin_msvcp_vcruntime_lines=0`）。
- 体积较 v0.4.3 略降（DLL 246784→246272、exe 172544→171520）：注入器删除 FreeLibrary 重试循环与 unload 复核，DLL 成功路径删除 `MH_Uninitialize` 调用。

## 3. R1-R7 整改结论（逐项：代码位置 / 测试方法 / 结果 / 未覆盖）

### R1 卸载状态机（P1-1 + P0-6/P0-7 强化）

**整改**（injector.cpp）：
- `RemoteCallShutdown`（injector.cpp:225-250）：CreateRemoteThread → WaitForSingleObject 15s → **GetExitCodeThread 必须检查 BOOL 返回**（失败打印 err 并返回 -1，绝不默认 0 当成功）；`return code==0 ? 0 : (code==1 ? 1 : -1)`。
- 卸载主流程（injector.cpp:384-401）：`sc` 为 0 或 1 均视为**关闭已确认**；`sc` 非 0/1（如 2=部分失败）→ 打印 "shutdown NOT confirmed (code=%d) - ABORT per unload contract" 并 exit 2（保留现场可重试）。
- 双 shutdown 幂等 seam（`CIVTRACE_INJ_TEST_DOUBLE_SHUTDOWN=1`）：二次调用必须返回 1，否则 exit 2。
- **v0.4.4 B2 收敛**：确认成功后**不再执行远程 FreeLibrary**（见 §0）。打印：
  `[+] B2 audit-run mode: civtrace.dll intentionally LEFT MAPPED until pid=N exits (no FreeLibrary in live process; MinHook trampolines stay valid)` → exit 0。
  相应删除：FreeLibrary×3 重试循环、`QueryRemoteModule` 二次复核（q2 = 0/1/-1）分支、"unloaded" 判定。
- **C1 注释更正（首轮复核）**：原 FreeLibrary 返回值注释语义错误已随代码段整体移除；共享头 `civtrace_common.h` 的卸载契约段落同步改写为审计运行模式语义，并保留历史理由（"FreeLibrary 成功 ≠ Hook 安全卸载"）。

**测试**：T4（GEC 失败模拟）、T3（双 shutdown 幂等）、T11（额外引用）、T1（`module_left_mapped` 断言）。

**结果**：
- T4：首卸 `shutdown NOT confirmed` → **exit 2**（`first_unload_exit=2`）；清除 seam 后二卸 `code=0` → exit 0（`second_unload_exit=0`）。PASS
- T3：`double-shutdown test: second call confirmed idempotent (code=1)` → exit 0。PASS
- T11：payload 经 P/Invoke `LoadLibraryW` 额外 +1 引用（marker=140710746587136）→ 卸载仍 `code=0` → **exit 0**（额外引用不再影响流程，因为不再 FreeLibrary）。PASS
- T1：`unload_exit=0`，随后**再次注入被正确识别为重复注入** `module_left_mapped: True`，证明模块确实保持映射。PASS

**未覆盖**：真实远程线程 15s 超时（非 SIM）；真实 `GetExitCodeThread` 失败。B2 模式下已不存在 FreeLibrary 重试路径，相关未覆盖项随之消失。

### R2 Hook 安装/Shutdown 同步状态机（P1-2 + P0-3）

**整改**（trace_dll.cpp）：
- 状态机（globals，~163-167）：`enum HookState { HS_RUNNING=0, HS_SHUTTING_DOWN=1, HS_COMPLETE=2, HS_FAILED=3 }` + `std::atomic<int> g_state{HS_RUNNING}`；`thread_local bool g_tlsInHook` + `std::atomic<long> g_inFlight{0}`。
- 31 个 Hook detour（B2 入口登记）：**第一行即 `g_inFlight.fetch_add(1, std::memory_order_relaxed);`**（31/31 全部落实，实测 `fetch_add_first_line=31`）；随后 `if (g_tlsInHook) { g_inFlight.fetch_sub(1); return Real_X(...); }` 对称透传（P0-2 重入保护），然后 `g_tlsInHook=true`；退出 `g_inFlight.fetch_sub(1); g_tlsInHook=false;`。
- `CivTraceShutdown`（trace_dll.cpp:1412-1477）：
  - CAS RUNNING→SHUTTING_DOWN（SHUTTING_DOWN/COMPLETE return 1 幂等；FAILED→重试续走）；
  - join g_init（InitWorker 在非 RUNNING 状态绝不装钩）；
  - `MH_DisableHook(ALL)` 失败 → Emit + HS_FAILED + **return 2（保留全部资源，可重试）**；
  - **B1：在途 Hook 排空（QPC 5s 死线）超时 → 立即 `return 2`**，不 join flusher、不 `MH_Uninitialize`、不 `DrainAndClose`（资源全保留，flusher 因 `g_stop` 未置位继续刷盘）；
  - 排空成功 → `g_stop=true` → join flusher → **`MH_Uninitialize` 已删除（B2）** → `DrainAndClose()` → `HS_COMPLETE` → return 0。
- `DllMain` DETACH（trace_dll.cpp:1489-1514）：非进程退出兜底保留原语义（禁钩成功才 `MH_Uninitialize`），并注明该分支只可能由**外部** FreeLibrary 触发——本工具 `-u` 不再卸载，故 M0-A 责任范围内的残余竞态已由"永不 FreeLibrary"消除。

**测试**：T1（基线）、T3（幂等）、T5（禁钩失败）、T14（B1 排空超时中止+重试）、T15（B2 并发关闭）。

**结果**：
- T1：`hooks installed ok=31 fail=0`、`CivTraceShutdown confirmed (code=0)`、`B2 audit-run mode: ... LEFT MAPPED`、`unload_exit=0`；线程/句柄 27→27、585→585（无泄漏）。PASS
- T5：`CIVTRACE_SIM_DISABLE_FAIL=1` 首卸 exit 2（DLL 保留）；seam 一次性消费 → 二卸走真实禁钩链 → code=0 → exit 0。PASS
- T14：`CIVTRACE_SIM_HOOK_BLOCK=1`（首次 `Hook_socket` 阻塞 7s）+ `blk_go` 握手 → 首卸 `first_unload_exit=2`、`still_alive_after_timeout=True`；socket 解锁后二卸 `second_unload_exit=0`；`timeout_line=1`、`session_end=1`、`blk_socket_done=True`。PASS
- T15：8 线程 C# 压测（`mt_runs=6208`）中注入 → 关闭一次成功 `unload_exit=0`、`still_alive=True`、`session_end=1`。PASS

**未覆盖**：真实 `MH_DisableHook` 失败（非 SIM）；B1 超时后 flusher 持续刷盘至进程退出的长时观察（T14 只验证中止 + 重试成功）。

### R3 flusher 创建失败 fail-closed（P1-3）

**整改**（trace_dll.cpp:1378-1400）：SIM seam 与真实 `catch(...)` 均：Emit "!!! flusher thread creation FAILED [SIM] - hooks NOT installed (fail-closed)" + OutputDebugStringA + **同步 fputs + fflush 落盘**（刷盘线程已死，队列无人排空）+ `g_state=HS_FAILED` + 不装钩。

**测试**：T6。**结果**：`failclosed` 行存在，`hooks_installed_count=0`。PASS。
**未覆盖**：真实 `std::thread` 创建失败（需资源耗尽场景）。

### R4 FindPids 动态收集 + 路径失败显式诊断（P1-4）

**整改**（injector.cpp:92-131）：`FindPids(const char*, std::vector<DWORD>&)` 动态 push_back 无截断；`PrintExePath` 对 OpenProcess / QueryFullProcessImageNameA 失败分别打印错误码。

**测试**：T13（`findpids_dynamic=1`）+ 运行日志多实例匹配打印。**结果**：PASS。**未覆盖**：Snapshot 失败路径。

### R5 IsWow64Process fail-closed + 特权结果报告（P1-5 + P2-2）

**整改**（injector.cpp）：`IsWow64Process` 失败 → "target architecture UNDETERMINED; refusing to proceed (civtrace.dll is x64 only)" + return 2（fail-closed），seam `CIVTRACE_INJ_SIM_ARCH_FAIL`；`EnableDebugPrivilege` 返回 int（0=成功 / 1=ERROR_NOT_ALL_ASSIGNED / -1=任一环节失败并打印错误码）。

**测试**：T10、T13。**结果**：T10 inject exit 2，清 env 后正常 inject+unload exit 0。PASS。
**未覆盖**：真实 32 位目标（本机无）、真实 `IsWow64Process` 失败、ERROR_NOT_ALL_ASSIGNED 部分授权路径（管理员环境全成功——非提权试运行可见该分支，见 §6.6）。

### R6 QueryRemoteModule 动态扩容重试（P2-1）

**整改**（injector.cpp:147-175）：`std::vector<HMODULE> mods(SimSmallBuf() ? 1 : 1024)`；循环 ≤6 次 `EnumProcessModulesEx`，不足则 `resize(count + 4096/sizeof(HMODULE))` 重试；6 次仍不足 return -1（不可判定绝不伪装未加载）。

**测试**：T7。**结果**：`inject_exit=0`、`unload_exit=0`。PASS。**未覆盖**：6 次重试仍不足。

### R7 README/文档限定与证据边界

- README v1.1 已声明：日志"仍有锁/分配/系统调用开销"、丢行信号可发现、31/31 ≠ 协议审计、E1-E5 未执行即未验证。
- 本报告 §3 每项标注代码位置/测试方法/结果/未覆盖；证据绑定构建哈希（§2）+ 环境（`environment.txt`）+ 原始输出（`run-T*.txt` + `raw-*.log`）。
- `civtrace_common.h` 契约段落已按 v0.4.4 审计运行模式改写，与实现一致（无"确认后 FreeLibrary"的过期表述）。

## 4. P0 十项（REV-001 遗留）复核

| P0 项 | 状态 |
|---|---|
| ① socket() 返回类型 SOCKET | 已落实（`typedef T_socket : SOCKET`；`Hook_socket` 返回 SOCKET）。T13 `t_socket_decl=1`、`hook_socket_decl=1` |
| ② 递归保护改 thread_local | 已落实（`g_tlsInHook` thread_local + `g_inFlight` 计数；T13 `g_inHook_residual=0`，`g_inFlight_refs=98`） |
| ③ Hook 执行体计数 + Shutdown 生命周期 | 已落实（R2：禁钩失败 return 2 保留资源；`g_inFlight` 显式排空 5s 死线；B2 后不再销毁 trampoline） |
| ④ Shutdown 状态区分 | 已落实（HS_RUNNING/SHUTTING_DOWN/COMPLETE/FAILED；FAILED 可重试；T5/T14 验证） |
| ⑤ 日志热路径零阻塞 | 已落实（预分配 ring + try_lock + drops 计数；README 限定措辞） |
| ⑥ RemoteCallShutdown 检查 `GetExitCodeThread` BOOL | 已强化（T4 验证失败即拒绝确认） |
| ⑦ 删除 FreeLibrary×2 | **v0.4.4 进一步提升**：不再执行任何 FreeLibrary（B2 审计运行模式），风险面归零 |
| ⑧ LoadLibraryW 超时禁止释放缓冲 | 已落实（T9 inject exit 2，远程缓冲保留） |
| ⑨ WSAEnumNetworkEvents 失败路径不读输出 | 已落实（仅 r==0 读 ne；p_inv 验证不崩溃） |
| ⑩ I/O 指针读取无额外访问异常 | 已落实（输出读取 gate 仅成功路径；p_inv 无效指针验证） |

## 5. 测试矩阵（15/15 PASS，全部原始日志在 `docs\reports\rev002\`）

| 测试 | 覆盖 | 期望 | 实测 | 结果 |
|---|---|---|---|---|
| T1 基线 | R2/R1 主链 + B2 映射保留 | hooks 31、dup skip、unload 0、still mapped | `ok=31`、`dup_exit=0`、`unload_exit=0`、`module_left_mapped=True` | ✅ |
| T2 强杀 | R2 DETACH | 无 session-end | 最后一行是 recvfrom 记录，无 session end | ✅ |
| T3 双 shutdown | R1 幂等 | 二次 code=1，退出 0 | `unload_exit=0` | ✅ |
| T4 GEC 失败 | P0-6 | 首卸 2、二卸 0 | `first=2`、`second=0` | ✅ |
| T5 禁钩失败 | R2 | 首卸 2 保留、二卸 0 | `first=2`、`second=0` | ✅ |
| T6 flusher 失败 | R3 | failclosed 行 + hooks=0 | 符合 | ✅ |
| T7 枚举扩容 | R6 | inject/unload 0 | 符合 | ✅ |
| T8 错误 DLL | R1 PE 身份 | 卸 2 + 正常卸 0 | `wrongdll=2`、`normal=0` | ✅ |
| T9 加载超时 | P0-8 | inject 2 缓冲保留 | `inject_exit=2` | ✅ |
| T10 架构失败 | R5 | inject 2 + 清 env 后 0 | `inject=2`、`normal=0` | ✅ |
| T11 额外引用 | R1 + B2 | 额外引用下卸载仍 0 | `unload_exit=0` | ✅ |
| T12 错误码透传 | ErrTx | err 精确一致 | `err=10038 equal=True` | ✅ |
| T13 静态核查 | P0-1/2、R4/R6、/MT | 各项断言 | 全符（`g_inFlight_refs=98`、`/MT` 0 行） | ✅ |
| T14 B1 排空超时 | R2/B1 | 首卸 2 中止链资源保留、二卸 0、timeout 行+session end | `first=2`、`second=0`、`timeout_line=1`、`still_alive=True` | ✅ |
| T15 B2 并发关闭 | R2/B2 | 8 线程压测中关闭 0、存活 | `unload_exit=0`、`mt_runs=6208`、`still_alive=True` | ✅ |

原始日志副本：`raw-120306-pid35388.log`（T1，24852 B）、`raw-120319-pid35172.log`（T2，27384 B）、`raw-120424-pid41804.log`（T14）、`raw-120433-pid38936.log`（T15，144590 B）等 14 份；`raw-log-sha256.txt` 记录主日志哈希。

## 6. 未覆盖项（诚实披露）

1. 真实故障注入（`MH_DisableHook` 失败、`std::thread` 创建失败、`IsWow64Process` 失败、`GetExitCodeThread` 失败、远程线程超时）均以 SIM env seam 验证同路径逻辑，真实触发依赖资源耗尽/特权场景，未在自动化中复现。
2. 真实 32 位目标进程（本机无）——wow64 拒绝分支代码存在，未实测。
3. B2 方案②的代价：注入器 `-u` **不再从活动进程移除 DLL**，模块映射保留至进程退出。如果后续生产版需要热卸载，必须另做方案①的库级同步证明——本报告不声称已解决。
4. B1 超时中止后 flusher 持续刷盘至进程退出的长时行为未单独观察（T14 仅验证中止 + 重试成功 + 日志完整性）。
5. 文明6 E1-E5 实验未执行（工具级测试 ≠ 联机验证）；按任务书在工具级验收通过后另行执行，设备/EOS 不可用将如实标注。
6. 测试期间一次**非提权**试运行（2026-11-11 12:00，`Admin: False`）产生了 `environment.txt` 的早期版本并覆盖了 T1/T2 记录；随后 12:02 的提权运行（`Admin: True`）完整重跑 15 项，本报告引用的是后者。该次试运行同时证明 `EnableDebugPrivilege` 的 ERROR_NOT_ALL_ASSIGNED 分支能正确打印并拒绝继续（`process 'powershell.exe' not found` 时 exit 1）。

## 7. 阶段限制确认

- [x] 未提交 Gate A 申请（M0-B 冻结维持）
- [x] 未开始 M0-B
- [x] 不把 31/31 装钩宣传为完整协议审计（§0 声明）
- [x] 不把 PowerShell 合成 UDP 测试宣传为文明6联机测试（§6.5）
- [x] 未修改 v2.1 稳定性阈值与架构决策

## 8. 结论

civtrace **v0.4.4** 完成 codex R1-R7 全部整改项；首轮复核的 B1（排空超时中止链保留资源）与 C1（FreeLibrary 注释语义）已通过；**补充复核指出的 B2 按审查方方案②（审计运行模式）收敛**——关闭成功路径不再 `MH_Uninitialize`，注入器确认后不再 `FreeLibrary`，模块保持映射至目标进程退出，使"未冻结线程在 detour 入口窄窗口"的理论竞态失去成立前提。

15/15 自动化测试通过（含 T14 B1 超时中止+重试、T15 并发关闭、T1 映射保留断言），二进制身份（§2）与环境（`environment.txt`）绑定证据，原始日志与哈希齐备。提交审批；批准前维持 M0-B / Gate A 冻结。
