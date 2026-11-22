# Contributing to CivLink

Thanks for your interest. CivLink is a personal, free, non-commercial project;
contributions are welcome, but the verification bar is intentionally high
because this tool injects into a game process and touches network traffic.

## Ground rules

- **Scope first.** v1.0 = Windows 10/11 x64, Steam Win64 Civilization VI,
  two players on an on-LAN or user-managed VPN topology. Read
  `docs/M0D-OPENSOURCE-PLAN-20261118.md` §9.1 and
  `docs/PROJECT-SCOPE-WIN-STEAM-2P.md` before proposing anything outside it.
- **No telemetry, no logs, no auto-update, no bundled third-party VPN.**
  These are product decisions, not oversights (§9.1 decisions d1/d5/d6/d7).
- **Do not ship a claim you did not test.** Mechanical/simulated evidence is
  never to be described as verified two-player online play. Gate A remains
  unapproved until the E2-A/E2-B/E3 evidence exists.
- **Respect third-party licenses.** MinHook is pinned at v1.3.4
  (BSD-2-Clause); do not upgrade it casually. See `THIRD-PARTY-NOTICES.md`.

## Development setup (Windows)

- Toolchain: MSVC Build Tools (`D:\MSVC\BuildTools` in current docs; adjust
  paths locally), Rust 1.75 via `cargo +1.75.0 --offline`, `csc.exe` from
  `MSBuild\Current\Bin\Roslyn`.
- Native build: `civlink/build-msvc.cmd` (produces the hook/client DLLs,
  `civlink_ctl.exe`, selftests; uses `/MT` static CRT and the pinned MinHook).
- GUI build: `civlink/gui/build-gui.ps1` (WinForms, single-file, no SDK;
  acceptance = stable source hash + 9,216/23,552/26,112-byte size + exit 0,
  **not** output SHA-256).
- Run injection tests from a directory outside the repository (e.g.
  `%TEMP%\civlink-*`) — inside a restricted workspace, `OpenProcess` can fail
  with err=5 and config writes with errno=13; that is an environment artifact,
  not a product bug.

## Workflow (per the project's collaboration model)

1. Open or reference an issue/brief describing the change and its evidence
   requirements.
2. Implement with the smallest surface that preserves existing behavior:
   - never bind `0.0.0.0:62056`, never use `SO_REUSEADDR`;
   - detours must be transparent (same arguments, same return, same last
     error); C2's only allowed side effect is
     `setsockopt(IPPROTO_IP, IP_UNICAST_IF=31, htonl(ifIndex))` with last error
     saved/restored.
3. Add or update headless selftests; include a mutation check that would fail
   if your new logic were removed (see `docs/M0C-C2-REVIEW-2.md` for why this
   matters).
4. Submit with a short note: what changed, what was verified (with hashes),
   and what remains unverified. Expect an independent audit before a change is
   merged into the release line.

## Commit / patch hygiene

- Keep UTF-8 without BOM for `.md`, `.cs`, `.ps1` files; respect each file's
  existing line endings (README uses CRLF; most docs use LF).
- Publish SHA-256 values for shipped binaries in the release note; do not
  promise byte-reproducible builds for the GUI (see `SECURITY.md`).
- If you add a dependency, update `THIRD-PARTY-NOTICES.md` in the same patch.

## Code of conduct

Be civil. No personal attacks, no doxxing, no pressure to disclose private
network details. By contributing you agree that your contribution is licensed
under the repository's MIT License for code and CC BY 4.0 for documentation.
