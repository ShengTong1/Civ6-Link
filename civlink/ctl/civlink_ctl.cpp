// civlink_ctl.cpp - CivLink F1 controller: inject / status / counters / shutdown
//
// Deliberately small and boring. Every remote call is validated the same way
// injector does it (REV-001/REV-002 lessons carried over):
//   * resolve the export RVA from a DONT_RESOLVE_DLL_REFERENCES mapping of the local DLL,
//   * confirm the module loaded in the target has the same PE identity (SizeOfImage +
//     TimeDateStamp + 'MZ'/'PE'), and refuse to compute a remote address if it differs,
//   * check GetExitCodeThread's BOOL return, never assume 0 on failure,
//   * on shutdown, do NOT FreeLibrary: the Hook DLL stays mapped by design (B2 audit-run
//     mode) so trampolines remain valid for threads already inside a detour.
//
// Usage:
//   civlink_ctl.exe inject   -x <process.exe> [-p <pid>] [-d <dll path>] [-w <seconds>]
//   civlink_ctl.exe inject-client -x <process.exe> [-p <pid>] [-d <dll path>] [-w <seconds>]
//                               [--iface <IP|ALL>] [-m <dll name>]
//   civlink_ctl.exe status   -x <process.exe> [-p <pid>]
//   civlink_ctl.exe counters -x <process.exe> [-p <pid>]
//   civlink_ctl.exe shutdown -x <process.exe> [-p <pid>]
//
// inject-client (M0-C C2): writes %LOCALAPPDATA%\CivLink\client-iface.txt (ALL or a local
// IPv4 address; the address is validated against the live up interfaces, fail-closed
// exit 1), then injects civlink_client.dll, which pins the discovery broadcasts to that
// NIC via IP_UNICAST_IF.  -m overrides the module name queried/injected for every
// command (default civlink_hook.dll).
//
// Exit codes: 0 ok / 1 usage or precondition failure / 2 target not found or ambiguous /
//             3 module not loaded / 4 remote call failed / 5 state not reached in time.
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <psapi.h>
#include <tlhelp32.h>
#include <iphlpapi.h>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "civlink_hook.h"
#include "civlink_client.h"

#pragma comment(lib, "psapi.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "iphlpapi.lib")

static std::vector<DWORD> g_matches;

// Module name targeted by QueryRemoteModule / injection. Defaults to the F1 hook DLL;
// inject-client and -m override it.
static const char* g_dllName = CIVLINK_HOOK_DLL_NAME_A;

static int EnableDebugPrivilege()
{
    HANDLE tok = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &tok)) {
        printf("[!] OpenProcessToken failed err=%lu\n", GetLastError());
        return -1;
    }
    LUID luid{};
    if (!LookupPrivilegeValueA(nullptr, "SeDebugPrivilege", &luid)) {
        printf("[!] LookupPrivilegeValue(SeDebugPrivilege) failed err=%lu\n", GetLastError());
        CloseHandle(tok);
        return -1;
    }
    TOKEN_PRIVILEGES tp{};
    tp.PrivilegeCount = 1;
    tp.Privileges[0].Luid = luid;
    tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
    const BOOL ok = AdjustTokenPrivileges(tok, FALSE, &tp, sizeof tp, nullptr, nullptr);
    const DWORD e = GetLastError();
    CloseHandle(tok);
    if (!ok) { printf("[!] AdjustTokenPrivileges failed err=%lu\n", e); return -1; }
    if (e == ERROR_NOT_ALL_ASSIGNED) {
        printf("[!] SeDebugPrivilege not granted - run elevated if the target is elevated\n");
        return 1;
    }
    return 0;
}

static int FindPids(const char* name, std::vector<DWORD>& out)
{
    const HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return -1;
    PROCESSENTRY32 pe{};
    pe.dwSize = sizeof pe;
    if (Process32First(snap, &pe)) {
        do {
            if (_stricmp(pe.szExeFile, name) == 0) out.push_back(pe.th32ProcessID);
        } while (Process32Next(snap, &pe));
    }
    CloseHandle(snap);
    return (int)out.size();
}

static void PrintExePath(DWORD pid)
{
    const HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!h) { printf("      pid=%lu -> (OpenProcess failed err=%lu)\n", (unsigned long)pid, GetLastError()); return; }
    char path[MAX_PATH * 2]{};
    DWORD sz = sizeof path;
    if (QueryFullProcessImageNameA(h, 0, path, &sz)) printf("      pid=%lu -> %s\n", (unsigned long)pid, path);
    else printf("      pid=%lu -> (QueryFullProcessImageName failed err=%lu)\n", (unsigned long)pid, GetLastError());
    CloseHandle(h);
}

struct RemoteModuleInfo { uintptr_t base = 0; size_t size = 0; };

// 1 = loaded, 0 = confirmed not loaded, -1 = cannot determine (never disguises -1 as 0).
static int QueryRemoteModule(HANDLE hProc, const char* dllname, RemoteModuleInfo* out)
{
    out->base = 0; out->size = 0;
    std::vector<HMODULE> mods(1024);
    DWORD needed = 0;
    for (int attempt = 0; attempt < 6; ++attempt) {
        const DWORD cb = (DWORD)(mods.size() * sizeof(HMODULE));
        if (!EnumProcessModulesEx(hProc, mods.data(), cb, &needed, LIST_MODULES_64BIT)) return -1;
        const DWORD count = needed / sizeof(HMODULE);
        if (count <= mods.size()) {
            for (DWORD i = 0; i < count; ++i) {
                char name[MAX_PATH]{};
                if (!GetModuleBaseNameA(hProc, mods[i], name, MAX_PATH)) continue;
                if (_stricmp(name, dllname) == 0) {
                    MODULEINFO mi{};
                    if (GetModuleInformation(hProc, mods[i], &mi, sizeof mi)) {
                        out->base = (uintptr_t)mi.lpBaseOfDll;
                        out->size = (size_t)mi.SizeOfImage;
                    } else {
                        out->base = (uintptr_t)mods[i];
                        out->size = 0;
                    }
                    return 1;
                }
            }
            return 0;
        }
        mods.resize((size_t)count + 4096 / sizeof(HMODULE));
    }
    return -1;
}

struct LocalPeIdentity {
    uintptr_t exportRva = 0;
    DWORD     sizeOfImage = 0;
    DWORD     timeStamp = 0;
};

static bool ResolveLocalPe(const char* dllpath, const char* exportName, LocalPeIdentity* out)
{
    HMODULE h = LoadLibraryExA(dllpath, nullptr, DONT_RESOLVE_DLL_REFERENCES);
    if (!h) return false;
    FARPROC p = GetProcAddress(h, exportName);
    if (p) out->exportRva = (uintptr_t)p - (uintptr_t)h;
    const uintptr_t base = (uintptr_t)h;
    const auto dos = (IMAGE_DOS_HEADER*)base;
    if (dos->e_magic == IMAGE_DOS_SIGNATURE) {
        const auto nt = (IMAGE_NT_HEADERS64*)(base + dos->e_lfanew);
        if (nt->Signature == IMAGE_NT_SIGNATURE) {
            out->sizeOfImage = nt->OptionalHeader.SizeOfImage;
            out->timeStamp = nt->FileHeader.TimeDateStamp;
        }
    }
    FreeLibrary(h);
    return p != nullptr;
}

static bool RemotePeIdentity(HANDLE hProc, uintptr_t remoteBase, const LocalPeIdentity& pe)
{
    if (pe.sizeOfImage == 0) return true;
    BYTE hdr[0x400]{};
    SIZE_T got = 0;
    if (!ReadProcessMemory(hProc, (LPCVOID)remoteBase, hdr, sizeof hdr, &got) || got < 0x200) return false;
    if (hdr[0] != 'M' || hdr[1] != 'Z') return false;
    const LONG e_lfanew = *(LONG*)(hdr + 0x3C);
    if (e_lfanew <= 0 || (SIZE_T)e_lfanew + 0x100 > got) return false;
    const BYTE* nt = hdr + e_lfanew;
    if (nt[0] != 'P' || nt[1] != 'E' || nt[2] != 0 || nt[3] != 0) return false;
    const DWORD stamp = *(DWORD*)(nt + 4 + 4);
    const DWORD size = *(DWORD*)(nt + 4 + 20 + 56);
    return stamp == pe.timeStamp && size == pe.sizeOfImage;
}

static bool BuildDefaultDllPath(char* out, size_t n)
{
    char self[MAX_PATH]{};
    if (!GetModuleFileNameA(nullptr, self, MAX_PATH)) return false;
    char* slash = strrchr(self, '\\');
    if (slash) *slash = '\0';
    snprintf(out, n, "%s\\%s", self, g_dllName);
    return GetFullPathNameA(out, (DWORD)n, out, nullptr) != 0;
}

// M0-C C2: describes a local IPv4 interface so the operator can see WHAT was chosen.
// Audit H-4: the loopback pseudo interface is rejected - pinning the discovery broadcast to
// 127.0.0.1 is never a real deployment, only a look-alike that made earlier "pinned" evidence
// meaningless.
struct IfaceInfo {
    bool     found = false;
    unsigned ifIndex = 0;
    unsigned ifType = 0;
    unsigned metric = 0;
    char     friendly[128]{};
    char     text[256]{};       // one-line summary for printing
    bool     isLoopback = false;
};

// Resolves `ip` to a live local IPv4 adapter. Fail-closed: unknown/foreign/down -> not found.
static IfaceInfo ResolveIface(const char* ip)
{
    IfaceInfo info;
    IN_ADDR want{};
    if (inet_pton(AF_INET, ip, &want) != 1) return info;

    ULONG size = 15 * 1024;
    PIP_ADAPTER_ADDRESSES aa = nullptr;
    for (int attempt = 0; attempt < 3; attempt++) {
        aa = (PIP_ADAPTER_ADDRESSES)malloc(size);
        if (!aa) return info;
        const DWORD rc = GetAdaptersAddresses(AF_INET, 0, nullptr, aa, &size);
        if (rc == ERROR_BUFFER_OVERFLOW) { free(aa); aa = nullptr; continue; }
        if (rc != NO_ERROR) { free(aa); return info; }
        break;
    }
    if (!aa) return info;

    for (PIP_ADAPTER_ADDRESSES a = aa; a && !info.found; a = a->Next) {
        if (a->OperStatus != IfOperStatusUp) continue;
        for (PIP_ADAPTER_UNICAST_ADDRESS u = a->FirstUnicastAddress; u && !info.found; u = u->Next) {
            if (u->Address.lpSockaddr->sa_family != AF_INET) continue;
            const sockaddr_in* sin = (const sockaddr_in*)u->Address.lpSockaddr;
            if (sin->sin_addr.S_un.S_addr != want.S_un.S_addr) continue;
            info.found = true;
            info.ifIndex = a->IfIndex;
            info.ifType = a->IfType;
            info.metric = a->Ipv4Metric;
            info.isLoopback = (a->IfType == IF_TYPE_SOFTWARE_LOOPBACK);
            WideCharToMultiByte(CP_ACP, 0, a->FriendlyName, -1, info.friendly,
                                (int)sizeof info.friendly, nullptr, nullptr);
            snprintf(info.text, sizeof info.text,
                     "%s (IfIndex=%lu IfType=%lu metric=%lu)", info.friendly,
                     (unsigned long)info.ifIndex, (unsigned long)info.ifType,
                     (unsigned long)info.metric);
        }
    }
    free(aa);
    return info;
}

// Prints where the config actually goes and who decided the path (audit H-3).
static void PrintConfigPathResolution(const char* path, bool fromEnv)
{
    printf("[*] client iface config path: %s\n", path);
    printf("[*] resolved by: %s\n", fromEnv ? "env override (CIVLINK_CLIENT_IFACE_FILE)"
                                            : "default (%LOCALAPPDATA%\\CivLink)");
    printf("[*] note: the DLL reads this from the GAME process environment, so an env override\n"
           "    set in this shell does NOT reach an injected game - use the default path there\n");
}

// M0-C C2: writes the client-iface config with a single ASCII line (ALL or the validated
// IPv4). Path = CIVLINK_CLIENT_IFACE_FILE (absolute override) else
// %LOCALAPPDATA%\CivLink\client-iface.txt. Creates the CivLink directory if needed.
// Returns 0 on success, -1 on failure.
static int WriteClientIfaceConfig(const char* iface)
{
    std::string path;
    char buf[MAX_PATH]{};
    bool fromEnv = false;
    const UINT o = GetEnvironmentVariableA("CIVLINK_CLIENT_IFACE_FILE", buf, sizeof buf);
    if (o > 0 && o < sizeof buf) {
        path.assign(buf); // explicit override: the DLL reads the same variable
        fromEnv = true;
    } else {
        const UINT n = GetEnvironmentVariableA("LOCALAPPDATA", buf, sizeof buf);
        if (n == 0 || n >= sizeof buf) {
            printf("[!] LOCALAPPDATA not available - cannot write the client-iface config\n");
            return -1;
        }
        std::string dir(buf);
        dir += "\\CivLink";
        CreateDirectoryA(dir.c_str(), nullptr); // ok if it already exists
        path = dir + "\\client-iface.txt";
    }
    PrintConfigPathResolution(path.c_str(), fromEnv);
    FILE* f = nullptr;
    if (fopen_s(&f, path.c_str(), "w") != 0 || !f) {
        printf("[!] cannot write %s (errno=%d lastError=%lu)\n", path.c_str(), errno,
               (unsigned long)GetLastError());
        return -1;
    }
    fprintf(f, "%s\n", iface);
    fclose(f);
    printf("[+] client iface config written: %s -> %s\n", iface, path.c_str());
    return 0;
}

// Runs an exported no-arg function remotely and returns its exit code (the function's int
// return value arrives as the thread exit code). Returns false when it cannot be confirmed.
static bool RemoteCallInt(HANDLE hProc, uintptr_t proc, DWORD* codeOut)
{
    const HANDLE t = CreateRemoteThread(hProc, nullptr, 0, (LPTHREAD_START_ROUTINE)proc, nullptr, 0, nullptr);
    if (!t) { printf("[!] CreateRemoteThread failed err=%lu\n", GetLastError()); return false; }
    const DWORD w = WaitForSingleObject(t, 15000);
    if (w != WAIT_OBJECT_0) {
        printf("[!] remote call wait failed (w=%lu)\n", (unsigned long)w);
        CloseHandle(t);
        return false;
    }
    DWORD code = 0;
    if (!GetExitCodeThread(t, &code)) {
        printf("[!] GetExitCodeThread failed err=%lu - result NOT read\n", GetLastError());
        CloseHandle(t);
        return false;
    }
    CloseHandle(t);
    *codeOut = code;
    return true;
}

static DWORD ResolveTarget(int argc, char** argv, const char* exeArg, DWORD wantPid)
{
    if (wantPid) return wantPid;
    if (!exeArg) return 0;
    g_matches.clear();
    const int n = FindPids(exeArg, g_matches);
    if (n <= 0) return 0;
    if (n > 1) {
        printf("[!] %d processes named '%s' - pass -p <pid>:\n", n, exeArg);
        for (DWORD pid : g_matches) PrintExePath(pid);
        return 0;
    }
    return g_matches[0];
}

int main(int argc, char** argv)
{
    printf("civlink_ctl v%s - CivLink F1 discovery hook controller\n", CIVLINK_HOOK_VERSION);
    if (argc < 2) {
        printf("Usage:\n"
               "  civlink_ctl.exe inject        -x <process.exe> [-p <pid>] [-d <dll>] [-w <sec>] [-m <name>]\n"
               "  civlink_ctl.exe inject-client -x <process.exe> [-p <pid>] [-d <dll>] [-w <sec>]\n"
               "                                  [--iface <IP|ALL>] [-m <name>]\n"
               "  civlink_ctl.exe status        -x <process.exe> [-p <pid>] [-m <name>]\n"
               "  civlink_ctl.exe counters      -x <process.exe> [-p <pid>] [-m <name>]\n"
               "  civlink_ctl.exe shutdown      -x <process.exe> [-p <pid>] [-m <name>]\n");
        return 1;
    }
    const char* cmd = argv[1];
    const char* exeArg = nullptr;
    const char* dllArg = nullptr;
    const char* ifaceArg = nullptr; // inject-client: ALL or a local IPv4
    DWORD wantPid = 0;
    int waitSec = 5;
    bool dllNameExplicit = false; // -m was given

    for (int i = 2; i < argc; i++) {
        if (!strcmp(argv[i], "-x") && i + 1 < argc) exeArg = argv[++i];
        else if (!strcmp(argv[i], "-p") && i + 1 < argc) wantPid = (DWORD)strtoul(argv[++i], nullptr, 0);
        else if (!strcmp(argv[i], "-d") && i + 1 < argc) dllArg = argv[++i];
        else if (!strcmp(argv[i], "-w") && i + 1 < argc) waitSec = (int)strtol(argv[++i], nullptr, 0);
        else if (!strcmp(argv[i], "-m") && i + 1 < argc) { g_dllName = argv[++i]; dllNameExplicit = true; }
        else if (!strcmp(argv[i], "--iface") && i + 1 < argc) ifaceArg = argv[++i];
    }

    // inject-client defaults its module to civlink_client.dll unless -m was given.
    if (!strcmp(cmd, "inject-client") && !dllNameExplicit) g_dllName = CIVLINK_CLIENT_DLL_NAME_A;

    // M0-C C2: validate the NIC before touching anything. ALL is always accepted; an explicit
    // IP must be a live local interface (fail-closed exit 1) so the DLL never silently gets a
    // config it will degrade away (initError 12). Audit H-4: loopback is refused outright -
    // it is not a deployment target and it made earlier "pinned" evidence look meaningful
    // when it was not.
    const char* ifaceChosen = nullptr;
    if (!strcmp(cmd, "inject-client")) {
        if (!ifaceArg) ifaceArg = "ALL";
        if (_stricmp(ifaceArg, "ALL") != 0) {
            const IfaceInfo info = ResolveIface(ifaceArg);
            if (!info.found) {
                printf("[!] --iface '%s' is not a live local IPv4 interface - refusing\n", ifaceArg);
                return 1;
            }
            if (info.isLoopback) {
                printf("[!] --iface '%s' resolves to the loopback pseudo interface (%s) - refusing\n",
                       ifaceArg, info.text);
                printf("    loopback is not a real egress choice; use ALL or a physical/virtual NIC\n");
                return 1;
            }
            printf("[+] interface selected: %s\n", info.text);
        } else {
            printf("[+] interface selected: ALL (no pinning, let the routing table decide)\n");
        }
        ifaceChosen = ifaceArg;
    }

    const DWORD pid = ResolveTarget(argc, argv, exeArg, wantPid);
    if (!pid) { printf("[!] target process not found (or ambiguous)\n"); return 2; }
    printf("[*] target pid=%lu\n", (unsigned long)pid);
    PrintExePath(pid);

    // Audit H-3/H-4 ordering fix: the config is written only after the target is resolved
    // and validated, so a failed injection never leaves a stale iface choice behind that a
    // later run would silently inherit.
    if (ifaceChosen) {
        if (WriteClientIfaceConfig(ifaceChosen) != 0) return 1;
    }

    EnableDebugPrivilege();

    HANDLE hProc = OpenProcess(PROCESS_CREATE_THREAD | PROCESS_QUERY_INFORMATION | PROCESS_VM_OPERATION |
                               PROCESS_VM_WRITE | PROCESS_VM_READ, FALSE, pid);
    if (!hProc) { printf("[!] OpenProcess failed err=%lu\n", GetLastError()); return 2; }

    // Auto-detect which CivLink module the target actually has loaded when the caller did
    // not pass -m. Without this, `status`/`counters` on a client-injected process resolved
    // the export RVAs from the local civlink_hook.dll, failed with "cannot resolve
    // CivLinkHookState", and exited 1 - which reads like "injection failed" to a user.
    if (!dllNameExplicit && strcmp(cmd, "inject") && strcmp(cmd, "inject-client")) {
        RemoteModuleInfo probe{};
        if (QueryRemoteModule(hProc, CIVLINK_HOOK_DLL_NAME_A, &probe) != 1) {
            if (QueryRemoteModule(hProc, CIVLINK_CLIENT_DLL_NAME_A, &probe) == 1) {
                g_dllName = CIVLINK_CLIENT_DLL_NAME_A;
                printf("[*] target has %s loaded - using it (override with -m)\n", g_dllName);
            }
        }
    }

    char dllpath[MAX_PATH]{};
    if (dllArg) {
        if (!GetFullPathNameA(dllArg, MAX_PATH, dllpath, nullptr)) {
            printf("[!] cannot resolve dll path '%s'\n", dllArg);
            CloseHandle(hProc);
            return 1;
        }
    } else if (!BuildDefaultDllPath(dllpath, sizeof dllpath)) {
        printf("[!] cannot resolve the default dll path (keep civlink_ctl.exe next to civlink_hook.dll)\n");
        CloseHandle(hProc);
        return 1;
    }

    if (!strcmp(cmd, "inject") || !strcmp(cmd, "inject-client")) {
        if (GetFileAttributesA(dllpath) == INVALID_FILE_ATTRIBUTES) {
            printf("[!] dll not found: %s\n", dllpath);
            CloseHandle(hProc);
            return 1;
        }

        // Architecture check: this DLL is x64 only. Fail closed if undeterminable.
        BOOL wow = FALSE;
        if (!IsWow64Process(hProc, &wow)) {
            printf("[!] IsWow64Process failed err=%lu - architecture undeterminable, refusing\n", GetLastError());
            CloseHandle(hProc);
            return 1;
        }
        if (wow) {
            printf("[!] target is a 32-bit (WOW64) process - %s is x64 only\n", g_dllName);
            CloseHandle(hProc);
            return 1;
        }

        RemoteModuleInfo mi{};
        const int q = QueryRemoteModule(hProc, g_dllName, &mi);
        if (q == 1) {
            printf("[*] %s already loaded at 0x%llx - not injecting twice\n",
                   g_dllName, (unsigned long long)mi.base);
            // A prior `shutdown` leaves the module MAPPED (B2 audit-run mode) but with
            // hooks disabled and g_state=-1. A second inject-client (e.g. after the
            // operator switched NICs) must re-activate it in place: re-read
            // client-iface.txt, re-enable the already-created hooks, reset state=1.
            // Only inject-client does this - the host hook.dll has no such export.
            if (!strcmp(cmd, "inject-client")) {
                LocalPeIdentity rpe{};
                if (!ResolveLocalPe(dllpath, "CivLinkReactivate", &rpe)) {
                    printf("[!] loaded %s has no CivLinkReactivate export - cannot re-activate\n"
                           "    (is the game running an OLD client DLL? restart the game to load the new one)\n",
                           g_dllName);
                } else if (!RemotePeIdentity(hProc, mi.base, rpe)) {
                    printf("[!] remote %s differs from the local DLL - refusing to re-activate\n",
                           g_dllName);
                } else {
                    DWORD rc = 0;
                    if (!RemoteCallInt(hProc, mi.base + rpe.exportRva, &rc)) {
                        printf("[!] CivLinkReactivate remote call failed\n");
                    } else {
                        const int r = (int)rc;
                        if (r == 0)
                            printf("[+] CivLinkReactivate: hooks re-enabled, client-iface.txt re-read\n");
                        else if (r == 1)
                            printf("[*] CivLinkReactivate: already running (no re-activation needed)\n");
                        else
                            printf("[!] CivLinkReactivate returned %d\n", r);
                    }
                }
            }
        } else if (q < 0) {
            printf("[!] cannot enumerate remote modules - refusing to inject blindly\n");
            CloseHandle(hProc);
            return 1;
        } else {
            const SIZE_T bytes = (strlen(dllpath) + 1) * sizeof(char);
            void* remote = VirtualAllocEx(hProc, nullptr, bytes, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
            if (!remote) { printf("[!] VirtualAllocEx failed err=%lu\n", GetLastError()); CloseHandle(hProc); return 1; }
            if (!WriteProcessMemory(hProc, remote, dllpath, bytes, nullptr)) {
                printf("[!] WriteProcessMemory failed err=%lu\n", GetLastError());
                VirtualFreeEx(hProc, remote, 0, MEM_RELEASE);
                CloseHandle(hProc);
                return 1;
            }
            const HMODULE k32 = GetModuleHandleA("kernel32.dll");
            const FARPROC loadLib = GetProcAddress(k32, "LoadLibraryW");
            const size_t wlen = strlen(dllpath) + 1;
            std::vector<wchar_t> wide(wlen);
            MultiByteToWideChar(CP_ACP, 0, dllpath, -1, wide.data(), (int)wlen);
            const SIZE_T wbytes = wlen * sizeof(wchar_t);
            void* remoteW = VirtualAllocEx(hProc, nullptr, wbytes, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
            if (!remoteW || !WriteProcessMemory(hProc, remoteW, wide.data(), wbytes, nullptr)) {
                printf("[!] staging the wide path failed err=%lu\n", GetLastError());
                if (remoteW) VirtualFreeEx(hProc, remoteW, 0, MEM_RELEASE);
                VirtualFreeEx(hProc, remote, 0, MEM_RELEASE);
                CloseHandle(hProc);
                return 1;
            }

            const HANDLE t = CreateRemoteThread(hProc, nullptr, 0, (LPTHREAD_START_ROUTINE)loadLib,
                                                remoteW, 0, nullptr);
            if (!t) {
                printf("[!] CreateRemoteThread(LoadLibraryW) failed err=%lu\n", GetLastError());
                VirtualFreeEx(hProc, remoteW, 0, MEM_RELEASE);
                VirtualFreeEx(hProc, remote, 0, MEM_RELEASE);
                CloseHandle(hProc);
                return 1;
            }
            const DWORD w = WaitForSingleObject(t, 15000);
            DWORD code = 0;
            bool got = false;
            if (w == WAIT_OBJECT_0 && GetExitCodeThread(t, &code)) got = true;
            CloseHandle(t);
            VirtualFreeEx(hProc, remoteW, 0, MEM_RELEASE);
            VirtualFreeEx(hProc, remote, 0, MEM_RELEASE);
            if (!got) {
                printf("[!] LoadLibraryW did not complete in time - remote module state unknown\n");
                CloseHandle(hProc);
                return 4;
            }
            printf("[+] LoadLibraryW returned 0x%lx\n", (unsigned long)code);
        }

        // Wait for the init thread to report running.
        LocalPeIdentity pe{};
        if (!ResolveLocalPe(dllpath, "CivLinkHookState", &pe)) {
            printf("[!] cannot resolve CivLinkHookState in %s\n", dllpath);
            CloseHandle(hProc);
            return 1;
        }
        RemoteModuleInfo after{};
        if (QueryRemoteModule(hProc, g_dllName, &after) != 1) {
            printf("[!] module not visible after LoadLibraryW - cannot verify identity\n");
            CloseHandle(hProc);
            return 3;
        }
        if (!RemotePeIdentity(hProc, after.base, pe)) {
            printf("[!] remote module PE identity differs from %s - refusing remote calls\n", dllpath);
            CloseHandle(hProc);
            return 3;
        }
        const uintptr_t stateFn = after.base + pe.exportRva;
        for (int i = 0; i < waitSec * 10; i++) {
            DWORD st = 0;
            if (RemoteCallInt(hProc, stateFn, &st) && st == 1) {
                // Print the module base as the module base. Session ids come from
                // `counters` (CivLinkGetCounters); the old version printed
                // after.base under a "session=" label, which put a base address
                // into an evidence field the Agent reports as session=.
                printf("[+] hooks active (CivLinkHookState=1)\n");
                printf("    dll base   : 0x%llx\n", (unsigned long long)after.base);
                printf("    session id : see 'civlink_ctl.exe counters' (CivLinkGetCounters)\n");
                CloseHandle(hProc);
                return 0;
            }
            Sleep(100);
        }
        printf("[!] hooks not active within %d s - run 'counters' for initError\n", waitSec);
        CloseHandle(hProc);
        return 5;
    }

    // Shared resolution for status / counters / shutdown.
    LocalPeIdentity pe{};
    const char* exportName = !strcmp(cmd, "shutdown") ? "CivLinkShutdown" : "CivLinkHookState";
    if (!ResolveLocalPe(dllpath, exportName, &pe)) {
        printf("[!] cannot resolve %s in %s\n", exportName, dllpath);
        CloseHandle(hProc);
        return 1;
    }
    RemoteModuleInfo mi{};
    const int q = QueryRemoteModule(hProc, g_dllName, &mi);
    if (q != 1) {
        printf("[!] %s is not loaded (q=%d)\n", g_dllName, q);
        CloseHandle(hProc);
        return 3;
    }
    if (!RemotePeIdentity(hProc, mi.base, pe)) {
        printf("[!] remote module PE identity differs from %s - refusing remote calls\n", dllpath);
        CloseHandle(hProc);
        return 3;
    }

    if (!strcmp(cmd, "status")) {
        DWORD st = 0;
        if (!RemoteCallInt(hProc, mi.base + pe.exportRva, &st)) { CloseHandle(hProc); return 4; }
        // CivLinkHookState returns int (1 running / 0 init / -1 shut down), but
        // RemoteCallInt gives us the thread exit code as an unsigned DWORD, so a
        // shut-down hook arrives as 0xFFFFFFFF. Cast back to int before deciding,
        // otherwise the caller sees "4294967295 (shut down)" instead of "-1".
        const int state = (int)st;
        printf("hook state : %d (%s)\n", state,
               state == 1 ? "running" : (state == 0 ? "initialising/failed" : "shut down"));
        CloseHandle(hProc);
        return state == 1 ? 0 : 1;
    }

    if (!strcmp(cmd, "shutdown")) {
        DWORD code = 0;
        if (!RemoteCallInt(hProc, mi.base + pe.exportRva, &code)) { CloseHandle(hProc); return 4; }
        printf("CivLinkShutdown returned %lu (%s)\n", (unsigned long)code,
               code == 0 ? "clean drain" : (code == 1 ? "already shut down" : "in-flight calls remained"));
        printf("[*] module intentionally LEFT MAPPED until target exit (B2 audit-run mode)\n");
        CloseHandle(hProc);
        return code <= 1 ? 0 : 4;
    }

    // counters: call the exported writer with a remote buffer, then read it back.
    LocalPeIdentity cpe{};
    if (!ResolveLocalPe(dllpath, "CivLinkGetCounters", &cpe)) {
        printf("[!] cannot resolve CivLinkGetCounters\n");
        CloseHandle(hProc);
        return 1;
    }
    void* remoteBuf = VirtualAllocEx(hProc, nullptr, sizeof(CivLinkCounters),
                                     MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!remoteBuf) { printf("[!] VirtualAllocEx failed err=%lu\n", GetLastError()); CloseHandle(hProc); return 1; }

    const HANDLE t = CreateRemoteThread(hProc, nullptr, 0,
                                        (LPTHREAD_START_ROUTINE)(mi.base + cpe.exportRva),
                                        remoteBuf, 0, nullptr);
    if (!t) {
        printf("[!] CreateRemoteThread(CivLinkGetCounters) failed err=%lu\n", GetLastError());
        VirtualFreeEx(hProc, remoteBuf, 0, MEM_RELEASE);
        CloseHandle(hProc);
        return 4;
    }
    const DWORD w = WaitForSingleObject(t, 10000);
    CloseHandle(t);
    if (w != WAIT_OBJECT_0) {
        printf("[!] counters call did not complete\n");
        VirtualFreeEx(hProc, remoteBuf, 0, MEM_RELEASE);
        CloseHandle(hProc);
        return 4;
    }
    CivLinkCounters c{};
    if (!ReadProcessMemory(hProc, remoteBuf, &c, sizeof c, nullptr)) {
        printf("[!] ReadProcessMemory(counters) failed err=%lu\n", GetLastError());
        VirtualFreeEx(hProc, remoteBuf, 0, MEM_RELEASE);
        CloseHandle(hProc);
        return 4;
    }
    VirtualFreeEx(hProc, remoteBuf, 0, MEM_RELEASE);
    CloseHandle(hProc);

    if (c.magic != CIVLINK_COUNTERS_MAGIC) {
        printf("[!] counter block magic mismatch (0x%llx) - layout mismatch, do not trust these numbers\n",
               (unsigned long long)c.magic);
        return 4;
    }
    printf("version        : %llu\n", (unsigned long long)c.version);
    printf("session id     : 0x%llx\n", (unsigned long long)c.sessionId);
    printf("running        : %ld\n", c.running);
    printf("shutdown       : %ld (in-flight at shutdown: %ld)\n", c.shutdown, c.shutdownLeft);
    printf("init error     : %ld\n", c.initError);
    printf("sent           : %llu\n", (unsigned long long)c.sent);
    printf("send fail      : %llu\n", (unsigned long long)c.sendFail);
    printf("reject oversize: %llu\n", (unsigned long long)c.rejectOversize);
    printf("sent notify    : %llu\n", (unsigned long long)c.sentNotify);
    printf("ignored        : %llu\n", (unsigned long long)c.ignoredNonDiscovery);
    printf("scatter/gather : %llu\n", (unsigned long long)c.scatterGather);
    printf("sock overflow  : %llu\n", (unsigned long long)c.sockTableOverflow);
    printf("src unknown    : %llu\n", (unsigned long long)c.srcEndpointUnknown);
    printf("state queries  : %llu\n", (unsigned long long)c.stateQueries);
    printf("observed frames: %llu\n", (unsigned long long)c.observedFrames);
    printf("raw sendto     : %llu\n", (unsigned long long)c.rawSendtoCalls);
    printf("raw wsasendto  : %llu\n", (unsigned long long)c.rawWsasendtoCalls);
    printf("raw bind       : %llu\n", (unsigned long long)c.rawBindCalls);
    printf("raw recvfrom   : %llu\n", (unsigned long long)c.rawRecvfromCalls);
    printf("raw wsarecvfrom: %llu\n", (unsigned long long)c.rawWsarecvfromCalls);
    printf("bind 62056     : %llu\n", (unsigned long long)c.bind62056Count);
    printf("recv on 62056  : %llu\n", (unsigned long long)c.recvfromOn62056);
    printf("wsarecv pending: %llu\n", (unsigned long long)c.wsarecvfromPending);
    printf("cvlh2 try      : %llu\n", (unsigned long long)c.cvlh2Try);
    printf("cvlh2 ok       : %llu\n", (unsigned long long)c.cvlh2Ok);
    printf("cvlh2 fail     : %llu\n", (unsigned long long)c.cvlh2Fail);
    printf("cvlh2 errno    : %llu\n", (unsigned long long)c.cvlh2Errno);
    printf("channel down   : %llu\n", (unsigned long long)c.channelDown);
    printf("accounted      : %llu (sent+sendFail+rejectOversize)\n",
           (unsigned long long)(c.sent + c.sendFail + c.rejectOversize));
    return 0;
}
