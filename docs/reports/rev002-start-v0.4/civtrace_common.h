// civtrace_common.h —— civtrace.dll 与 civinject.exe 的跨二进制契约（REV-001）
//
// 两个二进制都必须包含本头文件，保证版本号、DLL 文件名、导出名与卸载契约
// 只有唯一定义处；任何一侧单独修改而不改这里，都视为契约破坏。
#pragma once

#define CIVTRACE_VERSION           "0.4"
#define CIVTRACE_DLL_NAME_A        "civtrace.dll"
#define CIVTRACE_DLL_NAME_W        L"civtrace.dll"
#define CIVTRACE_SHUTDOWN_EXPORT_A "CivTraceShutdown"

// CivTraceShutdown(void) -> DWORD：
//   0 = shutdown 完成（全部 Hook 已禁用并等待在途 Hook 退出、日志已刷盘并关闭）
//   1 = 已经 shutdown（重复调用；此时同样可安全 FreeLibrary）
//   2 = shutdown 部分失败（MH_DisableHook / MH_Uninitialize 失败）
//
// 卸载契约（REV-001 P0-2，强制）：
//   注入器必须在远程调用 CivTraceShutdown 并确认返回 0 或 1 之后，才允许远程
//   FreeLibrary；返回 2、等待超时或 CreateRemoteThread 失败时，必须放弃
//   FreeLibrary 并保留现场（报告给操作者，由其决定关闭进程）。
//   理由：FreeLibrary 直接卸载映射页时，若仍有 Hook 执行体在原函数跳板里，
//   会在已卸载代码上执行 → 进程崩溃。FreeLibrary 成功 ≠ Hook 安全卸载。
