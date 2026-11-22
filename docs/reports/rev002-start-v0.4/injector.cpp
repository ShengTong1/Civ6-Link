// civinject v0.4 —— CivLink M0-A 追踪 DLL 注入器
//
// 用法：
//   civinject.exe -x CivilizationVI.exe              注入（DLL 默认取本程序同目录 civtrace.dll）
//   civinject.exe -x CivilizationVI.exe C:\path\civtrace.dll
//   civinject.exe -x CivilizationVI.exe -u           卸载（先远程调 CivTraceShutdown，确认成功才 FreeLibrary）
//   civinject.exe -x CivilizationVI.exe -p 12345     指定 PID（多进程同名匹配时消歧）
//   civinject.exe -x CivilizationVI.exe -p 12345 -u
//
// 注入方式与 injciv6 相同：SeDebugPrivilege + CreateRemoteThread(LoadLibraryW)。
// 需要管理员权限运行（游戏非提权时通常也要求注入器提权以拿到 PROCESS_ALL_ACCESS）。
//
// 退出码：0=成功；1=用法/环境错误；2=验证失败或按契约中止（不做危险操作）。
//
// v0.3（对应 m00276 审查 3.5 注入器审计项）：
//   - 目标架构检查：IsWow64Process 拒绝 32 位目标（DLL 为 x64）
//   - 重复注入检测；远程线程等待超时（15s）；-p 消歧；多匹配打印完整映像路径
//
// v0.4（CIVLINK-M0A-REV-001 源码审计整改）：
//   - P0-3：模块发现改用 EnumProcessModulesEx + GetModuleInformation（64 位基址
//     与映像大小全精度）。删除 RemoteModulePresent（远程 GetModuleHandleW 线程
//     退出码只有低 32 位，基址低 32 位恰为 0 时会误判，不再作为任何判据）。
//   - P0-2：卸载契约强制化——必须远程调用 CivTraceShutdown 且确认返回 0/1
//     才 FreeLibrary；返回 2 / 超时 / 远程线程创建失败一律中止并保留现场。
//     CivTraceShutdown 返回 DWORD（0=成功/1=已 shutdown/2=部分失败），
//     远程线程退出码即该值（完整 32 位，可判定）。
//   - P0-4：远程地址解析加固——卸载前做本地/远程 PE 身份一致性校验
//     （SizeOfImage + TimeDateStamp + 'MZ'/'PE' 魔数），DLL 文件与目标内已加载
//     模块不一致时拒绝换算导出地址（防止远程 Proc 指向垃圾代码打崩目标）。
//   - 版本号/导出名/DLL 名改用共享头 civtrace_common.h（单一契约定义处）。
//
// 注意（x64）：LoadLibraryW 远程线程的退出码只是返回值的低 32 位，仅作诊断
// 打印，绝不当作模块句柄或成败判据 —— 成败一律以 EnumProcessModulesEx 全精度
// 枚举复核为准。

#define WIN32_LEAN_AND_MEAN
#define PSAPI_VERSION 2
#include <windows.h>
#include <psapi.h>
#include <tlhelp32.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>

#include "civtrace_common.h"

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

// ---------------------------------------------------------------------------
// 模块发现（REV-001 P0-3）：EnumProcessModulesEx 全精度。
// 返回 1=已加载（*out 有效：64 位基址 + 映像大小）；0=确认未加载；
//      -1=无法枚举（权限/内部错误），"加载与否"不可判定。
// ---------------------------------------------------------------------------
struct RemoteModuleInfo { uintptr_t base = 0; size_t size = 0; };

static int QueryRemoteModule(HANDLE hProc, const char* dllname, RemoteModuleInfo* out) {
    out->base = 0; out->size = 0;
    HMODULE mods[1024];
    DWORD needed = 0;
    if (!EnumProcessModulesEx(hProc, mods, sizeof mods, &needed, LIST_MODULES_64BIT)) return -1;
    DWORD count = needed / sizeof(HMODULE);
    if (count > 1024) count = 1024;
    for (DWORD i = 0; i < count; ++i) {
        char name[MAX_PATH]{};
        if (!GetModuleBaseNameA(hProc, mods[i], name, MAX_PATH)) continue;
        if (_stricmp(name, dllname) == 0) {
            MODULEINFO mi{};
            if (GetModuleInformation(hProc, mods[i], &mi, sizeof mi)) {
                out->base = (uintptr_t)mi.lpBaseOfDll;
                out->size = (size_t)mi.SizeOfImage;
            } else {
                out->base = (uintptr_t)mods[i];   // 大小未知，仍可用基址（有本地 PE 校验兜底）
                out->size = 0;
            }
            return 1;
        }
    }
    return 0;
}

// ---------------------------------------------------------------------------
// 本地 PE 身份解析（REV-001 P0-4）：
//   LoadLibraryExA(DONT_RESOLVE_DLL_REFERENCES) 只映射不执行 DllMain；
//   解析导出 RVA 与 OptionalHeader.SizeOfImage / TimeDateStamp。
//   远程地址 = 远程模块基址 + RVA（假设成立的前提：目标内模块与本文件
//   是同一个 PE —— 由 RemotePeIdentity 校验保证）。
// ---------------------------------------------------------------------------
struct LocalPeIdentity {
    uintptr_t exportRva  = 0;
    DWORD     sizeOfImage = 0;
    DWORD     timeStamp   = 0;
};

static bool ResolveLocalPe(const char* dllpath, const char* exportName, LocalPeIdentity* out) {
    HMODULE h = LoadLibraryExA(dllpath, nullptr, DONT_RESOLVE_DLL_REFERENCES);
    if (!h) return false;
    FARPROC p = GetProcAddress(h, exportName);
    if (p) out->exportRva = (uintptr_t)p - (uintptr_t)h;
    uintptr_t base = (uintptr_t)h;
    auto dos = (IMAGE_DOS_HEADER*)base;
    if (dos->e_magic == IMAGE_DOS_SIGNATURE) {
        auto nt = (IMAGE_NT_HEADERS64*)(base + dos->e_lfanew);
        if (nt->Signature == IMAGE_NT_SIGNATURE) {
            out->sizeOfImage = nt->OptionalHeader.SizeOfImage;
            out->timeStamp   = nt->FileHeader.TimeDateStamp;
        }
    }
    FreeLibrary(h);
    return p != nullptr;
}

// 远程 PE 身份一致性校验：读目标内模块头部，验 'MZ'/'PE' + SizeOfImage + TimeDateStamp
// 与本地 DLL 文件一致。不一致 → 远程基址上不是这个 DLL，禁止换算导出地址。
static bool RemotePeIdentity(HANDLE hProc, uintptr_t remoteBase, const LocalPeIdentity& pe) {
    if (pe.sizeOfImage == 0) return true;   // 本地解析失败时无法比对，由上层决定
    BYTE hdr[0x400];
    SIZE_T got = 0;
    if (!ReadProcessMemory(hProc, (LPCVOID)remoteBase, hdr, sizeof hdr, &got) || got < 0x200) return false;
    if (hdr[0] != 'M' || hdr[1] != 'Z') return false;
    LONG e_lfanew = *(LONG*)(hdr + 0x3C);
    if (e_lfanew <= 0 || (SIZE_T)e_lfanew + 0x100 > got) return false;
    BYTE* nt = hdr + e_lfanew;
    if (nt[0] != 'P' || nt[1] != 'E' || nt[2] != 0 || nt[3] != 0) return false;
    DWORD stamp = *(DWORD*)(nt + 4 + 4);                 // FileHeader.TimeDateStamp
    DWORD size  = *(DWORD*)(nt + 4 + 20 + 56);           // OptionalHeader.SizeOfImage
    return stamp == pe.timeStamp && size == pe.sizeOfImage;
}

static bool BuildDefaultDllPath(char* out, size_t n) {
    char self[MAX_PATH];
    if (!GetModuleFileNameA(nullptr, self, MAX_PATH)) return false;
    char* slash = strrchr(self, '\\');
    if (slash) *slash = '\0';
    snprintf(out, n, "%s\\%s", self, CIVTRACE_DLL_NAME_A);
    return GetFullPathNameA(out, (DWORD)n, out, nullptr) != 0;
}

// 远程调用 CivTraceShutdown 并取完整退出码（导出返回 DWORD）。
// 返回 0=确认 shutdown 完成；1=确认已 shutdown；-1=无法确认（任何失败）。
static int RemoteCallShutdown(HANDLE hProc, uintptr_t remoteProc) {
    HANDLE t = CreateRemoteThread(hProc, nullptr, 0, (LPTHREAD_START_ROUTINE)remoteProc, nullptr, 0, nullptr);
    if (!t) { printf("[!] CreateRemoteThread(CivTraceShutdown) failed err=%lu\n", GetLastError()); return -1; }
    DWORD w = WaitForSingleObject(t, 15000);
    if (w != WAIT_OBJECT_0) {
        printf("[!] CivTraceShutdown wait timeout/failed (w=%lu) - hooks may still be active\n", (unsigned long)w);
        CloseHandle(t);
        return -1;
    }
    DWORD code = 0;
    GetExitCodeThread(t, &code);
    CloseHandle(t);
    return code == 0 ? 0 : (code == 1 ? 1 : -1);
}

int main(int argc, char** argv) {
    printf("civinject v" CIVTRACE_VERSION " - CivLink M0-A trace DLL injector\n");
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
            printf("[!] multiple processes matched; operating on pid=%lu. "
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

    HANDLE h = OpenProcess(PROCESS_ALL_ACCESS, FALSE, pid);
    if (!h) {
        printf("[!] pid=%lu OpenProcess failed err=%lu (run as Administrator; check antivirus)\n",
               (unsigned long)pid, GetLastError());
        return 1;
    }

    // 架构检查：x64 DLL 只能进 x64 进程
    BOOL wow64 = FALSE;
    if (IsWow64Process(h, &wow64) && wow64) {
        printf("[!] target is a 32-bit (WOW64) process - civtrace.dll is x64 only\n");
        CloseHandle(h);
        return 1;
    }

    if (unload) {
        printf("[*] unload: %s (pid=%lu)\n", dllpath, (unsigned long)pid);
        RemoteModuleInfo mi;
        int q = QueryRemoteModule(h, CIVTRACE_DLL_NAME_A, &mi);
        if (q == 0) {
            printf("[+] pid=%lu %s not loaded - nothing to unload\n", (unsigned long)pid, CIVTRACE_DLL_NAME_A);
            CloseHandle(h);
            return 0;
        }
        if (q == -1) {
            printf("[!] pid=%lu module enumeration unavailable - cannot verify load state; "
                   "refusing to unload blindly (close the process to unload safely)\n", (unsigned long)pid);
            CloseHandle(h);
            return 2;
        }

        // 卸载契约（civtrace_common.h）：必须先远程 CivTraceShutdown 确认 0/1，
        // 才允许 FreeLibrary。任何一步无法确认 → 中止并保留现场。
        LocalPeIdentity pe;
        if (!ResolveLocalPe(dllpath, CIVTRACE_SHUTDOWN_EXPORT_A, &pe) || pe.exportRva == 0) {
            printf("[!] cannot resolve export %s from local file: %s\n", CIVTRACE_SHUTDOWN_EXPORT_A, dllpath);
            printf("    refusing FreeLibrary: without confirmed shutdown, unloading can crash the target\n");
            CloseHandle(h);
            return 2;
        }
        if (mi.size != 0 && pe.sizeOfImage != 0 && mi.size != pe.sizeOfImage) {
            printf("[!] identity mismatch: loaded module SizeOfImage=%zu != local PE SizeOfImage=%lu\n"
                   "    the file on disk is NOT the DLL inside the process - refusing to compute remote address\n",
                   mi.size, (unsigned long)pe.sizeOfImage);
            CloseHandle(h);
            return 2;
        }
        if (!RemotePeIdentity(h, mi.base, pe)) {
            printf("[!] remote PE header identity check FAILED (MZ/PE/SizeOfImage/TimeDateStamp) @ %p\n"
                   "    refusing to compute remote export address\n", (void*)mi.base);
            CloseHandle(h);
            return 2;
        }

        uintptr_t remoteProc = mi.base + pe.exportRva;
        printf("[*] CivTraceShutdown @ base=0x%llx + rva=0x%llx = 0x%llx\n",
               (unsigned long long)mi.base, (unsigned long long)pe.exportRva, (unsigned long long)remoteProc);
        int sc = RemoteCallShutdown(h, remoteProc);
        if (sc != 0 && sc != 1) {
            printf("[!] shutdown NOT confirmed (code=%d) - ABORT per unload contract; "
                   "NO FreeLibrary issued. Close the process to unload safely.\n", sc);
            CloseHandle(h);
            return 2;
        }
        printf("[+] CivTraceShutdown confirmed (code=%d) - hooks disabled, log flushed\n", sc);

        // 确认成功后才 FreeLibrary（LoadLibraryW 引用计数 = 1；重复注入时 2）
        for (int i = 0; i < 2 && sc == 0; ++i) {
            HANDLE t = CreateRemoteThread(h, nullptr, 0, (LPTHREAD_START_ROUTINE)FreeLibrary, (LPVOID)mi.base, 0, nullptr);
            if (!t) { printf("[!] CreateRemoteThread(FreeLibrary) failed err=%lu\n", GetLastError()); break; }
            DWORD w = WaitForSingleObject(t, 15000);
            if (w != WAIT_OBJECT_0) { printf("[!] FreeLibrary wait timeout\n"); CloseHandle(t); break; }
            CloseHandle(t);
            Sleep(150);
        }
        Sleep(300);
        RemoteModuleInfo left;
        int q2 = QueryRemoteModule(h, CIVTRACE_DLL_NAME_A, &left);
        if (q2 == 0) {
            printf("[+] %s unloaded from pid=%lu\n", CIVTRACE_DLL_NAME_A, (unsigned long)pid);
            CloseHandle(h);
            return 0;
        }
        if (q2 == 1)
            printf("[!] pid=%lu module may still be loaded (refcount>1?); "
                   "closing the process is the reliable unload\n", (unsigned long)pid);
        else
            printf("[?] pid=%lu unload state cannot be verified - check the log file\n", (unsigned long)pid);
        CloseHandle(h);
        return 2;
    }

    // ---- 注入 ----
    if (GetFileAttributesA(dllpath) == INVALID_FILE_ATTRIBUTES) {
        printf("[!] dll not found: %s\n", dllpath);
        CloseHandle(h);
        return 1;
    }
    printf("[*] inject into pid=%lu: %s\n", (unsigned long)pid, dllpath);

    // 重复注入检测（全精度枚举）
    {
        RemoteModuleInfo have;
        int q = QueryRemoteModule(h, CIVTRACE_DLL_NAME_A, &have);
        if (q == 1) {
            printf("[!] %s already loaded @ 0x%llx - skip duplicate injection (use -u first)\n",
                   CIVTRACE_DLL_NAME_A, (unsigned long long)have.base);
            CloseHandle(h);
            return 0;
        }
        // q==-1：无法枚举。继续注入是安全的（LoadLibraryW 重复加载只增加引用计数，
        // 不会二次执行 DllMain），但结果验证可能不可用。
        if (q == -1)
            printf("[?] module enumeration unavailable - proceeding; verification may be limited\n");
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
    RemoteModuleInfo loaded;
    int present = QueryRemoteModule(h, CIVTRACE_DLL_NAME_A, &loaded);
    if (present == 1) {
        // 附加身份信号：已加载模块映像大小应与本地 PE 一致（基址已是全精度，无需比对退出码）
        LocalPeIdentity pe;
        if (ResolveLocalPe(dllpath, CIVTRACE_SHUTDOWN_EXPORT_A, &pe) &&
            pe.sizeOfImage != 0 && loaded.size != 0 && loaded.size != pe.sizeOfImage)
            printf("[!] warning: loaded SizeOfImage=%zu != local %lu (unexpected file identity)\n",
                   loaded.size, (unsigned long)pe.sizeOfImage);
        printf("[+] OK %s loaded @ 0x%llx (size=%zu)\n"
               "    log: %%LOCALAPPDATA%%\\CivLink\\M0A\\logs\\civtrace_*.log (150ms batch flush)\n",
               CIVTRACE_DLL_NAME_A, (unsigned long long)loaded.base, loaded.size);
        CloseHandle(h);
        return 0;
    }
    if (present == 0)
        printf("[!] load FAILED (thread exit 0x%08X, remote verification found nothing) "
               "- check antivirus / admin / dll dependencies\n", code);
    else
        printf("[?] load verification unavailable - check the log file manually (thread exit 0x%08X)\n", code);
    CloseHandle(h);
    return 2;
}
