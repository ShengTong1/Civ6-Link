#include <winsock2.h>
#include <stdio.h>
#include <stdlib.h>
#pragma comment(lib, "ws2_32.lib")
int main(int argc, char** argv) {
    WSADATA wd; WSAStartup(MAKEWORD(2,2), &wd);
    printf("=== optlen ???? (pid=%lu) ===\n", GetCurrentProcessId());
    int lens[] = { 1, 2, 4 };
    int vals[] = { 1, 0 };
    for (int li = 0; li < 3; ++li) {
        for (int vi = 0; vi < 2; ++vi) {
            SOCKET s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
            if (s == INVALID_SOCKET) { printf("socket FAIL err=%d\n", WSAGetLastError()); continue; }
            char buf[4] = {0,0,0,0}; buf[0] = (char)vals[vi];
            int optlen = lens[li];
            int sr = setsockopt(s, SOL_SOCKET, SO_BROADCAST, (const char*)buf, optlen);
            struct sockaddr_in to; memset(&to,0,sizeof to); to.sin_family=AF_INET; to.sin_port=htons(63000+li*10+vi); to.sin_addr.s_addr=htonl(INADDR_BROADCAST);
            char p[4]={0x8d,0xe8,0xfc,0x70};
            int n = sendto(s, p, 4, 0, (struct sockaddr*)&to, sizeof to);
            if (n==SOCKET_ERROR) printf("optlen=%d val=%d: setsockopt ret=%d -> sendto FAIL err=%d\n", optlen, vals[vi], sr, WSAGetLastError());
            else printf("optlen=%d val=%d: setsockopt ret=%d -> sendto OK n=%d\n", optlen, vals[vi], sr, n);
            closesocket(s);
        }
    }
    WSACleanup(); return 0;
}
