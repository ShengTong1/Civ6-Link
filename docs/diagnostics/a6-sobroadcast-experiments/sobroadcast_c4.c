// A-6 决定性实验 v4：完全复刻游戏序列并变体对照
// 游戏序列: socket() -> setsockopt(SO_BROADCAST,0) -> 100x sendto(255.255.255.255:62900-62999) -> select -> closesocket
// 变体矩阵（都先 set=0 再 sendto，与游戏一致）：
//   A: 无 bind，目标 255.255.255.255:62900          （复刻游戏；对照 c2 已 FAIL）
//   B: bind(0.0.0.0:0) 后 set0 -> 255.255.255.255
//   C: bind(26.74.126.98:0) 后 set0 -> 255.255.255.255   （Radmin 地址）
//   D: 无 bind，set0 后 getsockopt 读回 SO_BROADCAST 再 sendto 255.255.255.255
//   E: 无 bind，set0 -> sendto 26.255.255.255:62900（Radmin 定向广播）
// 每个变体 sendto 后打印结果；-wait 供外部注入 civtrace 交叉验证
// 编译: cl /nologo /O2 /MT sobroadcast_c4.c /link ws2_32.lib
#include <winsock2.h>
#include <ws2tcpip.h>
#include <stdio.h>
#include <stdlib.h>
#pragma comment(lib, "ws2_32.lib")

static void dump_sockaddr(const char* tag, const struct sockaddr_in* a) {
    char ip[64] = { 0 };
    inet_ntop(AF_INET, &a->sin_addr, ip, sizeof ip);
    printf("%s %s:%d", tag, ip, ntohs(a->sin_port));
}


static void variant2(const char* name, int bindmode, const char* target) {
    SOCKET s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (s == INVALID_SOCKET) { printf("%s: socket FAIL err=%d\n", name, WSAGetLastError()); return; }
    if (bindmode == 1) {
        struct sockaddr_in b; memset(&b, 0, sizeof b); b.sin_family = AF_INET; inet_pton(AF_INET, "192.168.31.59", &b.sin_addr); b.sin_port = 0;
        if (bind(s, (struct sockaddr*)&b, sizeof b) == SOCKET_ERROR) { printf("%s: bind FAIL err=%d\n", name, WSAGetLastError()); closesocket(s); return; }
    } else if (bindmode == 2) {
        struct sockaddr_in b; memset(&b, 0, sizeof b); b.sin_family = AF_INET; inet_pton(AF_INET, "26.74.126.98", &b.sin_addr); b.sin_port = 0;
        if (bind(s, (struct sockaddr*)&b, sizeof b) == SOCKET_ERROR) { printf("%s: bind FAIL err=%d\n", name, WSAGetLastError()); closesocket(s); return; }
    }
    int v = 0;
    int sr = setsockopt(s, SOL_SOCKET, SO_BROADCAST, (const char*)&v, sizeof v);
    struct sockaddr_in to; memset(&to, 0, sizeof to);
    to.sin_family = AF_INET; to.sin_port = htons(62920);
    inet_pton(AF_INET, target, &to.sin_addr);
    char payload[4] = { 0x8d, 0xe8, 0xfc, 0x70 };
    int n = sendto(s, payload, 4, 0, (struct sockaddr*)&to, sizeof to);
    if (n == SOCKET_ERROR) printf("%s: set0=%d -> sendto %s FAIL err=%d\n", name, sr, target, WSAGetLastError());
    else printf("%s: set0=%d -> sendto %s OK n=%d\n", name, sr, target, n);
    closesocket(s); fflush(stdout);
}
static void variant(const char* name, int bindmode, int target_is_limited, int readback) {
    SOCKET s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (s == INVALID_SOCKET) { printf("%s: socket FAIL err=%d\n", name, WSAGetLastError()); return; }
    if (bindmode == 1) {
        struct sockaddr_in b; memset(&b, 0, sizeof b); b.sin_family = AF_INET; b.sin_addr.s_addr = htonl(INADDR_ANY); b.sin_port = 0;
        if (bind(s, (struct sockaddr*)&b, sizeof b) == SOCKET_ERROR) { printf("%s: bind(0.0.0.0:0) FAIL err=%d\n", name, WSAGetLastError()); closesocket(s); return; }
    } else if (bindmode == 2) {
        struct sockaddr_in b; memset(&b, 0, sizeof b); b.sin_family = AF_INET; inet_pton(AF_INET, "26.74.126.98", &b.sin_addr); b.sin_port = 0;
        if (bind(s, (struct sockaddr*)&b, sizeof b) == SOCKET_ERROR) { printf("%s: bind(26.74.126.98:0) FAIL err=%d\n", name, WSAGetLastError()); closesocket(s); return; }
    }
    int v = 0;
    int sr = setsockopt(s, SOL_SOCKET, SO_BROADCAST, (const char*)&v, sizeof v);
    if (readback) {
        int rv = -1; socklen_t rl = sizeof rv;
        int gr = getsockopt(s, SOL_SOCKET, SO_BROADCAST, (char*)&rv, &rl);
        printf("%s: setsockopt ret=%d, getsockopt SO_BROADCAST readback=%d (ret=%d)\n", name, sr, rv, gr);
    } else {
        printf("%s: setsockopt(SO_BROADCAST,0) ret=%d\n", name, sr);
    }
    struct sockaddr_in to; memset(&to, 0, sizeof to);
    to.sin_family = AF_INET; to.sin_port = htons(62900);
    if (target_is_limited) to.sin_addr.s_addr = htonl(INADDR_BROADCAST);
    else inet_pton(AF_INET, "26.255.255.255", &to.sin_addr);
    dump_sockaddr("  -> dst", &to); printf(" len=4 ");
    char payload[4] = { 0x8d, 0xe8, 0xfc, 0x70 };
    int n = sendto(s, payload, 4, 0, (struct sockaddr*)&to, sizeof to);
    if (n == SOCKET_ERROR) printf("sendto FAIL err=%d (WSAEACCES=%d)\n", WSAGetLastError(), WSAGetLastError() == WSAEACCES);
    else printf("sendto OK n=%d\n", n);
    closesocket(s);
    fflush(stdout);
}

int main(int argc, char** argv) {
    int waitms = 0;
    if (argc > 1) waitms = atoi(argv[1]);
    WSADATA wd;
    if (WSAStartup(MAKEWORD(2, 2), &wd) != 0) { printf("WSAStartup FAIL\n"); return 1; }
    printf("=== SO_BROADCAST v4 matrix (pid=%lu) wait=%dms ===\n", GetCurrentProcessId(), waitms);
    fflush(stdout);
    if (waitms > 0) Sleep((DWORD)waitms);
    variant("A no-bind limited ", 0, 1, 0);
    variant("B bind-any limited", 1, 1, 0);
    variant("C bind-radmin-lim ", 2, 1, 0);
    variant("D no-bind readback", 0, 1, 1);
    variant("E no-bind radmin-b", 0, 0, 0);
    
    variant2("F no-bind WLAN-bcast ", 0, "192.168.31.255");
    variant2("G bind-WLAN lim     ", 1, "255.255.255.255");
    variant2("H bind-Radmin self  ", 2, "26.255.255.255");
    { SOCKET s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
      struct sockaddr_in to; memset(&to, 0, sizeof to); to.sin_family = AF_INET; to.sin_port = htons(62921); to.sin_addr.s_addr = htonl(INADDR_BROADCAST);
      char p[4] = { 0x8d, 0xe8, 0xfc, 0x70 };
      int n = sendto(s, p, 4, 0, (struct sockaddr*)&to, sizeof to);
      if (n == SOCKET_ERROR) printf("I no-set limited    -> sendto FAIL err=%d\n", WSAGetLastError()); else printf("I no-set limited    -> sendto OK n=%d\n", n);
      closesocket(s); }
if (waitms > 0) { printf("=== done, staying %dms ===\n", waitms); fflush(stdout); Sleep((DWORD)waitms); }
    WSACleanup();
    return 0;
}

