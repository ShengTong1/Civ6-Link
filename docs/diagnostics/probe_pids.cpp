// 诊断用：复刻 injector.cpp 的 FindPids，用同样的工具链编译，验证 Toolhelp 枚举是否在老版本 exe 里失效
#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <string.h>
#include <vector>

static int FindPids(const char* name, std::vector<DWORD>& out) {
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) {
        printf("snapshot INVALID err=%lu\n", GetLastError());
        return -1;
    }
    PROCESSENTRY32 pe{}; pe.dwSize = sizeof pe;
    printf("sizeof(PROCESSENTRY32)=%zu dwSize=%lu\n", sizeof(PROCESSENTRY32), (unsigned long)pe.dwSize);
    if (Process32First(snap, &pe)) {
        int n = 0;
        do {
            ++n;
            if (_stricmp(pe.szExeFile, name) == 0) out.push_back(pe.th32ProcessID);
        } while (Process32Next(snap, &pe));
        printf("enumerated %d processes\n", n);
    } else {
        printf("Process32First FAILED err=%lu\n", GetLastError());
    }
    CloseHandle(snap);
    return (int)out.size();
}

int main(int argc, char** argv) {
    const char* name = argc > 1 ? argv[1] : "notepad.exe";
    std::vector<DWORD> pids;
    int n = FindPids(name, pids);
    printf("FindPids('%s') -> %d\n", name, n);
    for (DWORD p : pids) printf("  pid=%lu\n", (unsigned long)p);
    return 0;
}
