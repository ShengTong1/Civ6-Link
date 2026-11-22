# M0-E 双机验证操作单审计报告（M0E-RUNBOOK-REVIEW-20261119）

- 被审：`docs\M0E-DUALMACHINE-RUNBOOK-20261119.md` v1.0（77 行）
- 权威基准：`docs\M0E-DISCOVERY-COMPLETION-20261118.md` v2.1（22,505 B / `7AF86CB4…206B25B` 实算一致）；`docs\M0E-REVIEW-2.md`（PASS 有条件通过）
- 审计方式：只读 + 机械核对（哈希实算、`civlink\agent\src\main.rs` 逐行比对、GUI 源码抽查）

## 裁定：有条件通过（允许在 PC-B 上线后直接使用，但应先落实 N-1/N-2 两处文字修订，约 5 分钟工作量）

关键数字：核对哈希/路径 9 项全对（设计 v2.1、REVIEW-2、nightly 8 文件+zip、冻结 agent 15321D49、main.rs E56A3056、tray F49CE006、MANIFEST 36/36 实数）；summary 行名与 `main.rs:3110-3345` summarize 全部对得上；发现 1 中 4 低。

## A 组：技术正确性

**A1（一致）**：§3 命令 `--listen-seconds 1800 --sim-lan-listen 0.0.0.0 --discovery-completion --reserve-62900` 与设计 §5.1 五条约束逐条相符：①配了 `--sim-lan-listen`（0.0.0.0 通配为 tray 自检认可组合，`civlink_tray.cs:687`）；②无 `--simulate`；③无 `--sim-real-capture`；④显式 `--reserve-62900`；⑤未改 `--game-discovery-addr`（默认 `127.0.0.1:62900`）。启动顺序（先建房后启 agent）与 m25442 教训、nightly VERSIONS.txt 口径一致。

**A2（行名全对，两处期望值口径偏差→N-2）**：与 `main.rs` summarize 实际输出逐行比对：`requests seen`（3279）、`port 62900 : reserved, not bound`（3244）、`replays sent`（3282）、`duplicate magic`（3303）、`pages collected`/`pages forwarded`（3285/3288，操作单合并成一行显示，可接受）、`egress pinned`（3314）、`timeouts`（3290）、`short replies`（3294）——行名与格式全部存在。偏差：①`requests seen` 每次 B 刷新实际 ≈99（100 magic 中 99 落在 agent 的 62901-62999，1 落游戏 62900），操作单"每次刷新 ≥1"字面为真但易误读为 1；②`duplicate magic` 期望公式 `100×N − N = 99N` 与设计 §4.7 实测口径不符（每轮 99 拦截 −1 轮 = **98**，见 M0E-B2-fixed：seen 99/replays 1/dup 98），应为 `≈98×N`。

**A3（够用，但 Ctrl+C 路径有误→N-1）**：1800 s = 30 min，覆盖 B 机刷新+加入+5 分钟对局有余量（前提是建房后及时启动 agent 并通知 B 开始）。超时退出路径正常：`main.rs:2798` 循环条件到期→跳出→`summarize`（3110）→`summary.txt` 落盘（3100-3106），失败会报错而非静默。**但 CLI Ctrl+C 无任何信号处理**（全文无 ctrlc/console ctrl handler），强杀进程不会走 3110 落盘路径——§5"超时或 Ctrl+C 后读 summary.txt"对 CLI 是错的；GUI tray 的停止按钮是写 ASCII stop 文件等 20 s（`civlink_tray.cs:564`），属优雅退出。操作单应改为：等 1800 s 自然超时，或用 GUI 停止 / `--stop-file`，不要按 Ctrl+C。

**A4（建议成立，无误导）**："不要反复重试"的理由成立：每轮刷新 100 magic，B 机 >750 ms 冷却窗的重试**会**触发新一轮重放+22 页回发（去重按 (client_ip, client_port)，换端口/超窗即新轮），但 62056 直连失败是数据面问题，反复刷新解决不了且白白消耗 `--completion-max-replies`（默认 1000）预算——预算耗尽后 agent 静默，会把故障表象进一步复杂化。建议成立。另注意 §6 未收录冷却窗用户须知（见 N-3）。

## B 组：完整性

**B1（基本无遗漏，两小缺口→N-4/N-5）**：B 机 nightly 产物已列入前置（"拷贝整个 nightly 目录"）——虽然 B 侧作为纯客户端只跑 Civ6 不跑 agent，拷贝整包用于哈希对账可接受但操作单未写校验步骤（N-5）。Civ6 版本一致有意义：22 页广告格式/页数与 62056 协议均为版本相关，跨版本可能既改发现载荷也致加入失败，操作单保留该约束正确。防火墙 Private+Public 双 profile 已覆盖已知历史坑；未覆盖的缺口是 A 机启动 agent 前不检查 62901-62999 是否被残留 agent 占用（上次跑完未退干净 → 本轮 bind fail 或旧 agent 抢答），见 N-4。

**B2（口径一致）**：§7 与项目口径逐条相符：不勾 E2-A/E2-B/E3、明确"E2 结案需按其原始定义复核（Gate A 复核流程）"、不移动 Gate、与设计 §11"不得据此宣称跨机可用/真实客户端可加入"和 REVIEW-2 §1"机械/模拟证据≠双人验证"一致；§1 边界排除 Fake-IP/Noise/Relay 亦相符。小注（不扣分）：§7 "M-1 PASS"（对局 ≥5 分钟）是操作单自定义的行为判据，未引用 M-1 原始验收定义——只作行为记录无碍，若后续要据此"结案 M-1"仍需走其自身流程。

**B3（一致）**：§5"归档 `M0A\captures\M0E-crossmachine-<时间戳>\`（项目根或审计仓库内均可，登记时按设计 §10 v2.1 口径注明）"与设计 §10 v2.1 N-1 勘误的两处分布口径（审计仓库内 completion/mutation/B2 系列、项目根 C3/B1/regress/C1/gui 系列）相符；新增证据两个落点均未在既有清单内，允许任选+登记注明符合勘误精神。

## C 组：文档质量

**C1（可独立执行）**：命令块可直接复制（占位符 `<nightly 目录>`/`<证据目录>` 有明确语境）；GUI 替代路径（勾选「回真实房间（M0-E）」，`civlink_tray.cs:368` 实存且拼参逻辑与 CLI 等价：`--sim-lan-listen <IP> --reserve-62900 --discovery-completion`，不传 `--simulate`）给了不熟 CLI 的执行者出路；§5 期望表 + §6 排查表使非专家可自行判断 PASS/FAIL。小瑕疵：`Get-NetUDPEndpoint` 假定进程名 `CivilizationVI_DX12`，DX11 版安装为 `CivilizationVI.exe` 时该行报错（不阻断，属环境差异）。

**C2（无陈旧引用）**：抽查 9 项全部实算一致——①设计文档 22,505 B / `7AF86CB4…206B25B` ✓；②`docs\M0E-REVIEW-2.md` 16,824 B ✓；③`docs\M0B-DUALMACHINE-RUNBOOK-20261117.md` 存在（6,561 B）✓；④`docs\NIGHTLY-PACKAGE-20261119.md` 存在 ✓；⑤agent `15321D49…`（nightly 与冻结件均 464,384 B）✓；⑥tray `F49CE006…`（27,648 B）✓；⑦zip `CC5A5DBA…`（600,458 B）✓；⑧MANIFEST 36/36 哈希行实数 ✓；⑨main.rs `E56A3056…`（176,308 B）✓。未发现作废哈希/路径。

## 新发现

| 编号 | 级别 | 内容 |
|---|---|---|
| N-1 | 中 | §5 "agent 退出（超时或 Ctrl+C）后读 summary.txt"：CLI Ctrl+C 无处理函数，进程被杀不落盘。应改为"等 1800 s 自然超时，或用 GUI 停止 / `--stop-file`"（依据：main.rs 全文无 ctrl 处理；tray 停止走 stop 文件）。 |
| N-2 | 低 | §5 期望值口径：`requests seen` 每次刷新实际 ≈99 非 1；`duplicate magic` 公式应为 `≈98×N`（设计 §4.7 实测 99/1/98），现写 `100×N−N=99N`。 |
| N-3 | 低 | §6 未收录设计 v2.1 N-6 冷却窗用户须知：B 机 750 ms 内连点刷新会被静默忽略（客户端表现为"这次没搜到"），排查表应加一行防误判。 |
| N-4 | 低 | §3 启动 agent 前未检查 62901-62999 无残留 agent 占用（上轮未退干净 → bind fail/旧进程抢答）；建议加一步 `Get-NetUDPEndpoint -LocalPort 62901-62999` 预检或注明看 summary `bind fail` 行。 |
| N-5 | 低 | B 机拷贝 nightly 后无哈希对账步骤；建议注明"按 MANIFEST.txt 抽验 agent/tray 两项"。 |

（观察，不计级：设计文档自身第 3 行仍写"版本 v2.0"而 §0 版本史已列 v2.1 为本版，属被引文档的内部小瑕，非操作单问题。）

## 结论

操作单技术内容与设计 v2.1、agent 0.4.6 实现高度一致，无陈旧引用，判定边界与项目口径相符。**允许在 PC-B 上线后使用**；建议执行前先修 N-1（必须，避免执行者 Ctrl+C 后找不到 summary 而误判失败）与 N-2（建议，避免对账时被 99 vs 98 的差值误导）；N-3~N-5 随下次回写一并处理即可。
