# CivLink nightly 包（2026-11-19）

> 状态：**打包完成，非发布候选**。M0-E 设计复审（`docs/M0E-REVIEW-2.md`）尚未返回；没有任何双机测试针对此包执行过。

## 1. 为什么打这个包

`dist\civlink-beta-20261114\` 是 2026-11-14 的旧 beta，与当前已审计产物完全脱节（agent 382,464 B/`93F17516…` vs 现在 464,384 B/`15321D49…`；且缺 `civlink_client.dll`、缺 GUI）。此前 `docs/M0D-RELEASE-READINESS-20261118.md` 已把「以当前产物重建 dist」登记为发布前必做项。本包是该登记项的一次执行，用作**自测与跨机复现**的载体，不是对外发布物。

## 2. 包内容

目录 `dist\civlink-20261119-nightly\`，同名 zip `dist\civlink-20261119-nightly.zip`（600,458 B / sha256 `CC5A5DBA093FF011FB287220DBA719E6E203AF84AA524AE2922251CD317F97A4`）。

| 文件 | 字节 | sha256 |
| --- | --- | --- |
| `civlink-agent.exe` | 464,384 | `15321D49806517028ECE8CC8A3DC8B0ED855C410915295CAF72EBEF4DDF06267` |
| `civlink_hook.dll` | 119,808 | `33438AD5844208E7689377668FB22381E285532938C8D3851B10D9E3B5B16376` |
| `civlink_client.dll` | 149,504 | `F3816C5E0E6C5BD5920CDCE8AA2B5378623E6420A5C1966E275D663C1B8385D3` |
| `civlink_ctl.exe` | 188,416 | `6FCE456E4156873F093732253E0381872F0CDEAAFFF61655D9460ABB73634D26` |
| `civlink_tray.exe` | 27,648 | `F49CE00632DBD15B06E41927B99F140A2F5A0DEE51FB3ACE2E406A2768C15582` |
| `civlink-relay.exe` | 262,144 | `9E323F818AF0DE7699F6C3DBA7D29FB786BBC27CDC2F2D5B908E935A7D60C98C` |
| `fixture-reply-set\` | 29 文件 / 88,156 | 见 `MANIFEST.txt` |
| `MANIFEST.txt` | 4,131 | `3D1F3726702EB56959E6054F680CA3FFE1EFA80C6C9BA0B8DB521E01B4ACD289` |
| `VERSIONS.txt` | 2,443 | `D8B9FFDE885FCC9EC608E30E1A05185F4785CFB9741537DC5D85A82DE48C2A30` |

`VERSIONS.txt` 说明了三个 agent 模式的语义（真实房间 / 模拟房间 / reserve-62900）与**正确的启动顺序**（先建房再启 agent，否则 agent 占满 62901–62999 使游戏建不了房），并写明本包未做双机验证。

## 3. 与旧包的关系

旧包保留不动（`dist\civlink-beta-20261114\`），因为它对应 F4-BETA 采信证据 `M0A\captures\F4-beta-20261114-174214` 与 `docs\F4-BETA-ACCEPTANCE-20261114.md`。删掉会让历史证据失去可复现的二进制。两个包并存时以本包为当前态。

## 4. 没证明什么

1. 没有双机验证：PC-B 于 2026-11-19 00:44 探测离线。
2. 没有验证 GUI 打包形态：`civlink_tray.exe` 与 `fixture-reply-set` 同目录的部署假设（审计 N2-2）未在干净机器上试过。
3. 没有验证 relay 与本包其他组件的版本搭配：`civlink-relay.exe` 仍是 F3 阶段产物（0.1.0），未随 M0-C/M0-E 重编。
4. 不改变 M0-E 的任何边界：不证明跨机、不证明真实客户端加入、不勾 E2-A/E2-B/E3、不移动 Gate A/B。
