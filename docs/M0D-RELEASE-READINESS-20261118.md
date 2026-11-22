# CivLink 开源发布就绪度评估（2026-11-18）

> 本文件是**发布就绪度内部评估**，不是发布骨架文件，不在合规审计
> `885ef6ac`（`M0D-OPENSOURCE-COMPLIANCE-REVIEW-20261118.md`）的审计范围。
> 结论以磁盘实测为准；机械/headless/模拟证据一律不等于双人真实联机验证。

## 1. 结论：**尚不可直接发布**（NOT READY）

合规文件（LICENSE / LICENSE-DOCS / THIRD-PARTY-NOTICES / CONTRIBUTING /
SECURITY）已落盘并送审，GUI 已两轮审计闭环并登记（README v1.35 /
HANDOVER 第22项）。但**发布包目录里的二进制仍是 2026-11-14 的旧 beta**，
与当前已审计源码产物不一致；若直接把 `dist/` 当发布物，用户拿到的将是
未经 C1/C2/GUI 审计的旧版本。

## 2. 关键发现：dist 与当前产物脱节（磁盘实测）

`dist\civlink-beta-20261114\` 内容：

| 文件 | 字节 | SHA-256 前12位 |
|---|---|---|
| civlink-agent.exe | 382,464 | `93f1751620c2` |
| civlink-relay.exe | 262,144 | `9e323f818af0` |
| civlink_ctl.exe | 173,056 | `23923dfbaab3` |
| civlink_hook.dll | 119,808 | `9424fc25fb45` |
| check-f4-package.ps1 | 3,966 | `be45a5fe1ad6` |
| run-f4-beta.ps1 | 14,079 | `f7b5643903fa` |
| KNOWN-LIMITATIONS.md | 4,555 | `e007c115c369` |
| VERSIONS.txt | 152 | `62cdc2d5a341` |

当前源码构建（`civlink\` 实测）：

| 文件 | 字节 | SHA-256 前12位 | 说明 |
|---|---|---|---|
| civlink-agent.exe | 421,376 | `4390af9df56a` | 含 C1 `--reserve-62900`、C2 `--iface` 能力（agent 0.4.6） |
| civlink_hook.dll | 119,808 | `33438ad58442` | 与旧包同尺寸不同哈希 |
| civlink_client.dll | 149,504 | `f3816c5e0e6c` | **新文件，旧包完全没有** |
| civlink_ctl.exe | 188,416 | `6fce456e4156` | 含 inject-client / --iface / 自动探测 |
| civlink_tray.exe | 26,112 | `9b480fe0c818` | **新文件，旧包完全没有**（GUI 产品版） |

结论：`dist/civlink-beta-20261114` 只能作为**历史 F4-beta 证据**保留，
不得作为 v1.0 发布物。发布前必须用当前源码重新打包，并逐项登记哈希。

## 3. 发布前必须完成（阻塞项）

1. **重新打包**：以当前 `civlink\` 五个产物 + GUI 运行所需
   `fixture-reply-set\`（审计 N2-2：exe 同目录须有该目录）生成新 dist，
   并写 `VERSIONS.txt` / `MANIFEST`（SHA-256）+ 复现构建脚本。
2. **合规审计**：`885ef6ac` 裁定 **有条件通过**、`allow_open_source_skeleton_ready
   = true`（见 `docs/M0D-OPENSOURCE-COMPLIANCE-REVIEW-20261118.md` §6 修复记录）。
   其实验室 4 项新发现中 N-1（HDE32/64 的 Patkov 署名）、N-3/N-4（README
   bare CR 与强调标记）**已由项目侧关闭**；N-2（证据路径口径）属发布时处理；
   第 3 项（`SECURITY.md` 漏洞联系渠道）**仍未关闭，发布前必须补齐**。
3. **三项产品裁定**（**二项已拍板、一项待定**，用户 2026-11-18 m29480）：
   - 版权署名：**已定 `shengtong`**（`LICENSE:3`、`docs/LICENSE-DOCS.md:30-33`
     已同步）；
   - GUI 白名单最终清单：**已定** `CivilizationVI_DX12` / `CivilizationVI` /
     `CivilizationVI_DX11` 三个（`civlink_tray.cs` `Whitelist` 已是该三项）；
   - 普通 A 房主默认流程：**仍待拍板**——需先向负责人解释"只注入 hook"
     与"注入并自动启 agent（含 `--sim-lan-listen` 模拟层）"两种默认流程的
     差异，再由负责人选定。
4. **P0/C4 未结案**：M-1 加入/数据面验证、真实对局跨机通道取证、
   E2-A/E2-B/E3 结案、Gate A 复核均未完成。发布说明必须保留
   "双人真实联机未验证 / Gate A 未批准"的边界语，**不得**写成已通过。

## 4. 已就绪部分（可复用）

- GUI：两轮审计闭环（首轮 NOT PASS → N-A..N-G 修复 → 复审 `F9623EBD`
  PASS），headless 自检 33/33、变异判别 M1=3/M2=1/M3=2 失败、真实窗口
  构造冒烟 PASS；已登记 README v1.35 / HANDOVER 第22项。
- 合规骨架：/LICENSE、docs/LICENSE-DOCS.md、/THIRD-PARTY-NOTICES.md、
  /CONTRIBUTING.md、/SECURITY.md 共 5 文件已落盘（UTF-8 无 BOM / LF），
  `885ef6ac` 已裁定**有条件通过、允许骨架就绪**；N-1/N-3/N-4 已关闭，
  `SECURITY.md` 联系渠道仍待补。当前哈希：`LICENSE` 1,587 B/`a5a3e2ce…`、
  `docs/LICENSE-DOCS.md` 1,792 B/`032df19f…`、`THIRD-PARTY-NOTICES.md`
  3,012 B/`b1a4b603…`、`CONTRIBUTING.md` 3,316 B/`93db49c2…`、`SECURITY.md`
  3,149 B/`cb223d78…`。
- 文档内部链接：全仓 159 个 Markdown、42 个相对链接，4 处"死链"均为
  PowerShell 代码块内 `](...)` 语法误报，**实际 0 个真死链**。

## 4.1 证据路径口径（审计 N-2）

审计引用的 `M0A\captures\...` 相对路径，其**实体位于父项目根**
`C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\`，不在本 audit 快照根
`CivLink-M0A-audit\` 下。引用这些证据时须写全父项目根路径，或随发布包
附自检输出副本并登记新哈希；不得让读者按 audit 根拼接出不存在的路径。

## 5. 发布口径（强制）

> 当前所有证据均为工具级 / headless / 单机 / 探针级与机械对账。
> README v1.35 状态行明确：C2-b 机制层跨机验证完成（探针级），
> **真实游戏跨机对局待验证**。Gate A 未批准。任何发布说明不得
> 写"双人真实联机已通过"或据此勾掉 E2-A/E2-B/E3。
