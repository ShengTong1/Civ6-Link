#include <winsock2.h>
#include <stdio.h>
#include <stdlib.h>
#pragma comment(lib, "ws2_32.lib")
// argv[1]=optlen argv[2]=val argv[3]=pre-wait-ms (????????, ??? setsockopt/sendto)
int main(int argc, char** argv) {
    WSADATA wd; WSAStartup(MAKEWORD(2,2), &wd);
    int optlen = argc>1 ? atoi(argv[1]) : 1;
    int val    = argc>2 ? atoi(argv[2]) : 1;
    int wait   = argc>3 ? atoi(argv[3]) : 0;
    printf("[c6] pid=%lu ready; optlen=%d val=%d pre-wait=%d\n", GetCurrentProcessId(), optlen, val, wait);
    fflush(stdout);
    if (wait) Sleep(wait);   // ?????????????
    SOCKET s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    char buf[4] = { (char)val, 0, 0, 0 };
    int sr = setsockopt(s, SOL_SOCKET, SO_BROADCAST, (const char*)buf, optlen);
    printf("[c6] setsockopt ret=%d err=%d\n", sr, WSAGetLastError());
    struct sockaddr_in to; memset(&to,0,sizeof to); to.sin_family=AF_INET; to.sin_port=htons(62950); to.sin_addr.s_addr=htonl(INADDR_BROADCAST);
    char p[4]={0x8d,0xe8,0xfc,0x70};
    int n = sendto(s, p, 4, 0, (struct sockaddr*)&to, sizeof to);
    if (n==SOCKET_ERROR) printf("[c6] sendto FAIL err=%d\n", WSAGetLastError());
    else printf("[c6] sendto OK n=%d\n", n);
    closesocket(s); WSACleanup(); return 0;
}
