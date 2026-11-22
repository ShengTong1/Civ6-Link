#include <windows.h>
#include <stdio.h>
int main(int argc, char** argv) {
    DWORD pid = (DWORD)atoi(argv[1]);
    HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!h) { printf("OpenProcess FAIL err=%d\n", GetLastError()); return 1; }
    HANDLE tok = NULL;
    if (!OpenProcessToken(h, TOKEN_QUERY, &tok)) { printf("OpenProcessToken FAIL err=%d\n", GetLastError()); CloseHandle(h); return 1; }
    DWORD e = 0; DWORD sz = 0;
    if (GetTokenInformation(tok, TokenElevation, &e, sizeof e, &sz))
        printf("TokenElevation=%d (0=not elevated, 1=limited, 2=full)\n", e);
    else printf("TokenElevation FAIL err=%d\n", GetLastError());
    TOKEN_ELEVATION_TYPE tet = TokenElevationTypeDefault; sz = 0;
    if (GetTokenInformation(tok, TokenElevationType, &tet, sizeof tet, &sz))
        printf("TokenElevationType=%d (1=full,2=limited,3=split)\n", (int)tet);
    else printf("TokenElevationType FAIL err=%d\n", GetLastError());
    DWORD il = 0; sz = 0;
    if (GetTokenInformation(tok, TokenIntegrityLevel, &il, sizeof il, &sz))
        printf("TokenIntegrityLevel RID=%lu\n", il);
    else printf("TokenIntegrityLevel FAIL err=%d\n", GetLastError());
    CloseHandle(tok); CloseHandle(h);
    return 0;
}
