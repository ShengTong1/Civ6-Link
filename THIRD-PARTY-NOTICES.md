# Third-Party Notices

CivLink incorporates or depends on the following third-party components. This
file is provided for attribution and license compliance; it is not legal advice.
See the root `LICENSE` (MIT, source code) and `docs/LICENSE-DOCS.md`
(CC BY 4.0, documentation).

## 1. MinHook — bundled source, compiled from source

- **Version:** v1.3.4 (pinned in `deps/MinHook`; do not upgrade without a
  fresh audit — the hook logic was validated against this exact tree).
- **Upstream:** https://github.com/TsudaKageyu/minhook
- **License:** BSD 2-Clause ("Simplified BSD License") for the core library.
- **Copyright:** (c) 2009-2017, Tsuda Kageyu. All rights reserved.
- **Bundled HDE32/HDE64 portion:** Portions Copyright (c) 2008-2009,
  Vyacheslav Patkov ("Hacker Disassembler Engine", distributed under the
  BSD-style terms reproduced in `deps/MinHook/LICENSE.txt:27-59` and noted at
  `deps/MinHook/src/hde/hde32.c:3` and `hde64.c:3`). This notice is required by
  `docs/M0D-OPENSOURCE-PLAN-20261118.md` §7.2; the full license text is bundled
  in `deps/MinHook/LICENSE.txt` and applies to that disassembler portion.
- **Used by:** `civlink/hook/civlink_hook.dll`, `civlink/client/civlink_client.dll`,
  and the `civtrace/` observation tool — all Win32 API detours.
- **Full license text:** `deps/MinHook/LICENSE.txt` (also `LICENSE.txt` in the
  upstream tree). No MinHook binary is redistributed; it is built locally by
  `civlink/build-msvc.cmd` with the pinned source.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the copyright notice, this list of
conditions and the disclaimer are retained in source or binary distributions.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS".

## 2. Rust crates — built from source, zero external crates

`civlink-agent`, `civlink-relay`, `civlink-fakeip` declare **no external
dependencies** (their `Cargo.lock` files contain only the crates themselves).
They are built with `cargo +1.75.0 --offline`. No third-party Rust code is
bundled.

## 3. Microsoft components — NOT redistributed, provided by the user's system

- **Microsoft Visual C++ Runtime** — statically linked into native binaries
  with `/MT`; MSVC Build Tools are used at build time only.
- **.NET Framework 4.x (WinForms)** for `civlink_tray.exe` / the legacy
  `civlink_ctl_gui.exe`, or **.NET Desktop Runtime 8.0.3** for the optional
  WPF path. Neither runtime is bundled; install it on the target machine.
- **Windows SDK** headers and import libraries (`winsock2.h`, `iphlpapi.lib`,
  `psapi.lib`) — system APIs, not redistributed.

## 4. Trademarks

Sid Meier's Civilization VI is a trademark of 2K Games / Firaxis Games.
Steam is a trademark of Valve Corporation. Radmin VPN is a trademark of
Famatech. ZeroTier is a trademark of ZeroTier, Inc. CivLink is an independent,
unofficial, personal, free project and is not affiliated with, endorsed by,
or sponsored by any of them.
