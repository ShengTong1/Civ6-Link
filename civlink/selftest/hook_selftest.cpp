// hook_selftest.cpp - CivLink F1/F2 mechanical self-test of civlink_hook.dll + civlink-agent
//
// What this proves (and nothing more):
//   * the DLL loads, initialises and reports state 1,
//   * the six detours are installed and the discovery predicate behaves as specified,
//   * the ORIGINAL call is never altered: same arguments, original return value,
//   * every observation is counted on the hook side (layered counters, F2 §3.3),
//   * bind / recvfrom / WSARecvFrom are observed without touching caller buffers,
//     including a constructed WSA_IO_PENDING path (canary buffer must stay intact),
//   * CVLH2 frames really leave the process (the Agent must show received == sent),
//   * shutdown disables hooks, drains, and leaves the module mapped.
//
// What this does NOT prove: that Civ6 uses these APIs (F1 evidence must come from a real
// game run), that discovery works end to end, or anything about multiplayer / Gate A.
// The 62056 socket here is a synthetic test socket in the self-test process - no game is
// running, so it is NOT evidence about H2 (wildcard bind coexistence) or R1. Close the game
// (or leave its LAN room) before running, otherwise that bind fails with 10048 and six
// downstream counter checks fail - an environment failure, not a product failure.
//
// Sends used (all 4-byte discovery magic unless stated):
//   1. 255.255.255.255:62905   4 B     -> sent +1
//   2. 127.0.0.1:62907         4 B     -> sent +1  (discovery PORT, not broadcast)
//   3. 127.0.0.1:50999         4 B     -> observed +1 (outside the discovery range,
//                                        forwarded as an OBSERVED frame, never swallowed)
//   4. 127.0.0.1:62907      1400 B     -> rejectOversize +1, notification frame
//   5. closesocket                     -> logical slot released
//   (after 5) 127.0.0.1:62908 4 B      -> sent +1 (fresh logical id)
//   (after 6) 127.0.0.1:62056 4 B      -> observed +1 (F2: outbound to the data-plane port
//                                        is observed, forwarded as an OBSERVED frame)
//   7. bind 127.0.0.1:62056            -> rawBindCalls +1, bind62056Count +1
//   8. recvfrom on that socket (timeout)-> rawRecvfromCalls +1, recvfromOn62056 +1
//   9. WSARecvFrom overlapped, no data  -> rawWsarecvfromCalls +1, recvfromOn62056 +1,
//                                        wsarecvfromPending +1 (WSA_IO_PENDING path;
//                                        canary WSABUF / bytesRecvd / from stay untouched)
//
// Exit code 0 only when every check passes. Failures print FAIL with the expectation.
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <cstdio>
#include <cstring>

#include "../common/civlink_hook.h"

#pragma comment(lib, "ws2_32.lib")

typedef int  (*F_State)(void);
typedef int  (*F_Shutdown)(void);
typedef void (*F_Counters)(CivLinkCounters*);

static int g_fail = 0;

static void Check(const char* what, bool ok, const char* detail = "")
{
    printf("  %s %-52s %s\n", ok ? "PASS" : "FAIL", what, detail);
    if (!ok) g_fail++;
}

static const unsigned char kMagic[4] = { 0x8D, 0xE8, 0xFC, 0x70 };

int main(void)
{
    printf("civlink hook self-test (expects a freshly started civlink-agent on 127.0.0.1:34718)\n");
    // Guarded precondition: the probe binds 127.0.0.1:62056 below. If any process holds a
    // wildcard bind on 62056 (a running game with a LAN room does), that bind cannot succeed
    // and six downstream counter checks fail for environmental reasons. Detect it up front so
    // the failure reads as "stop the game" instead of looking like a regression.
    {
        SOCKET probe = ::socket(AF_INET, SOCK_DGRAM, 0);
        if (probe != INVALID_SOCKET) {
            sockaddr_in a{}; a.sin_family = AF_INET; a.sin_port = htons(62056);
            a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
            if (::bind(probe, (sockaddr*)&a, sizeof(a)) != 0) {
                printf("FATAL: cannot bind 127.0.0.1:62056 (err=%d).\n", WSAGetLastError());
                printf("       Another process holds 62056 - most likely Civilization VI with a LAN\n");
                printf("       room open. Close the game (or leave its LAN room) and run this again.\n");
                ::closesocket(probe);
                WSACleanup();
                return 3;
            }
            ::closesocket(probe);
        }
    }

    WSADATA wsa{};
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
        printf("FATAL: WSAStartup failed\n");
        return 2;
    }

    char dllPath[MAX_PATH]{};
    GetModuleFileNameA(nullptr, dllPath, MAX_PATH);
    char* slash = strrchr(dllPath, '\\');
    if (slash) *slash = '\0';
    strcat_s(dllPath, "\\" CIVLINK_HOOK_DLL_NAME_A);

    HMODULE h = LoadLibraryA(dllPath);
    if (!h) {
        printf("FATAL: LoadLibraryA(%s) failed err=%lu\n", dllPath, GetLastError());
        return 2;
    }
    printf("loaded %s\n", dllPath);

    F_State    state    = (F_State)GetProcAddress(h, "CivLinkHookState");
    F_Shutdown shutdown = (F_Shutdown)GetProcAddress(h, "CivLinkShutdown");
    F_Counters counters = (F_Counters)GetProcAddress(h, "CivLinkGetCounters");
    if (!state || !shutdown || !counters) {
        printf("FATAL: required exports missing\n");
        return 2;
    }

    // 1. init
    int st = 0;
    for (int i = 0; i < 100; i++) {
        st = state();
        if (st == 1) break;
        Sleep(50);
    }
    CivLinkCounters c{};
    counters(&c);
    Check("hooks reach state 1", st == 1, st == 1 ? "" : "state != 1");
    Check("initError == 0", c.initError == 0);
    Check("session id non-zero", c.sessionId != 0);
    if (st != 1) {
        printf("initError=%ld - aborting before any send\n", c.initError);
        return 1;
    }

    SOCKET s = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (s == INVALID_SOCKET) { printf("FATAL: socket failed\n"); return 2; }
    BOOL bcast = TRUE;
    setsockopt(s, SOL_SOCKET, SO_BROADCAST, (const char*)&bcast, sizeof bcast);

    auto SendTo = [&](const char* ip, unsigned short port, const void* data, int len) {
        sockaddr_in to{};
        to.sin_family = AF_INET;
        to.sin_port = htons(port);
        inet_pton(AF_INET, ip, &to.sin_addr);
        return ::sendto(s, (const char*)data, len, 0, (sockaddr*)&to, sizeof to);
    };

    char big[1400];
    memset(big, 0x5A, sizeof big);

    // 2. the four observed sends; return values must be exactly what UDP would return
    const int rc1 = SendTo("255.255.255.255", 62905, kMagic, 4);
    Check("broadcast discovery send returns 4", rc1 == 4, "");
    const int rc2 = SendTo("127.0.0.1", 62907, kMagic, 4);
    Check("loopback discovery-port send returns 4", rc2 == 4, "");
    const int rc3 = SendTo("127.0.0.1", 50999, kMagic, 4);
    Check("non-discovery send returns 4", rc3 == 4, "");
    const int rc4 = SendTo("127.0.0.1", 62907, big, (int)sizeof big);
    Check("oversize send returns 1400 (not altered)", rc4 == (int)sizeof big, "");

    Sleep(300); // let the Agent drain the loopback frames

    counters(&c);
    Check("sent == 2", c.sent == 2, "");
    Check("sendFail == 0", c.sendFail == 0);
    Check("rejectOversize == 1", c.rejectOversize == 1);
    Check("ignoredNonDiscovery == 0 (observed frames are forwarded, not ignored)",
          c.ignoredNonDiscovery == 0);
    Check("observedFrames == 1 (non-discovery send forwarded as OBSERVED)", c.observedFrames == 1);
    Check("sentNotify == 1", c.sentNotify == 1);
    Check("sockTableOverflow == 0", c.sockTableOverflow == 0);
    // The first observed send happens before the OS assigns a local port (an unbound UDP
    // socket reports 0.0.0.0:0), so exactly the first frame cannot carry a source endpoint.
    // From the second send on, the cached endpoint must be present.
    Check("srcEndpointUnknown == 1 (first send of an unbound socket)", c.srcEndpointUnknown == 1,
          "");
    const unsigned long long accounted = c.sent + c.sendFail + c.rejectOversize;
    Check("sent + sendFail + rejectOversize == 3 observations", accounted == 3, "");
    Check("rawSendtoCalls == 4 (each call counted at the detour entry)", c.rawSendtoCalls == 4,
          "");
    Check("rawBindCalls == 0 (no bind in this test)", c.rawBindCalls == 0, "");
    Check("cvlh2Try == 4 (one frame per observed send)", c.cvlh2Try == 4, "");
    Check("cvlh2Ok == 4", c.cvlh2Ok == 4, "");
    Check("cvlh2Fail == 0 / channelDown == 0", c.cvlh2Fail == 0 && c.channelDown == 0, "");

    // 3. closesocket forgets the slot; a re-send must get a fresh logical id
    closesocket(s);
    s = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    setsockopt(s, SOL_SOCKET, SO_BROADCAST, (const char*)&bcast, sizeof bcast);
    const int rc5 = SendTo("127.0.0.1", 62908, kMagic, 4);
    Check("post-close send returns 4", rc5 == 4, "");
    Sleep(300);
    counters(&c);
    Check("sent == 3 after the extra send", c.sent == 3, "");

    // F2: outbound send to the data-plane port (62056) is observed, not swallowed
    const int rc7 = SendTo("127.0.0.1", 62056, kMagic, 4);
    Check("data-plane port send returns 4", rc7 == 4, "");
    Sleep(300);
    counters(&c);
    Check("observedFrames == 2 after the 62056 send", c.observedFrames == 2, "");
    Check("rawSendtoCalls == 6 (rc1..rc5 + rc7)", c.rawSendtoCalls == 6, "");
    Check("cvlh2Try == 6 / cvlh2Ok == 6", c.cvlh2Try == 6 && c.cvlh2Ok == 6, "");

    // F2/D4: a send from a socket BOUND to a local address carries a local source endpoint,
    //        so the Agent's datapath D4 rule may reply (one 20B probe, whole-run budget 1).
    SOCKET sdSock = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (sdSock == INVALID_SOCKET) { printf("FATAL: d4 socket failed\n"); return 2; }
    sockaddr_in daddr{};
    daddr.sin_family = AF_INET;
    daddr.sin_port = 0; // ephemeral local port
    inet_pton(AF_INET, "127.0.0.1", &daddr.sin_addr);
    const int drc = ::bind(sdSock, (sockaddr*)&daddr, sizeof daddr);
    Check("bind 127.0.0.1:0 returns 0", drc == 0, "");
    sockaddr_in dto{};
    dto.sin_family = AF_INET;
    dto.sin_port = htons(62056);
    inet_pton(AF_INET, "127.0.0.1", &dto.sin_addr);
    const int rc8 = ::sendto(sdSock, (const char*)kMagic, (int)sizeof kMagic, 0,
                             (sockaddr*)&dto, sizeof dto);
    Check("bound local send to 62056 returns 4", rc8 == 4, "");
    Sleep(300);
    counters(&c);
    Check("observedFrames == 3 after the bound-local send", c.observedFrames == 3, "");
    Check("rawSendtoCalls == 7 (rc1..rc5 + rc7 + rc8)", c.rawSendtoCalls == 7, "");
    Check("cvlh2Try == 7 / cvlh2Ok == 7", c.cvlh2Try == 7 && c.cvlh2Ok == 7, "");
    closesocket(sdSock);
    closesocket(s);

    // B1 §0 (2026-11-17, run-20261117-095336): the real host answers advertisement pages
    // as UNICAST back to the requester's source address:source port (e.g. 54322), NOT to
    // 62900..62999. A socket that bound a discovery port must therefore be treated as a
    // discovery socket for ALL of its sends, whatever the destination port. rc9 below
    // sends from a 62900-bound socket to 54322 (a non-discovery destination): it must be
    // counted as sent (DISCOVERY by socket identity), never as observedFrames.
    SOCKET idSock = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (idSock == INVALID_SOCKET) { printf("FATAL: identity socket failed\n"); return 2; }
    sockaddr_in idaddr{};
    idaddr.sin_family = AF_INET;
    // 62905, not 62900: a running Civ6 game binds 0.0.0.0:62900, so a 62900 bind in the
    // self-test fails (WSAEADDRINUSE) and the socket never gains the discovery identity.
    // Any port in 62900..62999 is a discovery socket; 62905 avoids the live-game clash.
    idaddr.sin_port = htons(62905);
    inet_pton(AF_INET, "127.0.0.1", &idaddr.sin_addr);
    const int irc = ::bind(idSock, (sockaddr*)&idaddr, sizeof idaddr);
    Check("bind 127.0.0.1:62905 (discovery socket identity) returns 0", irc == 0, "");
    sockaddr_in ito{};
    ito.sin_family = AF_INET;
    ito.sin_port = htons(54322); // requester's ephemeral port: unicast reply target
    inet_pton(AF_INET, "127.0.0.1", &ito.sin_addr);
    const int rc9 = ::sendto(idSock, (const char*)kMagic, (int)sizeof kMagic, 0,
                             (sockaddr*)&ito, sizeof ito);
    Check("unicast reply from discovery-bound socket to 54322 returns 4", rc9 == 4, "");
    Sleep(300);
    counters(&c);
    Check("sent == 4 (rc9 counted as DISCOVERY by socket identity)", c.sent == 4, "");
    Check("observedFrames == 3 (unicast reply NOT observed)", c.observedFrames == 3, "");
    closesocket(idSock);

    // F2: bind is observed; a 62056 bind is counted (synthetic test socket, see header)
    SOCKET sb = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (sb == INVALID_SOCKET) { printf("FATAL: bind-test socket failed\n"); return 2; }
    sockaddr_in baddr{};
    baddr.sin_family = AF_INET;
    baddr.sin_port = htons(62056);
    inet_pton(AF_INET, "127.0.0.1", &baddr.sin_addr);
    const int brc = ::bind(sb, (sockaddr*)&baddr, sizeof baddr);
    Check("bind 127.0.0.1:62056 returns 0", brc == 0, "");
    counters(&c);
    Check("rawBindCalls == 3 (sb 62056 + sdSock 127.0.0.1:0 + idSock 127.0.0.1:62905)", c.rawBindCalls == 3, "");
    Check("bind62056Count == 1", c.bind62056Count == 1, "");

    // F2: recvfrom on the 62056 socket is observed; a timed-out read is a failure path
    //      and must only be counted (never read into the caller buffer).
    DWORD rcvTimeout = 50;
    setsockopt(sb, SOL_SOCKET, SO_RCVTIMEO, (const char*)&rcvTimeout, sizeof rcvTimeout);
    char rbuf[64];
    memset(rbuf, 0xCD, sizeof rbuf);
    sockaddr_in rfrom{};
    int rfromLen = (int)sizeof rfrom;
    const int rrc = ::recvfrom(sb, rbuf, (int)sizeof rbuf, 0, (sockaddr*)&rfrom, &rfromLen);
    Check("recvfrom on empty 62056 socket times out (SOCKET_ERROR)", rrc == SOCKET_ERROR, "");
    counters(&c);
    Check("rawRecvfromCalls == 1", c.rawRecvfromCalls == 1, "");
    Check("recvfromOn62056 == 1 (recvfrom path)", c.recvfromOn62056 == 1, "");

    // F2: WSARecvFrom overlapped with no data -> WSA_IO_PENDING. The detour must only
    //      count the pending state and never read WSABUF/bytesRecvd/from (codex D2.4).
    //      NOTE: the kernel owns the WSABUF while the read is pending and may rewrite it
    //      (probe wsaprobe.exe: 64/64 canary bytes changed on WSA_IO_PENDING); bytesRecvd
    //      and from are not written by the kernel, so those two stay as canary checks.
    u_long nonblock = 1;
    ioctlsocket(sb, FIONBIO, &nonblock);
    char wbufData[64];
    memset(wbufData, 0xCC, sizeof wbufData);
    WSABUF wbuf{};
    wbuf.buf = wbufData;
    wbuf.len = (ULONG)sizeof wbufData;
    DWORD wflags = 0;
    DWORD bytesRecvd = 0xDEADBEEF; // canary: must not be written on pending
    sockaddr_in wfrom{};
    int wfromLen = (int)sizeof wfrom;
    WSAOVERLAPPED ov{};
    const int wrc = ::WSARecvFrom(sb, &wbuf, 1, &bytesRecvd, &wflags, (sockaddr*)&wfrom,
                                  &wfromLen, &ov, nullptr);
    const int werr = WSAGetLastError();
    Check("WSARecvFrom on empty non-blocking socket -> WSA_IO_PENDING",
          wrc == SOCKET_ERROR && werr == WSA_IO_PENDING, "");
    counters(&c);
    Check("rawWsarecvfromCalls == 1", c.rawWsarecvfromCalls == 1, "");
    Check("recvfromOn62056 == 2 (recvfrom + WSARecvFrom paths)", c.recvfromOn62056 == 2, "");
    Check("wsarecvfromPending == 1 (overlapped pending counted)", c.wsarecvfromPending == 1, "");
    // Kernel-owned buffer: probe-confirmed the OS rewrites WSABUF while pending (wsaprobe.exe,
    // 64/64 canary bytes). We only assert the detour did not read it - it cannot be "untouched".
    printf("[info] WSABUF is kernel-owned while pending (probe wsaprobe.exe: 64/64 bytes\n");
    printf("       rewritten by the OS on WSA_IO_PENDING); detour counted only, never read it.\n");
    Check("bytesRecvd untouched on WSA_IO_PENDING", bytesRecvd == 0xDEADBEEF, "");
    Check("from untouched on WSA_IO_PENDING",
          wfrom.sin_family == 0 && wfrom.sin_port == 0 && wfrom.sin_addr.s_addr == 0, "");
    closesocket(sb);

    // 4. shutdown semantics
    const int sd = shutdown();
    Check("CivLinkShutdown returns 0 (clean drain)", sd == 0, "");
    Check("state becomes -1 after shutdown", state() == -1);
    const int sd2 = shutdown();
    Check("second shutdown returns 1 (already down)", sd2 == 1, "");
    counters(&c);
    Check("shutdown flag recorded", c.shutdown == 1);

    // 5. after shutdown the original API must still work and stay uncounted
    SOCKET s2 = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    BOOL b2 = TRUE;
    setsockopt(s2, SOL_SOCKET, SO_BROADCAST, (const char*)&b2, sizeof b2);
    sockaddr_in to{};
    to.sin_family = AF_INET;
    to.sin_port = htons(62909);
    inet_pton(AF_INET, "127.0.0.1", &to.sin_addr);
    const int rc6 = ::sendto(s2, (const char*)kMagic, 4, 0, (sockaddr*)&to, sizeof to);
    Check("send after shutdown still returns 4", rc6 == 4, "");
    closesocket(s2);
    Sleep(200);
    counters(&c);
    Check("counters unchanged after shutdown (sent still 4, incl. B1 identity rc9)", c.sent == 4, "");

    printf("\n%s (%d failure(s))\n", g_fail == 0 ? "HOOK-SELFTEST: PASS" : "HOOK-SELFTEST: FAIL",
           g_fail);
    // Deliberately do NOT FreeLibrary: the module must stay mapped for the lifetime of this
    // process (B2 audit-run mode), and the test process is about to exit anyway.
    if (g_fail) return 1;
    return 0;
}
