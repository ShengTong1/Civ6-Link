// wsaprobe.c - minimal WSARecvFrom WSA_IO_PENDING buffer-touch probe
// Usage: wsaprobe.exe  (binds 127.0.0.1:62057, posts a pending WSARecvFrom, prints
//                        whether the WSABUF / bytesRecvd / from were modified)
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    WSADATA wsa{};
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) { printf("WSAStartup fail\n"); return 2; }

    SOCKET s = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    sockaddr_in a{};
    a.sin_family = AF_INET;
    a.sin_port = htons(62057);
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (::bind(s, (sockaddr*)&a, sizeof a) != 0) { printf("bind fail %d\n", WSAGetLastError()); return 2; }

    u_long nb = 1;
    ioctlsocket(s, FIONBIO, &nb);

    char data[64];
    memset(data, 0xCC, sizeof data);
    WSABUF wbuf{};
    wbuf.buf = data;
    wbuf.len = (ULONG)sizeof data;
    DWORD flags = 0;
    DWORD recvd = 0xDEADBEEF;
    sockaddr_in from{};
    from.sin_family = 0xA5A5; // canary marker
    from.sin_port = 0xBEEF;
    from.sin_addr.s_addr = 0xCAFEBEEF;
    int fromLen = sizeof from;
    WSAOVERLAPPED ov{};
    int rc = ::WSARecvFrom(s, &wbuf, 1, &recvd, &flags, (sockaddr*)&from, &fromLen, &ov, nullptr);
    int err = WSAGetLastError();
    printf("rc=%d err=%d\n", rc, err);
    if (rc == SOCKET_ERROR && err == WSA_IO_PENDING) {
        int changed = 0;
        for (int i = 0; i < (int)sizeof data; i++) if (data[i] != 0xCC) changed++;
        printf("buffer bytes changed: %d\n", changed);
        printf("recvd changed: %s\n", recvd == 0xDEADBEEF ? "no" : "YES");
        printf("from touched: %s (family=0x%04X port=0x%04X addr=0x%08X len=%d)\n",
               (from.sin_family == 0xA5A5 && from.sin_port == 0xBEEF &&
                from.sin_addr.s_addr == 0xCAFEBEEF) ? "no" : "YES",
               from.sin_family, from.sin_port, from.sin_addr.s_addr, fromLen);
        // cancel pending op by closing
        closesocket(s);
        printf("probe done\n");
        return 0;
    }
    printf("unexpected rc/err\n");
    closesocket(s);
    return 3;
}
