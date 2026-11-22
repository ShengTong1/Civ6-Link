// civlink_client.h - exported contract of the CivLink M0-C C2 client-side NIC-pinning
// Hook DLL (civlink_client.dll).
//
// Same contract shape as civlink_hook.h so that the civlink_ctl toolchain (status /
// counters / shutdown) works for both DLLs unchanged: same four exports, same POD
// CivLinkCounters struct with the same magic and version. The C2-specific semantics live
// in the counter field mapping (see civlink_client.cpp) and in the extra initError codes
// 11 / 12 defined below.
#ifndef CIVLINK_CLIENT_H
#define CIVLINK_CLIENT_H

#include "civlink_hook.h" // CIVLINK_API, CivLinkCounters, the four export declarations

#define CIVLINK_CLIENT_VERSION      "0.1.0-c2"
#define CIVLINK_CLIENT_DLL_NAME_A   "civlink_client.dll"
#define CIVLINK_CLIENT_DLL_NAME_W   L"civlink_client.dll"

// Configuration file (relative to %LOCALAPPDATA%): a single ASCII line, either ALL
// (case-insensitive) or a dotted IPv4 address. Written by civlink_ctl inject-client
// BEFORE the DLL is injected so it is read once at InitThread time.
#define CIVLINK_IFACE_CONFIG_REL    "CivLink\\client-iface.txt"

// C2-only initError codes (in addition to the civlink_hook.h range 1..10):
//   11 = config file present but invalid (not ALL and not a parseable IPv4 address)
//   12 = configured IP is not a local IPv4 address or its interface is down
// Both are non-fatal: the DLL degrades to ALL mode and still loads (fail-open).
#define CIVLINK_INITERR_CONFIG_INVALID 11
#define CIVLINK_INITERR_IFACE_UNAVAIL  12

extern "C" {
// Re-activate this module in place after CivLinkShutdown, WITHOUT unloading it (B2
// audit-run mode keeps the mapped module so trampolines stay valid). The resident DLL
// re-reads client-iface.txt - the operator may have switched NICs - and re-enables its
// hooks. Returns 0 on success, 1 if already running, 2 if hooks could not be re-enabled,
// 3 if the first-time InitThread has not finished yet. Civlink_ctl calls this by name
// (ResolveLocalPe + RemoteCallInt) when a second inject-client finds the module mapped.
CIVLINK_API int CivLinkReactivate(void);
}

#endif // CIVLINK_CLIENT_H
