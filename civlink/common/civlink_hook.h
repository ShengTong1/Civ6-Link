// civlink_hook.h - exported contract of the CivLink F1 discovery + F2 data-plane
// observation Hook DLL
//
// The injector / diagnostic tools call these exports inside the target process. The struct
// is a plain POD so it can cross the module boundary and be written to a file verbatim
// (no std::atomic, no padding surprises: all members are 8-byte unsigned).
#ifndef CIVLINK_HOOK_H
#define CIVLINK_HOOK_H

#include <windows.h>

#define CIVLINK_HOOK_VERSION       "0.2.0-f2"
#define CIVLINK_HOOK_DLL_NAME_A    "civlink_hook.dll"
#define CIVLINK_HOOK_DLL_NAME_W    L"civlink_hook.dll"
#define CIVLINK_COUNTERS_MAGIC     0x4C56434B554F43ull // "COUKVL"
#define CIVLINK_COUNTERS_VERSION   2

#ifdef CIVLINK_HOOK_EXPORTS
#define CIVLINK_API __declspec(dllexport)
#else
#define CIVLINK_API __declspec(dllimport)
#endif

// Reconciliation surface required by spec v2.1 §4.4. Every observed discovery send must be
// accounted for on both sides:
//   hook:  sent + sendFail + rejectOversize == observed discoveries
//   agent: received == sent + sentNotify, and agent.processed + agent.rejected == received
// F2 layered counters (design v0.2 §3.3, codex review §2.5): raw_* count every observed call
// at the detour; cvlh2_* count the local IPC channel for ALL frames (discovery, observed,
// notify). Only same-set layers may be reconciled, e.g. agent.received == cvlh2Ok when the
// channel reports no drops, and raw discovery sends == sent + sendFail + rejectOversize.
#pragma pack(push, 8)
struct CivLinkCounters {
    unsigned long long magic;                // CIVLINK_COUNTERS_MAGIC
    unsigned long long version;              // CIVLINK_COUNTERS_VERSION
    unsigned long long sessionId;            // matches the session_id inside every frame
    unsigned long long sent;                 // discovery frames successfully handed to the Agent
    unsigned long long sendFail;             // IPC sendto failed (discovery/notify family)
    unsigned long long rejectOversize;       // payload > 1280 B: rejected, notified, not sent
    unsigned long long sentNotify;           // of those rejects, how many notifications arrived
    unsigned long long ignoredNonDiscovery;  // sends not forwarded (state off / bad params)
    unsigned long long observedFrames;       // F2: non-discovery outbound frames forwarded
    unsigned long long scatterGather;        // WSASendTo with >1 buffer (partial observe)
    unsigned long long sockTableOverflow;    // logical-id table exhausted
    unsigned long long srcEndpointUnknown;   // getsockname failed: frame carries 0.0.0.0:0
    unsigned long long stateQueries;         // CivLinkHookState calls (liveness probe)
    // F2 layered counters (design v0.2 §3.3)
    unsigned long long rawSendtoCalls;       // every observed sendto (any target)
    unsigned long long rawWsasendtoCalls;    // every observed WSASendTo (non-overlapped)
    unsigned long long rawBindCalls;         // every observed bind
    unsigned long long rawRecvfromCalls;     // every observed recvfrom
    unsigned long long rawWsarecvfromCalls;  // every observed WSARecvFrom (status only)
    unsigned long long bind62056Count;       // binds whose port is 62056 (data plane)
    unsigned long long recvfromOn62056;      // recvfrom/WSARecvFrom on a 62056-bound socket
    unsigned long long wsarecvfromPending;   // WSARecvFrom returned WSA_IO_PENDING (status only)
    unsigned long long cvlh2Try;             // IPC send attempts (all frame kinds)
    unsigned long long cvlh2Ok;              // IPC sendto accepted (rc == len)
    unsigned long long cvlh2Fail;            // IPC sendto failed (rc != len)
    unsigned long long cvlh2Errno;           // WSAGetLastError of the last IPC failure
    unsigned long long channelDown;          // same as cvlh2Fail: Agent likely not listening
    long               initError;            // 0 ok, else the failing init step number
    long               shutdownLeft;         // in-flight count at the moment Shutdown returned
    long               shutdown;             // 0/1
    long               running;              // 0/1, hooks enabled and forwarding
};
#pragma pack(pop)

extern "C" {
// 1 = hooks enabled and forwarding; 0 = initialising or failed; -1 = shut down.
CIVLINK_API int CivLinkHookState(void);

// Disables the hooks, drains in-flight calls (max 5 s), and returns WITHOUT unmapping:
//   0 = clean drain, 1 = already shut down, 2 = calls still in flight when we gave up.
// The module stays mapped on purpose (B2 audit-run mode) - trampolines must remain valid
// for any thread that was already inside a detour when the hooks were disabled.
CIVLINK_API int CivLinkShutdown(void);

// Copies the counter block. Never blocks, never allocates.
CIVLINK_API void CivLinkGetCounters(CivLinkCounters* out);

// Process-generation id; identical to the session_id carried in every frame.
CIVLINK_API unsigned long long CivLinkSessionId(void);
}

#endif // CIVLINK_HOOK_H
