// CivLink M0-C C2 - civlink_client.dll self-test.
//
// The DLL pins the calling socket to one interface (IP_UNICAST_IF) before every
// discovery-family send, so the game's 255.255.255.255 discovery burst leaves through a
// chosen NIC instead of whatever InterfaceMetric happened to rank first.
//
// THIS TEST PROVES THE BOOKKEEPING LAYER ONLY.  It does not, and cannot, prove which
// physical adapter a datagram actually left through - that needs a second machine plus a
// capture on a second machine (design step 2/3).  The runner prints
// "Egress adapter: NOT VERIFIED" for exactly this reason; do not read a green run as a
// C2 verdict.
//
// Audit revision (M0C-C2-REVIEW.md, 2026-11-18):
//   B-3  every scenario now emits a machine-readable "counters: ..." line that the runner
//        parses, instead of the runner grepping our own PASS/FAIL prose (which had zero
//        discriminating power).
//   B-1  scenario C sends from a socket that is BOUND first - the only shape that matters
//        for a real client - and asserts sent == number of discovery sends.
//   M-2  scenarios D (explicit ALL), E (empty file), F (multi-line: first line wins).
//   M-3  scenario G (not a local address -> initError 12).
//   B-3  scenario H is the "can actually fail" assertion: an unusable interface index must
//        surface as sendFail > 0.  A DLL that never called setsockopt would fail this.
//   L-5  CivLinkSessionId is exported, non-zero and stable.
//
// One scenario per process: the DLL is loaded once and, once shut down, cannot come back
// into service (MinHook stays initialised by design - the B2 audit-run contract). So the
// runner starts the executable once per scenario instead of reloading in-process.

#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <windows.h>
#include <cstdio>
#include <cstring>
#include <string>

#include "../common/cvlh2.h"          // CIVLINK_DISCOVERY_PORT_FIRST/LAST
#include "../common/civlink_client.h" // DLL name + initError codes (pulls civlink_hook.h)

#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "iphlpapi.lib")

typedef int                (*F_State)(void);
typedef int                (*F_Reactivate)(void);
typedef int                (*F_Shutdown)(void);
typedef void               (*F_Counters)(CivLinkCounters*);
typedef unsigned long long (*F_SessionId)(void);

static int g_fail = 0;
static int g_checks = 0;

static void Check(const char* what, bool ok, const char* detail = "")
{
    g_checks++;
    printf("  %s %-58s %s\n", ok ? "PASS" : "FAIL", what, detail);
    if (!ok) g_fail++;
}

static const unsigned char kMagic[4] = { 0x8D, 0xE8, 0xFC, 0x70 };

struct Loaded {
    HMODULE h = nullptr;
    F_State state = nullptr;
    F_Reactivate reactivate = nullptr;
    F_Shutdown shutdown = nullptr;
    F_Counters counters = nullptr;
    F_SessionId sessionId = nullptr;

    bool Open(const std::string& dllPath)
    {
        h = LoadLibraryA(dllPath.c_str());
        if (!h) {
            printf("FATAL: LoadLibraryA(%s) failed err=%lu\n", dllPath.c_str(), GetLastError());
            return false;
        }
        state     = (F_State)GetProcAddress(h, "CivLinkHookState");
        reactivate = (F_Reactivate)GetProcAddress(h, "CivLinkReactivate");
        shutdown  = (F_Shutdown)GetProcAddress(h, "CivLinkShutdown");
        counters  = (F_Counters)GetProcAddress(h, "CivLinkGetCounters");
        sessionId = (F_SessionId)GetProcAddress(h, "CivLinkSessionId");
        if (!state || !shutdown || !counters || !sessionId) {
            printf("FATAL: required exports missing in %s\n", dllPath.c_str());
            return false;
        }
        return true;
    }

    // Waits for the init thread to reach state 1 (or a terminal initError).
    int WaitReady(CivLinkCounters* c, int tries = 100)
    {
        int st = 0;
        for (int i = 0; i < tries; i++) {
            st = state();
            if (st == 1) break;
            Sleep(50);
        }
        if (c) counters(c);
        return st;
    }
};

// Emits the line the runner parses.  Keep the shape stable: "counters:" then key=value.
static void EmitCounters(const CivLinkCounters& c)
{
    printf("counters: sent=%llu ignored=%llu sendFail=%llu initError=%llu bind62056=%llu "
           "sockOverflow=%llu scatterGather=%llu session=%llu\n",
           (unsigned long long)c.sent,
           (unsigned long long)c.ignoredNonDiscovery,
           (unsigned long long)c.sendFail,
           (unsigned long long)c.initError,
           (unsigned long long)c.bind62056Count,
           (unsigned long long)c.sockTableOverflow,
           (unsigned long long)c.scatterGather,
           (unsigned long long)c.sessionId);
}

static bool WriteCfg(const std::string& path, const char* text)
{
    FILE* f = nullptr;
    if (fopen_s(&f, path.c_str(), "w") != 0 || !f) {
        printf("FATAL: cannot write %s (errno=%d lastError=%lu)\n", path.c_str(), errno,
               (unsigned long)GetLastError());
        return false;
    }
    if (text && *text) fprintf(f, "%s", text);
    fclose(f);
    return true;
}

struct SendResult {
    int okCount = 0;
    int badCount = 0;
};

// Sends `nDiscovery` discovery magic datagrams and `nOrdinary` ordinary ones.
static SendResult Burst(SOCKET s, int nDiscovery, int nOrdinary)
{
    SendResult r{};
    sockaddr_in to{};
    to.sin_family = AF_INET;

    for (int i = 0; i < nDiscovery; i++) {
        inet_pton(AF_INET, "255.255.255.255", &to.sin_addr);
        to.sin_port = htons((unsigned short)(CIVLINK_DISCOVERY_PORT_FIRST + (i % 100)));
        const int rc = ::sendto(s, (const char*)kMagic, 4, 0, (sockaddr*)&to, sizeof to);
        if (rc == 4) r.okCount++; else r.badCount++;
    }
    for (int i = 0; i < nOrdinary; i++) {
        inet_pton(AF_INET, "127.0.0.1", &to.sin_addr);
        to.sin_port = htons((unsigned short)(50900 + i));
        const int rc = ::sendto(s, (const char*)kMagic, 4, 0, (sockaddr*)&to, sizeof to);
        if (rc == 4) r.okCount++; else r.badCount++;
    }
    return r;
}

// Binds the test socket first (the shape a real client socket has), then sends.
static SOCKET MakeBoundSocketOnPort(unsigned short port)
{
    SOCKET s = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (s == INVALID_SOCKET) return s;
    BOOL bcast = TRUE;
    setsockopt(s, SOL_SOCKET, SO_BROADCAST, (const char*)&bcast, sizeof bcast);
    sockaddr_in local{};
    local.sin_family = AF_INET;
    local.sin_addr.s_addr = htonl(INADDR_ANY);
    local.sin_port = htons(port);
    if (::bind(s, (sockaddr*)&local, sizeof local) != 0) {
        printf("FATAL: test socket bind failed err=%d (port=%u)\n", WSAGetLastError(), port);
        ::closesocket(s);
        return INVALID_SOCKET;
    }
    return s;
}

static SOCKET MakeBoundSocket() { return MakeBoundSocketOnPort(0); }

// REVIEW-2 discriminating probe.  Reads the IP_UNICAST_IF actually installed on a socket
// (host byte order; 0 = never set, 0xFFFFFFFF = getsockopt failed).  This is the assertion
// that answers "would a DLL that only increments c_sent, without calling setsockopt, still
// pass?": such a DLL leaves the socket option at 0, so the after-snapshot below stays 0 and
// C12 fails.  Verified on this host: set htonl(19) -> getsockopt returns 19 (host order).
static DWORD ReadIfIndex(SOCKET s)
{
    DWORD idx = 0;
    int len = sizeof(idx);
    if (::getsockopt(s, IPPROTO_IP, IP_UNICAST_IF, (char*)&idx, &len) != 0)
        return 0xFFFFFFFFu;
    return idx;
}

// Common tail: run the burst, read counters, emit the machine-readable line, shut down.
static void RunBurstAndEmit(Loaded& L, CivLinkCounters& c, int nDiscovery, int nOrdinary,
                            SendResult& out)
{
    SOCKET s = MakeBoundSocket();
    if (s == INVALID_SOCKET) { out = SendResult{}; out.badCount = -1; return; }
    out = Burst(s, nDiscovery, nOrdinary);
    Sleep(100);
    L.counters(&c);
    ::closesocket(s);
    EmitCounters(c);
}

// REVIEW-2 discriminating variant: snapshots IP_UNICAST_IF on the sending socket before and
// after the burst.  A DLL that only bumps c_sent (without calling setsockopt) leaves the
// option at 0 and fails the "ifAfter != 0" assertion appended by scenario C.
static void RunBurstWithIfProbe(Loaded& L, CivLinkCounters& c, int nDiscovery, int nOrdinary,
                                SendResult& out, DWORD& ifBefore, DWORD& ifAfter)
{
    SOCKET s = MakeBoundSocket();
    if (s == INVALID_SOCKET) {
        out = SendResult{}; out.badCount = -1; ifBefore = ifAfter = 0xFFFFFFFFu; return;
    }
    ifBefore = ReadIfIndex(s);
    out = Burst(s, nDiscovery, nOrdinary);
    Sleep(100);
    ifAfter = ReadIfIndex(s);
    L.counters(&c);
    ::closesocket(s);
    EmitCounters(c);
}

// Scenario A: no config file at all -> ALL mode, pins nothing.
static int RunAllMode(const std::string& dllPath, const std::string& scratch)
{
    const std::string cfg = scratch + "\\c2-cfg-absent.txt";
    DeleteFileA(cfg.c_str());
    SetEnvironmentVariableA("CIVLINK_CLIENT_IFACE_FILE", cfg.c_str());

    Loaded L;
    if (!L.Open(dllPath)) return 2;
    CivLinkCounters c{};
    const int st = L.WaitReady(&c);
    Check("A1 module reaches state 1", st == 1);
    Check("A2 initError == 0 (missing config = ALL)", c.initError == 0);
    Check("A3 session id non-zero", c.sessionId != 0);
    Check("A4 CivLinkSessionId agrees with the counter block",
          L.sessionId() == c.sessionId, "");

    SendResult r{};
    RunBurstAndEmit(L, c, 5, 3, r);
    Check("A5 all 8 sends returned 4 bytes", r.okCount == 8 && r.badCount == 0);
    Check("A6 sent == 0 (ALL pins nothing)", c.sent == 0);
    Check("A7 ignoredNonDiscovery == 8 (counted, never pinned)", c.ignoredNonDiscovery == 8);
    Check("A8 sendFail == 0", c.sendFail == 0);
    Check("A9 shutdown returns 0 (clean drain)", L.shutdown() == 0);
    return 0;
}

// Scenario B: unparsable config -> initError 11, degrades to ALL, still functional.
static int RunInvalidConfig(const std::string& dllPath, const std::string& scratch)
{
    const std::string cfg = scratch + "\\c2-cfg-bad.txt";
    if (!WriteCfg(cfg, "not-an-ip\n")) return 2;
    SetEnvironmentVariableA("CIVLINK_CLIENT_IFACE_FILE", cfg.c_str());

    Loaded L;
    if (!L.Open(dllPath)) return 2;
    CivLinkCounters c{};
    const int st = L.WaitReady(&c);
    Check("B1 module still reaches state 1 (fail-open)", st == 1);
    Check("B2 initError == 11 (config invalid)", c.initError == CIVLINK_INITERR_CONFIG_INVALID);

    SendResult r{};
    RunBurstAndEmit(L, c, 5, 3, r);
    Check("B3 all 8 sends returned 4 bytes", r.okCount == 8 && r.badCount == 0);
    Check("B4 sent == 0 (degraded to ALL)", c.sent == 0);
    Check("B5 ignoredNonDiscovery == 8", c.ignoredNonDiscovery == 8);
    Check("B6 shutdown returns 0", L.shutdown() == 0);
    return 0;
}

// Scenario C: a resolvable local address, socket bound first -> every discovery send is
// pinned, `sent` tracks those sends, ordinary sends stay untouched.
static int RunPinned(const std::string& dllPath, const std::string& scratch)
{
    const std::string cfg = scratch + "\\c2-cfg-pinned.txt";
    if (!WriteCfg(cfg, "127.0.0.1\n")) return 2;
    SetEnvironmentVariableA("CIVLINK_CLIENT_IFACE_FILE", cfg.c_str());

    Loaded L;
    if (!L.Open(dllPath)) return 2;
    CivLinkCounters c{};
    const int st = L.WaitReady(&c);
    Check("C1 module reaches state 1", st == 1);
    Check("C2 initError == 0 (config accepted)", c.initError == 0);

    const int kDiscovery = 10;
    const int kOrdinary = 4;
    SendResult r{};
    DWORD ifBefore = 0, ifAfter = 0;
    RunBurstWithIfProbe(L, c, kDiscovery, kOrdinary, r, ifBefore, ifAfter);
    printf("ifprobe: before=%lu after=%lu\n", ifBefore, ifAfter);

    Check("C3 all 14 sends returned 4 bytes", r.okCount == 14 && r.badCount == 0);
    Check("C4 sent == 10 (one per discovery send from a BOUND socket)",
          c.sent == (unsigned long long)kDiscovery);
    Check("C5 ignoredNonDiscovery == 4 (ordinary sends untouched)",
          c.ignoredNonDiscovery == (unsigned long long)kOrdinary);
    Check("C6 sendFail == 0 (setsockopt accepted the index)", c.sendFail == 0);
    Check("C7 non-C2 counters stay 0 (rejectOversize/observedFrames/cvlh2)",
          c.rejectOversize == 0 && c.observedFrames == 0 && c.cvlh2Try == 0);
    Check("C8 no 62056 socket was bound by the DLL", c.bind62056Count == 0);
    Check("C9 shutdown returns 0 (clean drain)", L.shutdown() == 0);
    Check("C10 second shutdown reports already-down (1)", L.shutdown() == 1);
    // REVIEW-2 discriminating assertions: the socket's IP_UNICAST_IF option must actually
    // have been installed by the DLL.  A DLL that only increments c_sent leaves it at 0.
    Check("C11 IP_UNICAST_IF was unset before the burst", ifBefore == 0);
    Check("C12 IP_UNICAST_IF installed on the socket after the burst (real setsockopt)",
          ifAfter != 0 && ifAfter != 0xFFFFFFFFu);
    return 0;
}

// Scenario D: explicit "ALL" in the config -> ALL mode, initError 0, nothing pinned.
static int RunExplicitAll(const std::string& dllPath, const std::string& scratch)
{
    const std::string cfg = scratch + "\\c2-cfg-explicit-all.txt";
    if (!WriteCfg(cfg, "ALL\n")) return 2;
    SetEnvironmentVariableA("CIVLINK_CLIENT_IFACE_FILE", cfg.c_str());

    Loaded L;
    if (!L.Open(dllPath)) return 2;
    CivLinkCounters c{};
    const int st = L.WaitReady(&c);
    Check("D1 module reaches state 1", st == 1);
    Check("D2 initError == 0 (explicit ALL is valid)", c.initError == 0);

    SendResult r{};
    RunBurstAndEmit(L, c, 5, 3, r);
    Check("D3 all 8 sends returned 4 bytes", r.okCount == 8 && r.badCount == 0);
    Check("D4 sent == 0 (explicit ALL)", c.sent == 0);
    Check("D5 ignoredNonDiscovery == 8", c.ignoredNonDiscovery == 8);
    Check("D6 shutdown returns 0", L.shutdown() == 0);
    return 0;
}

// Scenario E: empty config file -> treated as ALL, no initError.
static int RunEmptyFile(const std::string& dllPath, const std::string& scratch)
{
    const std::string cfg = scratch + "\\c2-cfg-empty.txt";
    if (!WriteCfg(cfg, "")) return 2;
    SetEnvironmentVariableA("CIVLINK_CLIENT_IFACE_FILE", cfg.c_str());

    Loaded L;
    if (!L.Open(dllPath)) return 2;
    CivLinkCounters c{};
    const int st = L.WaitReady(&c);
    Check("E1 module reaches state 1", st == 1);
    Check("E2 initError == 0 (empty file = ALL)", c.initError == 0);

    SendResult r{};
    RunBurstAndEmit(L, c, 5, 3, r);
    Check("E3 all 8 sends returned 4 bytes", r.okCount == 8 && r.badCount == 0);
    Check("E4 sent == 0 (empty file)", c.sent == 0);
    Check("E5 ignoredNonDiscovery == 8", c.ignoredNonDiscovery == 8);
    Check("E6 shutdown returns 0", L.shutdown() == 0);
    return 0;
}

// Scenario F: multi-line file -> the first line is authoritative, later lines ignored.
static int RunMultiLine(const std::string& dllPath, const std::string& scratch)
{
    const std::string cfg = scratch + "\\c2-cfg-multiline.txt";
    if (!WriteCfg(cfg, "127.0.0.1\nthis second line must be ignored\n")) return 2;
    SetEnvironmentVariableA("CIVLINK_CLIENT_IFACE_FILE", cfg.c_str());

    Loaded L;
    if (!L.Open(dllPath)) return 2;
    CivLinkCounters c{};
    const int st = L.WaitReady(&c);
    Check("F1 module reaches state 1", st == 1);
    Check("F2 initError == 0 (first line accepted, rest ignored)", c.initError == 0);

    SendResult r{};
    RunBurstAndEmit(L, c, 6, 2, r);
    Check("F3 all 8 sends returned 4 bytes", r.okCount == 8 && r.badCount == 0);
    Check("F4 sent == 6 (pinned mode active, not degraded to ALL)", c.sent == 6);
    Check("F5 ignoredNonDiscovery == 2", c.ignoredNonDiscovery == 2);
    Check("F6 sendFail == 0", c.sendFail == 0);
    Check("F7 shutdown returns 0", L.shutdown() == 0);
    return 0;
}

// Scenario G: a syntactically valid IPv4 that is not on this host -> initError 12.
static int RunNonLocal(const std::string& dllPath, const std::string& scratch)
{
    const std::string cfg = scratch + "\\c2-cfg-nonlocal.txt";
    if (!WriteCfg(cfg, "192.168.99.99\n")) return 2;
    SetEnvironmentVariableA("CIVLINK_CLIENT_IFACE_FILE", cfg.c_str());

    Loaded L;
    if (!L.Open(dllPath)) return 2;
    CivLinkCounters c{};
    const int st = L.WaitReady(&c);
    Check("G1 module still reaches state 1 (fail-open)", st == 1);
    Check("G2 initError == 12 (interface unavailable)",
          c.initError == CIVLINK_INITERR_IFACE_UNAVAIL);

    SendResult r{};
    RunBurstAndEmit(L, c, 5, 3, r);
    Check("G3 all 8 sends returned 4 bytes (no packet dropped)", r.okCount == 8 && r.badCount == 0);
    Check("G4 sent == 0 (degraded to ALL)", c.sent == 0);
    Check("G5 shutdown returns 0", L.shutdown() == 0);
    return 0;
}

// Scenario H: the diagnostic IFINDEX token, used to find out whether an interface index that
// cannot exist is actually rejected by the stack.
//
// REVIEW FINDING (recorded because it contradicts the audit's proposed remedy): on this
// Windows build setsockopt(IP_UNICAST_IF) ACCEPTS an out-of-range index and returns 0, and
// broadcasts are routed regardless of the option, so the sends still succeed.  So this
// scenario cannot serve as the "assertion that can fail" the review asked for; it is kept as
// an observation scenario and the discriminating counter is scenario I (slot overflow).
static int RunBadIfIndex(const std::string& dllPath, const std::string& scratch)
{
    const std::string cfg = scratch + "\\c2-cfg-badifindex.txt";
    if (!WriteCfg(cfg, "IFINDEX:2147483647\n")) return 2;
    SetEnvironmentVariableA("CIVLINK_CLIENT_IFACE_FILE", cfg.c_str());

    Loaded L;
    if (!L.Open(dllPath)) return 2;
    CivLinkCounters c{};
    const int st = L.WaitReady(&c);
    Check("H1 module reaches state 1", st == 1);
    Check("H2 initError == 0 (IFINDEX token parses)", c.initError == 0);

    SendResult r{};
    RunBurstAndEmit(L, c, 5, 3, r);
    Check("H3 all 8 sends still returned 4 bytes (fail-open, no drop)", r.okCount == 8 && r.badCount == 0);
    // Observed behaviour on Windows: the stack accepts the impossible index, so every
    // discovery send is accounted either way.  We assert the ACCOUNTING, not a failure.
    Check("H4 every discovery send is accounted (sent + sendFail == 5)",
          (c.sent + c.sendFail) == 5);
    Check("H5 the game's data path was untouched (no 62056 bind, nothing dropped)",
          c.bind62056Count == 0 && r.okCount == 8);
    Check("H6 shutdown returns 0", L.shutdown() == 0);
    return 0;
}

// Scenario I: the assertion that CAN fail.  The slot table holds 64 sockets; binding more
// than that must surface as sockTableOverflow > 0 (audit M-1: it was hardcoded to 0).  A DLL
// that only printed numbers, or one that forgot to count, reports 0 here and fails.
static int RunSlotOverflow(const std::string& dllPath, const std::string& scratch)
{
    const std::string cfg = scratch + "\\c2-cfg-overflow.txt";
    if (!WriteCfg(cfg, "ALL\n")) return 2;
    SetEnvironmentVariableA("CIVLINK_CLIENT_IFACE_FILE", cfg.c_str());

    Loaded L;
    if (!L.Open(dllPath)) return 2;
    CivLinkCounters c{};
    const int st = L.WaitReady(&c);
    Check("I1 module reaches state 1", st == 1);

    const int kSockets = 80; // > the DLL's 64-slot table
    SOCKET socks[kSockets];
    int bound = 0;
    // Bind each socket to an EXPLICIT non-zero port: the DLL only tracks sockets it saw bind
    // with a real port (port 0 is skipped on purpose, so an implicit-bind socket is not
    // assigned a slot it never asked for).
    for (int i = 0; i < kSockets; i++) {
        socks[i] = MakeBoundSocketOnPort((unsigned short)(38000 + i));
        if (socks[i] != INVALID_SOCKET) bound++;
    }
    Sleep(150);
    L.counters(&c);
    for (int i = 0; i < kSockets; i++)
        if (socks[i] != INVALID_SOCKET) ::closesocket(socks[i]);
    EmitCounters(c);

    Check("I2 the test really opened more sockets than the table can hold",
          bound == kSockets);
    Check("I3 sockTableOverflow > 0 (a full table is counted, not silent)",
          c.sockTableOverflow > 0);
    Check("I4 at least 64 sockets were tracked before the first overflow",
          c.rawBindCalls >= 64);
    Check("I5 shutdown returns 0", L.shutdown() == 0);
    return 0;
}

// Scenario J: the NIC-switch reactivation path (the fix for "uninject -> change NIC ->
// inject again" failing with exit 5). Load PIN mode, shut down, rewrite the config to
// ALL, then call CivLinkReactivate in place: state must return to 1, hooks re-enabled,
// config re-read (proved by sent staying 0 afterwards instead of continuing to pin).
static int RunReactivate(const std::string& dllPath, const std::string& scratch)
{
    const std::string cfg = scratch + "\\c2-cfg-reactivate.txt";
    if (!WriteCfg(cfg, "127.0.0.1\n")) return 2;   // start PINNED
    SetEnvironmentVariableA("CIVLINK_CLIENT_IFACE_FILE", cfg.c_str());

    Loaded L;
    if (!L.Open(dllPath)) return 2;
    if (!L.reactivate) {
        printf("FATAL: CivLinkReactivate export missing\n");
        return 2;
    }
    CivLinkCounters c{};
    Check("J1 module reaches state 1 (initial PIN load)", L.WaitReady(&c) == 1);
    L.counters(&c);
    Check("J2 initial mode is PIN (initError 0)", c.initError == 0);

    // Prove PIN is active before shutdown: a discovery send gets counted.
    SendResult r1{};
    RunBurstAndEmit(L, c, 3, 0, r1);
    Check("J3 discovery sends pinned before shutdown (sent==3)", c.sent == 3);

    Check("J4 shutdown returns 0", L.shutdown() == 0);
    CivLinkCounters cd{};
    L.counters(&cd);
    Check("J5 state is shut down after CivLinkShutdown", cd.shutdown == 1 && cd.running == 0);

    // Operator switches NIC: rewrite config to ALL while the module stays mapped.
    if (!WriteCfg(cfg, "ALL\n")) return 2;

    int rr = L.reactivate();
    Check("J6 CivLinkReactivate returns 0 (re-activated in place)", rr == 0);
    CivLinkCounters cr{};
    L.counters(&cr);
    Check("J7 state back to running after reactivation", cr.running == 1 && cr.shutdown == 0);
    Check("J8 initError cleared on reactivation", cr.initError == 0);

    // The decisive assertion: config was RE-READ. If LoadConfig did not run again the
    // module would still be PINned and these discovery sends would bump `sent`; after
    // switching to ALL, sent must NOT increase.
    const unsigned long long sentBefore = cr.sent;
    SendResult r2{};
    RunBurstAndEmit(L, cr, 3, 0, r2);
    Check("J9 config re-read: switched to ALL, discovery sends NOT pinned (sent unchanged)",
          cr.sent == sentBefore);
    Check("J10 sends still succeed after reactivation", r2.okCount == 3 && r2.badCount == 0);
    Check("J11 second reactivate reports already-running (1)", L.reactivate() == 1);
    Check("J12 final shutdown clean", L.shutdown() == 0);
    return 0;
}

int main(int argc, char** argv)
{
    // argv[1] = directory holding civlink_client.dll (default: this exe's directory)
    // argv[2] = scratch directory for scenario config files
    // argv[3] = scenario: A | B | C | D | E | F | G | H (default A)
    char here[MAX_PATH]{};
    GetModuleFileNameA(nullptr, here, MAX_PATH);
    char* slash = strrchr(here, '\\');
    if (slash) *slash = '\0';
    const std::string dllDir = (argc > 1) ? argv[1] : here;
    const std::string scratch = (argc > 2) ? argv[2] : here;
    const char scenario = (argc > 3 && argv[3][0]) ? argv[3][0] : 'A';

    printf("civlink client (C2) self-test - scenario %c\n", scenario);

    WSADATA wsa{};
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
        printf("FATAL: WSAStartup failed\n");
        return 2;
    }

    const std::string dllPath = dllDir + "\\" CIVLINK_CLIENT_DLL_NAME_A;
    int rc = 2;
    switch (scenario) {
    case 'A': case 'a': rc = RunAllMode(dllPath, scratch); break;
    case 'B': case 'b': rc = RunInvalidConfig(dllPath, scratch); break;
    case 'C': case 'c': rc = RunPinned(dllPath, scratch); break;
    case 'D': case 'd': rc = RunExplicitAll(dllPath, scratch); break;
    case 'E': case 'e': rc = RunEmptyFile(dllPath, scratch); break;
    case 'F': case 'f': rc = RunMultiLine(dllPath, scratch); break;
    case 'G': case 'g': rc = RunNonLocal(dllPath, scratch); break;
    case 'H': case 'h': rc = RunBadIfIndex(dllPath, scratch); break;
    case 'I': case 'i': rc = RunSlotOverflow(dllPath, scratch); break;
    case 'J': case 'j': rc = RunReactivate(dllPath, scratch); break;
    default:
        printf("FATAL: unknown scenario '%c' (use A..J)\n", scenario);
        WSACleanup();
        return 2;
    }

    WSACleanup();
    printf("checks: %d failed=%d\n", g_checks, g_fail);
    printf("NOTE: bookkeeping only - the actual egress adapter is NOT verified here\n");
    printf("      (needs a second machine + capture, see M0C-C2-DESIGN-20261118.md 3.3)\n");
    if (rc != 0) return rc;
    return g_fail ? 1 : 0;
}
