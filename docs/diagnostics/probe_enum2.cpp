// 诊断用：枚举失败点与错误码
#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>

int main() {
    for (int round = 1; round <= 3; ++round) {
        HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (snap == INVALID_HANDLE_VALUE) {
            printf("round %d: snapshot INVALID err=%lu\n", round, GetLastError());
            continue;
        }
        PROCESSENTRY32 pe{}; pe.dwSize = sizeof pe;
        int n = 0; DWORD lastErr = 0;
        BOOL ok = Process32First(snap, &pe);
        if (!ok) { lastErr = GetLastError(); }
        while (ok) {
            ++n;
            ok = Process32Next(snap, &pe);
            if (!ok) lastErr = GetLastError();
        }
        CloseHandle(snap);
        printf("round %d: count=%d lastErr=%lu (18=NO_MORE_FILES normal)\n", round, n, (unsigned long)lastErr);
    }

    // 对照：用 NtQuerySystemInformation 直接数进程
    typedef LONG (WINAPI *PFN)(ULONG, PVOID, ULONG, PULONG);
    HMODULE nt = GetModuleHandleA("ntdll.dll");
    PFN q = (PFN)GetProcAddress(nt, "NtQuerySystemInformation");
    if (q) {
        ULONG len = 1 << 22;
        BYTE* buf = (BYTE*)malloc(len);
        ULONG need = 0;
        LONG st = q(5 /*SystemProcessInformation*/, buf, len, &need);
        if (st == 0) {
            // SYSTEM_PROCESS_INFORMATION 数量：按 NextEntryOffset 链数
            int cnt = 0; BYTE* p = buf;
            for (;;) {
                ULONG next = *(ULONG*)(p);
                ++cnt;
                if (next == 0) break;
                p += next;
            }
            printf("NtQuerySystemInformation process count = %d\n", cnt);
        } else {
            printf("NtQuerySystemInformation status = 0x%08lX\n", (unsigned long)st);
        }
        free(buf);
    }
    return 0;
}
