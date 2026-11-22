# E2-B 双机真实验证审计任务书（子代理，预置）

**审计对象**：双机真实验证报告 `docs/M0B-DUALMACHINE-VERIFICATION-20261117.md`（执行后填写）
与证据目录 `M0A\captures\M0B-dualmachine-<stamp>\`（执行后产生）。

**背景**：M0-B Discovery Adapter（agent 绑 62901-62999 + 游戏占 62900 双路应答 + 真实广告页捕获/应答）
已验证到步骤 6（自检 10/10 PASS + 审计 205819b9 PASS 必改 0）。步骤 7 = 双机真实验证：
A 机 Civ6 建房 + agent --sim-lan-listen 0.0.0.0 --sim-real-capture --simulate fixture（hook 39D6735D 先注入后建房）；
B 机局域网刷新看真实房名（dingzihan2022 的游戏）+ 加入；数据面直连 A 机 Civ6 :62056。

**审计维度**：
1. **A 证据真实性**：agent summary/frame-log/real-page-01..22.bin/stderr 哈希复核、captured=22/active=yes、
   requests seen/replied 语义、时间戳与用户操作时序一致。
2. **B 证据真实性**：用户口述（oral 记录）+ 可选 B 侧 civtrace_*_client.log（sendto dst=<A机WLAN IP>:62056）。
3. **判定口径**：对照 M0B-DUALMACHINE-RUNBOOK §5 判定（B 见真实房名+成功加入=PASS；加入卡住=部分；FAIL 排查顺序）。
4. **边界**：不得把机械证据（自检 10/10/F5）宣传为双人验证；不证明对局完整性/长稳/跨网/Noise；
   E2-A/E3/Gate A 复核另行登记。
5. **登记链**：README v1.31+ 修订块、HANDOVER 第 19 项更新、结案报告与审计报告哈希引用。

**输出**：`docs/M0B-DUALMACHINE-REVIEW.md`（裁定：通过/有条件通过/不通过 + 必改/建议列表）。

**注意**：审计前先读 `docs/M0B-DUALMACHINE-VERIFICATION-20261117.md`、`docs/M0B-DUALMACHINE-RUNBOOK-20261117.md`、
`docs/M0B-FINAL-PROGRAM-PLAN-20261117.md`（v1.1）、`docs/M0B-ADAPTER-SELFTEST-REVIEW.md`（前置审计）。