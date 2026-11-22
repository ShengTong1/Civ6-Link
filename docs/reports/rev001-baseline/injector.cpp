// civinject v0.3 —— CivLink M0-A 追踪 DLL 注入器
//
// 用法：
//   civinject.exe -x CivilizationVI.exe              注入（DLL 默认取本程序同目录 civtrace.dll）
//   civinject.exe -x CivilizationVI.exe C:\path\civtrace.dll
//   civinject.exe -x CivilizationVI.exe -u           卸载（先调 DLL 导出 CivTraceShutdown 再 FreeLibrary）
//   civinject.exe -x CivilizationVI.exe -p 12345     指定 PID（多进程同名匹配时消歧）
//   civinject.exe -x CivilizationVI.exe -p 12345 -u
//
// 注入方式与 injciv6 相同：SeDebugPrivilege + CreateRemoteThread(LoadLibraryW)。
// 需要管理员权限运行（游戏非提权时通常也要求注入器提权以拿到 PROCESS_ALL_ACCESS）。
//
// v0.3（对应 m00276 审查 3.5 注入器审计项）：
//   - 目标架构检查：IsWow64Process 拒绝 32 位目标（DLL 为 x64）
//   - 重复注入检测：注入前 RemoteModulePresent 复核，已加载则跳过并报告
//   - 远程线程等待超时（15s），不无限等待
//   - 进程消歧：-p <pid> 强制选择；多匹配时打印每个 PID 的完整映像路径
//   - 卸载安全链：解析远程 civtrace.dll!CivTraceShutdown（DONT_RESOLVE_DLL_REFERENCES
//     本地探测导出地址 → 本地基址差换算远程地址 → CreateRemoteThread 调用），
//     让 DLL 先 Disable 全部 Hook 并等待 Hook 执行体退出，再 FreeLibrary；
//     FreeLibrary 成功 ≠ Hook 安全卸载（审查 8/3.5），故以此导出为准。
//   - 验证：模块枚举优先，打包/UWP 进程快照被拒时回退远程 GetModuleHandleW
//
// 注意（x64）：LoadLibraryW/GetModuleHandleW 远程线程的退出码只是返回值的低 32 位，
// 不可当作模块句柄或成败判据 —— 一律以模块枚举/远程 GetModuleHandleW 复核为准。

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>

static const char* DLL_NAME = "civtrace.dll";
static const char* SHUTDOWN_EXPORT = "CivTraceShutdown";

static void EnableDebugPrivilege() {
    HANDLE tok = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &tok)) return;
    LUID luid{};
    if (LookupPrivilegeValueA(nullptr, "SeDebugPrivilege", &luid)) {
        TOKEN_PRIVILEGES tp{};
        tp.PrivilegeCount = 1;
        tp.Privileges[0].Luid = luid;
        tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
        AdjustTokenPrivileges(tok, FALSE, &tp, sizeof(tp), nullptr, nullptr);
    }
    CloseHandle(tok);
}

static int FindPids(const char* name, DWORD* out, int maxn) {
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return 0;
    PROCESSENTRY32 pe{}; pe.dwSize = sizeof pe;
    int n = 0;
    if (Process32First(snap, &pe)) {
        do {
            if (_stricmp(pe.szExeFile, name) == 0 && n < maxn) out[n++] = pe.th32ProcessID;
        } while (Process32Next(snap, &pe));
    }
    CloseHandle(snap);
    return n;
}

static void PrintExePath(DWORD pid) {
    HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!h) return;
    char path[MAX_PATH * 2]{};
    DWORD sz = sizeof path;
    if (QueryFullProcessImageNameA(h, 0, path, &sz)) printf("      pid=%lu -> %s\n", (unsigned long)pid, path);
    CloseHandle(h);
}

// 返回模块句柄；snapDenied=true 表示模块快照被拒绝（无法区分加载与否），而非"不存在"
static HMODULE FindRemoteModule(DWORD pid, const char* dllname, bool* snapDenied = nullptr) {
    if (snapDenied) *snapDenied = false;
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
    if (snap == INVALID_HANDLE_VALUE) { if (snapDenied) *snapDenied = true; return nullptr; }
    MODULEENTRY32 me{}; me.dwSize = sizeof me;
    HMODULE h = nullptr;
    if (Module32First(snap, &me)) {
        do {
            if (_stricmp(me.szModule, dllname) == 0) { h = me.hModule; break; }
        } while (Module32Next(snap, &me));
    }
    CloseHandle(snap);
    return h;
}

// 远程 GetModuleHandleW 复核：1=存在，0=不存在，-1=无法验证
// （低 32 位语义：基址低 32 位非零 = 存在；GetModuleHandleW 返回 NULL = 不存在）
static int RemoteModulePresent(HANDLE h, const wchar_t* name) {
    size_t bytes = (wcslen(name) + 1) * sizeof(wchar_t);
    LPVOID remote = VirtualAllocEx(h, nullptr, bytes, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!remote) return -1;
    if (!WriteProcessMemory(h, remote, name, bytes, nullptr)) {
        VirtualFreeEx(h, remote, 0, MEM_RELEASE);
        return -1;
    }
    FARPROC pGetModuleHandleW = GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "GetModuleHandleW");
    HANDLE t = CreateRemoteThread(h, nullptr, 0, (LPTHREAD_START_ROUTINE)pGetModuleHandleW, remote, 0, nullptr);
    if (!t) { VirtualFreeEx(h, remote, 0, MEM_RELEASE); return -1; }
    DWORD w = WaitForSingleObject(t, 10000);
    if (w != WAIT_OBJECT_0) { CloseHandle(t); VirtualFreeEx(h, remote, 0, MEM_RELEASE); return -1; }
    DWORD code = 0;
    GetExitCodeThread(t, &code);
    CloseHandle(t);
    VirtualFreeEx(h, remote, 0, MEM_RELEASE);
    return code != 0 ? 1 : 0;
}

static bool BuildDefaultDllPath(char* out, size_t n) {
    char self[MAX_PATH];
    if (!GetModuleFileNameA(nullptr, self, MAX_PATH)) return false;
    char* slash = strrchr(self, '\\');
    if (slash) *slash = '\0';
    snprintf(out, n, "%s\\%s", self, DLL_NAME);
    return GetFullPathNameA(out, (DWORD)n, out, nullptr) != 0;
}

// 本地加载 DLL（不执行 DllMain）解析导出，返回"导出 RVA 偏移"用于远程地址换算
static bool ResolveExportOffset(const char* dllpath, const char* exportName, uintptr_t* rva) {
    HMODULE h = LoadLibraryExA(dllpath, nullptr, DONT_RESOLVE_DLL_REFERENCES);
    if (!h) return false;
    FARPROC p = GetProcAddress(h, exportName);
    if (p) *rva = (uintptr_t)p - (uintptr_t)h;
    FreeLibrary(h);
    return p != nullptr;
}

int main(int argc, char** argv) {
    printf("civinject v0.3 - CivLink M0-A trace DLL injector\n");
    const char* proc = nullptr;
    const char* dllarg = nullptr;
    bool unload = false;
    DWORD wantPid = 0;
    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "-x") && i + 1 < argc) proc = argv[++i];
        else if (!strcmp(argv[i], "-p") && i + 1 < argc) wantPid = (DWORD)strtoul(argv[++i], nullptr, 0);
        else if (!strcmp(argv[i], "-u")) unload = true;
        else dllarg = argv[i];
    }
    if (!proc) {
        printf("Usage:\n"
               "  civinject.exe -x <process.exe> [path\\to\\civtrace.dll]\n"
               "  civinject.exe -x <process.exe> -p <pid> [path\\to\\civtrace.dll]\n"
               "  civinject.exe -x <process.exe> -u [-p <pid>]\n");
        return 1;
    }

    EnableDebugPrivilege();

    DWORD pids[32];
    int np = FindPids(proc, pids, 32);
    if (!np) { printf("[!] process '%s' not found (launch the game first)\n", proc); return 1; }
    printf("[*] '%s' matched %d process(es):\n", proc, np);
    for (int i = 0; i < np; ++i) PrintExePath(pids[i]);

    DWORD pid;
    if (wantPid) {
        bool found = false;
        for (int i = 0; i < np; ++i) if (pids[i] == wantPid) { found = true; break; }
        if (!found) { printf("[!] -p %lu does not match any '%s' process\n", (unsigned long)wantPid, proc); return 1; }
        pid = wantPid;
    } else {
        pid = pids[0];
        if (np > 1)
            printf("[!] multiple processes matched; injecting into pid=%lu. "
                   "Close other instances or disambiguate with -p <pid>.\n", (unsigned long)pid);
    }

    char dllpath[MAX_PATH];
    if (dllarg) {
        snprintf(dllpath, sizeof dllpath, "%s", dllarg);
        char full[MAX_PATH];
        if (GetFullPathNameA(dllpath, MAX_PATH, full, nullptr)) snprintf(dllpath, sizeof dllpath, "%s", full);
    } else {
        if (!BuildDefaultDllPath(dllpath, sizeof dllpath)) {
            printf("[!] cannot resolve default dll path\n");
            return 1;
        }
    }

    if (unload) {
        printf("[*] unload: %s (pid=%lu)\n", dllpath, (unsigned long)pid);
        HANDLE h = OpenProcess(PROCESS_ALL_ACCESS, FALSE, pid);
        if (!h) {
            printf("[!] pid=%lu OpenProcess failed err=%lu\n", (unsigned long)pid, GetLastError());
            return 1;
        }
        bool denied = false;
        HMODULE m = FindRemoteModule(pid, DLL_NAME, &denied);
        if (!m && !denied) {
            printf("[+] pid=%lu civtrace.dll not loaded - nothing to unload\n", (unsigned long)pid);
            CloseHandle(h);
            return 0;
        }
        if (m) {
            // 1) 调用导出 CivTraceShutdown：先禁用全部 Hook 并等待 Hook 执行体退出
            uintptr_t rva = 0;
            if (ResolveExportOffset(dllpath, SHUTDOWN_EXPORT, &rva)) {
                uintptr_t remoteProc = (uintptr_t)m + rva;
                HANDLE t = CreateRemoteThread(h, nullptr, 0, (LPTHREAD_START_ROUTINE)remoteProc, nullptr, 0, nullptr);
                if (t) {
                    DWORD w = WaitForSingleObject(t, 15000);
                    if (w == WAIT_OBJECT_0) printf("[*] CivTraceShutdown executed (hooks disabled, log flushed)\n");
                    else printf("[!] CivTraceShutdown wait timeout (%lu) - proceeding with FreeLibrary\n", (unsigned long)w);
                    CloseHandle(t);
                } else {
                    printf("[!] remote CivTraceShutdown failed err=%lu - falling back to FreeLibrary\n", GetLastError());
                }
            } else {
                printf("[*] export CivTraceShutdown not resolvable (old dll?) - direct FreeLibrary\n");
            }
            // 2) FreeLibrary（LoadLibraryW 引用计数 = 1；多注 2 次）
            for (int i = 0; i < 2; ++i) {
                HANDLE t = CreateRemoteThread(h, nullptr, 0, (LPTHREAD_START_ROUTINE)FreeLibrary, (LPVOID)m, 0, nullptr);
                if (!t) { printf("[!] CreateRemoteThread(FreeLibrary) failed err=%lu\n", GetLastError()); break; }
                DWORD w = WaitForSingleObject(t, 15000);
                if (w != WAIT_OBJECT_0) { printf("[!] FreeLibrary wait timeout\n"); CloseHandle(t); break; }
                CloseHandle(t);
                Sleep(150);
            }
        }
        Sleep(300);
        bool denied2 = false;
        HMODULE left = FindRemoteModule(pid, DLL_NAME, &denied2);
        int present = left ? 1 : (denied2 ? RemoteModulePresent(h, L"civtrace.dll") : 0);
        if (present == 0)
            printf("[+] civtrace.dll unloaded from pid=%lu\n", (unsigned long)pid);
        else if (present == 1)
            printf("[!] pid=%lu module may still be loaded (refcount>1?); "
                   "closing the process is the reliable unload\n", (unsigned long)pid);
        else
            printf("[?] pid=%lu unload state cannot be verified - check the log file\n", (unsigned long)pid);
        CloseHandle(h);
        return present == 0 ? 0 : 2;
    }

    // ---- 注入 ----
    if (GetFileAttributesA(dllpath) == INVALID_FILE_ATTRIBUTES) {
        printf("[!] dll not found: %s\n", dllpath);
        return 1;
    }
    printf("[*] inject into pid=%lu: %s\n", (unsigned long)pid, dllpath);

    HANDLE h = OpenProcess(PROCESS_ALL_ACCESS, FALSE, pid);
    if (!h) {
        printf("[!] OpenProcess failed err=%lu (run as Administrator; check antivirus)\n", GetLastError());
        return 1;
    }

    // 架构检查：x64 DLL 只能进 x64 进程
    BOOL wow64 = FALSE;
    if (IsWow64Process(h, &wow64) && wow64) {
        printf("[!] target is a 32-bit (WOW64) process - civtrace.dll is x64 only\n");
        CloseHandle(h);
        return 1;
    }

    // 重复注入检测
    {
        bool denied = false;
        HMODULE have = FindRemoteModule(pid, DLL_NAME, &denied);
        int present = have ? 1 : (denied ? RemoteModulePresent(h, L"civtrace.dll") : 0);
        if (present == 1) {
            if (have)
                printf("[!] civtrace.dll already loaded @ %p - skip duplicate injection (use -u first)\n", (void*)have);
            else
                printf("[!] civtrace.dll already loaded (snapshot denied) - skip duplicate injection (use -u first)\n");
            CloseHandle(h);
            return 0;
        }
    }

    wchar_t wpath[MAX_PATH];
    MultiByteToWideChar(CP_ACP, 0, dllpath, -1, wpath, MAX_PATH);
    size_t bytes = (wcslen(wpath) + 1) * sizeof(wchar_t);

    LPVOID remote = VirtualAllocEx(h, nullptr, bytes, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!remote) { printf("[!] VirtualAllocEx failed err=%lu\n", GetLastError()); CloseHandle(h); return 1; }
    if (!WriteProcessMemory(h, remote, wpath, bytes, nullptr)) {
        printf("[!] WriteProcessMemory failed err=%lu\n", GetLastError());
        VirtualFreeEx(h, remote, 0, MEM_RELEASE);
        CloseHandle(h);
        return 1;
    }

    FARPROC pLoadLibraryW = GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "LoadLibraryW");
    HANDLE t = CreateRemoteThread(h, nullptr, 0, (LPTHREAD_START_ROUTINE)pLoadLibraryW, remote, 0, nullptr);
    if (!t) {
        printf("[!] CreateRemoteThread failed err=%lu (most likely antivirus - see README 1.4)\n", GetLastError());
        VirtualFreeEx(h, remote, 0, MEM_RELEASE);
        CloseHandle(h);
        return 1;
    }
    DWORD w = WaitForSingleObject(t, 15000);
    DWORD code = 0;
    if (w == WAIT_OBJECT_0) GetExitCodeThread(t, &code);
    CloseHandle(t);
    VirtualFreeEx(h, remote, 0, MEM_RELEASE);
    if (w != WAIT_OBJECT_0)
        printf("[!] LoadLibraryW remote thread did not exit within 15s (process may be hung or guarded)\n");

    Sleep(300);
    bool denied = false;
    HMODULE loaded = FindRemoteModule(pid, DLL_NAME, &denied);
    int present = loaded ? 1 : (denied ? RemoteModulePresent(h, L"civtrace.dll") : 0);
    if (present == 1)
        printf("[+] OK civtrace.dll loaded @ %p\n"
               "    log: %%LOCALAPPDATA%%\\CivLink\\M0A\\logs\\civtrace_*.log (150ms batch flush)\n",
               (void*)loaded);
    else if (present == 0)
        printf("[!] load FAILED (thread exit 0x%08X, remote verification found nothing) "
               "- check antivirus / admin / dll dependencies\n", code);
    else
        printf("[?] load verification unavailable - check the log file manually (thread exit 0x%08X)\n", code);
    CloseHandle(h);
    return present == 1 ? 0 : 2;
}
