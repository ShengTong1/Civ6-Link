// civtrace_common.h —— civtrace.dll 与 civinject.exe 的跨二进制契约（REV-001/REV-002）
//
// 两个二进制都必须包含本头文件，保证版本号、DLL 文件名、导出名与卸载契约
// 只有唯一定义处；任何一侧单独修改而不改这里，都视为契约破坏。
#pragma once

#define CIVTRACE_VERSION           "0.4.5"
#define CIVTRACE_DLL_NAME_A        "civtrace.dll"
#define CIVTRACE_DLL_NAME_W        L"civtrace.dll"
#define CIVTRACE_SHUTDOWN_EXPORT_A "CivTraceShutdown"

// CivTraceShutdown(void) -> DWORD：
//   0 = shutdown 完成（全部 Hook 已禁用并等待在途 Hook 退出、日志已刷盘并关闭）
//   1 = 已经 shutdown（重复调用 / 正在关闭中；同样可安全重试或结束流程）
//   2 = shutdown 失败（禁钩失败 → 资源保留、Hook 仍在，可重试；或在途 Hook 排空超时 →
//       REV-002 B1：关闭链立即中止，MinHook/日志/队列资源与 DLL 全部保留，可安全重试）
//
// 卸载契约（REV-001 P0-2 强制；REV-002 R1/B1 修订；v0.4.4 B2 收敛为审计运行模式）：
//   注入器必须在远程调用 CivTraceShutdown 并确认返回 0 或 1，才视为关闭成功；
//   返回 2、等待超时、CreateRemoteThread 失败或 GetExitCodeThread 读取失败时，
//   必须视为未关闭并保留现场（报告给操作者，由其决定关闭进程）。
//   REV-002 R1：本工具对模块的 LoadLibrary 责任 = 恰一次（注入路径 LoadLibraryW 一次）。
//   v0.4.4 REV-002 B2 收敛（审计运行模式，Option 2）：确认 shutdown 成功后注入器
//   **不再执行远程 FreeLibrary**——MinHook 保持初始化（trampoline 永保有效），模块
//   保持映射，由目标进程退出时 OS 自然卸载。理由：MinHook 禁钩路径无法确定性证明
//   "所有可能执行 detour 的线程都已冻结"（OpenThread/SuspendThread 失败只标 0 仍返回
//   MH_OK），活动进程内 FreeLibrary+MH_Uninitialize 存在残余入口线程 use-after-free
//   的理论窗口；审计运行模式使该窗口无害化（竞态即使发生也只安全走完 Real_* 调用）。
//   注入器 -u 在确认 shutdown 后打印 "module left mapped" 并以 0 退出。
//   理由（历史）：FreeLibrary 直接卸载映射页时，若仍有 Hook 执行体在原函数跳板里，
//   会在已卸载代码上执行 → 进程崩溃。FreeLibrary 成功 ≠ Hook 安全卸载。
//
// 状态机（REV-002 R2，trace_dll 内部）：
//   HS_RUNNING -> HS_SHUTTING_DOWN -> HS_COMPLETE / HS_FAILED；
//   禁钩失败或排空超时（B1）时 DLL 进入 HS_FAILED 并保留全部资源（可重试 Shutdown 续走关闭链；
//   B1 超时中止后 flusher 因 g_stop 未置位继续刷盘——日志持续落盘直至重试成功）；
//   InitWorker 在非 RUNNING 状态绝不装钩；DllMain DETACH 兜底禁钩失败时只刷盘日志，
//   不执行 MH_Uninitialize（无法证明在途 Hook 已排空时不得释放 MinHook 资源）。
