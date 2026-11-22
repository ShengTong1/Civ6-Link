// 诊断用：打印 Toolhelp 枚举到的全部进程，判断是否令牌受限
#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <string.h>

int main() {
    printf("sizeof(PROCESSENTRY32)=%zu\n", sizeof(PROCESSENTRY32));
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) { printf("snapshot INVALID err=%lu\n", GetLastError()); return 1; }
    PROCESSENTRY32 pe{}; pe.dwSize = sizeof pe;
    int n = 0;
    if (Process32First(snap, &pe)) {
        do {
            ++n;
            printf("%5lu  %s\n", (unsigned long)pe.th32ProcessID, pe.szExeFile);
        } while (Process32Next(snap, &pe));
    } else {
        printf("Process32First FAILED err=%lu\n", GetLastError());
    }
    CloseHandle(snap);
    printf("total=%d\n", n);

    // 令牌信息
    HANDLE tok = nullptr;
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)) {
        BYTE buf[4096]; DWORD len = 0;
        if (GetTokenInformation(tok, TokenIntegrityLevel, buf, sizeof buf, &len)) {
            TOKEN_MANDATORY_LABEL* tml = (TOKEN_MANDATORY_LABEL*)buf;
            DWORD* rid = (DWORD*)GetSidSubAuthority(tml->Label.Sid,
                            (DWORD)(*GetSidSubAuthorityCount(tml->Label.Sid) - 1));
            printf("integrity level RID = %lu\n", (unsigned long)*rid);
        }
        if (GetTokenInformation(tok, TokenIsAppContainer, buf, sizeof buf, &len))
            printf("IsAppContainer = %d\n", *(DWORD*)buf);
        if (GetTokenInformation(tok, TokenRestrictedSids, buf, sizeof buf, &len)) {
            TOKEN_GROUPS* g = (TOKEN_GROUPS*)buf;
            printf("restricted SID count = %lu\n", (unsigned long)g->GroupCount);
        } else {
            printf("TokenRestrictedSids err=%lu\n", GetLastError());
        }
        CloseHandle(tok);
    }
    return 0;
}
