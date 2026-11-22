// A-6 决定性对照 v2：原生 C winsock，注入 civtrace 后观测读值路径
// 用法: sobroadcast_c2.exe [wait-ms]  — 启动后先等待，便于外部注入 civtrace
// 编译: cl /nologo /O2 /MT sobroadcast_c2.c /link ws2_32.lib
#include <winsock2.h>
#include <stdio.h>
#include <stdlib.h>
#pragma comment(lib, "ws2_32.lib")

static void test(int flag, int port) {
    SOCKET s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (s == INVALID_SOCKET) { printf("flag=%d socket FAIL err=%d\n", flag, WSAGetLastError()); return; }
    int sr = 0;
    const char* setdesc = "not-set";
    if (flag >= 0) {
        int v = flag;
        sr = setsockopt(s, SOL_SOCKET, SO_BROADCAST, (const char*)&v, sizeof v);
        setdesc = flag ? "set=1" : "set=0";
    }
    struct sockaddr_in to;
    memset(&to, 0, sizeof to);
    to.sin_family = AF_INET;
    to.sin_port = htons((unsigned short)port);
    to.sin_addr.s_addr = htonl(INADDR_BROADCAST);
    char payload[4] = { 0x8d, 0xe8, 0xfc, 0x70 };
    int n = sendto(s, payload, 4, 0, (struct sockaddr*)&to, sizeof to);
    if (n == SOCKET_ERROR) {
        printf("flag=%d %s setsockopt_ret=%d -> sendto FAIL err=%d (WSAEACCES=%d)\n",
               flag, setdesc, sr, WSAGetLastError(), WSAGetLastError() == WSAEACCES);
    } else {
        printf("flag=%d %s setsockopt_ret=%d -> sendto OK n=%d\n", flag, setdesc, sr, n);
    }
    closesocket(s);
}

int main(int argc, char** argv) {
    int waitms = 0;
    if (argc > 1) waitms = atoi(argv[1]);
    WSADATA wd;
    if (WSAStartup(MAKEWORD(2, 2), &wd) != 0) { printf("WSAStartup FAIL\n"); return 1; }
    printf("=== native C SO_BROADCAST v2 (pid=%lu) waiting %d ms for injection ===\n",
           GetCurrentProcessId(), waitms);
    fflush(stdout);
    if (waitms > 0) Sleep((DWORD)waitms);
    test(-1, 62907);
    test(0, 62908);
    test(1, 62909);
    if (waitms > 0) {
        printf("=== done, staying alive %d ms for -u shutdown ===\n", waitms);
        fflush(stdout);
        Sleep((DWORD)waitms);
    }
    WSACleanup();
    return 0;
}
