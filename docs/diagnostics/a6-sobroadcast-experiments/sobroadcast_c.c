// A-6 决定性对照：原生 C winsock，socket->setsockopt(SO_BROADCAST)->sendto(255.255.255.255)
// 编译: cl /nologo /O2 /MT sobroadcast_c.c /link ws2_32.lib
// 输出: 每种 flag 下 setsockopt ret 与 sendto ret/错误码
#include <winsock2.h>
#include <ws2tcpip.h>
#include <stdio.h>
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
    to.sin_addr.s_addr = htonl(INADDR_BROADCAST); // 255.255.255.255
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

int main(void) {
    WSADATA wd;
    if (WSAStartup(MAKEWORD(2, 2), &wd) != 0) { printf("WSAStartup FAIL\n"); return 1; }
    printf("=== native C SO_BROADCAST test (this process pid=%lu) ===\n", GetCurrentProcessId());
    test(-1, 62907);
    test(0, 62908);
    test(1, 62909);
    WSACleanup();
    return 0;
}
