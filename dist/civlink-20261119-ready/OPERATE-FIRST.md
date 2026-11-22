CivLink M0-E ready package - shortest operation note (2026-11-19)
================================================================

This is a READINESS-CHECKED package, NOT a proven two-player setup.
No cross-machine join test has been run. Read the Boundary section.

What is new in this package vs civlink-20261119-nightly
-------------------------------------------------------
- run-m0e-preflight.ps1 : read-only readiness check (no admin, no changes).
- fix-m0e-preflight.ps1 : OPTIONAL admin helper, adds 2 inbound Allow rules
                          and can lower the Radmin VPN interface metric.
- this note. All three are listed in MANIFEST.txt.

Minimum steps (HOST / A side, real-room mode)
---------------------------------------------
0. UNZIP the whole package to a folder. Run the preflight BEFORE anything else:
     powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run-m0e-preflight.ps1
   exit 0 READY / "READY WITH CAVEATS" (read each caveat) / exit 2 ACTION NEEDED.
   To check a copied Agent path: add -AgentPath "<full path>\civlink-agent.exe".
   If C4.1 says NO Allow rule but prints a ZERO-UAC REMEDY: run the Agent from
   that byte-identical covered path instead of raising UAC.
1. Start Civilization VI, create a LAN room. The game binds 0.0.0.0:62900.
2. Re-run preflight: the game 62900/62056 premise must now PASS (full READY).
3. Start the Agent (real-room mode):
     civlink-agent.exe --sim-lan-listen 0.0.0.0 --discovery-completion --reserve-62900
   Order matters: if the Agent starts first it takes 62901..62999 and the game
   cannot create the room. --reserve-62900 keeps 62900 for the game.
4. Client (B side) refreshes the LAN list. The real room must appear.

Boundary (MANDATORY)
--------------------
The preflight checks only mechanical readiness (firewall path/profile, ports,
metric, integrity). "READY WITH CAVEATS" names what is NOT verified - a caveat
is not a pass. Cross-machine join, data path 62056, long-run stability are NOT
verified. No E2-A/E2-B/E3 claim, no Gate A/B move. Mechanical evidence != two-player proof.

Undo the optional fix helper
----------------------------
See the UNDO section at the top of fix-m0e-preflight.ps1. It deletes only its own
two firewall rules by name and restores the metric from scripts\network-env backup.