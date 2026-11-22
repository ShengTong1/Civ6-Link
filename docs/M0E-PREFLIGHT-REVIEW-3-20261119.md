# M0-E Preflight v3 Mechanical Review (2026-11-19)

VERDICT: PASS

All 6 points hold against the on-disk bytes (hashes confirmed as stated).
Scope: read-only mechanical verification of the v3 finalization vs P-1..P-15.
This is a readiness check only: a PASS here is NOT a claim that two-machine MP
is playable, that E2-A/E2-B/E3 passed, or that Gate A/B moved.

## 1. P-14 C1.1 filename + MZ header - HOLDS
run-m0e-preflight.v3.ps1:133-159: PathType Leaf, then leaf name -ine
'civlink-agent.exe' -> FAIL, then first 2 bytes must be 'MZ' -> FAIL, else PASS.
Evidence v3-t2-agentpath-ps1.txt:4 `FAIL C1.1 the file ...run-m0e-preflight.v3.ps1
is named 'run-m0e-preflight.v3.ps1' - civlink-agent.exe expected`, headline 11
checks. Fake PASS gone. MZ branch verified by code read (no dedicated capture).

## 2. P-11 package MANIFEST missing/unlisted = FAIL - HOLDS
Code :170-197: isPackage = VERSIONS.txt present; missing/unlisted MANIFEST ->
FAIL C1.2 in package, WARN outside. Control v3m-control-no-manifest.txt:4-5
PASS C1.1 + `FAIL C1.2 release package ... has NO MANIFEST.txt`; :26
`ACTION NEEDED - 1 FAIL, 5 WARN, 12 checks`, exit 2 (MUTATION-RECORD:14,27).
Contrast m3 mutant: WARN C1.2, exit 0. Residual: deleting VERSIONS.txt demotes
to WARN (acknowledged in-source :168-169; inherent to local marker).

## 3. P-1 C2.2/C2.3 WARN when game not running - HOLDS
Code :213-232 + :449-465: gamePid=0 always emits WARN C2.2/C2.3 ("NOT verified")
and adds the game CAVEAT to READY WITH CAVEATS; never a bare READY.
v3-t1-baseline-dev.txt:6-8 both WARN lines; :26-31 `READY WITH CAVEATS -
0 FAIL, 6 WARN, 12 checks` + game CAVEAT. Same lines in t2/t3/control/m3.

## 4. P-15 count 12/11 + header - HOLDS
Header :60-62 now says 12 with Agent, 11 when C1.1 fails (C1.2 skipped) -
the wrong "CONSTANT 12" claim is gone. C1.2 sits in `if ($agentValid)` (:161).
12 checks: t1:26, t4:26, control/m3/m4:26. 11 checks: t2 (bad name):25,
t3 (dir as -AgentPath):25. Matches exactly.

## 5. P-10/P-3 layout-independent path + readable FAIL - HOLDS
run.ps1:109-129: candidates = scriptDir\civlink-agent.exe first, then
dist\civlink-*-nightly sorted Name -Descending (newest); no hard-coded date
(grep 20261119 in run.ps1 = comments/runbook only). No hit -> print candidates
+ FAIL C1.1. fix.ps1:71-85 mirrors this; :90-93 PathType Leaf + readable FATAL;
:40 [ValidateRange(1,9999)]. Evidence: t1 dev layout PASS C1.1; t3 dir gives
`FAIL C1.1 agent exe not found: <dir>`, full output, 11 checks, no crash.
Minor: fix.ps1:82 keeps hard-coded date only as a last-resort fallback when no
nightly dir exists - not the primary resolver; claim still holds.

## 6. Mutation-record honest wording - HOLDS
MUTATION-RECORD.txt:9-14 table column "catch layer": M4 ASSERTION (headline +
caveat), M3 ASSERTION (FAIL->WARN + caveat + WARN 5->6), control EXIT CODE.
:29-32 verbatim "M3/M4 are caught at the ASSERTION layer only ... NOT by exit
code"; exit-code evidence from v1 M1 and this control (0->2); "Do NOT state
'mutations were caught' without naming which layer." Raw evidence agrees:
m4 bare READY exit 0, m3 WARN exit 0, control FAIL C1.2 exit 2.
