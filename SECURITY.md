# Security Policy — CivLink

## Scope and threat model

CivLink is a personal, free, _Windows-only_ companion tool for Sid Meier's
Civilization VI (Steam Win64). It patches game network calls inside the game
process via MinHook to observe and redirect *discovery* traffic; it does not
intercept game logic, does not decrypt anything, and does not phone home.

Out of scope: cheating detection evasion, anti-cheat bypass, protected game
accounts, and any use on machines you do not own or administer.

## Supported configuration

- Windows 10/11 x64; Civilization VI via Steam Win64.
- Third-party network layers (Radmin VPN, ZeroTier, etc.), if used, are
  **user-installed and user-configured**; CivLink does not bundle, start, or
  elevate them.
- v1.0 is a two-player, on-LAN build. No official public relay, no telemetry,
  no log upload, no crash reporting.

## Reporting a vulnerability

Please report privately instead of opening a public issue. Include:

- affected version / file hash,
- steps to reproduce (isolated from any real matchroom),
- impact and suggested fix.

Contact channel will be filled in before publication (project has no public
channel yet). Until then, open a GitHub issue titled `[SECURITY]` with only
the minimum necessary detail, or contact the maintainer privately if a
security advisory is enabled.

I will acknowledge within 7 days where possible, triage severity, and publish
a fix or mitigation in a release note. Do not include live personal data,
room names, or real credentials in a report; redact them (the GUI diagnostic
export does the same).

## Disclosure policy

- Critical (remote code execution / privilege escalation in a shipped
  binary): coordinate disclosure, fix first.
- High/medium: fix in the next patch release, credit reporter if desired.
- Low / documentation-only: public issue is fine.

## Integrity and build security

- Native binaries (`civlink-agent.exe`, `civlink_hook.dll`,
  `civlink_client.dll`, `civlink_ctl.exe`) are built from audited source with
  `/MT` static CRT and a pinned MinHook v1.3.4 tree; release notes publish
  SHA-256 values for cross-checking.
- The Tauri GUI embeds the frontend at build time; accept it only from a
  trusted release note with matching hashes.
- Never run a CivLink binary whose provenance you cannot verify.

## Non-goals of v1.0 (explicit)

- No network authentication/encryption: discovery frames and the CVLH2
  datapath are plaintext by design in this prototype. Do not use on a network
  you do not trust.
- No anonymous statistics, no public relay, no global matchmaking.
