# M0-A 源码审计整改报告

| 项 | 值 |
|----|----|
| 任务编号 | CIVLINK-M0A-REV-001 |
| 任务性质 | 技术审计整改（不进入 M0-B） |
| 整改对象 | civtrace v0.3（追踪 DLL + 注入器）→ **v0.4** |
| 整改日期 | 2026-11-10 |
| 整改人 | CivLink 开发（AI 协作） |
| 验收人 | CivLink 技术审批员 |
| 关联规范 | 《CivLink 技术设计规范 v2.1》（未做任何修改） |
| 基线快照 | `docs\reports\rev001-baseline\{trace_dll.cpp, injector.cpp}`（v0.3 原样备份） |

---

## 1. 交付物清单（P0-1）

| 文件 | 状态 | 说明 |
|------|------|------|
| `civtrace\trace_dll.cpp` | 修改（66+/24-） | 追踪 DLL v0.4，31 API |
| `civtrace\injector.cpp` | 重写（221+/130-） | 注入器 v0.4，419 行 |
| `civtrace\civtrace_common.h` | **新增** | 共享头：版本号/DLL 名/导出名/卸载契约常量，两 cpp 共同 include |
| `docs\reports\rev001\diff-trace_dll.patch` | 新增 | v0.3→v0.4 完整差异（11.4KB） |
| `docs\reports\rev001\diff-injector.patch` | 新增 | v0.3→v0.4 完整差异（24.3KB） |
| `civtrace\build-rev001.log` | 新增 | MSVC 干净构建日志 |
| `docs\reports\rev001\run2-*.txt` | 新增 | 最终二进制全量测试证据（见 §6） |

## 2. 构建与二进制身份

- 构建：MSVC 14.51（BuildTools @ D:\MSVC\BuildTools），`/nologo /utf-8 /O2 /MT /EHsc`，**0 warning / 0 error**（`build-rev001.log`）。
- MinHook v1.3.4（pin，BSD-2）静态编入。
- 最终二进制 SHA256：
  - `civtrace.dll` = `7dba505cc8152179cde6c0225f812bccf10e5835446726f5bc4e99e067409927`
  - `civinject.exe` = `c09ad2669e0c99f125e05e9819d2cefd474f27d1529a337294ff0d9f3ca11a81`
- 测试环境（`run2-environment/environment.txt`）：Windows 11 专业版 build 26100 UBR 4946，提权运行，2026-11-10 23:05 +08:00。

## 3. P0 十项逐项结论

### P0-2（ injector 卸载流程）——**已修复并加固**

v0.3 违规：`CivTraceShutdown` 远程调用失败/超时/导出无法解析时，仍回退执行 `FreeLibrary`——违反"确认成功后才能 FreeLibrary"。

v0.4 卸载链（`injector.cpp` `Unload()`）：
1. `QueryRemoteModule`（P0-3 的全精度枚举）确认模块加载；
2. `ResolveLocalPe`：本地解析 PE 的导出 RVA + SizeOfImage + TimeDateStamp；
3. **SizeOfImage 与远程模块尺寸严格相等校验，不等则 abort（exit 2）**——防止用户提供错误 DLL 文件导致远程函数指针指向垃圾内存；
4. `RemotePeIdentity`：读取远程 PE 头，验证 MZ/PE/SizeOfImage/TimeDateStamp 四重身份一致才允许换算远程导出地址；
5. 远程调用 `CivTraceShutdown`（DWORD 返回：0=成功 / 1=已 shutdown / 2=部分失败），**退出码必须为 0 或 1**；
6. 确认成功后才 `FreeLibrary`×2，随后 `QueryRemoteModule` 复核确认卸载。

任何一步失败：**放弃卸载并保留现场（exit 2）**，绝不 FreeLibrary。
证据：`run2-T3-shutdown-unload.txt`（`CivTraceShutdown confirmed (code=0)` → 才出现 `unloaded`）；`run2-T6-wrongdll-refusal.txt`（用 `ws2_32.dll` 冒充：`cannot resolve export ... refusing FreeLibrary`，exit=2）。

### P0-3（远程 64 位模块验证）——**已修复**

v0.3 的 `RemoteModulePresent` 通过远程调用 `GetModuleHandleW` 并把 64 位 HMODULE 截断为 32 位退出码作判据——**已删除**。v0.4 一律使用 `EnumProcessModulesEx(LIST_MODULES_64BIT)` + `GetModuleBaseNameA` + `GetModuleInformation`，基址/尺寸全精度（`QueryRemoteModule` 返回 1=确认加载 / 0=确认未加载 / -1=无法枚举）。注入验证同样走此链路，并把 SizeOfImage 作为附加身份信号（`run2-T1`：`loaded @ 0x7ff9cdcb0000 (size=262144)` 全精度）。

### P0-4（远程 API 地址解析）——**已核查并加固**

- `LoadLibraryW` / `GetModuleHandleW`：`GetProcAddress(GetModuleHandleW("kernel32.dll"), ...)`——本机 kernel32 与目标系统库同基址（ASLR 系统级一致），成立；
- `CivTraceShutdown`：不再假设任何偏移，完全由本地 PE 导出表解析 RVA + §P0-2 第 3/4 步身份校验后才换算 `远程基址+RVA`（`run2-T3`：`rva=0x88a0` 计算并调用成功）。

### P0-5（并发安全）——**已核查，一处重大缺陷修复（BUG#1）**

**BUG#1（致命，本轮发现并修复）**：v0.3 `InitWorker` 从未启动日志刷盘线程（`g_flusher` 只有 join 调用、无创建语句）——日志在会话期内全部滞留内存队列（上限 65536 行，超限丢弃），仅在卸载/进程退出时一次性落盘；若目标被强杀，日志全丢。
修复：`InitWorker` 在安装钩子前启动 `FlushLoop`（150ms 批量刷盘）。
证据：`run2-T1-inject.txt` `liveflush size0=0 size1=26132 grew=26132 bytes`（注入后未卸载，日志持续落盘）。

其余并发项核查结论（代码审计）：
- DllMain 极简：仅 `DisableThreadLibraryCalls` + 启动初始化线程（无 Loader Lock 阻塞操作）；
- 卸载单线程化：`CivTraceShutdown` → `MH_DisableHook(MH_ALL_HOOKS)` → join 初始化线程与刷盘线程 → `MH_Uninitialize` → 关文件，顺序执行；
- `g_shutdown.exchange(true)` 保证幂等（二次调用返回 1）；
- DETACH 分支仅在进程内显式 FreeLibrary 之外的兜底路径出现，其 Loader Lock 风险已注释声明；
- 证据：`run2-T3` 卸载后目标线程数 27→27、句柄 583→583（与注入前基线一致，无线程/句柄泄漏）。

### P0-6（Overlapped 三态）——**已核查，一处读取门修复（BUG#3）**

- Hook 内 Overlapped 严格三态：`ov=done`（同步完成，可读输出）/ `ov=PENDING`（`WSA_IO_PENDING`，**绝不读取** from/bytes/缓冲）/ `ov=err`；
- **BUG#3 修复**：`GetQueuedCompletionStatus(Ex)` 在 `ok==FALSE`（超时/失败）时不再读取 `*lpNumberOfBytes` / `*lpOverlapped` / `*lpNumberOfEntries`；GQCS 仅在 `ok==TRUE` 或 `*lpOverlapped` 非空（失败完成包，参数有效）时读取。

### P0-7（ErrTx 错误状态保存恢复）——**已修复一处缺陷（BUG#2）**

v0.3 恢复顺序 `SetLastError(win)` → `WSASetLastError(wsa)`：Windows 两者共用同一 per-thread 错误槽位，最终生效值为 wsa——对 ws2_32 Hook 无害（游戏读 Winsock 错误），但 **kernel32 三 Hook（CreateIoCompletionPort/GQCS/GQCSEx）失败后游戏读 `GetLastError` 会得到过期的 wsa 值**。
修复：`ErrTx` 增加 `win32` 标志（kernel32 Hook 置位）；`end()` 恢复时 `SetLastError(win)` 后**仅当非 win32 才调用 `WSASetLastError(wsa)`**。
行为验证：`run2` 真实 UDP 流量日志中错误标记链路正确（`recvfrom ... err=10054`，即 WSAECONNRESET，非阻塞 recvfrom 对未连接对端的预期错误），说明捕获/恢复事务在真实调用路径上工作。

### P0-8（有界队列满载不阻塞）——**已核查**

日志队上限 65536 行；超限时新日志行**丢弃并计数（`g_drops++`）**，调用线程（游戏线程）绝不等待或阻塞。证据：`run2` A/B 两目标各 ~150 对 send/recv 高频流量，全程 `drops=0`（`run2-T3` session end 行）。

### P0-9（退出报告准确丢弃数）——**已核查**

`FlushLoop` 检测到 drops 变化时周期性上报 `!!! log-drops total=...`；`DrainAndClose` 写 `===== session end seq=N drops=M =====` 汇总（`run2-T3`：`seq=173 drops=0`）。
诚实披露：本测试流量未达到队列上限，drops>0 的上报路径为代码审计确认，未构造触发场景（见 §7）。

### P0-10（31 API 签名/透传/错误处理）——**已逐项核查**

31 个 Hook（ws2_32 28 个 + kernel32 3 个）签名与 ws2_32/kernel32 导出逐一比对：参数列表、调用约定（WSAAPI/WINAPI）、返回值透传、`ErrTx` 事务包裹全部一致；`WSAPoll` 使用 ABI 等价自定义结构（`CVL_POLLFD`，16 字节布局与 `WSAPOLLFD` 相同）。错误处理统一模式：real 调用 → 立即 `WSAGetLastError`（任何日志动作之前）→ 日志 → 按事务恢复。安装证据：`run2-T1` `hooks installed ok=31 fail=0 (observe-only)`。

### P0 之外的额外修复

- **日志格式缺陷**：`caller=` 双前缀（`CallerOf` 返回值自带前缀 + Hook 模板再次拼接）。修复：`CallerOf` 返回裸值。对比 run1 证据 `caller=caller=System.ni.dll+0x7ccdde` → run2 证据 `caller=System.ni.dll+0x7ccdde`。

## 4. 测试执行记录（最终二进制，run2，2026-11-10 23:05–23:07）

| # | 场景 | 结果 | 证据文件 |
|---|------|------|---------|
| T1 | 注入 + 31/31 装钩 + 实时落盘 | 通过（`ok=31 fail=0`；liveflush +26132B） | `run2-T1-inject.txt` |
| T2 | 重复注入 | 通过（`already loaded @ 0x7ff9cdcb0000 - skip`） | `run2-T2-duplicate.txt` |
| T6 | **加载状态下**用错误 DLL（ws2_32.dll）卸载 | 通过（拒绝解析导出，`refusing FreeLibrary`，exit=2） | `run2-T6-wrongdll-refusal.txt` |
| T3 | 确认式卸载（Shutdown code=0 → FreeLibrary） | 通过（目标存活；线程 27→27、句柄 583→583；log 尾 `session end seq=173 drops=0`） | `run2-T3-shutdown-unload.txt` |
| T5 | 对未注入进程卸载 | 通过（`not loaded - nothing to unload`，exit=0） | `run2-T5-unload-notloaded.txt` |
| T4 | 注入后 `taskkill /F` 异常退出 | 通过（已刷盘行完好 24562B；无 session-end 行=符合预期；末行 `recvfrom ... err=10054`） | `run2-T4-abnormal-kill.txt` |

原始追踪日志（SHA256 见 `run2-log-sha256.txt`）：
- `run2-log-A.pid36632.log`（174 行，含 150 次非阻塞 sendto/recvfrom 循环、错误标记、caller 解析）
- `run2-log-B.pid38652.log`（158 行，强杀前最后状态）

测试脚本：`civtrace\test-rev001.ps1`（v2，可复现）。

## 5. 修改文件清单与差异

| 文件 | v0.3 → v0.4 |
|------|-------------|
| `civtrace\trace_dll.cpp` | 66 insertions / 24 deletions（`diff-trace_dll.patch`） |
| `civtrace\injector.cpp` | 221 insertions / 130 deletions（`diff-injector.patch`） |
| `civtrace\civtrace_common.h` | 新增文件（共享常量与卸载契约） |

## 6. 诚实披露——未执行或未触发的测试

按"不得把尚未执行的测试写成通过"的要求，以下路径**未被本次测试覆盖**：

1. **SizeOfImage 不匹配拒绝分支**（本地 PE 与远程模块尺寸不等）：需构造同导出名不同尺寸的 PE，未构造；该分支代码审计确认，但无运行证据。
2. **`RemotePeIdentity` 远程头校验失败分支**：T6 触发的是更早的"本地导出解析失败"分支；远程头不匹配分支无独立运行证据。
3. **32 位目标拒绝分支**：需 32 位进程，未构造。
4. **GQCS 限流路径**（前 50 次全记、之后每 1000 次 1 次）：需真实 IOCP 高频场景；本测试目标无 IOCP 流量。
5. **drops>0 上报路径**：测试流量未超过队列上限。
6. **文明6 真实进程实验（E1–E5）**：本任务全部测试基于 powershell.exe 合成 UDP 负载；文明6 内的 Socket 行为审计是 M0-A 的正式实验内容，尚未执行。

以上第 1–5 项为防御性分支（拒绝危险操作/限流），主流程已被正/反两向测试覆盖；第 6 项是本工具包的用途本身，需要真实游戏环境与多台设备，属于后续实验计划（README v1.1 §3–§7）。

## 7. 阶段限制声明（任务第五节，逐条确认）

- [x] **未开始 M0-B 任何正式开发**——本轮仅改动追踪工具自身；
- [x] **未将冒烟测试宣传为文明6多人联机已验证**——测试目标为 powershell.exe 合成负载，与文明6 无关；
- [x] **未将 Hook 安装成功等同于 Socket 行为审计完成**——审计结论以 E1–E5 实验证据为准（尚未执行）；
- [x] **未修改 CivLink v2.1 的任何稳定性阈值与架构决策**——规范文件本轮零改动。

## 8. 结论

REV-001 P0 十项全部处置完毕：3 项缺陷修复（BUG#1 日志刷盘线程缺失〔致命〕、BUG#2 kernel32 错误槽位恢复、BUG#3 GQCS 失败态读无效输出）、1 项违规整改（卸载必须确认 Shutdown 成功）、1 项判据替换（64 位模块全精度验证）、1 项格式修复（caller 双前缀），其余核查确认通过。最终二进制 v0.4 已通过 6 项正/反测试，全部原始证据保留于 `docs\reports\rev001\`。

**提交审批员审核。**
