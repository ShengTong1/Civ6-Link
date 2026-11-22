// A-6 决定性实验：游戏进程内探针 DLL
// 在目标进程（游戏）内执行: WSAStartup -> socket -> setsockopt(SO_BROADCAST,0) -> sendto(255.255.255.255:62900)
// 结果写文件，验证"游戏进程内 SO_BROADCAST=0 向有限广播发送"是否成功（对照独立进程必失败）
// 编译: cl /nologo /O2 /MT /LD probe_inject_dll.c /link ws2_32.lib
#include <winsock2.h>
#include <stdio.h>
#include <windows.h>

// civinject 需要校验导出名 CivTraceInitialize（共享头契约），提供空实现
__declspec(dllexport) int __stdcall CivTraceInitialize(const wchar_t* dummy) { return 0; }

static void append_result(const char* line) {
    FILE* f = fopen("C:\\Users\\dd\\Desktop\\injciv6-v0.3.3\\M0A\\captures\\probe-inject-result.txt", "a");
    if (f) { fprintf(f, "%s\n", line); fclose(f); }
}

BOOL APIENTRY DllMain(HMODULE h, DWORD reason, LPVOID reserved) {
    if (reason == DLL_PROCESS_ATTACH) {
        char buf[256];
        WSADATA wd;
        if (WSAStartup(MAKEWORD(2, 2), &wd) != 0) {
            snprintf(buf, sizeof buf, "[%lu] WSAStartup FAIL err=%d", GetCurrentProcessId(), WSAGetLastError());
            append_result(buf); return TRUE;
        }
        SOCKET s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (s == INVALID_SOCKET) {
            snprintf(buf, sizeof buf, "[%lu] socket FAIL err=%d", GetCurrentProcessId(), WSAGetLastError());
            append_result(buf); WSACleanup(); return TRUE;
        }
        int v = 0;
        int sr = setsockopt(s, SOL_SOCKET, SO_BROADCAST, (const char*)&v, sizeof v);
        struct sockaddr_in to;
        memset(&to, 0, sizeof to);
        to.sin_family = AF_INET; to.sin_port = htons(62900); to.sin_addr.s_addr = htonl(INADDR_BROADCAST);
        char payload[4] = { 0x8d, 0xe8, 0xfc, 0x70 };
        int n = sendto(s, payload, 4, 0, (struct sockaddr*)&to, sizeof to);
        if (n == SOCKET_ERROR)
            snprintf(buf, sizeof buf, "[%lu] IN-PROCESS set0=%d -> sendto 255.255.255.255 FAIL err=%d", GetCurrentProcessId(), sr, WSAGetLastError());
        else
            snprintf(buf, sizeof buf, "[%lu] IN-PROCESS set0=%d -> sendto 255.255.255.255 OK n=%d", GetCurrentProcessId(), sr, n);
        append_result(buf);
        closesocket(s);
        WSACleanup();
    }
    return TRUE;
}
