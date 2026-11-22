// A-6 决定性实验 v3：验证游戏"setsockopt(0) 后广播仍成功"的可能解释
// 假设：游戏广播开启走 WSASetSockOpt（civtrace 未 Hook 该 API），setsockopt(0) 只是后续调用
// 实验矩阵：
//   A: socket -> setsockopt(SO_BROADCAST,0) -> sendto           （期望 FAIL，已证实）
//   B: socket -> pWSASetSockOpt(sO_BROADCAST,1) -> sendto        （期望 OK）
//   C: socket -> pWSASetSockOpt(sO_BROADCAST,1) -> setsockopt(0) -> sendto  （若 OK → 证明 setsockopt(0) 后仍可广播?）
//   D: socket -> bind(INADDR_ANY:0) -> setsockopt(0) -> sendto  （验证 bind 是否绕过检查）
//   E: socket -> setsockopt(0) -> WSASetSockOpt(1) -> sendto    （若 OK → 游戏序列解释=WSASetSockOpt 在其后）
// 编译: cl /nologo /O2 /MT sobroadcast_c3.c /link ws2_32.lib
#include <winsock2.h>
#include <stdio.h>
#pragma comment(lib, "ws2_32.lib")
// 动态加载 WSASetSockOpt（ws2_32 导出；静态链接签名易错，此处用 GetProcAddress）
typedef int (__stdcall *FnWSASetSockOpt)(SOCKET, int, int, const char*, int, void*, void*);
static FnWSASetSockOpt pWSASetSockOpt = NULL;

static void one(const char* name, int mode) {
    int wsa1 = 0;
    SOCKET s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (s == INVALID_SOCKET) { printf("%s: socket FAIL err=%d\n", name, WSAGetLastError()); return; }
    int sr0 = -99, sr1 = -99;
    // mode: 0=A set0-only, 1=B WSA-set1-only, 2=C WSA-set1 then set0, 3=D set0 then WSA-set1
    if (mode == 0 || mode == 2 || mode == 3) {
        if (mode == 2) { int v = 1; sr1 = pWSASetSockOpt(s, SOL_SOCKET, SO_BROADCAST, (const char*)&v, sizeof v, NULL, NULL); }
        int v = 0; sr0 = setsockopt(s, SOL_SOCKET, SO_BROADCAST, (const char*)&v, sizeof v);
        if (mode == 3) { int v2 = 1; sr1 = pWSASetSockOpt(s, SOL_SOCKET, SO_BROADCAST, (const char*)&v2, sizeof v2, NULL, NULL); }
    }
    if (mode == 1) { int v = 1; sr1 = pWSASetSockOpt(s, SOL_SOCKET, SO_BROADCAST, (const char*)&v, sizeof v, NULL, NULL); }
    struct sockaddr_in to;
    memset(&to, 0, sizeof to);
    to.sin_family = AF_INET;
    to.sin_port = htons(62910 + mode);
    to.sin_addr.s_addr = htonl(INADDR_BROADCAST);
    char payload[4] = { 0x8d, 0xe8, 0xfc, 0x70 };
    int n = sendto(s, payload, 4, 0, (struct sockaddr*)&to, sizeof to);
    if (n == SOCKET_ERROR)
        printf("%s: set0=%d WSAset1=%d -> sendto FAIL err=%d\n", name, sr0, sr1, WSAGetLastError());
    else
        printf("%s: set0=%d WSAset1=%d -> sendto OK n=%d\n", name, sr0, sr1, n);
    closesocket(s);
}

int main(int argc, char** argv) {
    HMODULE ws2 = GetModuleHandleA("ws2_32.dll");
    if (ws2) pWSASetSockOpt = (FnWSASetSockOpt)GetProcAddress(ws2, "WSASetSockOpt");
    if (!pWSASetSockOpt) { printf("cannot resolve WSASetSockOpt\n"); return 1; }
    WSADATA wd;
    if (WSAStartup(MAKEWORD(2, 2), &wd) != 0) { printf("WSAStartup FAIL\n"); return 1; }
    printf("=== SO_BROADCAST v3 matrix (pid=%lu) ===\n", GetCurrentProcessId());
    fflush(stdout);
    one("A set0-only     ", 0);
    one("B WSAset1-only  ", 1);
    one("C WSAset1+set0  ", 2);
    one("D set0+WSAset1  ", 3);
    if (argc > 1) Sleep((DWORD)atoi(argv[1])); // 供外部注入后驻留
    printf("=== done ===\n");
    fflush(stdout);
    WSACleanup();
    return 0;
}


