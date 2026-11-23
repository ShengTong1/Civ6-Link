# Contributing to CivLink

Thanks for your interest. CivLink is a personal, free, non-commercial project;
contributions are welcome, but the verification bar is intentionally high
because this tool injects into a game process and touches network traffic.

## Ground rules

- **Scope first.** v1.0 = Windows 10/11 x64, Steam Win64 Civilization VI,
  two players on an on-LAN or user-managed VPN topology. Proposals outside
  this scope need a written decision before code is written.
- **No telemetry, no logs, no auto-update, no bundled third-party VPN.**
  These are product decisions, not oversights.
- **Do not ship a claim you did not test.** Mechanical/simulated evidence is
  never to be described as verified two-player online play.
- **Respect third-party licenses.** MinHook is pinned at v1.3.4
  (BSD-2-Clause); do not upgrade it casually. See `THIRD-PARTY-NOTICES.md`.

## Development setup (Windows)

- Toolchain: MSVC Build Tools (path in `civlink/build-msvc.cmd`, overridable
  via the `VCVARS` environment variable), Rust 1.75 pinned via `cargo
  +1.75.0` for the agent (its Cargo.lock is format v3; a newer cargo must
  not rewrite it to v4, or 1.75 can no longer read it), and the default
  `cargo` for the Tauri GUI.
- Native build: `civlink/build-msvc.cmd` (produces the hook/client DLLs,
  `civlink_ctl.exe`, and the C++ selftests; `/MT` static CRT, pinned MinHook).
- Agent build: `cd civlink/agent && cargo build --release --features
  peer-discover --target-dir target-175`. The agent's optional dependencies
  (if-addrs, socket2) are vendored under `civlink/agent/vendor/`, so the
  build works offline.
- GUI build: `cd civlink/gui-tauri/src-tauri && cargo build --release`.
- Run injection tests from a directory outside the repository (e.g.
  `%TEMP%\civlink-*`) — inside a restricted workspace, `OpenProcess` can fail
  with err=5 and config writes with errno=13; that is an environment artifact,
  not a product bug.

## Workflow

1. Open or reference an issue/brief describing the change and its evidence
   requirements.
2. Implement with the smallest surface that preserves existing behavior:
   - never bind `0.0.0.0:62056`, never use `SO_REUSEADDR`;
   - detours must be transparent (same arguments, same return, same last
     error); the client's only allowed side effect is
     `setsockopt(IPPROTO_IP, IP_UNICAST_IF=31, htonl(ifIndex))` with last
     error saved/restored.
3. Add or update headless selftests; include a mutation check that would fail
   if your new logic were removed.
4. Submit with a short note: what changed, what was verified (with hashes),
   and what remains unverified. Expect an independent audit before a change
   is merged into the release line.

## Commit / patch hygiene

- Keep UTF-8 without BOM for `.md`, `.ps1` files; README.md uses CRLF.
- Publish SHA-256 values for shipped binaries in the release note.
- If you add a dependency, update `THIRD-PARTY-NOTICES.md` in the same patch.

## Code of conduct

Be civil. No personal attacks, no doxxing, no pressure to disclose private
network details. By contributing you agree that your contribution is licensed
under the repository's MIT License for code and CC BY 4.0 for documentation.
