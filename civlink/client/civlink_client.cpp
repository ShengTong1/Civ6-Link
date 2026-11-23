// civlink_client.cpp - CivLink M0-C C2 client-side NIC-pinning Hook DLL.
//
// Purpose (user request m26492 / confirmed m26578): when injected into the game on the
// client (non-host) machine, pin the discovery broadcasts (255.255.255.255:62900-62999)
// to a user-chosen NIC so the broadcast leaves the machine on the interface the host can
// actually hear (e.g. WLAN instead of a mesh-VPN adapter that has the lowest metric).
//
// Plan B (primary): per-send setsockopt
// IP_UNICAST_IF (level 31) with the interface index in network byte order, Vista+.
// Plan C (fallback, only if B is proven ineffective on the real two-machine test):
// broadcast copy-and-forward on every interface; NOT implemented in this increment.
// The DLL reads one config line at InitThread time from
// %LOCALAPPDATA%\CivLink\client-iface.txt ("ALL" or a dotted IPv4 address); the civlink_ctl
// inject-client subcommand writes it before injecting.
//
// Audit revision (M0C-C2-REVIEW.md, 2026-11-18) - what changed and why:
//   * B-1/B-3 + M-6: the per-socket "pinned once" flag is GONE.  The option is now set on
//     every discovery send (idempotent, ~1 us).  Reason: the flag could never be stored for
//     a socket that never called bind (the slot table only created entries in Hook_bind), so
//     `sent` silently meant "setsockopt calls" for unbound sockets and "1" for bound ones -
//     a split semantics that would have failed the real-game expectation.  Per-send pinning
//     also removes the "set before the implicit bind, may be cleared by it" timing risk
//     (review M-6), which this build cannot exclude with single-machine evidence.
//     `sent` is therefore defined as: discovery sends whose setsockopt(IP_UNICAST_IF) was
//     accepted by the stack (== discovery sends when pinning works).
//   * B-2: PinSend saves WSAGetLastError() before setsockopt and restores it afterwards, so
//     a pin failure can never leak a bogus error code into an application whose send
//     actually succeeded ("same last error" hard constraint).
//   * H-1: every detour now keeps the real call INSIDE the g_inFlight window, so
//     CivLinkShutdown's drain really covers the original send/bind/close call.
//   * H-2: overlapped WSASendTo is pinned too (setsockopt is orthogonal to sync/async);
//     the old "!ov" exclusion silently left async discovery sends unpinned.
//   * M-1/M-5: sockTableOverflow and scatterGather are real counters now, not hardcoded 0.
//
// Diagnostic config token (self-test / support only, documented in design 5.1):
//   "IFINDEX:<n>" pins by raw interface index instead of by IPv4 address.  It exists so the
//   self-test can prove that an unusable index is observable (counted in sendFail) instead
//   of silently "working".  Normal deployments never use it.
//
// Discipline (same as hook.cpp, kept): every detour is pure pass-through - same arguments,
// same original return value, same last error; the only modification is the optional
// IP_UNICAST_IF option on discovery-targeted sends when the config pins an interface.
// No payload is read, copied, altered, forwarded or duplicated anywhere in this DLL
// (no ForwardFrame, no IPC, no cvlh2 - this DLL never talks to the Agent).
//
// Export contract is identical in shape to civlink_hook.dll so civlink_ctl works on both:
// CivLinkHookState / CivLinkShutdown / CivLinkGetCounters / CivLinkSessionId, plus the
// same CivLinkCounters POD (magic "COUKVL", version 2).  initError adds codes 11/12.
//
// Shutdown semantics (B2 audit-run mode): hooks are disabled and drained, the module is
// left mapped until the process exits; the caller must never FreeLibrary a live process.
// Include order matters: winsock2.h must come before windows.h (windows.h would pull in
// winsock.h and every later winsock2/ws2ipdef declaration then collides).
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <ws2ipdef.h>
#include <windows.h>
#include <iphlpapi.h>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "civlink_client.h"
#include "cvlh2.h" // CIVLINK_DISCOVERY_PORT_FIRST/LAST, CIVLINK_DATAPATH_PORT (macros only)
#include "MinHook.h"

#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "iphlpapi.lib")

namespace {

// ---------------------------------------------------------------- globals
std::atomic<int> g_state{0};          // 0 init / 1 running / -1 shutdown
std::atomic<int> g_reactivating{0};   // 0 idle / 1 reactivation in progress (no double-enable)
std::atomic<int> g_inFlight{0};
std::atomic<unsigned long long> g_sessionId{0};
std::atomic<unsigned long> c_sent{0};           // discovery sends pinned (setsockopt accepted)
std::atomic<unsigned long> c_sendFail{0};       // setsockopt failed (send still passed through)
std::atomic<unsigned long> c_ignoredNonDiscovery{0}; // sends not pinned (non-discovery/state off)
std::atomic<unsigned long> c_rawSendto{0};
std::atomic<unsigned long> c_rawWsasendto{0};
std::atomic<unsigned long> c_rawBind{0};
std::atomic<unsigned long> c_rawRecvfrom{0};
std::atomic<unsigned long> c_rawWsarecvfrom{0};
std::atomic<unsigned long> c_bind62056{0};
std::atomic<unsigned long> c_recvfrom62056{0};
std::atomic<unsigned long> c_wsarecvfromPending{0};
std::atomic<unsigned long> c_stateQueries{0};
std::atomic<unsigned long> c_shutdownLeft{0};
std::atomic<unsigned long> c_initError{0};
std::atomic<unsigned long> c_sockOverflow{0};   // slot table full (M-1: real counter now)
std::atomic<unsigned long> c_scatterGather{0};  // WSASendTo with >1 buffer (M-5)

// ---------------------------------------------------------------- config / interface
enum class Mode { ALL, PIN };
Mode g_mode = Mode::ALL;
unsigned long g_pinIfIndex = 0; // host-order interface index for IP_UNICAST_IF

// Builds the config path: CIVLINK_CLIENT_IFACE_FILE (absolute path override, used by the
// self-test and by portable installs) else %LOCALAPPDATA%\CivLink\client-iface.txt.
// Returns false when no usable path can be formed.
static bool BuildConfigPath(std::string& out)
{
    char buf[MAX_PATH] = {0};
    const UINT n = GetEnvironmentVariableA("CIVLINK_CLIENT_IFACE_FILE", buf, sizeof buf);
    if (n > 0 && n < sizeof buf) {
        out.assign(buf);
        return true;
    }
    const UINT m = GetEnvironmentVariableA("LOCALAPPDATA", buf, sizeof buf);
    if (m == 0 || m >= sizeof buf) return false; // no LOCALAPPDATA: default ALL
    out.assign(buf);
    out += "\\";
    out += CIVLINK_IFACE_CONFIG_REL;
    return true;
}

// Reads the client-iface config; returns initError (0 ok, 11 invalid, 12 unavailable) but
// ALWAYS leaves a usable mode (invalid -> ALL, fail-open).
unsigned long LoadConfig()
{
    // Reactivation path (NIC switched since first load): reset to the fail-open default
    // FIRST so that switching PIN -> ALL / a different IP never leaves a stale mode or
    // interface index behind. A successful PIN parse below overwrites these again.
    g_mode = Mode::ALL;
    g_pinIfIndex = 0;

    std::string path;
    if (!BuildConfigPath(path)) return 0; // no config location: ALL
    FILE* f = nullptr;
    if (fopen_s(&f, path.c_str(), "r") != 0 || !f) return 0; // missing file: ALL
    char line[64] = {0};
    const bool got = fgets(line, sizeof line, f) != nullptr;
    fclose(f);
    if (!got) return 0; // empty: ALL

    // strip trailing CR/LF/space
    char* e = line + strlen(line);
    while (e > line && (e[-1] == '\r' || e[-1] == '\n' || e[-1] == ' ' || e[-1] == '\t')) e--;
    *e = 0;
    if (line[0] == 0) return 0;
    if (_stricmp(line, "ALL") == 0) return 0;

    // Diagnostic token (self-test only): "IFINDEX:<decimal>" pins by raw interface index.
    // Lets the self-test drive an unusable index and prove the failure is observable
    // (counted in sendFail) instead of silently "succeeding" as a bookkeeping-only pass.
    if (_strnicmp(line, "IFINDEX:", 8) == 0) {
        char* endp = nullptr;
        const unsigned long idx = strtoul(line + 8, &endp, 10);
        if (!endp || *endp != 0 || idx == 0) return CIVLINK_INITERR_CONFIG_INVALID;
        g_pinIfIndex = idx;
        g_mode = Mode::PIN;
        return 0;
    }

    // dotted IPv4: must match a currently-up local interface
    IN_ADDR addr{};
    if (inet_pton(AF_INET, line, &addr) != 1)
        return CIVLINK_INITERR_CONFIG_INVALID;

    // resolve host-order ifindex for the address (GetAdaptersAddresses retry loop)
    ULONG size = 15 * 1024;
    PIP_ADAPTER_ADDRESSES aa = nullptr;
    for (int attempt = 0; attempt < 3; attempt++) {
        aa = (PIP_ADAPTER_ADDRESSES)malloc(size);
        if (!aa) break;
        const DWORD rc = GetAdaptersAddresses(AF_INET, 0, nullptr, aa, &size);
        if (rc == ERROR_BUFFER_OVERFLOW) { free(aa); aa = nullptr; continue; }
        if (rc != NO_ERROR) { free(aa); aa = nullptr; break; }
        break;
    }
    if (!aa) return CIVLINK_INITERR_IFACE_UNAVAIL;

    unsigned long foundIndex = 0;
    bool foundUp = false;
    for (PIP_ADAPTER_ADDRESSES a = aa; a; a = a->Next) {
        if (a->OperStatus != IfOperStatusUp) continue;
        for (PIP_ADAPTER_UNICAST_ADDRESS u = a->FirstUnicastAddress; u; u = u->Next) {
            const SOCKET_ADDRESS* sa = &u->Address;
            if (sa->lpSockaddr->sa_family != AF_INET) continue;
            const sockaddr_in* sin = (const sockaddr_in*)sa->lpSockaddr;
            if (sin->sin_addr.S_un.S_addr == addr.S_un.S_addr) {
                foundIndex = a->IfIndex;
                foundUp = true;
                break;
            }
        }
        if (foundUp) break;
    }
    free(aa);
    if (!foundUp) return CIVLINK_INITERR_IFACE_UNAVAIL;

    g_pinIfIndex = foundIndex;
    g_mode = Mode::PIN;
    return 0;
}

// ---------------------------------------------------------------- socket slots
// Slot table mirrors hook.cpp: maps SOCKET -> bound-port, guarded by a single SRW lock.
// Audit revision B-1: the per-socket "pinned" bit was removed.  It could not be stored for
// sockets that never bind (slots were only created in Hook_bind), which made `sent` mean
// "setsockopt calls" for unbound sockets and "1" for bound ones; and pinning per send is
// both idempotent and free of the "does bind reset the option?" timing risk (M-6).
struct Slot {
    SOCKET s = INVALID_SOCKET;
    uint16_t portBe = 0;
};
Slot g_slots[64];
SRWLOCK g_slotLock = SRWLOCK_INIT;

Slot* FindSlot(SOCKET s)
{
    for (int i = 0; i < 64; i++)
        if (g_slots[i].s == s) return &g_slots[i];
    return nullptr;
}

// M-1: a full table is no longer silent - it is counted in sockTableOverflow, which is
// exported as a real counter (the review found it hardcoded to 0 while the design defined
// it as "slot table exhausted").
Slot* FindOrCreateSlot(SOCKET s)
{
    AcquireSRWLockExclusive(&g_slotLock);
    Slot* sl = FindSlot(s);
    if (!sl) {
        for (int i = 0; i < 64; i++) {
            if (g_slots[i].s == INVALID_SOCKET) { g_slots[i].s = s; sl = &g_slots[i]; break; }
        }
    }
    ReleaseSRWLockExclusive(&g_slotLock);
    if (!sl) c_sockOverflow.fetch_add(1, std::memory_order_relaxed);
    return sl; // may be null when the table is full (64)
}

void SlotSetBoundPort(SOCKET s, uint16_t portBe)
{
    AcquireSRWLockExclusive(&g_slotLock);
    Slot* sl = FindSlot(s);
    if (sl) sl->portBe = portBe;
    ReleaseSRWLockExclusive(&g_slotLock);
}

uint16_t SlotBoundPort(SOCKET s)
{
    AcquireSRWLockShared(&g_slotLock);
    const Slot* sl = FindSlot(s);
    const uint16_t p = sl ? sl->portBe : 0;
    ReleaseSRWLockShared(&g_slotLock);
    return p;
}

void ForgetSocket(SOCKET s)
{
    AcquireSRWLockExclusive(&g_slotLock);
    Slot* sl = FindSlot(s);
    if (sl) { sl->s = INVALID_SOCKET; sl->portBe = 0; }
    ReleaseSRWLockExclusive(&g_slotLock);
}

// ---------------------------------------------------------------- discovery target
// Same rule as hook.cpp IsDiscoveryTarget: a send counts as a discovery send when the
// destination port is 62900-62999 or the destination is the limited broadcast address.
// (The socket-identity rule from B1 §0 - a socket that once bound 62900-62999 - is NOT
// needed here: the client never owns the host discovery socket, it only sends to it.)
bool IsDiscoveryTarget(const sockaddr_in* sin)
{
    if (sin->sin_family != AF_INET) return false;
    const unsigned port = ntohs(sin->sin_port);
    if (port >= CIVLINK_DISCOVERY_PORT_FIRST && port <= CIVLINK_DISCOVERY_PORT_LAST) return true;
    if (sin->sin_addr.S_un.S_addr == INADDR_BROADCAST) return true;
    return false;
}

// ---------------------------------------------------------------- detours
static int (WSAAPI* Real_sendto)(SOCKET, const char*, int, int, const struct sockaddr*, int) = nullptr;
static int (WSAAPI* Real_WSASendTo)(SOCKET, LPWSABUF, DWORD, LPDWORD, DWORD,
                                     const struct sockaddr*, int,
                                     LPWSAOVERLAPPED, LPWSAOVERLAPPED_COMPLETION_ROUTINE) = nullptr;
static int (WSAAPI* Real_closesocket)(SOCKET) = nullptr;
static int (WSAAPI* Real_bind)(SOCKET, const struct sockaddr*, int) = nullptr;
static int (WSAAPI* Real_recvfrom)(SOCKET, char*, int, int, struct sockaddr*, int*) = nullptr;
static int (WSAAPI* Real_WSARecvFrom)(SOCKET, LPWSABUF, DWORD, LPDWORD, LPDWORD,
                                       struct sockaddr*, LPINT,
                                       LPWSAOVERLAPPED, LPWSAOVERLAPPED_COMPLETION_ROUTINE) = nullptr;

// __declspec(thread) guard against re-entry; static (not atomic) like hook.cpp - a detour
// may only be re-entered by an original call it itself made, and the thread guard covers it.
static __declspec(thread) bool tlsInHook = false;

// Pins one send on a discovery socket to the configured interface.  Pure side-effect: the
// original send call afterwards is untouched.  Fails open - a setsockopt error is counted
// but never blocks the game's send.
//
// Audit revision B-2: the thread's last error is saved before setsockopt and restored after
// it, on BOTH paths.  Without this, a failed pin would leave WSAEINVAL/WSAENOTSOCK behind
// and the application would read it after a sendto that actually succeeded - an observable
// behaviour difference from an un-hooked process ("same last error" is a hard constraint).
//
// Audit revision B-1: no per-socket flag any more.  The option is set on every discovery
// send: idempotent, ~1 us, and it necessarily lands after any implicit bind.  `sent` counts
// discovery sends whose setsockopt the stack accepted.
static void PinSend(SOCKET s)
{
    if (g_mode != Mode::PIN) { c_ignoredNonDiscovery.fetch_add(1, std::memory_order_relaxed); return; }
    const int savedErr = WSAGetLastError();
    DWORD beIdx = htonl(g_pinIfIndex);
    const int rc = setsockopt(s, IPPROTO_IP, IP_UNICAST_IF, (const char*)&beIdx, sizeof beIdx);
    WSASetLastError(savedErr);
    if (rc == 0)
        c_sent.fetch_add(1, std::memory_order_relaxed);
    else
        c_sendFail.fetch_add(1, std::memory_order_relaxed);
}

static int WSAAPI Hook_sendto(SOCKET s, const char* buf, int len, int flags,
                              const struct sockaddr* to, int tolen)
{
    g_inFlight.fetch_add(1, std::memory_order_relaxed);
    if (tlsInHook) {
        const int rc = Real_sendto(s, buf, len, flags, to, tolen);
        g_inFlight.fetch_sub(1, std::memory_order_relaxed);
        return rc;
    }
    tlsInHook = true;
    c_rawSendto.fetch_add(1, std::memory_order_relaxed);
    if (g_state.load() == 1 && to && tolen >= (int)sizeof(sockaddr_in) &&
        IsDiscoveryTarget((const sockaddr_in*)to))
        PinSend(s);
    else
        c_ignoredNonDiscovery.fetch_add(1, std::memory_order_relaxed);
    // H-1: the real call stays inside the in-flight window so CivLinkShutdown's drain
    // actually covers it (a trampoline must not be disabled while this thread is using it).
    const int rc = Real_sendto(s, buf, len, flags, to, tolen);
    tlsInHook = false;
    g_inFlight.fetch_sub(1, std::memory_order_relaxed);
    return rc;
}

static int WSAAPI Hook_WSASendTo(SOCKET s, LPWSABUF bufs, DWORD count, LPDWORD sent,
                                 DWORD flags, const struct sockaddr* to, int tolen,
                                 LPWSAOVERLAPPED ov, LPWSAOVERLAPPED_COMPLETION_ROUTINE fn)
{
    g_inFlight.fetch_add(1, std::memory_order_relaxed);
    if (tlsInHook) {
        const int rc = Real_WSASendTo(s, bufs, count, sent, flags, to, tolen, ov, fn);
        g_inFlight.fetch_sub(1, std::memory_order_relaxed);
        return rc;
    }
    tlsInHook = true;
    c_rawWsasendto.fetch_add(1, std::memory_order_relaxed);
    if (count > 1) c_scatterGather.fetch_add(1, std::memory_order_relaxed); // M-5: real count
    // H-2: no "!ov" exclusion.  setsockopt is orthogonal to synchronous/asynchronous, so an
    // overlapped discovery send must be pinned too; excluding it left async sends unpinned.
    if (g_state.load() == 1 && to && tolen >= (int)sizeof(sockaddr_in) && bufs && count >= 1 &&
        IsDiscoveryTarget((const sockaddr_in*)to))
        PinSend(s);
    else
        c_ignoredNonDiscovery.fetch_add(1, std::memory_order_relaxed);
    const int rc = Real_WSASendTo(s, bufs, count, sent, flags, to, tolen, ov, fn);
    tlsInHook = false;
    g_inFlight.fetch_sub(1, std::memory_order_relaxed);
    return rc;
}

static int WSAAPI Hook_closesocket(SOCKET s)
{
    g_inFlight.fetch_add(1, std::memory_order_relaxed);
    if (tlsInHook) {
        const int rc = Real_closesocket(s);
        g_inFlight.fetch_sub(1, std::memory_order_relaxed);
        return rc;
    }
    tlsInHook = true;
    ForgetSocket(s);
    const int rc = Real_closesocket(s);
    tlsInHook = false;
    g_inFlight.fetch_sub(1, std::memory_order_relaxed);
    return rc;
}

static int WSAAPI Hook_bind(SOCKET s, const struct sockaddr* name, int namelen)
{
    g_inFlight.fetch_add(1, std::memory_order_relaxed);
    if (tlsInHook) {
        const int rc = Real_bind(s, name, namelen);
        g_inFlight.fetch_sub(1, std::memory_order_relaxed);
        return rc;
    }
    tlsInHook = true;
    c_rawBind.fetch_add(1, std::memory_order_relaxed);
    uint16_t portBe = 0;
    if (name && namelen >= (int)sizeof(sockaddr_in) && name->sa_family == AF_INET)
        portBe = ((const sockaddr_in*)name)->sin_port;
    const int rc = Real_bind(s, name, namelen);
    if (rc == 0 && portBe != 0) {
        FindOrCreateSlot(s); // ensure a slot exists (overflow is counted, M-1)
        SlotSetBoundPort(s, portBe);
        if (ntohs(portBe) == CIVLINK_DATAPATH_PORT)
            c_bind62056.fetch_add(1, std::memory_order_relaxed);
    }
    tlsInHook = false;
    g_inFlight.fetch_sub(1, std::memory_order_relaxed);
    return rc;
}

static int WSAAPI Hook_recvfrom(SOCKET s, char* buf, int len, int flags,
                                struct sockaddr* from, int* fromlen)
{
    g_inFlight.fetch_add(1, std::memory_order_relaxed);
    if (tlsInHook) {
        // REVIEW-2 H-1: the real call must stay inside the in-flight window even on the
        // re-entrancy path, otherwise CivLinkShutdown's drain can disable the trampoline
        // while this thread is still standing on it.
        const int rc = Real_recvfrom(s, buf, len, flags, from, fromlen);
        g_inFlight.fetch_sub(1, std::memory_order_relaxed);
        return rc;
    }
    tlsInHook = true;
    c_rawRecvfrom.fetch_add(1, std::memory_order_relaxed);
    if (ntohs(SlotBoundPort(s)) == CIVLINK_DATAPATH_PORT)
        c_recvfrom62056.fetch_add(1, std::memory_order_relaxed);
    const int rc = Real_recvfrom(s, buf, len, flags, from, fromlen);
    tlsInHook = false;
    g_inFlight.fetch_sub(1, std::memory_order_relaxed);
    return rc;
}

static int WSAAPI Hook_WSARecvFrom(SOCKET s, LPWSABUF bufs, DWORD count, LPDWORD bytes,
                                   LPDWORD flags, struct sockaddr* from, LPINT fromlen,
                                   LPWSAOVERLAPPED ov, LPWSAOVERLAPPED_COMPLETION_ROUTINE fn)
{
    g_inFlight.fetch_add(1, std::memory_order_relaxed);
    if (tlsInHook) {
        // REVIEW-2 H-1: same fix as recvfrom - real call inside the in-flight window.
        const int rc = Real_WSARecvFrom(s, bufs, count, bytes, flags, from, fromlen, ov, fn);
        g_inFlight.fetch_sub(1, std::memory_order_relaxed);
        return rc;
    }
    tlsInHook = true;
    c_rawWsarecvfrom.fetch_add(1, std::memory_order_relaxed);
    if (ntohs(SlotBoundPort(s)) == CIVLINK_DATAPATH_PORT)
        c_recvfrom62056.fetch_add(1, std::memory_order_relaxed);
    const int rc = Real_WSARecvFrom(s, bufs, count, bytes, flags, from, fromlen, ov, fn);
    if (rc == SOCKET_ERROR && WSAGetLastError() == WSA_IO_PENDING)
        c_wsarecvfromPending.fetch_add(1, std::memory_order_relaxed);
    tlsInHook = false;
    g_inFlight.fetch_sub(1, std::memory_order_relaxed);
    return rc;
}

// ---------------------------------------------------------------- init / shutdown
static DWORD WINAPI InitThread(LPVOID)
{
    WSADATA wsa{};
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) { c_initError.store(1); return 1; }

    // Config first (read once at init); invalid/unavailable config degrades to ALL and is
    // still loaded (fail-open), recorded in initError 11/12.
    const unsigned long cfgErr = LoadConfig();
    if (cfgErr) c_initError.store(cfgErr);

    LARGE_INTEGER qpc{};
    QueryPerformanceCounter(&qpc);
    g_sessionId = ((uint64_t)GetCurrentProcessId() << 32) ^ (uint64_t)qpc.QuadPart;

    if (MH_Initialize() != MH_OK) { c_initError.store(3); return 1; }
    if (MH_CreateHook((LPVOID)::sendto, (LPVOID)&Hook_sendto, (LPVOID*)&Real_sendto) != MH_OK) {
        c_initError.store(4); return 1;
    }
    if (MH_CreateHook((LPVOID)::WSASendTo, (LPVOID)&Hook_WSASendTo, (LPVOID*)&Real_WSASendTo) != MH_OK) {
        c_initError.store(5); return 1;
    }
    if (MH_CreateHook((LPVOID)::closesocket, (LPVOID)&Hook_closesocket, (LPVOID*)&Real_closesocket) != MH_OK) {
        c_initError.store(6); return 1;
    }
    if (MH_CreateHook((LPVOID)::bind, (LPVOID)&Hook_bind, (LPVOID*)&Real_bind) != MH_OK) {
        c_initError.store(7); return 1;
    }
    if (MH_CreateHook((LPVOID)::recvfrom, (LPVOID)&Hook_recvfrom, (LPVOID*)&Real_recvfrom) != MH_OK) {
        c_initError.store(8); return 1;
    }
    if (MH_CreateHook((LPVOID)::WSARecvFrom, (LPVOID)&Hook_WSARecvFrom, (LPVOID*)&Real_WSARecvFrom) != MH_OK) {
        c_initError.store(9); return 1;
    }
    if (MH_EnableHook(MH_ALL_HOOKS) != MH_OK) { c_initError.store(10); return 1; }

    g_state.store(1);
    return 0;
}

} // namespace

extern "C" CIVLINK_API int CivLinkHookState(void)
{
    c_stateQueries.fetch_add(1, std::memory_order_relaxed);
    return g_state.load();
}

extern "C" CIVLINK_API int CivLinkShutdown(void)
{
    const int prev = g_state.exchange(-1);
    if (prev == -1) return 1; // already shut down
    if (prev == 1) MH_DisableHook(MH_ALL_HOOKS);
    for (int i = 0; i < 500; i++) { // drain up to 5 s
        if (g_inFlight.load() == 0) break;
        Sleep(10);
    }
    const long left = g_inFlight.load();
    c_shutdownLeft.store(left);
    return left == 0 ? 0 : 2; // 2: caller must keep the module mapped (B2 audit-run mode)
}

extern "C" CIVLINK_API int CivLinkReactivate(void)
{
    // Re-activate in place after a prior CivLinkShutdown. The module is intentionally kept
    // mapped (B2 audit-run mode) so the installed trampolines stay valid; we only need to
    // re-read client-iface.txt (the operator may have switched NICs) and re-enable the
    // already-created MinHook hooks. No DllMain / InitThread runs a second time.
    const int before = g_state.load();
    if (before == 1) return 1; // already running - nothing to do
    if (before == 0) return 3; // first-time InitThread has not finished yet

    // Guard against two concurrent reactivations both enabling hooks.
    if (g_reactivating.exchange(1) != 0) return 1;

    // Let any in-flight hook calls drain before reconfiguring the pin mode.
    for (int i = 0; i < 500; i++) { // drain up to 5 s
        if (g_inFlight.load() == 0) break;
        Sleep(10);
    }

    c_initError.store(0);
    const unsigned long cfgErr = LoadConfig(); // idempotent: resets mode/index first
    if (cfgErr) c_initError.store(cfgErr);

    int rc = 0;
    if (MH_EnableHook(MH_ALL_HOOKS) != MH_OK) {
        c_initError.store(10);
        rc = 2; // hooks could not be re-enabled
    }
    if (rc == 0) g_state.store(1);

    g_reactivating.store(0);
    return rc;
}

extern "C" CIVLINK_API void CivLinkGetCounters(CivLinkCounters* out)
{
    if (!out) return;
    memset(out, 0, sizeof *out);
    out->magic = CIVLINK_COUNTERS_MAGIC;
    out->version = CIVLINK_COUNTERS_VERSION;
    out->sessionId = g_sessionId;
    out->sent = c_sent.load();
    out->sendFail = c_sendFail.load();
    out->ignoredNonDiscovery = c_ignoredNonDiscovery.load();
    // C2: no IPC/observation chain - these stay 0
    out->rejectOversize = 0;
    out->sentNotify = 0;
    out->observedFrames = 0;
    out->scatterGather = c_scatterGather.load();         // M-5: real count now
    out->sockTableOverflow = c_sockOverflow.load();      // M-1: real count now
    out->srcEndpointUnknown = 0;
    out->stateQueries = c_stateQueries.load();
    out->rawSendtoCalls = c_rawSendto.load();
    out->rawWsasendtoCalls = c_rawWsasendto.load();
    out->rawBindCalls = c_rawBind.load();
    out->rawRecvfromCalls = c_rawRecvfrom.load();
    out->rawWsarecvfromCalls = c_rawWsarecvfrom.load();
    out->bind62056Count = c_bind62056.load();
    out->recvfromOn62056 = c_recvfrom62056.load();
    out->wsarecvfromPending = c_wsarecvfromPending.load();
    out->cvlh2Try = 0;
    out->cvlh2Ok = 0;
    out->cvlh2Fail = 0;
    out->cvlh2Errno = 0;
    out->channelDown = 0;
    out->initError = c_initError.load();
    out->shutdownLeft = c_shutdownLeft.load();
    out->shutdown = (g_state.load() == -1) ? 1 : 0;
    out->running = (g_state.load() == 1) ? 1 : 0;
}

extern "C" CIVLINK_API unsigned long long CivLinkSessionId(void)
{
    return g_sessionId;
}

BOOL WINAPI DllMain(HMODULE hmod, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hmod);
        const HANDLE t = CreateThread(nullptr, 0, InitThread, nullptr, 0, nullptr);
        if (t) CloseHandle(t);
    }
    return TRUE;
}
