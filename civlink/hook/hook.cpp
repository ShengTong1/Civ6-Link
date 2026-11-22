// hook.cpp - CivLink F1 discovery + F2 data-plane observation Hook DLL
//
// SCOPE (REV-016 §3 F1 + F2 design v0.2 §3.3, second increment):
//   * Observe the discovery send path: sendto / WSASendTo whose destination is
//     255.255.255.255 or whose destination port is in the discovery range 62900..62999.
//   * F2: ALSO observe the data-plane path - every other outbound send (e.g. UDP 62056) is
//     forwarded to the Agent as an observation frame (CIVLINK_FLAG_OBSERVED), and bind /
//     recvfrom / WSARecvFrom are observed as counters only (never forwarded, never altered).
//   * Forward each observation to the local Agent as one CVLH2 frame over loopback UDP.
//   * NEVER alter the game's behaviour: the original API is always called, its return value
//     and last error are returned untouched, no call is swallowed. (Swallowing belongs to
//     F2/F3 and requires the Agent to actually deliver the packet.)
//
// HARD RULES taken from the M0-A audit findings (REV-002 lessons, see civtrace/):
//   * Every detour increments g_inFlight as its very first statement and decrements on every
//     exit path. A thread_local guard (g_tlsInHook) passes through instead of observing, so
//     our own IPC send can never recurse into the detour.
//   * The IPC socket and its sockaddr are built BEFORE any hook is enabled.
//   * Shutdown disables hooks, drains in-flight calls, then LEAVES THE MODULE MAPPED (B2
//     audit-run mode): we never call MH_Uninitialize, so a thread that was already inside a
//     detour keeps a valid trampoline until process exit.
//   * No blocking waits, no file I/O, no allocation on the observed path. A failed IPC send
//     is counted, never retried, and never changes the game's result.
//
// Counter reconciliation (spec §4.4 + F2 design v0.2 §3.3):
//   sent + sendFail + rejectOversize == observed discovery sends
//   sent + observedFrames == Agent.processed   (same-set, all non-notify frames)
//   sentNotify == Agent.rejected               (oversize notifications)
//   Agent's received must equal sent + observedFrames + sentNotify.
//   cvlh2Try/Ok/Fail/Errno/channelDown describe the IPC channel itself and are only
//   reconciled with the Agent's totals.received when the channel reports no drops.
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <atomic>
#include <cstring>

#include "../../deps/MinHook/include/MinHook.h"
#include "../common/cvlh2.h"
#include "../common/civlink_hook.h"

#pragma comment(lib, "ws2_32.lib")

// ---------------------------------------------------------------- function typedefs
typedef int (WSAAPI* T_sendto)(SOCKET, const char*, int, int, const struct sockaddr*, int);
typedef int (WSAAPI* T_WSASendTo)(SOCKET, LPWSABUF, DWORD, LPDWORD, DWORD,
                                  const struct sockaddr*, int, LPWSAOVERLAPPED,
                                  LPWSAOVERLAPPED_COMPLETION_ROUTINE);
typedef int (WSAAPI* T_closesocket)(SOCKET);
typedef int (WSAAPI* T_bind)(SOCKET, const struct sockaddr*, int);
typedef int (WSAAPI* T_recvfrom)(SOCKET, char*, int, int, struct sockaddr*, int*);
typedef int (WSAAPI* T_WSARecvFrom)(SOCKET, LPWSABUF, DWORD, LPDWORD, LPDWORD,
                                    struct sockaddr*, LPINT, LPWSAOVERLAPPED,
                                    LPWSAOVERLAPPED_COMPLETION_ROUTINE);

static T_sendto      Real_sendto      = nullptr;
static T_WSASendTo   Real_WSASendTo   = nullptr;
static T_closesocket Real_closesocket = nullptr;
static T_bind        Real_bind        = nullptr;
static T_recvfrom    Real_recvfrom    = nullptr;
static T_WSARecvFrom Real_WSARecvFrom = nullptr;

// ---------------------------------------------------------------- global state
static std::atomic<long> g_inFlight{0};
static thread_local bool g_tlsInHook = false;
static std::atomic<int>  g_state{0};     // 0 initialising, 1 running, -1 shut down

static SOCKET      g_ipcSock = INVALID_SOCKET;
static sockaddr_in g_ipcAddr;
static uint64_t    g_sessionId = 0;
static unsigned long g_seq = 0;          // only advanced by threads inside the hook body

// internal counters (atomically updated; copied into the POD CivLinkCounters on demand)
static std::atomic<unsigned long long> c_sent{0};
static std::atomic<unsigned long long> c_sendFail{0};
static std::atomic<unsigned long long> c_rejectOversize{0};
static std::atomic<unsigned long long> c_sentNotify{0};
static std::atomic<unsigned long long> c_ignored{0};
static std::atomic<unsigned long long> c_observed{0};
static std::atomic<unsigned long long> c_scatter{0};
static std::atomic<unsigned long long> c_stateQueries{0};
static std::atomic<long>               c_initError{0};
static std::atomic<long>               c_shutdownLeft{0};

// F2 layered counters (design v0.2 §3.3)
static std::atomic<unsigned long long> c_rawSendto{0};
static std::atomic<unsigned long long> c_rawWsasendto{0};
static std::atomic<unsigned long long> c_rawBind{0};
static std::atomic<unsigned long long> c_rawRecvfrom{0};
static std::atomic<unsigned long long> c_rawWsarecvfrom{0};
static std::atomic<unsigned long long> c_bind62056{0};
static std::atomic<unsigned long long> c_recvfrom62056{0};
static std::atomic<unsigned long long> c_wsarecvfromPending{0};
static std::atomic<unsigned long long> c_cvlh2Try{0};
static std::atomic<unsigned long long> c_cvlh2Ok{0};
static std::atomic<unsigned long long> c_cvlh2Fail{0};
static std::atomic<unsigned long long> c_cvlh2Errno{0};
static std::atomic<unsigned long long> c_channelDown{0};

// logical socket id table: bounded, allocation-free, SOCKET -> {id, generation}.
// The discovery path uses one socket per burst, so 64 slots with linear probing plus an
// overflow counter is sufficient; overflow only degrades reconciliation fidelity.
struct SockSlot {
    SOCKET   s;
    uint32_t id;
    uint32_t gen;
    bool     used;
    // Local endpoint, resolved once with getsockname (unhooked) so the Agent knows where to
    // deliver a discovery reply. Cached: no syscall per observed frame.
    bool     haveSrc;
    uint32_t srcIpBe;
    uint16_t srcPortBe;
    // F2: bound local port in network byte order as observed by the bind hook (0 = not
    // observed / bound). Lets the recvfrom hooks count data-plane receives on 62056.
    uint16_t boundPortBe;
};
static SockSlot              g_sockSlots[64];
static SRWLOCK               g_sockLock = SRWLOCK_INIT;
static std::atomic<uint32_t> g_nextLogicalId{1};
static std::atomic<unsigned long long> c_sockOverflow{0};
static std::atomic<unsigned long long> c_srcUnknown{0};

static uint32_t LogicalSocketId(SOCKET s)
{
    AcquireSRWLockExclusive(&g_sockLock);
    SockSlot* freeSlot = nullptr;
    for (int i = 0; i < 64; i++) {
        if (g_sockSlots[i].used && g_sockSlots[i].s == s) {
            const uint32_t id = g_sockSlots[i].id;
            ReleaseSRWLockExclusive(&g_sockLock);
            return id;
        }
        if (!g_sockSlots[i].used && !freeSlot) freeSlot = &g_sockSlots[i];
    }
    if (!freeSlot) {
        c_sockOverflow.fetch_add(1, std::memory_order_relaxed);
        freeSlot = &g_sockSlots[0]; // degrade, never block
    }
    freeSlot->s = s;
    freeSlot->id = g_nextLogicalId.fetch_add(1, std::memory_order_relaxed);
    freeSlot->gen = 1;
    freeSlot->used = true;
    freeSlot->haveSrc = false;
    freeSlot->srcIpBe = 0;
    freeSlot->srcPortBe = 0;
    freeSlot->boundPortBe = 0;
    const uint32_t id = freeSlot->id;
    ReleaseSRWLockExclusive(&g_sockLock);
    return id;
}

// F2: records the bound local port (network byte order) observed by the bind hook.
static void SlotSetBoundPort(SOCKET s, uint16_t portBe)
{
    AcquireSRWLockExclusive(&g_sockLock);
    for (int i = 0; i < 64; i++) {
        if (g_sockSlots[i].used && g_sockSlots[i].s == s) {
            g_sockSlots[i].boundPortBe = portBe;
            break;
        }
    }
    ReleaseSRWLockExclusive(&g_sockLock);
}

// F2: returns the bound port observed by the bind hook, or 0 when not observed.
static uint16_t SlotBoundPort(SOCKET s)
{
    uint16_t port = 0;
    AcquireSRWLockShared(&g_sockLock);
    for (int i = 0; i < 64; i++) {
        if (g_sockSlots[i].used && g_sockSlots[i].s == s) {
            port = g_sockSlots[i].boundPortBe;
            break;
        }
    }
    ReleaseSRWLockShared(&g_sockLock);
    return port;
}

// Resolves and caches the socket's local IPv4 endpoint. Called from the hook body only when
// the cached value is still unknown; getsockname is not hooked, so no recursion is possible,
// and a failure simply leaves the endpoint unknown (the Agent reports it rather than guessing).
static bool SlotHasSrc(SOCKET s, bool* usedFound)
{
    bool have = false;
    *usedFound = false;
    AcquireSRWLockShared(&g_sockLock);
    for (int i = 0; i < 64; i++) {
        if (g_sockSlots[i].used && g_sockSlots[i].s == s) {
            have = g_sockSlots[i].haveSrc;
            *usedFound = true;
            break;
        }
    }
    ReleaseSRWLockShared(&g_sockLock);
    return have;
}

static void EnsureLocalEndpoint(SOCKET s)
{
    bool used = false;
    if (SlotHasSrc(s, &used)) return;

    sockaddr_in local{};
    int len = sizeof local;
    if (::getsockname(s, (sockaddr*)&local, &len) != 0 || local.sin_family != AF_INET) return;
    // An unbound UDP socket reports 0.0.0.0:0. That is not an endpoint the Agent could
    // deliver a reply to, so it must NOT be cached as "known": keep it unresolved and retry
    // on the next frame (after the first send the OS has assigned a real port).
    if (local.sin_port == 0) return;

    AcquireSRWLockExclusive(&g_sockLock);
    for (int i = 0; i < 64; i++) {
        if (g_sockSlots[i].used && g_sockSlots[i].s == s) {
            g_sockSlots[i].haveSrc = true;
            g_sockSlots[i].srcIpBe = local.sin_addr.s_addr;
            g_sockSlots[i].srcPortBe = local.sin_port;
            break;
        }
    }
    ReleaseSRWLockExclusive(&g_sockLock);
}

// Copies the cached local endpoint out. Returns false when still unknown.
static bool ReadLocalEndpoint(SOCKET s, uint32_t* ipBe, uint16_t* portBe)
{
    bool ok = false;
    AcquireSRWLockShared(&g_sockLock);
    for (int i = 0; i < 64; i++) {
        if (g_sockSlots[i].used && g_sockSlots[i].s == s) {
            if (g_sockSlots[i].haveSrc) {
                *ipBe = g_sockSlots[i].srcIpBe;
                *portBe = g_sockSlots[i].srcPortBe;
                ok = true;
            }
            break;
        }
    }
    ReleaseSRWLockShared(&g_sockLock);
    return ok;
}

static void ForgetSocket(SOCKET s)
{
    AcquireSRWLockExclusive(&g_sockLock);
    for (int i = 0; i < 64; i++) {
        if (g_sockSlots[i].used && g_sockSlots[i].s == s) {
            g_sockSlots[i].used = false;
            break;
        }
    }
    ReleaseSRWLockExclusive(&g_sockLock);
}

// ---------------------------------------------------------------- forwarding
// Returns true and sets *flagsOut when the destination belongs to the discovery path, or
// when the sending socket is itself a discovery socket (bound to 62900..62999). The
// socket-identity rule is B1 §0 forensics (2026-11-17, run-20261117-095336): the real host
// answers advertisement pages as UNICAST back to the requester's source address:source port
// (e.g. 54322), NOT to 62900..62999, so a destination-port-only test would miss every page.
// A socket that ever bound a discovery port is therefore treated as discovery for all of its
// sends, whatever the destination port. Pure observation: the game's send is never swallowed.
static bool IsDiscoveryTarget(SOCKET s, const sockaddr_in* sin, uint8_t* flagsOut)
{
    if (!sin || sin->sin_family != AF_INET) return false;
    uint8_t flags = 0;
    if (sin->sin_addr.s_addr == INADDR_BROADCAST) flags |= CIVLINK_FLAG_LIMITED_BCAST;
    const uint16_t port = cvlh_port_from_be16(sin->sin_port);
    if (port >= CIVLINK_DISCOVERY_PORT_FIRST && port <= CIVLINK_DISCOVERY_PORT_LAST)
        flags |= CIVLINK_FLAG_DISCOVERY;
    // B1 §0: unicast advertisement pages leave a discovery-bound socket (e.g. bound
    // 0.0.0.0:62900, dst 26.74.126.98:54322). Socket identity wins over the destination test.
    const uint16_t bound = cvlh_port_from_be16(SlotBoundPort(s));
    if ((flags & CIVLINK_FLAG_DISCOVERY) == 0 &&
        bound >= CIVLINK_DISCOVERY_PORT_FIRST && bound <= CIVLINK_DISCOVERY_PORT_LAST)
        flags |= CIVLINK_FLAG_DISCOVERY;
    if (!flags) return false;
    if (flagsOut) *flagsOut = flags;
    return true;
}

// Sends one frame to the Agent. Called with g_tlsInHook already set; uses Real_sendto so the
// local IPC send can never be re-observed. Failures are counted, never retried.
// Layering (F2 design v0.2 §3.3): cvlh2Try/Ok/Fail/Errno/channelDown describe the IPC channel
// for ALL frame kinds; sent/observedFrames/sentNotify classify what the Agent received;
// sendFail/rejectOversize stay on the discovery family so that
//   sent + sendFail + rejectOversize == observed discovery sends  (spec §4.4) still holds.
static void ForwardFrame(SOCKET s, const sockaddr_in* dst, const uint8_t* payload,
                         size_t payloadLen, uint8_t flags)
{
    uint8_t buf[CIVLINK_FRAME_MAX_TOTAL];
    const uint32_t seq = (uint32_t)++g_seq;
    const uint32_t id = LogicalSocketId(s);

    EnsureLocalEndpoint(s); // cached after the first observed send; never blocks
    uint32_t srcIpBe = 0;
    uint16_t srcPortBe = 0;
    if (!ReadLocalEndpoint(s, &srcIpBe, &srcPortBe))
        c_srcUnknown.fetch_add(1, std::memory_order_relaxed);

    size_t n = cvlh_encode(buf, sizeof buf, seq, g_sessionId, id, 1,
                           srcIpBe, srcPortBe,
                           dst->sin_addr.s_addr, dst->sin_port,
                           flags, payload, payloadLen);
    bool isNotify = false;
    if (n == 0) {
        // Oversize or encode failure: send a payload-less notification so the Agent can
        // count the reject too. Silent loss is forbidden by the spec.
        c_rejectOversize.fetch_add(1, std::memory_order_relaxed);
        n = cvlh_encode(buf, sizeof buf, seq, g_sessionId, id, 1, 0, 0,
                        dst->sin_addr.s_addr, dst->sin_port,
                        (uint8_t)(flags | CIVLINK_FLAG_REJECTED_OVERSIZE | CIVLINK_FLAG_NO_PAYLOAD),
                        nullptr, 0);
        if (n == 0) { c_sendFail.fetch_add(1, std::memory_order_relaxed); return; }
        isNotify = true;
    }

    c_cvlh2Try.fetch_add(1, std::memory_order_relaxed);
    const int rc = Real_sendto(g_ipcSock, (const char*)buf, (int)n, 0,
                               (const sockaddr*)&g_ipcAddr, sizeof g_ipcAddr);
    if (rc == (int)n) {
        c_cvlh2Ok.fetch_add(1, std::memory_order_relaxed);
        if (isNotify) c_sentNotify.fetch_add(1, std::memory_order_relaxed);
        else if (flags & CIVLINK_FLAG_DISCOVERY) c_sent.fetch_add(1, std::memory_order_relaxed);
        else c_observed.fetch_add(1, std::memory_order_relaxed);
    } else {
        c_cvlh2Fail.fetch_add(1, std::memory_order_relaxed);
        c_channelDown.fetch_add(1, std::memory_order_relaxed);
        c_cvlh2Errno.store(WSAGetLastError(), std::memory_order_relaxed);
        // Discovery-family only: an observed-frame IPC failure must not disturb §4.4.
        if (isNotify || (flags & CIVLINK_FLAG_DISCOVERY))
            c_sendFail.fetch_add(1, std::memory_order_relaxed);
    }
}

// ---------------------------------------------------------------- detours
static int WSAAPI Hook_sendto(SOCKET s, const char* buf, int len, int flags,
                              const struct sockaddr* to, int tolen)
{
    g_inFlight.fetch_add(1, std::memory_order_relaxed);
    if (g_tlsInHook) {
        const int rc = Real_sendto(s, buf, len, flags, to, tolen);
        g_inFlight.fetch_sub(1, std::memory_order_relaxed);
        return rc;
    }
    g_tlsInHook = true;
    c_rawSendto.fetch_add(1, std::memory_order_relaxed);
    if (g_state.load(std::memory_order_relaxed) == 1 && to &&
        tolen >= (int)sizeof(sockaddr_in) && len > 0 && buf) {
        uint8_t f = 0;
        if (IsDiscoveryTarget(s, (const sockaddr_in*)to, &f)) {
            ForwardFrame(s, (const sockaddr_in*)to, (const uint8_t*)buf, (size_t)len, f);
        } else {
            // F2: non-discovery outbound (e.g. the 62056 data plane) is forwarded as an
            // observation frame. Pure observation: the game's send is never swallowed.
            ForwardFrame(s, (const sockaddr_in*)to, (const uint8_t*)buf, (size_t)len,
                         CIVLINK_FLAG_OBSERVED);
        }
    } else {
        c_ignored.fetch_add(1, std::memory_order_relaxed);
    }
    g_tlsInHook = false;
    // The game's call is never altered: same arguments, original return value and last error.
    // H-1: keep the real call INSIDE the g_inFlight window (mirrors civlink_client.cpp) so
    // CivLinkShutdown's drain really covers the original send (Brooks-Lint residual R3).
    const int rc = Real_sendto(s, buf, len, flags, to, tolen);
    g_inFlight.fetch_sub(1, std::memory_order_relaxed);
    return rc;
}

static int WSAAPI Hook_WSASendTo(SOCKET s, LPWSABUF bufs, DWORD count, LPDWORD sent,
                                 DWORD flags, const struct sockaddr* to, int tolen,
                                 LPWSAOVERLAPPED ov, LPWSAOVERLAPPED_COMPLETION_ROUTINE fn)
{
    g_inFlight.fetch_add(1, std::memory_order_relaxed);
    if (g_tlsInHook) {
        const int rc = Real_WSASendTo(s, bufs, count, sent, flags, to, tolen, ov, fn);
        g_inFlight.fetch_sub(1, std::memory_order_relaxed);
        return rc;
    }
    g_tlsInHook = true;
    c_rawWsasendto.fetch_add(1, std::memory_order_relaxed);
    // Observe only buffered (non-overlapped) sends; overlapped completions happen later and
    // must not be touched here.
    if (g_state.load(std::memory_order_relaxed) == 1 && to &&
        tolen >= (int)sizeof(sockaddr_in) && bufs && count >= 1 && !ov) {
        uint8_t f = 0;
        if (IsDiscoveryTarget(s, (const sockaddr_in*)to, &f)) {
            ForwardFrame(s, (const sockaddr_in*)to, (const uint8_t*)bufs[0].buf,
                         bufs[0].len, (uint8_t)(f | CIVLINK_FLAG_VIA_WSASENDTO));
            if (count > 1) c_scatter.fetch_add(1, std::memory_order_relaxed);
        } else {
            ForwardFrame(s, (const sockaddr_in*)to, (const uint8_t*)bufs[0].buf,
                         bufs[0].len,
                         (uint8_t)(CIVLINK_FLAG_OBSERVED | CIVLINK_FLAG_VIA_WSASENDTO));
            if (count > 1) c_scatter.fetch_add(1, std::memory_order_relaxed);
        }
    } else {
        c_ignored.fetch_add(1, std::memory_order_relaxed);
    }
    g_tlsInHook = false;
    // H-1: real call stays inside the g_inFlight window (mirrors civlink_client.cpp).
    const int rc = Real_WSASendTo(s, bufs, count, sent, flags, to, tolen, ov, fn);
    g_inFlight.fetch_sub(1, std::memory_order_relaxed);
    return rc;
}

static int WSAAPI Hook_closesocket(SOCKET s)
{
    g_inFlight.fetch_add(1, std::memory_order_relaxed);
    if (g_tlsInHook) {
        const int rc = Real_closesocket(s);
        g_inFlight.fetch_sub(1, std::memory_order_relaxed);
        return rc;
    }
    g_tlsInHook = true;
    ForgetSocket(s); // release the logical id so it is not silently reused
    g_tlsInHook = false;
    // H-1: real call stays inside the g_inFlight window (mirrors civlink_client.cpp).
    const int rc = Real_closesocket(s);
    g_inFlight.fetch_sub(1, std::memory_order_relaxed);
    return rc;
}

// F2 observation detour: records the bind target (AF_INET port), the return value and the
// immediate last error. Never alters the arguments, the return value or the last error.
// The socket's bound port is cached in the slot table so the recvfrom hooks can count
// receives on the data-plane port (62056).
static int WSAAPI Hook_bind(SOCKET s, const struct sockaddr* name, int namelen)
{
    g_inFlight.fetch_add(1, std::memory_order_relaxed);
    if (g_tlsInHook) {
        g_inFlight.fetch_sub(1, std::memory_order_relaxed);
        return Real_bind(s, name, namelen);
    }
    g_tlsInHook = true;
    c_rawBind.fetch_add(1, std::memory_order_relaxed);
    uint16_t portBe = 0;
    if (name && namelen >= (int)sizeof(sockaddr_in) && name->sa_family == AF_INET)
        portBe = ((const sockaddr_in*)name)->sin_port;
    const int rc = Real_bind(s, name, namelen);
    if (rc == 0 && portBe != 0) {
        LogicalSocketId(s); // ensure a slot exists so SlotSetBoundPort/recvfrom lookups work
        SlotSetBoundPort(s, portBe);
        if (cvlh_port_from_be16(portBe) == CIVLINK_DATAPATH_PORT)  // 62056
            c_bind62056.fetch_add(1, std::memory_order_relaxed);
    }
    g_tlsInHook = false;
    g_inFlight.fetch_sub(1, std::memory_order_relaxed);
    return rc; // original return value; last error left exactly as the original set it
}

// F2 observation detour: counts recvfrom calls and whether they target the data-plane
// socket. On synchronous success the buffer head is NOT read (nothing is forwarded inbound
// in this increment); on failure only the call is recorded.
static int WSAAPI Hook_recvfrom(SOCKET s, char* buf, int len, int flags,
                                struct sockaddr* from, int* fromlen)
{
    g_inFlight.fetch_add(1, std::memory_order_relaxed);
    if (g_tlsInHook) {
        g_inFlight.fetch_sub(1, std::memory_order_relaxed);
        return Real_recvfrom(s, buf, len, flags, from, fromlen);
    }
    g_tlsInHook = true;
    c_rawRecvfrom.fetch_add(1, std::memory_order_relaxed);
    if (cvlh_port_from_be16(SlotBoundPort(s)) == CIVLINK_DATAPATH_PORT)
        c_recvfrom62056.fetch_add(1, std::memory_order_relaxed);
    const int rc = Real_recvfrom(s, buf, len, flags, from, fromlen);
    // rc > 0 would be a synchronous success; the payload is deliberately not inspected here.
    g_tlsInHook = false;
    g_inFlight.fetch_sub(1, std::memory_order_relaxed);
    return rc;
}

// F2 observation detour (review §2.4): the overlapped WSARecvFrom may report success
// immediately (rc == 0, bytesReceived valid) or return SOCKET_ERROR with WSA_IO_PENDING.
// In BOTH failure modes we only record status - we never read the WSABUF, the source
// address or the completion byte count. No completion-notification hook is added in this
// increment, so an overlapped completion is simply not observed afterwards.
static int WSAAPI Hook_WSARecvFrom(SOCKET s, LPWSABUF bufs, DWORD count, LPDWORD bytes,
                                   LPDWORD flags, struct sockaddr* from, LPINT fromlen,
                                   LPWSAOVERLAPPED ov, LPWSAOVERLAPPED_COMPLETION_ROUTINE fn)
{
    g_inFlight.fetch_add(1, std::memory_order_relaxed);
    if (g_tlsInHook) {
        g_inFlight.fetch_sub(1, std::memory_order_relaxed);
        return Real_WSARecvFrom(s, bufs, count, bytes, flags, from, fromlen, ov, fn);
    }
    g_tlsInHook = true;
    c_rawWsarecvfrom.fetch_add(1, std::memory_order_relaxed);
    if (cvlh_port_from_be16(SlotBoundPort(s)) == CIVLINK_DATAPATH_PORT)
        c_recvfrom62056.fetch_add(1, std::memory_order_relaxed);
    const int rc = Real_WSARecvFrom(s, bufs, count, bytes, flags, from, fromlen, ov, fn);
    if (rc == SOCKET_ERROR && WSAGetLastError() == WSA_IO_PENDING)
        c_wsarecvfromPending.fetch_add(1, std::memory_order_relaxed);
    // rc == 0 (synchronous success): bytes now contains the completion count, but the
    // buffers/address are deliberately not inspected here (review §2.4 allows a summary
    // read on sync success; this increment records only the call).
    g_tlsInHook = false;
    g_inFlight.fetch_sub(1, std::memory_order_relaxed);
    return rc;
}

// ---------------------------------------------------------------- init / shutdown
static DWORD WINAPI InitThread(LPVOID)
{
    // Build the IPC socket BEFORE enabling any hook so nothing here can reach a detour.
    WSADATA wsa{};
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) { c_initError.store(1); return 1; }
    g_ipcSock = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (g_ipcSock == INVALID_SOCKET) { c_initError.store(2); return 1; }

    memset(&g_ipcAddr, 0, sizeof g_ipcAddr);
    g_ipcAddr.sin_family = AF_INET;
    g_ipcAddr.sin_port = cvlh_port_to_be16(CIVLINK_IPC_AGENT_PORT);
    g_ipcAddr.sin_addr.s_addr = inet_addr(CIVLINK_IPC_HOST_STR);

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

    // Drain: wait up to 5 s for in-flight calls. On timeout we still return 2 WITHOUT tearing
    // anything down - the caller must keep the module mapped (B2 audit-run mode).
    for (int i = 0; i < 500; i++) {
        if (g_inFlight.load(std::memory_order_relaxed) == 0) break;
        Sleep(10);
    }
    const long left = g_inFlight.load(std::memory_order_relaxed);
    c_shutdownLeft.store(left);
    return left == 0 ? 0 : 2;
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
    out->rejectOversize = c_rejectOversize.load();
    out->sentNotify = c_sentNotify.load();
    out->ignoredNonDiscovery = c_ignored.load();
    out->observedFrames = c_observed.load();
    out->scatterGather = c_scatter.load();
    out->sockTableOverflow = c_sockOverflow.load();
    out->srcEndpointUnknown = c_srcUnknown.load();
    out->stateQueries = c_stateQueries.load();
    out->rawSendtoCalls = c_rawSendto.load();
    out->rawWsasendtoCalls = c_rawWsasendto.load();
    out->rawBindCalls = c_rawBind.load();
    out->rawRecvfromCalls = c_rawRecvfrom.load();
    out->rawWsarecvfromCalls = c_rawWsarecvfrom.load();
    out->bind62056Count = c_bind62056.load();
    out->recvfromOn62056 = c_recvfrom62056.load();
    out->wsarecvfromPending = c_wsarecvfromPending.load();
    out->cvlh2Try = c_cvlh2Try.load();
    out->cvlh2Ok = c_cvlh2Ok.load();
    out->cvlh2Fail = c_cvlh2Fail.load();
    out->cvlh2Errno = c_cvlh2Errno.load();
    out->channelDown = c_channelDown.load();
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
