// civtrace v0.4 —— CivLink M0-A Socket 行为追踪 DLL（observe-only）
//
// 用途（v2.0 规范 §11 M0-A / §2.2 H3/H8/H10）：
//   记录文明6 对 Winsock API 的真实调用行为——socket 创建、选项、绑定、收发、
//   异步/事件/IOCP 通知方式、关闭时序。只观察、不改写、不干预任何收发，
//   作为协议审计证据源；禁止随 CivLink 正式版本分发。
//
// v0.4（CIVLINK-M0A-REV-001 源码审计整改）：
//   BUG#1 修复：InitWorker 从未启动 FlushLoop —— 会话期日志只堆积在内存队列
//     （超 65536 行即丢弃、进程被杀时全丢）。现于装钩前启动刷盘线程。
//   BUG#2 修复：ErrTx 对 kernel32 Hook（iocp 三件套）错误恢复错误——
//     RestoreErr 先 SetLastError 再 WSASetLastError，最终 TLS 槽位=wsa 旧值，
//     kernel32 失败后游戏读 GetLastError 得到的是 stale WSA 错误。现加
//     win32 标志：win32=true 时只恢复 Win32 last error，不再写 WSA 槽位。
//   BUG#3 修复：GQCS/GQCSEx 在 ret=FALSE 且无完成包（超时）时输出参数内容
//     不确定，现仅在 ok 或 *pov 非空（失败完成包，参数有效）时才读取。
//   CivTraceShutdown 改为返回 DWORD（0=成功/1=已 shutdown/2=部分失败），
//     注入器确认 0/1 后才 FreeLibrary（卸载契约见 civtrace_common.h）。
//   版本号/导出名/DLL 名移入共享头 civtrace_common.h（单一契约定义处）。
//
// v0.3（对应 m00276 技术审查 P0-4/P0-5）：
//   1. 每个 Hook 在 real 调用后立即捕获 last error，日志完成后再恢复：
//      成功路径恢复调用前状态，失败路径恢复 real 调用后的状态
//      （ErrTx：begin→real→commit→end）。日志函数绝不改变原 API 语义。
//   2. Overlapped 三态显式标注：ov=done（同步完成，可读输出）/ ov=PENDING
//      （WSA_IO_PENDING，绝不读 from/bytes/buf）/ ov=err。
//   3. 第二层 H3 审计 API：getsockopt / WSAIoctl（含 SIO_GET_EXTENSION_FUNCTION_POINTER
//      的 GUID 解码：ConnectEx/AcceptEx/WSARecvMsg/WSASendMsg 等）/
//      WSAGetOverlappedResult / WSAWaitForMultipleEvents / WSACreateEvent /
//      WSACloseEvent / WSAEnumNetworkEvents + kernel32 IOCP 三件套
//      （CreateIoCompletionPort / GetQueuedCompletionStatus[Ex]，GQCS 限流记录）。
//   4. 延迟初始化：DllMain 只做 DisableThreadLibraryCalls + 启动 Init 线程，
//      日志/模块表/装钩全部延迟到 Loader Lock 释放后（P0-5.3）。
//   5. 批量启停钩：安装 MH_EnableHook(MH_ALL_HOOKS) 一次批量；卸载走导出
//      CivTraceShutdown()（先 MH_DisableHook(MH_ALL_HOOKS) 再 join/Uninitialize/刷盘），
//      注入器在 FreeLibrary 之前调用该导出。
//   6. 日志：%LOCALAPPDATA%\CivLink\M0A\logs\civtrace_<ts>_pid<N>[_TAG].log
//      （回退 DLL 目录 → %TEMP%）；每行 双时间戳（墙钟 + QPC）；
//      有界队列 + 丢弃计数（绝不阻塞游戏线程）；会话头记录 pid/exe/版本/
//      qpc-freq↔墙钟对应/hook 统计/日志路径（P1-5）。
//   7. Socket 句柄复用代次：SockInfo.gen 在句柄复用（旧条目存在或已 CLOSED）时 +1。
//
// 时间基准约定（README §2）：本机排序用 qpc/seq；跨机对齐用墙钟（NTP）；
// QPC↔墙钟对应关系在会话头记录一次。
//
// 构建：见 ../README.md（MSVC: build-msvc.cmd；MinGW: Makefile）。

#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0601
#ifndef _CRT_SECURE_NO_WARNINGS
#define _CRT_SECURE_NO_WARNINGS
#endif

#include <winsock2.h>
#include <ws2tcpip.h>
#include <mswsock.h>
#include <windows.h>
#include <tlhelp32.h>
#include <intrin.h>
#include <cstdio>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <unordered_map>
#include <mutex>
#include <thread>
#include <atomic>

#include <MinHook.h>
#include "civtrace_common.h"

#pragma intrinsic(_ReturnAddress)

#ifndef SIO_GET_EXTENSION_FUNCTION_POINTER
#define SIO_GET_EXTENSION_FUNCTION_POINTER 0xC8000006u
#endif

// ===================================================================
// 自持函数指针类型（不依赖头文件版本差异）
// ===================================================================
typedef int    (WSAAPI *T_socket)(int, int, int);
typedef SOCKET (WSAAPI *T_WSASocketA)(int, int, int, LPWSAPROTOCOL_INFOA, GROUP, DWORD);
typedef SOCKET (WSAAPI *T_WSASocketW)(int, int, int, LPWSAPROTOCOL_INFOW, GROUP, DWORD);
typedef int    (WSAAPI *T_bind)(SOCKET, const sockaddr*, int);
typedef int    (WSAAPI *T_sendto)(SOCKET, const char*, int, int, const sockaddr*, int);
typedef int    (WSAAPI *T_WSASendTo)(SOCKET, LPWSABUF, DWORD, LPDWORD, DWORD, const sockaddr*, int, LPWSAOVERLAPPED, LPWSAOVERLAPPED_COMPLETION_ROUTINE);
typedef int    (WSAAPI *T_recvfrom)(SOCKET, char*, int, int, sockaddr*, int*);
typedef int    (WSAAPI *T_WSARecvFrom)(SOCKET, LPWSABUF, DWORD, LPDWORD, LPDWORD, sockaddr*, LPINT, LPWSAOVERLAPPED, LPWSAOVERLAPPED_COMPLETION_ROUTINE);
typedef int    (WSAAPI *T_select)(int, fd_set*, fd_set*, fd_set*, const timeval*);
typedef int    (WSAAPI *T_closesocket)(SOCKET);
typedef int    (WSAAPI *T_ioctlsocket)(SOCKET, long, u_long*);
typedef int    (WSAAPI *T_setsockopt)(SOCKET, int, int, const char*, int);
typedef int    (WSAAPI *T_getsockopt)(SOCKET, int, int, char*, int*);
typedef int    (WSAAPI *T_connect)(SOCKET, const sockaddr*, int);
typedef int    (WSAAPI *T_getsockname)(SOCKET, sockaddr*, int*);
typedef int    (WSAAPI *T_getpeername)(SOCKET, sockaddr*, int*);
typedef int    (WSAAPI *T_WSAEventSelect)(SOCKET, WSAEVENT, long);
typedef int    (WSAAPI *T_WSAAsyncSelect)(SOCKET, HWND, u_int, long);
typedef int    (WSAAPI *T_WSASend)(SOCKET, LPWSABUF, DWORD, LPDWORD, DWORD, LPWSAOVERLAPPED, LPWSAOVERLAPPED_COMPLETION_ROUTINE);
typedef int    (WSAAPI *T_WSARecv)(SOCKET, LPWSABUF, DWORD, LPDWORD, LPDWORD, LPWSAOVERLAPPED, LPWSAOVERLAPPED_COMPLETION_ROUTINE);
typedef int    (WSAAPI *T_WSACleanup)(void);
typedef int    (WSAAPI *T_WSAIoctl)(SOCKET, DWORD, LPVOID, DWORD, LPVOID, DWORD, LPDWORD, LPWSAOVERLAPPED, LPWSAOVERLAPPED_COMPLETION_ROUTINE);
typedef BOOL   (WSAAPI *T_WSAGetOverlappedResult)(SOCKET, LPWSAOVERLAPPED, LPDWORD, BOOL, LPDWORD);
typedef DWORD  (WSAAPI *T_WSAWaitForMultipleEvents)(DWORD, const WSAEVENT*, BOOL, DWORD, BOOL);
typedef WSAEVENT (WSAAPI *T_WSACreateEvent)(void);
typedef BOOL   (WSAAPI *T_WSACloseEvent)(WSAEVENT);
typedef int    (WSAAPI *T_WSAEnumNetworkEvents)(SOCKET, WSAEVENT, LPWSANETWORKEVENTS);

// WSAPoll：自定义等价结构，规避不同工具链头文件的声明差异
typedef struct { SOCKET fd; short events; short revents; } CVL_POLLFD;
typedef int    (WSAAPI *T_WSAPoll)(CVL_POLLFD*, ULONG, int);

// IOCP（kernel32）。GetQueuedCompletionStatusEx 的 entries 参数以 void* 传入
//（ABI 等价；不依赖 _OVERLAPPED_ENTRY 头文件声明），只记录 removed 计数。
typedef HANDLE (WINAPI *T_CreateIoCompletionPort)(HANDLE, HANDLE, ULONG_PTR, DWORD);
typedef BOOL   (WINAPI *T_GetQueuedCompletionStatus)(HANDLE, LPDWORD, PULONG_PTR, LPOVERLAPPED*, DWORD);
typedef BOOL   (WINAPI *T_GetQueuedCompletionStatusEx)(HANDLE, void*, ULONG, PULONG, DWORD, BOOL);

static T_socket          Real_socket;
static T_WSASocketA      Real_WSASocketA;
static T_WSASocketW      Real_WSASocketW;
static T_bind            Real_bind;
static T_sendto          Real_sendto;
static T_WSASendTo       Real_WSASendTo;
static T_recvfrom        Real_recvfrom;
static T_WSARecvFrom     Real_WSARecvFrom;
static T_select          Real_select;
static T_closesocket     Real_closesocket;
static T_ioctlsocket     Real_ioctlsocket;
static T_setsockopt      Real_setsockopt;
static T_getsockopt      Real_getsockopt;
static T_connect         Real_connect;
static T_getsockname     Real_getsockname;
static T_getpeername     Real_getpeername;
static T_WSAEventSelect  Real_WSAEventSelect;
static T_WSAAsyncSelect  Real_WSAAsyncSelect;
static T_WSAPoll         Real_WSAPoll;
static T_WSASend         Real_WSASend;
static T_WSARecv         Real_WSARecv;
static T_WSACleanup      Real_WSACleanup;
static T_WSAIoctl        Real_WSAIoctl;
static T_WSAGetOverlappedResult Real_WSAGetOverlappedResult;
static T_WSAWaitForMultipleEvents Real_WSAWaitForMultipleEvents;
static T_WSACreateEvent  Real_WSACreateEvent;
static T_WSACloseEvent   Real_WSACloseEvent;
static T_WSAEnumNetworkEvents Real_WSAEnumNetworkEvents;
static T_CreateIoCompletionPort   Real_CreateIoCompletionPort;
static T_GetQueuedCompletionStatus     Real_GetQueuedCompletionStatus;
static T_GetQueuedCompletionStatusEx   Real_GetQueuedCompletionStatusEx;

// ===================================================================
// 全局状态与日志基础设施
// ===================================================================
static std::mutex        g_mu;        // 保护 日志队列 + socket 状态表 + seq
static std::mutex        g_fileMu;    // 保护 文件写入/关闭
static std::mutex        g_modMu;     // 保护 调用者模块表 + caller 缓存
static std::vector<std::string> g_queue;
static FILE*             g_log = nullptr;
static std::wstring      g_logPath;
static std::atomic<bool> g_stop{false};
static std::atomic<bool> g_shutdown{false};
static std::atomic<bool> g_inHook{false};   // 递归保险：日志路径若误调被钩 API 则透传不记
static std::thread       g_flusher;
static std::thread       g_init;
static HMODULE           g_hmod = nullptr;
static unsigned long long g_seq = 0;
static unsigned long     g_pid = 0;
static std::atomic<unsigned> g_hooksOk{0};
static std::atomic<unsigned> g_hooksFail{0};
static std::atomic<unsigned long long> g_drops{0};
static constexpr size_t  kMaxQueue = 65536;  // 有界队列上限（行）；超出即丢弃计数
static std::atomic<unsigned long long> g_gqcsCalls{0};

struct SockInfo {
    int af = 0; int type = 0;
    bool nb = false; bool async = false; bool closed = false;
    unsigned gen = 0;               // 句柄复用代次
    std::string bound;
};
static std::unordered_map<unsigned long long, SockInfo> g_socks;

struct ModInfo { uintptr_t base = 0; size_t size = 0; std::string name; };
static std::vector<ModInfo> g_mods;
static std::unordered_map<void*, std::string> g_callerCache;

// ---- last error 事务：begin→(real 调用)→commit→end ----
// end() 按结果恢复：失败恢复 real 后状态；成功恢复调用前状态
//（Winsock 成功路径不清 last error，语义上游戏看到的是调用前的旧值）。
// Windows 上 WSA last error 与 Win32 last error 同为 per-thread 槽位。
// REV-001 BUG#2：ws2_32 Hook 失败后游戏读 WSA 错误 → 最终槽位必须是 wsa；
// kernel32 Hook（iocp 三件套）失败后游戏读 GetLastError → 最终槽位必须是
// win。故 win32=true（kernel32 路径）时只恢复 Win32 槽位，不写 WSA 槽位。
struct ErrState { int wsa = 0; DWORD win = 0; };
static void CaptureErr(ErrState* s) { s->wsa = WSAGetLastError(); s->win = GetLastError(); }
struct ErrTx {
    ErrState pre, post;
    bool failed = false;
    bool win32  = false;   // kernel32 Hook 置 true：错误恢复只走 Win32 槽位
    void begin() { CaptureErr(&pre); }
    void commit(bool f) { CaptureErr(&post); failed = f; }
    void end() {
        const ErrState& s = failed ? post : pre;
        SetLastError(s.win);
        if (!win32) WSASetLastError(s.wsa);
    }
};

// ---- 错误标记（H3 信号，规范码文本）----
static const char* ErrTag(int r, int e) {
    thread_local char buf[40];
    if (r >= 0) { buf[0] = '\0'; return buf; }
    if (e == WSAEWOULDBLOCK)  return " [WSAEWOULDBLOCK]";
    if (e == WSA_IO_PENDING)  return " [WSA_IO_PENDING]";
    snprintf(buf, sizeof buf, " err=%d", e);
    return buf;
}
// Overlapped 三态：done=同步完成（输出缓冲可读）/ PENDING=已提交未完成（禁止读）/ err
static const char* OvTag(int r, int e, LPWSAOVERLAPPED ov) {
    if (!ov) return "";
    if (r == 0) return " ov=done";
    if (e == WSA_IO_PENDING) return " ov=PENDING";
    return " ov=err";
}

// ---- 日志行入队（双时间戳：墙钟 + QPC）----
static void Emit(const char* body) {
    LARGE_INTEGER q; QueryPerformanceCounter(&q);
    SYSTEMTIME st; GetLocalTime(&st);
    char buf[2816];
    std::lock_guard<std::mutex> lk(g_mu);
    if (g_queue.size() >= kMaxQueue) {
        g_drops.fetch_add(1, std::memory_order_relaxed);
        return;                                  // 绝不阻塞游戏线程
    }
    int n = snprintf(buf, sizeof buf,
                     "%02u:%02u:%02u.%03u qpc=%llu #%06llu tid=%lu %s\r\n",
                     st.wHour, st.wMinute, st.wSecond, st.wMilliseconds,
                     (unsigned long long)q.QuadPart, ++g_seq,
                     (unsigned long)GetCurrentThreadId(), body);
    if (n <= 0) return;
    g_queue.emplace_back(buf, (size_t)n);
}

static void FlushLoop() {
    unsigned long long reported = 0;
    while (!g_stop.load()) {
        std::vector<std::string> chunk;
        { std::lock_guard<std::mutex> lk(g_mu); if (!g_queue.empty()) chunk.swap(g_queue); }
        if (!chunk.empty()) {
            std::lock_guard<std::mutex> lk(g_fileMu);
            if (g_log) {
                for (auto& s : chunk) fwrite(s.data(), 1, s.size(), g_log);
                fflush(g_log);
            }
        }
        unsigned long long d = g_drops.load(std::memory_order_relaxed);
        if (d != reported) {
            reported = d;
            char b[128];
            snprintf(b, sizeof b, "!!! log-drops total=%llu (queue overflow)", d);
            Emit(b);
        }
        Sleep(150);
    }
}

// ---- 目录创建（逐级）----
static void MkDirsW(wchar_t* path) {
    for (wchar_t* p = path + 3; *p; ++p) {      // 跳过 "X:\"
        if (*p == L'\\') { *p = L'\0'; CreateDirectoryW(path, nullptr); *p = L'\\'; }
    }
    CreateDirectoryW(path, nullptr);
}

static void OpenLogFile() {
    SYSTEMTIME st; GetLocalTime(&st);
    wchar_t tag[40] = L"";
    {
        wchar_t t[40]; DWORD n = GetEnvironmentVariableW(L"CIVTRACE_TAG", t, 40);
        if (n > 0 && n < 32)
            for (DWORD i = 0, j = 0; i < n && j < 24; ++i)
                if ((t[i] >= L'A' && t[i] <= L'Z') || (t[i] >= L'a' && t[i] <= L'z') ||
                    (t[i] >= L'0' && t[i] <= L'9') || t[i] == L'-' || t[i] == L'_')
                    tag[j++] = t[i];
    }
    wchar_t fname[96];
    _snwprintf(fname, 96, L"civtrace_%04u%02u%02u_%02u%02u%02u_pid%lu%s%s.log",
               st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond,
               g_pid, tag[0] ? L"_" : L"", tag);

    // 1) 首选 %LOCALAPPDATA%\CivLink\M0A\logs
    wchar_t dir[560];
    if (GetEnvironmentVariableW(L"LOCALAPPDATA", dir, 460) && dir[0]) {
        wcscat_s(dir, L"\\CivLink\\M0A\\logs");
        MkDirsW(dir);
        wchar_t full[704];
        _snwprintf(full, 704, L"%s\\%s", dir, fname);
        g_log = _wfopen(full, L"ab");
        if (g_log) { g_logPath = full; return; }
    }
    // 2) 回退 DLL 目录
    wchar_t dp[MAX_PATH];
    if (g_hmod && GetModuleFileNameW(g_hmod, dp, MAX_PATH)) {
        wchar_t* slash = wcsrchr(dp, L'\\');
        if (slash) *slash = L'\0';
        wchar_t full[MAX_PATH + 96];
        _snwprintf(full, MAX_PATH + 96, L"%s\\%s", dp, fname);
        g_log = _wfopen(full, L"ab");
        if (g_log) { g_logPath = full; return; }
    }
    // 3) 最后回退 %TEMP%
    wchar_t tmp[MAX_PATH];
    if (GetTempPathW(MAX_PATH, tmp)) {
        wchar_t full[MAX_PATH + 96];
        _snwprintf(full, MAX_PATH + 96, L"%scivtrace-fallback_%s", tmp, fname);
        g_log = _wfopen(full, L"ab");
        if (g_log) { g_logPath = full; return; }
    }
    g_logPath = L"(none)";
}

static void DrainAndClose() {
    // 会话结束行（drops/seq 汇总）
    {
        std::lock_guard<std::mutex> lk(g_mu);
        unsigned long long d = g_drops.load(std::memory_order_relaxed);
        char buf[160];
        int n = snprintf(buf, sizeof buf, "===== session end seq=%llu drops=%llu =====\r\n", g_seq, d);
        if (n > 0) g_queue.emplace_back(buf, (size_t)n);
    }
    std::vector<std::string> chunk;
    { std::lock_guard<std::mutex> lk(g_mu); chunk.swap(g_queue); }
    std::lock_guard<std::mutex> lk(g_fileMu);
    if (g_log) {
        for (auto& s : chunk) fwrite(s.data(), 1, s.size(), g_log);
        fflush(g_log);
        fclose(g_log);
        g_log = nullptr;
    }
}

// ---- 模块表（调用者解析）----
static void RefreshModulesLocked() {
    g_mods.clear();
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, GetCurrentProcessId());
    if (snap == INVALID_HANDLE_VALUE) return;
    MODULEENTRY32W me; me.dwSize = sizeof me;
    if (Module32FirstW(snap, &me)) {
        do {
            char name[256];
            WideCharToMultiByte(CP_UTF8, 0, me.szModule, -1, name, sizeof name, nullptr, nullptr);
            ModInfo m;
            m.base = (uintptr_t)me.modBaseAddr;
            m.size = (size_t)me.modBaseSize;
            m.name = name;
            g_mods.push_back(m);
        } while (Module32NextW(snap, &me));
    }
    CloseHandle(snap);
}

// ---- 调用者解析：模块名+偏移，带缓存与 5s 节流刷新 ----
// 注意：返回裸值（"module+0x..." 或 "?"），不加前缀——各 Hook 的日志模板
// 已带 "caller=%s"，前缀在这里拼接会出现 "caller=caller=" 双前缀
//（REV-001 实测发现的日志格式缺陷）。
static void CallerOf(void* ret, char* out, size_t n) {
    if (!ret) { snprintf(out, n, "?"); return; }
    std::lock_guard<std::mutex> lk(g_modMu);
    auto it = g_callerCache.find(ret);
    if (it != g_callerCache.end()) { snprintf(out, n, "%s", it->second.c_str()); return; }

    uintptr_t a = (uintptr_t)ret;
    const char* found = nullptr;
    char resolved[160] = "?";
    for (auto& m : g_mods)
        if (a >= m.base && a < m.base + m.size) {
            snprintf(resolved, sizeof resolved, "%s+0x%llx", m.name.c_str(), (unsigned long long)(a - m.base));
            found = resolved;
            break;
        }
    if (!found) {
        static DWORD s_last = 0;
        DWORD now = GetTickCount();
        if (now - s_last > 5000) { s_last = now; RefreshModulesLocked();
            for (auto& m : g_mods)
                if (a >= m.base && a < m.base + m.size) {
                    snprintf(resolved, sizeof resolved, "%s+0x%llx", m.name.c_str(), (unsigned long long)(a - m.base));
                    found = resolved; break;
                }
        }
    }
    g_callerCache.emplace(ret, found ? resolved : "?");
    snprintf(out, n, "%s", found ? resolved : "?");
}

// ---- 地址格式化 ----
static void FmtAddr(const sockaddr* sa, int len, char* out, size_t n) {
    if (!sa || len < 2) { snprintf(out, n, "-"); return; }
    if (sa->sa_family == AF_INET && len >= 8) {
        char ip[64];
        inet_ntop(AF_INET, &((sockaddr_in*)sa)->sin_addr, ip, sizeof ip);
        snprintf(out, n, "%s:%u", ip, (unsigned)ntohs(((sockaddr_in*)sa)->sin_port));
    } else if (sa->sa_family == AF_INET6 && len >= 24) {
        char ip[80];
        inet_ntop(AF_INET6, &((sockaddr_in6*)sa)->sin6_addr, ip, sizeof ip);
        snprintf(out, n, "[%s]:%u", ip, (unsigned)ntohs(((sockaddr_in6*)sa)->sin6_port));
    } else {
        snprintf(out, n, "af=%d(len=%d)", (int)sa->sa_family, len);
    }
}

// ---- socket 状态摘要 ----
static void FmtSock(SOCKET s, char* out, size_t n) {
    std::lock_guard<std::mutex> lk(g_mu);
    auto it = g_socks.find((unsigned long long)s);
    if (it == g_socks.end()) { snprintf(out, n, "s=0x%llx?", (unsigned long long)s); return; }
    const SockInfo& si = it->second;
    size_t off = snprintf(out, n, "s=0x%llx af=%d type=%d", (unsigned long long)s, si.af, si.type);
    if (si.nb)     off += snprintf(out + off, n - off, " NB");
    if (si.async)  off += snprintf(out + off, n - off, " ASYNC");
    if (si.gen)    off += snprintf(out + off, n - off, " g%u", si.gen);
    if (si.closed) off += snprintf(out + off, n - off, " CLOSED");
    if (!si.bound.empty()) snprintf(out + off, n - off, " bound=%s", si.bound.c_str());
}

static void NoteSock(SOCKET s, int af, int type, bool overlapped) {
    std::lock_guard<std::mutex> lk(g_mu);
    SockInfo& si = g_socks[(unsigned long long)s];
    if (si.af != 0 || si.closed) si.gen++;      // 句柄复用 → 代次 +1
    si.af = af; si.type = type; si.closed = false;
    if (overlapped) si.async = true;            // WSA_FLAG_OVERLAPPED 是异步信号之一
}
static void NoteBind(SOCKET s, const std::string& addr) {
    std::lock_guard<std::mutex> lk(g_mu);
    g_socks[(unsigned long long)s].bound = addr;
}
static void SetNonBlocking(SOCKET s, bool nb) {
    std::lock_guard<std::mutex> lk(g_mu);
    g_socks[(unsigned long long)s].nb = nb;
}
static void NoteAsync(SOCKET s) {
    std::lock_guard<std::mutex> lk(g_mu);
    g_socks[(unsigned long long)s].async = true;
}
static void MarkClosed(SOCKET s) {
    std::lock_guard<std::mutex> lk(g_mu);
    auto it = g_socks.find((unsigned long long)s);
    if (it != g_socks.end()) it->second.closed = true;
    if (g_socks.size() > 4096)                  // 防膨胀：清掉已关闭条目
        for (auto i = g_socks.begin(); i != g_socks.end();)
            if (i->second.closed) i = g_socks.erase(i); else ++i;
}

// ---- fd_set 摘要 ----
static void FmtFdSet(const fd_set* fs, char* out, size_t n) {
    if (!fs) { snprintf(out, n, "-"); return; }
    size_t off = 0;
    off += snprintf(out + off, n - off, "n=%u[", (unsigned)fs->fd_count);
    for (u_int i = 0; i < fs->fd_count && i < 6; ++i)
        off += snprintf(out + off, n - off, "%s0x%llx", i ? "," : "", (unsigned long long)fs->fd_array[i]);
    if (fs->fd_count > 6) off += snprintf(out + off, n - off, ",...");
    snprintf(out + off, n - off, "]");
}

// ---- setsockopt/getsockopt 选项名 ----
static void OptName(int level, int optname, char* out, size_t n) {
    if (level != SOL_SOCKET) { snprintf(out, n, "lvl=0x%x opt=0x%x", (unsigned)level, (unsigned)optname); return; }
    switch ((unsigned)optname) {
    case SO_REUSEADDR:       snprintf(out, n, "SO_REUSEADDR"); return;
    case (unsigned)(~SO_REUSEADDR): snprintf(out, n, "SO_EXCLUSIVEADDRUSE"); return;
    case SO_BROADCAST:       snprintf(out, n, "SO_BROADCAST"); return;
    case SO_KEEPALIVE:       snprintf(out, n, "SO_KEEPALIVE"); return;
    case SO_RCVBUF:          snprintf(out, n, "SO_RCVBUF"); return;
    case SO_SNDBUF:          snprintf(out, n, "SO_SNDBUF"); return;
    case SO_RCVTIMEO:        snprintf(out, n, "SO_RCVTIMEO"); return;
    case SO_SNDTIMEO:        snprintf(out, n, "SO_SNDTIMEO"); return;
    default:                 snprintf(out, n, "0x%x", (unsigned)optname); return;
    }
}

// ---- payload 预览（≤16 字节 hex；发现包 4B / 首包 120B 的关键证据）----
static void HexPreview(const char* p, int len, char* out, size_t n) {
    if (!p || len <= 0) { snprintf(out, n, ""); return; }
    int m = len > 16 ? 16 : len;
    size_t off = snprintf(out, n, " data=");
    for (int i = 0; i < m && off < n; ++i)
        off += snprintf(out + off, n - off, "%s%02x", i ? " " : "", (unsigned char)p[i]);
    if (len > 16 && off < n) snprintf(out + off, n - off, " ...");
}
static void HexPreviewWSABUF(LPWSABUF bufs, DWORD cnt, DWORD done, char* out, size_t n) {
    if (!bufs || cnt == 0 || !bufs[0].buf) { snprintf(out, n, ""); return; }
    DWORD lim = done && done < bufs[0].len ? done : bufs[0].len;
    HexPreview(bufs[0].buf, (int)lim, out, n);
}

// ---- 事件掩码 ----
static void FmtEventMask(long m, char* out, size_t n) {
    static const struct { long v; const char* s; } t[] = {
        {FD_READ, "READ"}, {FD_WRITE, "WRITE"}, {FD_OOB, "OOB"}, {FD_ACCEPT, "ACCEPT"},
        {FD_CONNECT, "CONNECT"}, {FD_CLOSE, "CLOSE"}, {FD_QOS, "QOS"}, {FD_GROUP_QOS, "GQOS"},
        {FD_ROUTING_INTERFACE_CHANGE, "RIC"}, {FD_ADDRESS_LIST_CHANGE, "ALC"},
    };
    size_t off = 0;
    for (auto& e : t)
        if (m & e.v) off += snprintf(out + off, n - off, "%s%s", off ? "|" : "", e.s);
    if (!off) snprintf(out, n, "0");
}

// ---- WSAIoctl 扩展函数指针 GUID 解码（H3：ConnectEx/WSARecvMsg 等）----
static void GuidName(const void* pg, char* out, size_t n) {
    static const struct NamedGuid { const char* name; GUID g; } k_ext[] = {
#ifdef WSAID_CONNECTEX
        {"ConnectEx", WSAID_CONNECTEX},
#endif
#ifdef WSAID_ACCEPT_EX
        {"AcceptEx", WSAID_ACCEPT_EX},
#endif
#ifdef WSAID_GETACCEPTEXSOCKADDRS
        {"GetAcceptExSockaddrs", WSAID_GETACCEPTEXSOCKADDRS},
#endif
#ifdef WSAID_TRANSMITFILE
        {"TransmitFile", WSAID_TRANSMITFILE},
#endif
#ifdef WSAID_DISCONNECTEX
        {"DisconnectEx", WSAID_DISCONNECTEX},
#endif
#ifdef WSAID_WSARECVMSG
        {"WSARecvMsg", WSAID_WSARECVMSG},
#endif
#ifdef WSAID_WSASENDMSG
        {"WSASendMsg", WSAID_WSASENDMSG},
#endif
        {"?", {0, 0, 0, {0, 0, 0, 0, 0, 0, 0, 0}}},   // 兜底：保证数组非空（不会命中）
    };
    const GUID* g = (const GUID*)pg;
    for (auto& r : k_ext)
        if (memcmp(g, &r.g, sizeof(GUID)) == 0) { snprintf(out, n, "ext=%s", r.name); return; }
    const unsigned char* p = (const unsigned char*)g;
    size_t off = snprintf(out, n, "ext-guid=");
    for (int i = 0; i < 16 && off < n; ++i)
        off += snprintf(out + off, n - off, "%02x", p[i]);
}

// ===================================================================
// Hook 实现（全部只观察；ErrTx 保存/恢复 last error）
// 约定：if (g_inHook) 透传（防日志路径误调被钩 API 的递归）；
//       real 调用前预格式化参数；real 后立即 commit；日志后 end() 恢复。
// ===================================================================

static int WSAAPI Hook_socket(int af, int type, int protocol) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_socket(af, type, protocol);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    int r = Real_socket(af, type, protocol);
    tx.commit(r == INVALID_SOCKET);
    int e = tx.post.wsa;
    if (r != INVALID_SOCKET) NoteSock((SOCKET)r, af, type, false);
    char line[1024], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "socket af=%d type=%d proto=%d ret=0x%llx caller=%s%s",
             af, type, protocol, (unsigned long long)(SOCKET)r, cb, ErrTag(r, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static SOCKET WSAAPI Hook_WSASocketA(int af, int type, int protocol, LPWSAPROTOCOL_INFOA pi, GROUP g, DWORD flags) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_WSASocketA(af, type, protocol, pi, g, flags);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    SOCKET s = Real_WSASocketA(af, type, protocol, pi, g, flags);
    tx.commit(s == INVALID_SOCKET);
    int e = tx.post.wsa;
    if (s != INVALID_SOCKET) NoteSock(s, af, type, (flags & WSA_FLAG_OVERLAPPED) != 0);
    char line[1024], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "WSASocketA af=%d type=%d flags=0x%x%s ret=0x%llx caller=%s%s",
             af, type, (unsigned)flags, (flags & WSA_FLAG_OVERLAPPED) ? "[OVERLAPPED]" : "",
             (unsigned long long)s, cb, ErrTag((int)s, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return s;
}

static SOCKET WSAAPI Hook_WSASocketW(int af, int type, int protocol, LPWSAPROTOCOL_INFOW pi, GROUP g, DWORD flags) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_WSASocketW(af, type, protocol, pi, g, flags);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    SOCKET s = Real_WSASocketW(af, type, protocol, pi, g, flags);
    tx.commit(s == INVALID_SOCKET);
    int e = tx.post.wsa;
    if (s != INVALID_SOCKET) NoteSock(s, af, type, (flags & WSA_FLAG_OVERLAPPED) != 0);
    char line[1024], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "WSASocketW af=%d type=%d flags=0x%x%s ret=0x%llx caller=%s%s",
             af, type, (unsigned)flags, (flags & WSA_FLAG_OVERLAPPED) ? "[OVERLAPPED]" : "",
             (unsigned long long)s, cb, ErrTag((int)s, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return s;
}

static int WSAAPI Hook_bind(SOCKET s, const sockaddr* name, int namelen) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_bind(s, name, namelen);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    char sb[128], ab[96];
    FmtSock(s, sb, sizeof sb);
    FmtAddr(name, namelen, ab, sizeof ab);
    int r = Real_bind(s, name, namelen);
    tx.commit(r == SOCKET_ERROR);
    int e = tx.post.wsa;
    if (r == 0) NoteBind(s, ab);
    char line[1024], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "bind %s addr=%s ret=%d caller=%s%s", sb, ab, r, cb, ErrTag(r, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static int WSAAPI Hook_sendto(SOCKET s, const char* buf, int len, int flags, const sockaddr* to, int tolen) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_sendto(s, buf, len, flags, to, tolen);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    char sb[128], ab[96], hx[96];
    FmtSock(s, sb, sizeof sb);
    FmtAddr(to, tolen, ab, sizeof ab);
    int r = Real_sendto(s, buf, len, flags, to, tolen);
    tx.commit(r == SOCKET_ERROR);
    int e = tx.post.wsa;
    HexPreview(buf, r >= 0 ? len : 0, hx, sizeof hx);
    char line[1120], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "sendto %s dst=%s len=%d ret=%d%s caller=%s%s",
             sb, ab, len, r, hx, cb, ErrTag(r, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static int WSAAPI Hook_WSASendTo(SOCKET s, LPWSABUF bufs, DWORD cnt, LPDWORD sent, DWORD flags,
                                 const sockaddr* to, int tolen, LPWSAOVERLAPPED ov, LPWSAOVERLAPPED_COMPLETION_ROUTINE cr) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_WSASendTo(s, bufs, cnt, sent, flags, to, tolen, ov, cr);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    char sb[128], ab[96], hx[96];
    FmtSock(s, sb, sizeof sb);
    FmtAddr(to, tolen, ab, sizeof ab);
    int r = Real_WSASendTo(s, bufs, cnt, sent, flags, to, tolen, ov, cr);
    tx.commit(r == SOCKET_ERROR);
    int e = tx.post.wsa;
    HexPreviewWSABUF(bufs, cnt, 0, hx, sizeof hx);
    char line[1200], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "WSASendTo %s dst=%s cnt=%u%s ret=%d%s caller=%s%s",
             sb, ab, (unsigned)cnt, OvTag(r, e, ov), r, hx, cb, ErrTag(r, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static int WSAAPI Hook_recvfrom(SOCKET s, char* buf, int len, int flags, sockaddr* from, int* fromlen) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_recvfrom(s, buf, len, flags, from, fromlen);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    char sb[128], ab[96], hx[96];
    FmtSock(s, sb, sizeof sb);
    int r = Real_recvfrom(s, buf, len, flags, from, fromlen);
    tx.commit(r == SOCKET_ERROR);
    int e = tx.post.wsa;
    if (r >= 0 && from && fromlen) FmtAddr(from, *fromlen, ab, sizeof ab);
    else snprintf(ab, sizeof ab, "-");
    HexPreview(buf, r >= 0 ? r : 0, hx, sizeof hx);
    char line[1200], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "recvfrom %s ret=%d src=%s len=%d%s caller=%s%s",
             sb, r, ab, r >= 0 ? r : 0, hx, cb, ErrTag(r, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static int WSAAPI Hook_WSARecvFrom(SOCKET s, LPWSABUF bufs, DWORD cnt, LPDWORD bytes, LPDWORD flags,
                                   sockaddr* from, LPINT fromlen, LPWSAOVERLAPPED ov, LPWSAOVERLAPPED_COMPLETION_ROUTINE cr) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_WSARecvFrom(s, bufs, cnt, bytes, flags, from, fromlen, ov, cr);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    char sb[128], ab[96], hx[96];
    FmtSock(s, sb, sizeof sb);
    int r = Real_WSARecvFrom(s, bufs, cnt, bytes, flags, from, fromlen, ov, cr);
    tx.commit(r == SOCKET_ERROR);
    int e = tx.post.wsa;
    // PENDING 状态绝不读 from / bytes / 缓冲内容（输出在完成时才有效）
    if (r == 0 && from && fromlen) FmtAddr(from, *fromlen, ab, sizeof ab);
    else snprintf(ab, sizeof ab, "-");
    if (r == 0) HexPreviewWSABUF(bufs, cnt, bytes ? *bytes : 0, hx, sizeof hx);
    else snprintf(hx, sizeof hx, "");
    char line[1280], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "WSARecvFrom %s ret=%d src=%s cnt=%u%s%s caller=%s%s",
             sb, r, ab, (unsigned)cnt, OvTag(r, e, ov), hx, cb, ErrTag(r, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static int WSAAPI Hook_select(int nfds, fd_set* rset, fd_set* wset, fd_set* eset, const timeval* tv) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_select(nfds, rset, wset, eset, tv);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    char rb[200], wb[200], eb[200];
    FmtFdSet(rset, rb, sizeof rb);
    FmtFdSet(wset, wb, sizeof wb);
    FmtFdSet(eset, eb, sizeof eb);
    int r = Real_select(nfds, rset, wset, eset, tv);
    tx.commit(r == SOCKET_ERROR);
    int e = tx.post.wsa;
    char line[1400], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "select rfd=%s wfd=%s efd=%s timeout=%s ret=%d caller=%s%s",
             rb, wb, eb, tv ? "set" : "null(inf)", r, cb, ErrTag(r, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static int WSAAPI Hook_closesocket(SOCKET s) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_closesocket(s);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    char sb[128];
    FmtSock(s, sb, sizeof sb);                  // 关闭前状态
    int r = Real_closesocket(s);
    tx.commit(r == SOCKET_ERROR);
    int e = tx.post.wsa;
    MarkClosed(s);
    char line[1024], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "closesocket %s ret=%d caller=%s%s", sb, r, cb, ErrTag(r, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static int WSAAPI Hook_ioctlsocket(SOCKET s, long cmd, u_long* argp) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_ioctlsocket(s, cmd, argp);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    int r = Real_ioctlsocket(s, cmd, argp);
    tx.commit(r == SOCKET_ERROR);
    int e = tx.post.wsa;
    if (cmd == FIONBIO && argp && r == 0) SetNonBlocking(s, *argp != 0);
    char line[1024], cb[160];
    CallerOf(ret, cb, sizeof cb);
    if (cmd == FIONBIO)
        snprintf(line, sizeof line, "ioctlsocket s=0x%llx FIONBIO nb=%u ret=%d caller=%s%s",
                 (unsigned long long)s, argp ? (unsigned)*argp : 0, r, cb, ErrTag(r, e));
    else
        snprintf(line, sizeof line, "ioctlsocket s=0x%llx cmd=0x%lx ret=%d caller=%s%s",
                 (unsigned long long)s, (unsigned long)cmd, r, cb, ErrTag(r, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static int WSAAPI Hook_setsockopt(SOCKET s, int level, int optname, const char* optval, int optlen) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_setsockopt(s, level, optname, optval, optlen);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    char on[48];
    OptName(level, optname, on, sizeof on);
    int val = 0;
    if (optval && optlen >= (int)sizeof(int)) val = *(const int*)optval;
    int r = Real_setsockopt(s, level, optname, optval, optlen);
    tx.commit(r == SOCKET_ERROR);
    int e = tx.post.wsa;
    char line[1024], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "setsockopt s=0x%llx %s val=%d ret=%d caller=%s%s",
             (unsigned long long)s, on, val, r, cb, ErrTag(r, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static int WSAAPI Hook_getsockopt(SOCKET s, int level, int optname, char* optval, int* optlen) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_getsockopt(s, level, optname, optval, optlen);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    char on[48];
    OptName(level, optname, on, sizeof on);
    int r = Real_getsockopt(s, level, optname, optval, optlen);
    tx.commit(r == SOCKET_ERROR);
    int e = tx.post.wsa;
    int val = 0; bool hasVal = false;
    if (r == 0 && level == SOL_SOCKET && optval && optlen && *optlen >= (int)sizeof(int)) {
        val = *(const int*)optval; hasVal = true;
    }
    char line[1024], cb[160];
    CallerOf(ret, cb, sizeof cb);
    if (hasVal)
        snprintf(line, sizeof line, "getsockopt s=0x%llx %s val=%d ret=%d caller=%s%s",
                 (unsigned long long)s, on, val, r, cb, ErrTag(r, e));
    else
        snprintf(line, sizeof line, "getsockopt s=0x%llx %s ret=%d caller=%s%s",
                 (unsigned long long)s, on, r, cb, ErrTag(r, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static int WSAAPI Hook_connect(SOCKET s, const sockaddr* name, int namelen) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_connect(s, name, namelen);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    char ab[96];
    FmtAddr(name, namelen, ab, sizeof ab);
    int r = Real_connect(s, name, namelen);
    tx.commit(r == SOCKET_ERROR);
    int e = tx.post.wsa;
    char line[1024], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "connect s=0x%llx dst=%s ret=%d caller=%s%s",
             (unsigned long long)s, ab, r, cb, ErrTag(r, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static int WSAAPI Hook_getsockname(SOCKET s, sockaddr* name, int* namelen) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_getsockname(s, name, namelen);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    int r = Real_getsockname(s, name, namelen);
    tx.commit(r == SOCKET_ERROR);
    int e = tx.post.wsa;
    char ab[96];
    if (r == 0 && name && namelen) FmtAddr(name, *namelen, ab, sizeof ab);
    else snprintf(ab, sizeof ab, "-");
    char line[1024], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "getsockname s=0x%llx -> %s ret=%d caller=%s%s",
             (unsigned long long)s, ab, r, cb, ErrTag(r, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static int WSAAPI Hook_getpeername(SOCKET s, sockaddr* name, int* namelen) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_getpeername(s, name, namelen);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    int r = Real_getpeername(s, name, namelen);
    tx.commit(r == SOCKET_ERROR);
    int e = tx.post.wsa;
    char ab[96];
    if (r == 0 && name && namelen) FmtAddr(name, *namelen, ab, sizeof ab);
    else snprintf(ab, sizeof ab, "-");
    char line[1024], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "getpeername s=0x%llx -> %s ret=%d caller=%s%s",
             (unsigned long long)s, ab, r, cb, ErrTag(r, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static int WSAAPI Hook_WSAEventSelect(SOCKET s, WSAEVENT ev, long events) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_WSAEventSelect(s, ev, events);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    int r = Real_WSAEventSelect(s, ev, events);
    tx.commit(r == SOCKET_ERROR);
    int e = tx.post.wsa;
    if (r == 0) NoteAsync(s);
    char em[160];
    FmtEventMask(events, em, sizeof em);
    char line[1024], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "WSAEventSelect s=0x%llx event=%p events=0x%lx(%s) ret=%d caller=%s%s",
             (unsigned long long)s, (void*)ev, (unsigned long)events, em, r, cb, ErrTag(r, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static int WSAAPI Hook_WSAAsyncSelect(SOCKET s, HWND hwnd, u_int msg, long events) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_WSAAsyncSelect(s, hwnd, msg, events);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    int r = Real_WSAAsyncSelect(s, hwnd, msg, events);
    tx.commit(r == SOCKET_ERROR);
    int e = tx.post.wsa;
    if (r == 0) NoteAsync(s);
    char em[160];
    FmtEventMask(events, em, sizeof em);
    char line[1024], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "WSAAsyncSelect s=0x%llx hwnd=%p msg=%u events=0x%lx(%s) ret=%d caller=%s%s",
             (unsigned long long)s, (void*)hwnd, (unsigned)msg, (unsigned long)events, em, r, cb, ErrTag(r, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static int WSAAPI Hook_WSAPoll(CVL_POLLFD* fds, ULONG nfds, int timeout) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_WSAPoll(fds, nfds, timeout);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    int r = Real_WSAPoll(fds, nfds, timeout);
    tx.commit(r == SOCKET_ERROR);
    int e = tx.post.wsa;
    char line[1200], cb[160];
    CallerOf(ret, cb, sizeof cb);
    size_t off = snprintf(line, sizeof line, "WSAPoll n=%u timeout=%d ret=%d [", (unsigned)nfds, timeout, r);
    if (fds) for (ULONG i = 0; i < nfds && i < 6; ++i)
        off += snprintf(line + off, sizeof(line) - off, "%s0x%llx:0x%x/0x%x", i ? "," : "",
                        (unsigned long long)fds[i].fd, (unsigned)(unsigned short)fds[i].events,
                        (unsigned)(unsigned short)fds[i].revents);
    snprintf(line + off, sizeof(line) - off, "] caller=%s%s", cb, ErrTag(r, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static int WSAAPI Hook_WSASend(SOCKET s, LPWSABUF bufs, DWORD cnt, LPDWORD sent, DWORD flags,
                               LPWSAOVERLAPPED ov, LPWSAOVERLAPPED_COMPLETION_ROUTINE cr) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_WSASend(s, bufs, cnt, sent, flags, ov, cr);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    int r = Real_WSASend(s, bufs, cnt, sent, flags, ov, cr);
    tx.commit(r == SOCKET_ERROR);
    int e = tx.post.wsa;
    char line[1024], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "WSASend s=0x%llx cnt=%u%s ret=%d caller=%s%s",
             (unsigned long long)s, (unsigned)cnt, OvTag(r, e, ov), r, cb, ErrTag(r, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static int WSAAPI Hook_WSARecv(SOCKET s, LPWSABUF bufs, DWORD cnt, LPDWORD bytes, LPDWORD flags,
                               LPWSAOVERLAPPED ov, LPWSAOVERLAPPED_COMPLETION_ROUTINE cr) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_WSARecv(s, bufs, cnt, bytes, flags, ov, cr);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    int r = Real_WSARecv(s, bufs, cnt, bytes, flags, ov, cr);
    tx.commit(r == SOCKET_ERROR);
    int e = tx.post.wsa;
    char line[1024], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "WSARecv s=0x%llx cnt=%u%s ret=%d caller=%s%s",
             (unsigned long long)s, (unsigned)cnt, OvTag(r, e, ov), r, cb, ErrTag(r, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static int WSAAPI Hook_WSAIoctl(SOCKET s, DWORD code, LPVOID inb, DWORD inbl, LPVOID outb, DWORD outbl,
                                LPDWORD retb, LPWSAOVERLAPPED ov, LPWSAOVERLAPPED_COMPLETION_ROUTINE cr) {
    if (g_inHook.load(std::memory_order_relaxed))
        return Real_WSAIoctl(s, code, inb, inbl, outb, outbl, retb, ov, cr);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    char gn[80] = "";
    if (code == SIO_GET_EXTENSION_FUNCTION_POINTER && inb && inbl >= 16)
        GuidName(inb, gn, sizeof gn);
    int r = Real_WSAIoctl(s, code, inb, inbl, outb, outbl, retb, ov, cr);
    tx.commit(r == SOCKET_ERROR);
    int e = tx.post.wsa;
    char line[1200], cb[160];
    CallerOf(ret, cb, sizeof cb);
    if (gn[0])
        snprintf(line, sizeof line, "WSAIoctl s=0x%llx code=0x%08lx %s ov=%s ret=%d caller=%s%s",
                 (unsigned long long)s, (unsigned long)code, gn, ov ? "yes" : "no", r, cb, ErrTag(r, e));
    else
        snprintf(line, sizeof line, "WSAIoctl s=0x%llx code=0x%08lx in=%lu out=%lu ov=%s ret=%d caller=%s%s",
                 (unsigned long long)s, (unsigned long)code, (unsigned long)inbl, (unsigned long)outbl,
                 ov ? "yes" : "no", r, cb, ErrTag(r, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static BOOL WSAAPI Hook_WSAGetOverlappedResult(SOCKET s, LPWSAOVERLAPPED ov, LPDWORD lpcbTransfer, BOOL fWait, LPDWORD lpdwFlags) {
    if (g_inHook.load(std::memory_order_relaxed))
        return Real_WSAGetOverlappedResult(s, ov, lpcbTransfer, fWait, lpdwFlags);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    BOOL ok = Real_WSAGetOverlappedResult(s, ov, lpcbTransfer, fWait, lpdwFlags);
    tx.commit(ok == FALSE);
    int e = tx.post.wsa;
    char line[1024], cb[160];
    CallerOf(ret, cb, sizeof cb);
    if (ok)
        snprintf(line, sizeof line, "WSAGetOverlappedResult s=0x%llx ov=%p wait=%d ret=1 bytes=%lu flags=0x%lx caller=%s%s",
                 (unsigned long long)s, (void*)ov, (int)fWait,
                 (unsigned long)(lpcbTransfer ? *lpcbTransfer : 0),
                 (unsigned long)(lpdwFlags ? *lpdwFlags : 0), cb, ErrTag(ok ? 0 : -1, e));
    else
        snprintf(line, sizeof line, "WSAGetOverlappedResult s=0x%llx ov=%p wait=%d ret=0 caller=%s%s",
                 (unsigned long long)s, (void*)ov, (int)fWait, cb, ErrTag(-1, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return ok;
}

static DWORD WSAAPI Hook_WSAWaitForMultipleEvents(DWORD cEvents, const WSAEVENT* lphEvents, BOOL fWaitAll, DWORD timeout, BOOL fAlertable) {
    if (g_inHook.load(std::memory_order_relaxed))
        return Real_WSAWaitForMultipleEvents(cEvents, lphEvents, fWaitAll, timeout, fAlertable);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    DWORD r = Real_WSAWaitForMultipleEvents(cEvents, lphEvents, fWaitAll, timeout, fAlertable);
    tx.commit(r == WSA_WAIT_FAILED);
    int e = tx.post.wsa;
    char line[1024], cb[160];
    CallerOf(ret, cb, sizeof cb);
    if (r == WSA_WAIT_FAILED)
        snprintf(line, sizeof line, "WSAWaitForMultipleEvents n=%lu all=%d timeout=%lu ret=FAILED caller=%s%s",
                 (unsigned long)cEvents, (int)fWaitAll, (unsigned long)timeout, cb, ErrTag(-1, e));
    else if (r == WSA_WAIT_TIMEOUT)
        snprintf(line, sizeof line, "WSAWaitForMultipleEvents n=%lu all=%d timeout=%lu ret=TIMEOUT caller=%s",
                 (unsigned long)cEvents, (int)fWaitAll, (unsigned long)timeout, cb);
    else
        // 注意：SDK 头文件在 winsock2.h 先于 windows.h 时只定义 WSA_WAIT_FAILED/
        // EVENT_0/TIMEOUT（回退块），WSA_WAIT_OBJECT_0/WSA_WAIT_IO_COMPLETION 不存在，
        // 故用 winbase 的 WAIT_* 宏与 WSA_WAIT_EVENT_0（值相等：0）。
        snprintf(line, sizeof line, "WSAWaitForMultipleEvents n=%lu all=%d timeout=%lu ret=obj+%lu caller=%s",
                 (unsigned long)cEvents, (int)fWaitAll, (unsigned long)timeout,
                 (unsigned long)(r == (DWORD)WAIT_IO_COMPLETION ? 0 : r - WSA_WAIT_EVENT_0), cb);
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static WSAEVENT WSAAPI Hook_WSACreateEvent(void) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_WSACreateEvent();
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    WSAEVENT ev = Real_WSACreateEvent();
    tx.commit(ev == WSA_INVALID_EVENT);
    int e = tx.post.wsa;
    char line[512], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "WSACreateEvent ret=%p caller=%s%s", (void*)ev, cb, ErrTag(ev == WSA_INVALID_EVENT ? -1 : 0, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return ev;
}

static BOOL WSAAPI Hook_WSACloseEvent(WSAEVENT ev) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_WSACloseEvent(ev);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    BOOL r = Real_WSACloseEvent(ev);
    tx.commit(r == FALSE);
    int e = tx.post.wsa;
    char line[512], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "WSACloseEvent ev=%p ret=%d caller=%s%s", (void*)ev, (int)r, cb, ErrTag(r == FALSE ? -1 : 0, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static int WSAAPI Hook_WSAEnumNetworkEvents(SOCKET s, WSAEVENT ev, LPWSANETWORKEVENTS ne) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_WSAEnumNetworkEvents(s, ev, ne);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    int r = Real_WSAEnumNetworkEvents(s, ev, ne);
    tx.commit(r == SOCKET_ERROR);
    int e = tx.post.wsa;
    char em[160] = "";
    long err0 = 0;
    if (r == 0 && ne) { FmtEventMask(ne->lNetworkEvents, em, sizeof em); err0 = ne->iErrorCode[0]; }
    char line[1024], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "WSAEnumNetworkEvents s=0x%llx events=0x%lx(%s) err0=%ld ret=%d caller=%s%s",
             (unsigned long long)s, (unsigned long)(ne ? ne->lNetworkEvents : 0), em,
             (long)err0, r, cb, ErrTag(r, e));
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

static int WSAAPI Hook_WSACleanup(void) {
    if (g_inHook.load(std::memory_order_relaxed)) return Real_WSACleanup();
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin();
    int r = Real_WSACleanup();
    tx.commit(r == SOCKET_ERROR);
    char line[256], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "WSACleanup ret=%d caller=%s", r, cb);
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

// ---- IOCP（kernel32）----
static bool IsKnownSocket(HANDLE h) {
    std::lock_guard<std::mutex> lk(g_mu);
    return g_socks.count((unsigned long long)(uintptr_t)h) != 0;
}

static HANDLE WINAPI Hook_CreateIoCompletionPort(HANDLE file, HANDLE existing, ULONG_PTR key, DWORD threads) {
    if (g_inHook.load(std::memory_order_relaxed))
        return Real_CreateIoCompletionPort(file, existing, key, threads);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin(); tx.win32 = true;    // kernel32：错误走 Win32 槽位（REV-001）
    HANDLE r = Real_CreateIoCompletionPort(file, existing, key, threads);
    tx.commit(r == nullptr);
    char line[1024], cb[160];
    CallerOf(ret, cb, sizeof cb);
    snprintf(line, sizeof line, "iocp-create file=0x%llx%s existing=0x%llx port=0x%llx key=0x%llx threads=%lu caller=%s",
             (unsigned long long)(uintptr_t)file,
             (file && file != INVALID_HANDLE_VALUE && IsKnownSocket(file)) ? "(sock)" : "",
             (unsigned long long)(uintptr_t)existing,
             (unsigned long long)(uintptr_t)r, (unsigned long long)key,
             (unsigned long)threads, cb);
    Emit(line);
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return r;
}

// GQCS/GQCSEx 可能为极热循环：前 50 次全记 + 之后每 1000 次记 1 次（call# 计数）
static BOOL WINAPI Hook_GetQueuedCompletionStatus(HANDLE port, LPDWORD bytes, PULONG_PTR key, LPOVERLAPPED* pov, DWORD ms) {
    if (g_inHook.load(std::memory_order_relaxed))
        return Real_GetQueuedCompletionStatus(port, bytes, key, pov, ms);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin(); tx.win32 = true;    // kernel32：错误走 Win32 槽位（REV-001）
    BOOL ok = Real_GetQueuedCompletionStatus(port, bytes, key, pov, ms);
    tx.commit(ok == FALSE);
    DWORD e = tx.post.win;
    unsigned long long n = ++g_gqcsCalls;
    if (n <= 50 || n % 1000 == 0) {
        char line[1024], cb[160];
        CallerOf(ret, cb, sizeof cb);
        // REV-001 BUG#3：ret=FALSE 且 *pov==NULL（超时，无完成包）时输出参数
        // 内容不确定，不读；ret=FALSE 但 *pov 非空 = 出队的失败完成包，参数有效
        //（MSDN），可读。
        if (ok || (pov && *pov))
            snprintf(line, sizeof line, "iocp-wait port=0x%llx ret=%d bytes=%lu ov=%p lasterr=%lu call#=%llu caller=%s",
                     (unsigned long long)(uintptr_t)port, (int)ok,
                     (unsigned long)(bytes ? *bytes : 0),
                     (pov && *pov) ? (void*)*pov : nullptr, (unsigned long)e, n, cb);
        else
            snprintf(line, sizeof line, "iocp-wait port=0x%llx ret=TIMEOUT lasterr=%lu call#=%llu caller=%s",
                     (unsigned long long)(uintptr_t)port, (unsigned long)e, n, cb);
        Emit(line);
    }
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return ok;
}

static BOOL WINAPI Hook_GetQueuedCompletionStatusEx(HANDLE port, void* entries, ULONG count, PULONG removed, DWORD ms, BOOL alertable) {
    if (g_inHook.load(std::memory_order_relaxed))
        return Real_GetQueuedCompletionStatusEx(port, entries, count, removed, ms, alertable);
    g_inHook.store(true, std::memory_order_relaxed);
    void* ret = _ReturnAddress();
    ErrTx tx; tx.begin(); tx.win32 = true;    // kernel32：错误走 Win32 槽位（REV-001）
    BOOL ok = Real_GetQueuedCompletionStatusEx(port, entries, count, removed, ms, alertable);
    tx.commit(ok == FALSE);
    DWORD e = tx.post.win;
    unsigned long long n = ++g_gqcsCalls;
    if (n <= 50 || n % 1000 == 0) {
        char line[1024], cb[160];
        CallerOf(ret, cb, sizeof cb);
        // REV-001 BUG#3：失败时 *removed 内容不确定，不读
        if (ok)
            snprintf(line, sizeof line, "iocp-wait-ex port=0x%llx ret=1 removed=%lu call#=%llu caller=%s",
                     (unsigned long long)(uintptr_t)port,
                     (unsigned long)(removed ? *removed : 0), n, cb);
        else
            snprintf(line, sizeof line, "iocp-wait-ex port=0x%llx ret=0 lasterr=%lu call#=%llu caller=%s",
                     (unsigned long long)(uintptr_t)port, (unsigned long)e, n, cb);
        Emit(line);
    }
    tx.end();
    g_inHook.store(false, std::memory_order_relaxed);
    return ok;
}

// ===================================================================
// 安装与生命周期
// ===================================================================
static bool InstallHooks() {
    if (MH_Initialize() != MH_OK) { Emit("!!! MH_Initialize FAILED"); return false; }
    struct Entry { const wchar_t* dll; const char* name; void* detour; void** orig; };
    static const Entry table[] = {
        {L"ws2_32.dll", "socket",         (void*)&Hook_socket,         (void**)&Real_socket},
        {L"ws2_32.dll", "WSASocketA",     (void*)&Hook_WSASocketA,     (void**)&Real_WSASocketA},
        {L"ws2_32.dll", "WSASocketW",     (void*)&Hook_WSASocketW,     (void**)&Real_WSASocketW},
        {L"ws2_32.dll", "bind",           (void*)&Hook_bind,           (void**)&Real_bind},
        {L"ws2_32.dll", "sendto",         (void*)&Hook_sendto,         (void**)&Real_sendto},
        {L"ws2_32.dll", "WSASendTo",      (void*)&Hook_WSASendTo,      (void**)&Real_WSASendTo},
        {L"ws2_32.dll", "recvfrom",       (void*)&Hook_recvfrom,       (void**)&Real_recvfrom},
        {L"ws2_32.dll", "WSARecvFrom",    (void*)&Hook_WSARecvFrom,    (void**)&Real_WSARecvFrom},
        {L"ws2_32.dll", "select",         (void*)&Hook_select,         (void**)&Real_select},
        {L"ws2_32.dll", "closesocket",    (void*)&Hook_closesocket,    (void**)&Real_closesocket},
        {L"ws2_32.dll", "ioctlsocket",    (void*)&Hook_ioctlsocket,    (void**)&Real_ioctlsocket},
        {L"ws2_32.dll", "setsockopt",     (void*)&Hook_setsockopt,     (void**)&Real_setsockopt},
        {L"ws2_32.dll", "getsockopt",     (void*)&Hook_getsockopt,     (void**)&Real_getsockopt},
        {L"ws2_32.dll", "connect",        (void*)&Hook_connect,        (void**)&Real_connect},
        {L"ws2_32.dll", "getsockname",    (void*)&Hook_getsockname,    (void**)&Real_getsockname},
        {L"ws2_32.dll", "getpeername",    (void*)&Hook_getpeername,    (void**)&Real_getpeername},
        {L"ws2_32.dll", "WSAEventSelect", (void*)&Hook_WSAEventSelect, (void**)&Real_WSAEventSelect},
        {L"ws2_32.dll", "WSAAsyncSelect", (void*)&Hook_WSAAsyncSelect, (void**)&Real_WSAAsyncSelect},
        {L"ws2_32.dll", "WSAPoll",        (void*)&Hook_WSAPoll,        (void**)&Real_WSAPoll},
        {L"ws2_32.dll", "WSASend",        (void*)&Hook_WSASend,        (void**)&Real_WSASend},
        {L"ws2_32.dll", "WSARecv",        (void*)&Hook_WSARecv,        (void**)&Real_WSARecv},
        {L"ws2_32.dll", "WSACleanup",     (void*)&Hook_WSACleanup,     (void**)&Real_WSACleanup},
        {L"ws2_32.dll", "WSAIoctl",       (void*)&Hook_WSAIoctl,       (void**)&Real_WSAIoctl},
        {L"ws2_32.dll", "WSAGetOverlappedResult", (void*)&Hook_WSAGetOverlappedResult, (void**)&Real_WSAGetOverlappedResult},
        {L"ws2_32.dll", "WSAWaitForMultipleEvents", (void*)&Hook_WSAWaitForMultipleEvents, (void**)&Real_WSAWaitForMultipleEvents},
        {L"ws2_32.dll", "WSACreateEvent", (void*)&Hook_WSACreateEvent, (void**)&Real_WSACreateEvent},
        {L"ws2_32.dll", "WSACloseEvent",  (void*)&Hook_WSACloseEvent,  (void**)&Real_WSACloseEvent},
        {L"ws2_32.dll", "WSAEnumNetworkEvents", (void*)&Hook_WSAEnumNetworkEvents, (void**)&Real_WSAEnumNetworkEvents},
        {L"kernel32.dll", "CreateIoCompletionPort",       (void*)&Hook_CreateIoCompletionPort,       (void**)&Real_CreateIoCompletionPort},
        {L"kernel32.dll", "GetQueuedCompletionStatus",    (void*)&Hook_GetQueuedCompletionStatus,    (void**)&Real_GetQueuedCompletionStatus},
        {L"kernel32.dll", "GetQueuedCompletionStatusEx",  (void*)&Hook_GetQueuedCompletionStatusEx,  (void**)&Real_GetQueuedCompletionStatusEx},
    };
    for (const auto& en : table) {
        MH_STATUS st = MH_CreateHookApi(en.dll, en.name, en.detour, en.orig);
        if (st != MH_OK) {
            char line[256];
            snprintf(line, sizeof line, "!!! MH_CreateHookApi(%ls!%s) failed status=%d", en.dll, en.name, (int)st);
            Emit(line);
            g_hooksFail.fetch_add(1);
        } else {
            g_hooksOk.fetch_add(1);
        }
    }
    if (MH_EnableHook(MH_ALL_HOOKS) != MH_OK) {  // 批量启钩：单次线程协调
        Emit("!!! MH_EnableHook(ALL) FAILED");
        g_hooksFail.fetch_add(1);
        return false;
    }
    char line[160];
    snprintf(line, sizeof line, "=== hooks installed ok=%u fail=%u (observe-only) ===",
             (unsigned)g_hooksOk.load(), (unsigned)g_hooksFail.load());
    Emit(line);
    return g_hooksFail.load() == 0;
}

static void InitWorker() {
    OpenLogFile();
    {
        char exe[MAX_PATH * 2];
        GetModuleFileNameA(nullptr, exe, sizeof exe);
        Emit("===== civtrace " CIVTRACE_VERSION " session start =====");
        char b[2048];
        snprintf(b, sizeof b, "log-path=%ls", g_logPath.c_str());
        Emit(b);
        snprintf(b, sizeof b, "exe=%s", exe);
        Emit(b);
        LARGE_INTEGER f, q; SYSTEMTIME st;
        QueryPerformanceFrequency(&f); QueryPerformanceCounter(&q); GetLocalTime(&st);
        snprintf(b, sizeof b,
                 "pid=%lu qpc-freq=%llu wall=%04u-%02u-%02u %02u:%02u:%02u.%03u qpc=%llu",
                 (unsigned long)g_pid, (unsigned long long)f.QuadPart,
                 st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, st.wMilliseconds,
                 (unsigned long long)q.QuadPart);
        Emit(b);
        snprintf(b, sizeof b, "note: local ordering=qpc/seq; cross-machine alignment=wall clock; tag env=CIVTRACE_TAG");
        Emit(b);
    }
    { std::lock_guard<std::mutex> lk(g_modMu); RefreshModulesLocked(); }
    // REV-001 BUG#1：刷盘线程必须在装钩前启动——否则会话期日志只堆在内存
    // 队列（超 65536 行即丢弃，进程被杀时全丢），只有卸载/退出才一次性落盘。
    try { g_flusher = std::thread(FlushLoop); }
    catch (...) { Emit("!!! flusher thread creation FAILED - log flushes only at shutdown"); }
    InstallHooks();
}

// 导出：注入器在 FreeLibrary 之前调用。此处无 Loader Lock，可安全等待与反初始化。
// 返回值契约（civtrace_common.h）：0=成功 / 1=已 shutdown / 2=部分失败。
// 远程线程退出码 = 该返回值（DWORD，完整 32 位），注入器凭它决定是否 FreeLibrary。
extern "C" __declspec(dllexport) DWORD NTAPI CivTraceShutdown(void) {
    if (g_shutdown.exchange(true)) return 1;   // 重复调用：此前已完成（或已开始）卸载链
    Emit("=== shutdown requested via export ===");
    g_stop = true;
    bool ok = true;
    if (g_init.joinable()) g_init.join();          // 确保装钩线程已结束（罕见竞态）
    if (MH_DisableHook(MH_ALL_HOOKS) != MH_OK) { Emit("!!! MH_DisableHook(ALL) failed"); ok = false; }
    if (g_flusher.joinable()) g_flusher.join();    // 等待正在执行的 Hook 退出 + 刷盘
    if (MH_Uninitialize() != MH_OK) { Emit("!!! MH_Uninitialize failed"); ok = false; }
    DrainAndClose();
    return ok ? 0 : 2;
}

static BOOL APIENTRY DllMain(HMODULE hmod, DWORD reason, LPVOID reserved) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hmod);
        g_hmod = hmod;
        g_pid = GetCurrentProcessId();
        try { g_init = std::thread(InitWorker); }   // 延迟初始化：避开 Loader Lock
        catch (...) { /* 线程创建失败：保持未装钩，注入器验证会报告 */ }
        return TRUE;
    }
    if (reason == DLL_PROCESS_DETACH) {
        bool processExit = (reserved != nullptr);
        if (g_shutdown.exchange(true)) return TRUE; // 已走导出卸载链，无需再处理
        g_stop = true;
        if (!processExit) {
            // 兜底路径（注入器未调用导出时）：Loader Lock 下等待有死锁风险，
            // 仅在导出链不可用时的最后手段；常规卸载必须走 CivTraceShutdown。
            if (g_init.joinable()) g_init.join();
            if (g_flusher.joinable()) g_flusher.join();
            MH_Uninitialize();
        } else {
            if (g_init.joinable()) g_init.detach();
            if (g_flusher.joinable()) g_flusher.detach();
        }
        DrainAndClose();
    }
    return TRUE;
}
