# metric-helper v3 离线修复验证记录

- 脚本：`CivLink-M0A-audit\scripts\set-broadcast-path.ps1`
- 授权依据：REV-005 复核决断第 ③ 条——"metric helper 允许离线修复并接受代码复核，暂不授权实际应用"
- 执行方式：**仅离线验证**。所有 `apply` / `restore` 测试都止步于 `-DryRun` 或权限门禁，**没有任何一次真实修改网卡 metric**。
- 验证日期：2026-11-12
- 验证环境：PC-A（DESKTOP-E9ERP1I，Windows 11 build 26100.4946），非管理员 PowerShell 5.1

---

## §1 修复的缺陷（对照 REV-004 / REV-005 复核意见）

| 编号 | 复核指出的问题 | v3 的处置 | 验证用例 |
|---|---|---|---|
| **D-1** | apply 会**覆盖**已有备份；第二次 apply 时改动集为空，就把好备份写成了 `entries: []` | 每次 apply 写入**新的时间戳文件**（`civlink-metric-<stamp>.json`），永不覆盖；改动集为空时**直接退出、不写备份** | T3、T12 |
| **D-2** | keep 接口的**原始** metric / AutomaticMetric 没被保存，但 apply 会钉住它 | 备份新增 `keep.OriginalMetric` / `keep.OriginalAuto` / `keep.TargetMetric` | T7（合成备份结构） |
| **D-3** | restore 每步都用 `-ErrorAction SilentlyContinue`，失败静默 | 统一走 `Set-Metric`（`-ErrorAction Stop` + try/catch），失败计入 `$script:Failures` | 代码复核 |
| **D-4** | restore 把出口检查 `| Out-Null` 丢弃，失败也报成功 | 新增 `Test-Row` 逐项 **readback 校验**；任何不一致 → **exit 3**；apply 亦然 → **exit 4** | T5、T6、T8 |
| **D-5** | 无法在不改任何东西的前提下留下可信状态表 | 新增 `snapshot` 动作：写 JSON + TXT 状态表，零改动 | T2 |
| **D-6** | （v3 自查新发现）抬高计划会把**回环接口**也一起抬；回环不承载广播，纯属扩大影响面 | `Test-IfExcluded` 排除 loopback / 127.x，计划里单独列出 "skip" | T13 |

另外补强：

- **备份 schema 版本**：`schema = 2`。restore 读 v2 旧备份会**明确拒绝**并说明原因（v2 无 keep 原始值、且可能是空改动集）。
- **拒绝空改动集 restore**：即使 schema 正确，`changed` 为空也拒绝（这正是 v2 那次事故的形态）。
- **`-DryRun` 与权限解耦**：v2 在动作分派前就检查管理员，导致 dry run 也需要提权；v3 把权限门禁放进各动作、且放在 `-DryRun` 之后，dry run 保持只读。**注意：这是测试中发现并修掉的回归**——第一版 v3 把门禁删在分派前，非管理员 dry run 会一路走到写文件前才被拦；现在 dry run 与只读动作真的一次都不提权。
- **`list-backups`**：只读列出所有备份及其 schema / peer / keepIf / 改动条数，便于审计判断哪份可用。
- **退出码**：0 成功 / 1 需管理员 / 2 参数或备份不可用 / 3 restore 校验失败 / 4 apply 校验失败 / 5 拒绝（同 peer 已有备份、或空改动集）。

---

## §2 验证用例与结果（全部通过）

| 用例 | 内容 | 期望 | 实测 |
|---|---|---|---|
| T1 | `-Action status -PeerIp 192.168.31.214`（只读） | 打印接口表、预测出口、判定 `[OK]`，exit 0 | ✅ exit 0；预测 if=10 WLAN == peer path if=10 |
| T2 | `-Action snapshot`（只读） | 生成 json+txt 状态表，零改动 | ✅ 2579 B + 724 B，exit 0 |
| T3 | `-Action apply ... -DryRun`（无竞争接口） | 打印"NOTHING TO DO"，不写备份，exit 0 | ✅ exit 0，备份数不变 |
| T4 | `-Action list-backups` | 空目录打印 `(none)`，exit 0 | ✅ exit 0 |
| T5 | `-Action restore`（无 v3 备份） | 明确报错，exit 2 | ✅ exit 2 |
| T6 | `-Action restore -BackupFile <v2 旧备份>` | 以 schema 不足为由拒绝，exit 2 | ✅ exit 2 |
| T7 | `-Action restore -DryRun`（合成 v3 备份） | 只打印还原计划，不动网卡，exit 0 | ✅ 列出 if=18→1 / if=15→35 / if=10→45 |
| T8 | restore 指向 `changed: []` 的备份 | 拒绝，exit 2 | ✅ exit 2 |
| T9 | `-Action apply` 缺 `-PeerIp` | 拒绝并给示例，exit 2 | ✅ exit 2 |
| T10 | `-Action apply`（非管理员，无竞争接口） | 先给出计划，因无改动退出 0，不写备份 | ✅ exit 0 |
| T11 | `-Action apply -DryRun -PeerIp 192.168.191.200` | 给出抬高 3 个接口的计划 | ✅ 见 T13（D-6 修复后为 2 个） |
| T12 | `-Action apply`（非管理员 + 有改动计划） | **必须拒绝**，exit 1，**不写备份** | ✅ exit 1，备份数 before=2 after=2 |
| T13 | 同 T11，D-6 修复后 | 跳过回环 if=1，只抬 2 个接口 | ✅ skip if=1 (127.0.0.1/8)，raise if=10 / if=18 |

**测试副作用声明**：全部用例在 `%TEMP%\civlink-v3-test\` 做备份目录隔离，未触碰 `%USERPROFILE%\civlink-metric-backups\`；未对任何网卡执行 `Set-NetIPInterface`（T12 在门禁处 exit 1，未进入写路径）。

---

## §3 仍未做的事（必须由审计/用户决定）

1. **未在真实网卡上应用**。REV-005 只授权离线修复 + 代码复核。
2. **未修复 PC-A 当前被改过的 metric**。备份 `entries: []` 不可作凭证；REV-005 要求先重建可信状态表再决定。v3 的 `snapshot` 动作正是为此准备的读取工具，但**是否用它作为恢复依据仍需批准**。
3. **未与 PC-B 侧副本同步**。PC-B 手上仍是 v2（`76DD95B0…`）。在获得批准前不应让 PC-B 替换副本，避免"看起来可以用了"的误解。
4. **G2 判据修订未落盘**。REV-005 已指出 G2 用 PowerShell bind 发包，不能代表 Civ6 的实际发包路径；操作单/交接文档的 G2 章节应改为"由游戏本体发包"，该修订尚未提交。
