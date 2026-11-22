# M0-E 预检：审计期间自查记录（不改动送审件）

> 时间：2026-11-19 11:07
> 状态：`run-m0e-preflight.ps1` 已按被审哈希冻结（17,408 B / `F60DE7779F2BCCF1C57F4B979D2387ABC1C0578A5DFA192326E27CBE3ADEB365`），本文件只记录我自查发现的问题，**待审计裁定返回后一并处置**，不在审计期间改动被审对象。

## 已发现的候选问题

### P-1（中）游戏未运行时 C2.2 / C2.3 整段静默跳过

`run-m0e-preflight.ps1:123` 是 `if ($gamePid -ne 0) { ... }`，游戏没跑时 `$gamePid = 0`，于是**62900 与 62056 两项检查完全不产生任何 PASS/WARN/FAIL 行**。

后果：

1. 检查总数会漂移。**实测两轮基线（`run1-nightly` 与 `run2-covered`）都是 `10 checks`，因为两次游戏都没运行**——完整跑应该出现 C2.2/C2.3 时是 12 项。任何按"检查数"或行数做断言的调用方会误判。
2. 更严重的是**语义丢失**：`run2-covered.txt` 结尾是 `PREFLIGHT: READY - 0 FAIL, 4 WARN, 10 checks`，而这一轮**游戏根本没运行**，62900 这个"建房必须持有"的前提一次都没被验证过。操作员看到 READY 会误以为"可以直接开双机了"。这不是假设——证据目录里就躺着一个在这样的状态下给出 READY 的样例。
3. 由此还暴露一个更基本的问题：**C2.2/C2.3 在任何一轮基线里都没被执行过**，所以它们的实现正确性目前没有任何证据支撑（只有代码阅读）。
3. 文档 `docs\M0E-PREFLIGHT-20261119.md` §2 的检查项表把 `C2.2 游戏持有 62900（FAIL 级）` 列为固定检查项，与实现的"条件执行"不一致——属于 B 组 C1 问题（文档说做了、代码没做）。

修法方向（待裁定后执行）：游戏未运行时不要整段跳过，而是显式输出
`WARN C2.2 62900 not verified - game not running; start the game and create the LAN room, then re-run`
`WARN C2.3 62056 not verified - game not running`
并在 `PREFLIGHT: READY` 分支里，若 C2.1 未 PASS，则把结论降级为 `PREFLIGHT: READY FOR HOST-ONLY (game not running yet)` 之类，避免"READY"被读成"可以直接开双机"。

### P-2（低）`Test-Coverage` 的 severity 参数对 C5 生效，但对 C2.2 没有对应机制

C5 已按"正在运行的版本"分级（`C5.CivilizationVI` 在跑 DX12 时降为 WARN，实测输出印证），这一点实现是对的。但 C2.2 是硬 FAIL，没有"游戏还没开"这一合法状态的分级——与 P-1 同源。

### P-3（低）参数校验缺失导致两类不友好退出

- `-AgentPath <目录>`：`Test-Path` 为真 → 走 `Get-FileHash`（对目录抛异常）→ 输出文件根本没写（`outline=0`），退出码 1，用户看不到任何可读信息。缺一个 `Test-Path -PathType Leaf`。
- `-VirtualAlias` / `-VirtualMetric`：**预检脚本根本没有这两个参数**（只有 `fix-` 脚本有）。我早先的对抗性测试用错脚本了，实际行为是 `NamedParameterNotFound` 退出 1，属正常。此项撤销。
- `-VirtualMetric 99999` 传给 `fix-` 脚本时 PowerShell 直接崩（`exit=-1`），因为 `[int]` 没有 `[ValidateRange]`。属低危（管理员手动输入才会踩），但加 `[ValidateRange(1,9999)]` 成本为零。

### P-4（信息）`Get-FileHash` 对不存在路径不判空

`run-m0e-preflight.ps1:226` 的 `if (Test-Path $want)` 已经守住了主路径，`228-233` 的 `coveredPaths` 也逐项 `Test-Path`，这部分是稳的。无问题，仅记录已核查。

## 我自己犯并已纠正的错误

- **审计期间改了送审文件**：11:00 左右我把第 14 行注释里的中文（netsh 输出被 GBK 终端渲染成乱码 `鍒涘缓鎴块棿鐐逛簡娌″弽搴?`）改成英文，使脚本变成纯 ASCII。这违反了"送审对象冻结"——上一轮 C2 审计的 L-3 条正是对同一问题的批评。**已按字节还原**，实测回到 `F60DE777…`，与送审哈希一致。
- 正确做法（下次）：纯 ASCII 化的价值（避免编码歧义）应当**在送审前**完成；送审后若确有编码隐患，只能记录为"建议项"并在裁定后再改，同时同步更新所有引用哈希。

## 待审计返回后的动作清单

1. 若裁定含 P-1 类问题 → 修 `run-m0e-preflight.ps1`（C2 段显式 WARN + READY 分级），重跑 4 个基线 + 2 个变异，更新证据与文档，**换新哈希后重新登记**。
2. 修 `fix-m0e-preflight.ps1` 的 `[ValidateRange]` 与 `Test-Path -PathType Leaf`。
3. 同步 `docs\M0E-PREFLIGHT-20261119.md` §2 表格与 §5 证据哈希。
4. 登记 README v1.37 + HANDOVER 第 24 项。

## 追加发现（P-5）

### P-5（中）操作单完全没有引用预检脚本

`docs\M0E-DUALMACHINE-RUNBOOK-20261119.md` 里 `preflight` 出现 **0 次**，§3 步骤 0 只写了"确认无残留 agent 占用发现端口（N-4）"这一条手写 PowerShell，没有指向新脚本。

后果：操作员拿到的是两份互不相干的文件，`M0E-PREFLIGHT-20261119.md` §7 声称的"顺序固定：preflight → READY → runbook"在操作单侧没有任何落地，实际执行时很可能被跳过——那这个脚本就等于白做。

但这属于**改动已被审计的操作单**（v1.1 / 6,696 B / `6C3BA55C…`，审计报告 `190DEF2C…` 已按该哈希 PASS），不能顺手改。处置方案：等预检审计裁定返回后，与 P-1 的脚本修正**合并成一次协调更新**：
1. 修 `run-m0e-preflight.ps1`（C2 显式 WARN + READY 分级）与 `fix-m0e-preflight.ps1`（校验）
2. 操作单升 v1.2：§3 步骤 0 换成"先跑 `run-m0e-preflight.ps1` 至 READY"
3. 全部重跑证据、换新哈希、更新文档、重新登记 README v1.37 + HANDOVER 第 24 项

一次性换掉所有引用哈希，避免中间态出现"文档写 A 哈希、文件是 B"的错位。
## 追加发现（P-6）

### P-6（低→中）`fix-m0e-preflight.ps1` 的"不删规则"承诺与实现不符

头注释 L19 写：

```
#   * no firewall rule is deleted (existing rules are left alone)
```

但 L86 实际执行：

```powershell
netsh advfirewall firewall delete rule name="$($pair.Name)" | Out-Null
```

即"先按名字删自己的规则，再加回去"（`civlink-agent-m0e-udp-in` / `civlink-agent-m0e-tcp-in`）。这个设计本身是对的——同名规则需要先删才能刷新 `Program` 路径，否则会叠出两条指向不同路径整天打架的规则。**但它确实在删规则**，与头注释的绝对表述矛盾。

实际危害：删掉的只是脚本自己命名的两条规则，不会碰到用户的任何既有规则。所以是**文档准确性**问题，不是破坏性操作。但审计口径上"绝对承诺与实际不符"是必须改的，否则日后有人据此认为可以放心跑。

修法：把 L19 改成
`#   * no PRE-EXISTING rule is deleted. The script re-creates only its own two rules (#   civlink-agent-m0e-udp-in / -tcp-in) by name, which is required to refresh the Program path.`
并在 UNDO 段补一句：这两条规则也可能是别的 CivLink 版本加的，删前先 `netsh advfirewall firewall show rule name="civlink-agent-m0e-udp-in"` 看一眼 `Program` 指向。

### P-7（已核，无问题）`fix-` 脚本的复核确实会计入失败

L114-119 的判断是 `if ($hits.Count -lt 2 -or -not ($coverProfiles -contains 'Private') -or -not ($coverProfiles -contains 'Public')) { $script:Problems++ }`，末尾 `Problems -gt 0 → exit 2`。所以规则没真正生效时不会出现 "FIX: DONE"。**结论：无缺陷，撤销该项。**

### P-8（已核，无问题）`profile=any` 的回读形态与预检的覆盖算法相容

我先前担心 `profile=any` 会回读成 `Any` 而让预检的 `$missing` 计算错位。实测 `netsh advfirewall firewall show rule name=all dir=in verbose` 的 821 条规则里，`Profiles` 取值只有 6 种（`Domain,Private,Public` 304 条 / `Public` 264 / `Domain` 76 / `Private,Public` 74 / `Private` 65 / `Domain,Private` 38），**没有任何一条写成 `Any`**。所以 `Test-Coverage` 里 `if ($p -eq 'Any') { continue }` 那条分支实际用不上，而 `Domain,Private,Public` 能正确满足 `Private`/`Public` 两项。**结论：无缺陷。**

（顺带核实：现有 `civlink-agent.exe` Allow 规则大多是 `Private,Public`，2 条只有 `Public`；游戏 DX12 那条是 `Private,Public`，DX11 那条只有 `Public`——与 run1-nightly 输出一致。）
## P-1 的 C2 分支已实测（证据已归档）

我用一个自建的假游戏进程（`CivilizationVI_DX12.exe`，绑 `0.0.0.0:62900` + `0.0.0.0:62056`，命名为游戏进程名以命中预检的 `Get-Process -Name` 过滤）补齐了这一分支的执行证据：

- 证据 `M0A\captures\M0E-preflight-selftest-20261119-1110\run3-with-game-ports.txt`（2,666 B / `747059201FC0DCEDF2B421627D79AFFBBC80FC062210F4B2ACA986707623DABF`，pid 与时间戳已脱敏为 `<FAKE>` / `<scrubbed>`）
- 结果：`PASS C2.1` / `PASS C2.2 game holds 0.0.0.0:62900` / `PASS C2.3 game holds 0.0.0.0:62056`，检查数 **12**，`PREFLIGHT: ACTION NEEDED - 1 FAIL, 2 WARN, 12 checks`（exit 2，那 1 FAIL 仍是 C4.1 的 nightly 路径无规则，与本项无关）。

由此确认：

1. **C2.2/C2.3 的实现本身是对的**——不是死代码，端口检测、地址取值都正确，只是此前从未被执行到。
2. **P-1 的"检查数从 10 漂到 12"是真实存在的**，两轮基线（10）与这一轮（12）直接对照可见。
3. 但 P-1 的**严重性判定要下调**：C2.2 从未执行时给出的是 `WARN C2.1` + `10 checks`，而 READY 那轮（run2-covered）同时带着 4 个 WARN；操作员若只看末行 `PREFLIGHT: READY` 确实可能误判，但输出里 `WARN C2.1 Civ6 is not running` 是明写的。所以这是**信息设计缺陷**（READY 与 WARN 并置时语义被末行吃掉），不是"隐藏了致命问题"。仍应修，但不是阻断。

补充一处**测试方法学**说明：这个假进程只是占住两个端口、响应 `Get-Process` 名称匹配，它**不会**像真游戏那样应答 loopback 重放。所以本轮证据只证明 C2 分支的条件判定与计数，不证明 M0-E 重放链路——不得据此宣称联机或发现链路有任何进展。
## P-9（低，文档一致性）：证据目录文件数从 6 变成 7

`docs\M0E-PREFLIGHT-20261119.md` §5 的证据表列了 6 个文件（run1/run2/run4/mut-m1/mut-m2/MUTATION-RECORD）。新增 `run3-with-game-ports.txt` 后目录是 7 个。

该文档已按 `A61330C9…` 通过送审，不能现在改。登记时需在 README 修订块写明「证据目录在审计后补入 run3（C2 分支实测），预检文档 §5 的表未更新，以目录实际内容为准」；或者等 P-1 修正时一并把 §5 表补全并换哈希。

7 个文件的当前哈希（前 16 位）：`run1-nightly` `61176EC938555BCF`、`run2-covered` `30BEEA4846E723FB`、`run3-with-game-ports` `747059201FC0DCED`、`run4-tampered` `67D26BC571729884`、`mut-m1-nightly` `1CFF0C72D72C42C9`、`mut-m2-tampered` `00429CCD212EB339`、`MUTATION-RECORD` `C441A55BB55ED4F9`。

（注意 `mut-m2-tampered.txt` 现在是 2,325 B，早先记录也写 2,325 B，但哈希 `00429CCD…` 与更早一次读到的值不同——因为 M2 的运行时间戳每次都会变。这类"每次跑哈希都变"的证据本身就说明它不该按哈希登记，只能按断言行登记。）
## P-1 的现成补丁（待裁定后套用，现在不改）

### 补丁 A：C2 段不再整段跳过（替换 `run-m0e-preflight.ps1` L123-137 的 `if ($gamePid -ne 0) { … }` 结构）

改成"游戏没跑也输出两行 WARN"，并把 62900 未验证记进一个标志位 `$gamePortsVerified`：

```powershell
$gamePortsVerified = $false
if ($gamePid -eq 0) {
    Warn 'C2.2' '62900 NOT verified - Civ6 is not running. Create the LAN room, then re-run this script.'
    Warn 'C2.3' '62056 NOT verified - Civ6 is not running.'
} else {
    $eps = @(Get-NetUDPEndpoint -OwningProcess $gamePid -ErrorAction SilentlyContinue)
    $p62900 = @($eps | Where-Object { $_.LocalPort -eq 62900 })
    $p62056 = @($eps | Where-Object { $_.LocalPort -eq 62056 })
    if ($p62900.Count -gt 0) {
        Pass 'C2.2' ('game holds {0}:62900 (discovery)' -f $p62900[0].LocalAddress)
    } else {
        Fail 'C2.2' 'game does NOT hold 62900 - the LAN room is not created yet (M0-E replays to 127.0.0.1:62900 and needs it)'
    }
    if ($p62056.Count -gt 0) {
        Pass 'C2.3' ('game holds {0}:62056 (data path)' -f $p62056[0].LocalAddress)
        $gamePortsVerified = $true
    } else {
        Warn 'C2.3' 'game does not hold 62056 yet - data-path join (M-1) cannot work in this state'
    }
}
```

要点：`$gamePortsVerified` 只在 **62056 真的被游戏持有**（且 62900 也验过）时才为真。这样"游戏没跑"与"游戏跑了但没建房"都能区分出来，而不再是同一个静默跳过。

### 补丁 B：verdict 段区分"完整 READY"与"主机半就绪"（替换 L349-359）

```powershell
Emit ''
if ($script:Fails -gt 0) {
    Emit ("PREFLIGHT: ACTION NEEDED - {0} FAIL, {1} WARN, {2} checks" -f $script:Fails, $script:Warns, $script:Checks)
    Emit 'Fix every FAIL above, then re-run this script. Do not start the dual-machine run until it says READY.'
    $code = 2
} elseif (-not $gamePortsVerified) {
    Emit ("PREFLIGHT: READY FOR HOST-ONLY - 0 FAIL, {0} WARN, {1} checks" -f $script:Warns, $script:Checks)
    Emit 'Firewall and adapter checks are clean, but the game 62900/62056 premise is UNVERIFIED'
    Emit '(Civ6 not running or no LAN room yet). Create the LAN room, then re-run this script'
    Emit 'and require the full "PREFLIGHT: READY" before letting the other machine refresh.'
    $code = 0
} else {
    Emit ("PREFLIGHT: READY - 0 FAIL, {0} WARN, {1} checks" -f $script:Warns, $script:Checks)
    Emit 'Next: docs\M0E-DUALMACHINE-RUNBOOK-20261119.md (create the room FIRST, then start the Agent).'
    $code = 0
}
```

这样"游戏没跑"再也不会被末行的 `READY` 吞掉；两种 READY 在末行就字面不同，操作员和脚本都能分辨。退出码仍为 0（不是 FAIL，不该阻断防火墙修复流程）。

### 补丁 A+B 的连带影响

1. 检查数恒定 **12**。当前实现：游戏未跑时 10 项（C2.2/C2.3 被跳过），游戏跑时 12 项（实测 `run3-with-game-ports.txt` 就是 12）。补丁后无论游戏在不在跑都输出 C2.1 + C2.2 + C2.3 三项，故总数恒为 12——这正是想要的（行数不再随环境漂移，脚本可被可靠断言）。**两轮基线必须重跑**并更新 `docs\M0E-PREFLIGHT-20261119.md` §5。
2. `run2-covered.txt` 的 `PREFLIGHT: READY` 会变成 `PREFLIGHT: READY FOR HOST-ONLY`——这是正确行为，但要在文档里写明"这条历史证据在新版下会给出不同结论"，否则日后对比会以为退化。
3. 变异脚本 M1/M2 不受影响（都不碰 C2 段），但需重跑确认 2/2 仍被捕获。
## P-10（中，部署可用性）：预检脚本按"开发者目录布局"推路径，打包后无法直接用

`run-m0e-preflight.ps1:77-82`：

```powershell
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = Split-Path -Parent $scriptDir
$nightly   = Join-Path $repoRoot 'dist\civlink-20261119-nightly'
if ([string]::IsNullOrWhiteSpace($AgentPath)) { $AgentPath = Join-Path $nightly 'civlink-agent.exe' }
```

这套推导只在脚本位于 `<repo>\civlink\` 时成立。**发行版是 zip，用户会把整个包解到任意目录（如 `D:\CivLink\`），脚本就放在包根**——此时 `$scriptDir` = 包根、`$repoRoot` = 包的上一级、`$nightly` = `<包的上一级>\dist\civlink-20261119-nightly`，**必然找不到 agent**。

实测（把 nightly 包内容 + 脚本一起放到 `%TEMP%\pf-deploy\` 后从包根运行）：

```
FAIL  C1.1  agent exe not found: C:\Users\dd\AppData\Local\Temp\dist\civlink-20261119-nightly\civlink-agent.exe
WARN  C4.1  agent (the exe you will run): exe missing, skipped
PREFLIGHT: ACTION NEEDED - 1 FAIL, 4 WARN, 9 checks
```

注意它去找的是 `%TEMP%\dist\...` 而不是 `%TEMP%\pf-deploy\`——路径推导完全错位，**且报错文本会误导用户以为包缺文件**。同时检查数掉到 9（C1.2 因 agent 缺失被跳过），又一次证明"检查数漂移"（P-1 第 1 点）。

严重性：**这是发行阻断级的可用性缺陷**，但不在"当前开发环境能不能跑通"的范围内——所以三轮基线（从 `civlink\` 目录跑）都发现不了它。用户拿到 zip 后第一次运行预检就会被劝退。

修法（按优先级回落，任一步命中即用，并打印命中依据）：

1. 显式 `-AgentPath`；
2. **`$scriptDir\civlink-agent.exe` 存在 → 用脚本同目录**（打包布局，这是发行版的正解）；
3. `$repoRoot\dist\civlink-20261119-nightly\civlink-agent.exe` 存在 → 用开发布局；
4. 全不中 → FAIL C1.1，错误文本里同时列出探过的三个路径，让用户知道该把脚本放哪或该用 `-AgentPath`。

同理 `MANIFEST.txt` 的定位（L92）已经是"跟 agent 同目录"，这一条本身是对的，只要 C1.1 选中了正确目录就自动跟着对——所以只需改 L77-82 这一处。

另附：`$nightly` 里面写死了日期 `civlink-20261119-nightly`，下个 nightly 一打包就失效。修法同批做：把写死的日期换成"在 `dist\` 下按名字挑最新的 `civlink-*-nightly`"（或读取 `VERSIONS.txt` 首行）。这一条与 P-10 是同一处代码，应合并修。

### P-10 的连带影响

- 修复后 `docs\M0E-PREFLIGHT-20261119.md` §1/§4 要补"整包部署"这一使用形态（现在的文档只讲从仓库跑）。
- 发行包 `VERSIONS.txt` 里应加一行"包根运行 `run-m0e-preflight.ps1` 自检"，否则用户不会想到有这个东西。
- 需要在包里放一份预检脚本（当前 `dist\civlink-20261119-nightly\` 里**没有** `run-m0e-preflight.ps1`，实测 `ps1 count: 0`；包内只有 6 个 exe/dll + `fixture-reply-set\` + `MANIFEST.txt` + `VERSIONS.txt`），否则用户拿到包也没法自检。
- **`fix-m0e-preflight.ps1` 有同一处缺陷**：L62-65 也是 `$repoRoot = Split-Path -Parent $scriptDir` + 写死 `'dist\civlink-20261119-nightly\civlink-agent.exe'`，L122 的 `$backupDir = Join-Path $repoRoot 'scripts\network-env'` 同理。因此 P-10 的修法要**两个脚本一起改**（`fix-` 的 fail 文本也应列出探过的路径）。注意 `fix-` 的 `-AgentPath` 需要在提权前就解析好绝对路径再透传（现有 L48 已透传，逻辑对，只差默认值的推导）。
## P-11（中）完整性校验可被"删掉 MANIFEST"静默降级

在 `%TEMP%\pf-probe\` 复现完整开发布局（`civlink\` + `dist\civlink-20261119-nightly\`）后做了四组对抗性探针，证据已脱敏归档到 `M0A\captures\M0E-preflight-selftest-20261119-1110\probe-p*.txt`（`<PROBE>` = 临时根、`time: <scrubbed>`）：

| 探针 | 改动 | 结果 |
|---|---|---|
| p1 基线 | 无 | `PREFLIGHT: ACTION NEEDED - 1 FAIL, 3 WARN, 10 checks` exit 2（FAIL 仅为该临时路径无防火墙规则） |
| p2 | 删 `MANIFEST.txt` | **`WARN  C1.2 MANIFEST.txt not next to the agent - cannot verify integrity (custom deployment?)`**，exit 2 但**C1.2 不再是 PASS** |
| p3 | 从 MANIFEST 删掉 `civlink-agent.exe` 那一行 | **`WARN  C1.2 civlink-agent.exe not listed in MANIFEST.txt`** |
| p4 | 把包目录重命名（日期不同） | `FAIL C1.1 agent exe not found`（写死路径，见 P-10），**检查数掉到 9** |

**p2/p3 是要害**：C1.2 的语义是"agent 与 MANIFEST 一致"，但 MANIFEST 缺失或没列该文件时它降级为 WARN，而**退出码仍可能是 0**（只要 C4.1 有规则）。也就是说：**把 MANIFEST.txt 删了，一个被替换过的 agent 就能通过预检**——完整性校验在最需要它的场景下自动消失，且用户看到的只是 WARN。这与"零 UAC 兜底""发布包哈希对账"的初衷相反。

修法（建议）：C1.2 在**发行包布局**（agent 同目录有 `VERSIONS.txt` 或 `fixture-reply-set\`）下缺失 MANIFEST 应为 **FAIL**；只有显式 `-AgentPath` 指向包外路径时才降 WARN（那时确实是自定义部署）。

### 探针复现方法（可重复）

```
新建 %TEMP%\pf-probe\
  civlink\run-m0e-preflight.ps1                       (送审件副本)
  dist\civlink-20261119-nightly\                      (nightly 包副本)
每次运行前把 dist\ 还原
& powershell -NoProfile -ExecutionPolicy Bypass -File %TEMP%\pf-probe\civlink\run-m0e-preflight.ps1 -OutFile <out>
```

注意：在 `%TEMP%` 下跑 C4.1 **必然 FAIL**（临时路径不会有防火墙规则），这是噪声不是缺陷——探针只用于观察 C1.2/C2/C1.1 的行为与检查数。

### 归档哈希

`probe-p1.txt` 2,518 B/`65C1B8713554F388B61DBAC9DF9829AD2C005EDD6FC10CCDAC97D928FA205C7A`、`probe-p2.txt` 2,561 B/`AEAA070A4F352EEB2D42CF67902D059D80ACD944D176447D468CD17B3A85894A`、`probe-p3.txt` 2,524 B/`D37758634776EFB34A57C54E81A13DAAD7D4EC2308A95DC64E55FDA1B79B98CA`、`probe-p4.txt` 2,149 B/`E67B1CBE72DEB78C17E6C84A939E7529466A20993CE9F7B200529F1B9627832D`。
### ★P-11 的决定性实证：完整 `PREFLIGHT: READY` 可以在"完整性从未校验"的状态下拿到

用**已覆盖防火墙路径**的 agent（`civlink\agent\target\release\civlink-agent.exe`，该目录**没有** `MANIFEST.txt`，实测 `Test-Path` = False）跑：

```
PASS  C1.1  agent present: …\civlink\agent\target\release\civlink-agent.exe (464384 B, 15321D4980651702)
WARN  C1.2  MANIFEST.txt not next to the agent - cannot verify integrity (custom deployment?)
PASS  C4.1  agent (the exe you will run): inbound Allow covers [Private,Public] (covers all profiles in use)
PREFLIGHT: READY - 0 FAIL, 4 WARN, 10 checks
exit=0
```

**`exit=0` + `PREFLIGHT: READY`，而 C1.2 从未做过任何校验。** 这正好是"零 UAC 兜底"推荐的路径——也就是说：**预检自己建议用户走的免提权路径，恰好落在完整性校验的盲区里**。这条与 P-1（游戏没跑也给 READY）合起来说明：

> `PREFLIGHT: READY` 目前**不蕴含**"agent 二进制可信"与"游戏建房前提成立"两件事，它只蕴含"防火墙/端口/进程占用这些机械条件没发现问题"。

这不是危言——用户/后续流程若把 READY 当作"可以开跑"的绿灯，恰好会在最关键的两个前提上无证据。因此 P-1 与 P-11 的修复应合并成一次：**让末行结论与它真正验过的范围一致**（READY FOR HOST-ONLY / READY WITH UNVERIFIED INTEGRITY 之类），而不是笼统的 READY。
## v2 候选脚本（不动送审件，另存一份）——P-1/P-3/P-10/P-11 的实现与实测

送审件 `run-m0e-preflight.ps1`（`F60DE777…`）在整个审计期间**未被改动**。四项修法另存为
`civlink\run-m0e-preflight.v2-candidate.ps1`（**22,585 B / sha256=`0F469F4170F174C15C0A0E507DD029443B59E29499F108F0F2165C5960ACA874`**），
头注释标明 `V2 CANDIDATE ... NOT AUDITED YET`。四处改动：

1. **P-10 布局无关**：`$agentCandidates` 先试 `$scriptDir\civlink-agent.exe`（解包后的包布局），再按 `dist\civlink-*-nightly` **按名倒序取最新**（不再写死 `20261119`）。全不中时先打印探过的所有候选再 FAIL。
2. **P-11 包内完整性不再静默降级**：`$isPackage` 判据**只用 `VERSIONS.txt` 存在**（打包步骤唯一产物）。包内 MANIFEST 缺失→FAIL、未列该文件→FAIL；包外仍 WARN。
   *为何不用 `fixture-reply-set\` 做判据*：开发树 `civlink\` 里也有这个目录，第一版判据把仓库检出误判成"被篡改的下载包"（实测 `FAIL C1.2 release package at …\civlink has NO MANIFEST.txt`）→ 已收窄。
3. **P-1 检查项恒定**：C2.2/C2.3 改为**总有输出行**；游戏不在时输出 `WARN C2.2 62900 NOT verified …` / `WARN C2.3 62056 NOT verified …`，并置 `$gamePortsVerified`（需 62900 与 62056 双双成立）。
4. **P-3 参数校验**：全部 `Test-Path -PathType Leaf`；`-AgentPath` 指目录时给可读 FAIL 而不是 `Get-FileHash` 抛异常导致输出文件为空。
5. **结论行三分支**：`Fails>0` → `ACTION NEEDED` exit 2；有 caveat → **`READY WITH CAVEATS`** exit 0 并逐条列出 `CAVEAT:`；否则 → `READY` exit 0。检查数恒定 **12**。

### 实测（证据 `M0A\captures\M0E-preflight-v2-selftest-20261119-1125\`，5 个输出 + 1 份脚本副本）

| 用例 | 环境 | 结果 |
|---|---|---|
| T1 包布局 | 脚本与 agent 同目录，游戏未跑 | `PASS C1.1/C1.2` + `WARN C2.2/C2.3 NOT verified` + `ACTION NEEDED - 1 FAIL, 5 WARN, 12 checks` exit 2（FAIL 仅为临时路径无防火墙规则） |
| T2 包内删 MANIFEST | 同上 | **`FAIL C1.2 release package … has NO MANIFEST.txt … do not run it`**，`2 FAIL, 5 WARN, 12 checks` exit 2 ← P-11 生效 |
| T3 包内 MANIFEST 去掉 agent 行 | 同上 | **`FAIL C1.2 civlink-agent.exe is NOT listed in the package MANIFEST.txt`**，exit 2 ← P-11 生效 |
| T4 包布局 + 假游戏占 62900/62056 | 假 `CivilizationVI_DX12` | `PASS C1.2` + `PASS C2.1/C2.2/C2.3`，仍 `ACTION NEEDED`（唯一 FAIL 是临时路径无防火墙规则） |
| T5 已覆盖路径 + 临时补 MANIFEST/VERSIONS + 假游戏 | `civlink\agent\target\release\` | **`PREFLIGHT: READY - 0 FAIL, 2 WARN, 12 checks` exit 0** ← 证明三分支可收敛到普通 READY，且 P-1/P-11 的 caveat 不是死代码 |

开发布局（真实仓库，无 `-AgentPath`）实测：`PASS C1.1` / `WARN C1.2`（包外，正确降级）/ `WARN C2.2 C2.3` → **`READY WITH CAVEATS - 0 FAIL, 6 WARN, 12 checks` exit 0**，两条 CAVEAT 均正确点名。

T5/T1/T4 的假游戏与临时 MANIFEST/VERSIONS 均已清理：`62900/62056` 现均 free、无 `CivilizationVI_DX12` 进程、`civlink\agent\target\release\` 无残留 MANIFEST/VERSIONS。

### 残留缺口（必须在文档里说清，不能靠 caveat 掩盖）

**删掉 `VERSIONS.txt` 就能把 P-11 的 FAIL 降回 WARN。** 判据与证据同处一个可写目录，任何本机打包判据都只能提高门槛、不能构成防护。真正的答案是发布侧签名/HTTPS+独立公布的哈希，已登记为发布阻断项方向；本预检只做"别让校验静默消失"这件事。
## `fix-m0e-preflight.ps1` 的 v2 候选（同样不动送审件）

`civlink\fix-m0e-preflight.v2-candidate.ps1`（**9,870 B / sha256=`27E044CCB933B1EBAD1FAEB18C86E80239DA5F147A4401132F617FA72CC69F0C`**，头注释标 `V2 CANDIDATE ... NOT AUDITED YET`）：

- **P-6**：`WHAT IT DOES NOT CHANGE` 段改成 "no PRE-EXISTING rule is deleted. The script re-creates ONLY its own two rules … deletes each one BY NAME and re-adds it, which is required to refresh the Program path"。`UNDO` 段补一句"先 `netsh advfirewall firewall show rule name=…` 看 Program 指向"。
- **P-3**：`[ValidateRange(1, 9999)]` 加在 `[int]$VirtualMetric` 上。实测 `-VirtualMetric 99999` 现在得到可读的绑定错误（`The 99999 argument is greater than the maximum allowed range of 9999`），不再是 v1 那种 `exit=-1` 的硬崩。
- **P-10**：Agent 路径改成"包布局优先（脚本同目录有 `civlink-agent.exe`），否则 `dist\civlink-*-nightly\` 按名倒序取最新"，去掉写死的 `20261119`；`Test-Path` 一律加 `-PathType Leaf`。
- **附带**（做 P-10 时顺手发现的真实故障）：`$backupDir = Join-Path $repoRoot 'scripts\network-env'` 在**只读介质**（U 盘写保护 / CD / 锁定的共享）上会直接抛错、`$ErrorActionPreference='Stop'` 下整个脚本死掉——而"原值备份"恰恰是撤销的前提。改成 `try/catch` 回落到 `%LOCALAPPDATA%\CivLink\network-env` 并打印实际路径。
- 语法检查：`[Parser]::ParseFile` → **0 syntax errors**。

### 还差的（v2 候选未做）

`fix-m0e-preflight.ps1` 的 C5 游戏路径仍是写死的 `E:\SteamLibrary\...\Win64Steam\CivilizationVI_DX12.exe`——这个在**预检脚本**里只影响 C5 信息性检查，但在 fix 脚本里不影响任何写操作，所以没列为缺陷；不过它意味着换 Steam 库位置后 C5 会静默跳过。已记为待办，不进本轮修正。

## P-12（中）caveat 层断言的变异判别力，第一次测法本身是错的

给 v2 候选补变异时踩了一个方法学坑，值得单独记下来，因为它差点让我写出一个假的"变异已捕获"结论。

**第一次测法（错）**：把 `dist\civlink-20261119-nightly\` 复制到 `%TEMP%\pf-v2-mut\pkg\`，脚本放在包根，构成"包布局"再改字节造变异。
- 基线（删 MANIFEST）：`FAIL C1.2 release package at <TMP>\pkg has NO MANIFEST.txt …`、`PREFLIGHT: ACTION NEEDED - 2 FAIL, 5 WARN, 12 checks`、exit 2。
- **M3**（`if ($isPackage)` → `if ($false)`，包内缺 MANIFEST 退回 WARN）：`FAIL C1.2` 确实变成 `WARN C1.2`，**但 exit 仍是 2**（`1 FAIL, 6 WARN`）——因为包在 `%TEMP%` 下必然没有指向该路径的防火墙 Allow 规则，C4.1 恒 FAIL，verdict 走的是 `Fails>0` 分支。
- **M4**（`if (-not $gamePortsVerified) { $caveats.Add(…) }` → `if ($false)`）：干净包基线 `ACTION NEEDED - 1 FAIL, 5 WARN`，**变异前后输出逐字相同**——caveat 分支从未被执行。

**结论**：在 `%TEMP%` 布局下，M4 **零判别力**、M3 只在断言层可捕获。如果照第一次的结果登记成"变异已捕获"，那就是拿一个被无关 FAIL 掩盖的测试冒充证据。**防火墙噪声必须先消除，才能测 caveat 层。**

**第二次测法（对）**：Windows 按**绝对路径**匹配防火墙规则，所以唯一能让 C4.1 PASS 又不改防火墙的位置是 `civlink\agent\target\release\`（该路径已有 `Private,Public` Allow 规则，且 agent 与发布包字节相同）。临时放 `MANIFEST.txt`（该 agent 的哈希+大小）与 `VERSIONS.txt` 让它构成包布局，跑完全部删除。

实测（证据 `M0A\captures\M0E-preflight-v2-mutation-20261119-1135\`，4 个 txt + MUTATION-RECORD，全部 `time:` 行已脱敏为 `<scrubbed>` 以便哈希稳定）：

| 运行 | exit | headline | C1.2 |
|---|---|---|---|
| `v2m-clean.txt` | 0 | `READY WITH CAVEATS - 0 FAIL, 5 WARN` | PASS matches MANIFEST |
| `v2m-m4-caveat-suppressed.txt` | 0 | **`READY - 0 FAIL, 5 WARN`** | PASS matches MANIFEST |
| `v2m-m3-package-downgraded.txt` | 0 | `READY WITH CAVEATS - 0 FAIL, 6 WARN` | **WARN** cannot verify integrity |
| `v2m-control-manifest-missing.txt` | 2 | `ACTION NEEDED - 1 FAIL, 5 WARN` | **FAIL** NO MANIFEST.txt |

- **M4 捕获点**：caveat 行消失 **且** headline 从 `READY WITH CAVEATS` 静默退化成裸 `READY`，而游戏根本没在跑。exit 两种都是 0 → **只在断言层（headline 文案 + caveat 列表）可捕获，退出码层不可捕获**。这恰恰是操作员无法察觉的失效形态，也正是为什么判别器必须是文案而不是退出码。
- **M3 捕获点**：`FAIL` 降级为 `WARN`、多出一条 `CAVEAT: the Agent binary integrity is UNVERIFIED`、WARN 计数 5→6，exit 仍 0 → **同样只在断言层**。
- **对照组**（未变异 + 删 MANIFEST）→ `FAIL C1.2` + exit 2，证明上面两个变异的 exit 0 不是脚本本来就那样。

**登记口径（不得混用）**：M3/M4 = 断言层；退出码层是被**另外两个**变异/用例覆盖的（v1 的 M1 防火墙匹配强制为真：`%TEMP%` 布局下 exit 2→0；以及本组 control：exit 0→2）。两者不能在同一张表里笼统写成"变异被捕获"。

**残留**：`civlink\agent\target\release\` 的临时 `MANIFEST.txt`/`VERSIONS.txt`/`run-m0e-preflight.ps1` 均已删除（实测 leftovers=0、script left=False），`%TEMP%\pf-v2-mut` 已删，无游戏无 agent、62900/62056 均空闲。

## P-13（中）发布包里没有预检脚本，也没有操作说明

`dist\civlink-20261119-nightly\` 实测内容：6 个二进制（`civlink-agent.exe` / `civlink-relay.exe` / `civlink_client.dll` / `civlink_ctl.exe` / `civlink_hook.dll` / `civlink_tray.exe`）+ `MANIFEST.txt` + `VERSIONS.txt` + `fixture-reply-set\`（含 `json\` 与三个 bin）。**`.ps1` 计数 = 0，`.md` 计数 = 0。**

后果：v2 候选预检正是按"脚本与 `civlink-agent.exe` 同目录"（P-10 的包布局分支）设计的，但它不在包里 → 拿到 zip 的人手上只有 `VERSIONS.txt`，**所有 C1-C7 机械检查（防火墙路径覆盖、Profile 覆盖、62900/62056 是否真被游戏持有、metric 竞争、MANIFEST 完整性）都得自己肉眼做**。这正是我在自查记录里反复认定的"历史上每轮真机失败都是环境问题"的那一类失败。

同时确认了两件**没有**问题的事：
- 包内 `civlink_tray.exe --selftest` 从包目录运行 → `CivLink GUI SELFTEST PASS`、`checks=40 failed=0`、exit 0。`civlink_tray.cs:545` 用 `AppDomain.CurrentDomain.BaseDirectory` 找同目录的 `civlink-agent.exe`，包布局成立。
- `VERSIONS.txt` 的 "Order that works" 段已经把正确顺序（先建房 → 再启 agent，且带 `--reserve-62900`）和 Boundary 段（未做双机测试、不得描述为可用联机）写清楚了，措辞与设计 v2.1 一致，不需要改。

**修法**：把 `run-m0e-preflight.ps1`（或 v2 候选通过审计后的定版）连同 `fix-m0e-preflight.ps1`、以及一份面向操作员的最短说明一起打进下一个包，并在 `MANIFEST.txt` 里列出。这属于**重新打包**，会同时改变 zip 哈希、`MANIFEST.txt` 哈希和 `docs\NIGHTLY-PACKAGE-20261119.md` 的引用哈希 → 必须与 preflight 三件套的最终定版合并成**一次**协调更新，不能现在动（当前包是已登记产物，`CC5A5DBA…`）。

**未做**：没有修改当前包的任何字节（避免让已登记的 zip 哈希失效），只记档。

## P-14（中低）C1.1 只验证"文件存在"，不验证"它真的是 agent"

v2 候选修掉了 P-3（`-AgentPath` 指向目录时给可读 FAIL 而不是 `Get-FileHash` 抛异常），但我用其它非 exe 的叶子文件复测时发现**这个洞没堵全，而且 v1 也有**：

```
-AgentPath <目录>          → FAIL C1.1 agent exe not found: <dir> (pass -AgentPath, or keep this script next to civlink-agent.exe)   exit 2   ← P-3 已修
-AgentPath <不存在的文件>  → FAIL C1.1 agent exe not found: C:\nope\nothing.exe                                                      exit 2   ← 正确
-AgentPath <任意 .ps1/.txt> → PASS C1.1 agent present: <...>\pf.ps1 (22585 B, 0F469F4170F174C1)                                     exit 2   ← 假 PASS
```

**v1 与 v2 表现完全相同**（实测两个脚本指向同一个 `.ps1`，都打印 `PASS C1.1 agent present: …pf.ps1 (17408 B, F60DE7779F2BCCF1)` / `(22585 B, 0F469F4170F174C1)`）。

**后果**：C1.1 的语义是"agent 存在"，但它实际只判了"这个路径是一个存在的文件"。若操作员把 `-AgentPath` 指错（指到 `civlink_ctl.exe`、某个日志、或路径拼错但恰好命中了别的文件），预检会给出 **PASS agent present**，随后 C1.2 因为找不到 MANIFEST 只能 WARN，C4.1 又拿这个错误路径去查防火墙 → 必然 FAIL。最终退出码仍是 2，但**失败理由指向防火墙/完整性，而不是"你指的东西根本不是 agent"**。这属于最容易被误读的一类诊断误导。

**修法（低成本，我倾向第 1 条 + 第 2 条一起）**：
1. 文件名基线：`Split-Path -Leaf` 不等于 `civlink-agent.exe` 时 **FAIL C1.1**，措辞 `the file at <path> is named '<leaf>' - civlink-agent.exe expected (did you point -AgentPath at the wrong file?)`。
2. PE 校验：读头两个字节是否为 `MZ`（`[IO.File]::ReadAllBytes` 前 2 字节），不是则 FAIL。这条同时能挡住"改名成 .exe 的非 PE 文件"，成本几乎为零，且不引入新依赖。

**未做**：本轮只在 %TEMP% 副本上验证，**没有改任何脚本字节**（v1 送审件与 v2 候选都保持原哈希）。这条要并入 preflight 定版的那一次协调更新。
---

## P-15 + v3 定版（2026-11-19 11:59，自查主导收口）

### 审计子代理三次失败 → 停止重派
- 92c682bf（无产物）、4cec1d46（报告停在 1,297 B / 18 个「待填」骨架），连续失败；不再无限重派，改为自查主导定版，并把"独立审计未完成"如实登记为发布阻断备注。
- v1 送审件（`F60DE777…`）与 v2 候选（`0F469F41…`）**保持原字节不动**，作为历史证据。

### P-15（低）v2 头注释的"check count CONSTANT 12"是错的
- 边界探针：脚本放无 `dist\` 兄弟目录的纯部署布局 → `FAIL C1.1` + `PREFLIGHT: ACTION NEEDED - 1 FAIL, 6 WARN, 11 checks` exit 2。机制：C1.1 走 FAIL 分支时 C1.2 被 `else` 跳过（`v2:122`），故 11 项。
- 定版措辞改为：**agent 存在时 12 项；C1.1 失败时 C1.2 不适用，总数 11**。

### v3 定版脚本（磁盘权威）
| 文件 | 字节 | sha256 |
|---|---|---|
| `civlink\run-m0e-preflight.v3.ps1` | 24,386 | `0224B23190FEA918BB59C2AA624DB109EF5669F9E0DFA52FEF88899A627709F8` |
| `civlink\fix-m0e-preflight.v3.ps1` | 10,242 | `6387CBAA98EB6E02B85C8743B327B9D920CC08400C4B9C5635E7C006A785BB63` |

合并的修正：P-1（C2.2/C2.3 恒有输出 + gamePortsVerified）、P-3（`Test-Path -PathType Leaf` + `[ValidateRange(1,9999)]`）、P-6（fix "不删规则"注释澄清）、P-10（布局无关 + 去写死日期 + 只读介质备份回落）、P-11（包内 MANIFEST 缺失/未列 = FAIL）、**P-14（C1.1 文件名 + PE magic MZ 双重校验）**、**P-15（11/12 计数更正）**。两者 `[Parser]::ParseFile` = 0 syntax errors。

### v3 采信实测（`M0A\captures\M0E-preflight-v3-selftest-20261119-1156\`，7 文件含脚本副本与 MANIFEST）
| 用例 | exit | headline | 关键行 |
|---|---|---|---|
| T1 开发布局（无游戏） | 0 | `READY WITH CAVEATS - 0 FAIL, 6 WARN, 12 checks` | C1.1 PASS(15321D49) / C1.2 WARN / C2.2/C2.3 WARN NOT verified / 2 CAVEAT |
| T2 `-AgentPath <v3.ps1>` | 2 | `ACTION NEEDED - 2 FAIL, 5 WARN, 11 checks` | **`FAIL C1.1 the file … is named 'run-m0e-preflight.v3.ps1' - civlink-agent.exe expected`**（P-14 假 PASS 消除；11 项=P-15） |
| T3 `-AgentPath <目录>` | 2 | `ACTION NEEDED - 2 FAIL, 5 WARN, 11 checks` | `FAIL C1.1 agent exe not found: <dir>` |
| T4 假游戏占 62900/62056 | 0 | `READY WITH CAVEATS - 0 FAIL, 3 WARN, 12 checks` | C2.1/C2.2/C2.3 全 PASS；game caveat 消失，仅剩 integrity caveat |

假游戏 `%TEMP%\civlink-v3-game\CivilizationVI_DX12.exe`（C# 编译，绑 0.0.0.0:62900+62056，pid 26144）跑完已删；清理实测 leftover ports=0、leftover game procs=0。

**证据哈希**：`v3-t1-baseline-dev.txt` 2,843 B/`B1C450543C2320F25…`、`v3-t2-agentpath-ps1.txt` 2,626 B/`F4B9225D3184A756E…`、`v3-t3-agentpath-dir.txt` 2,583 B/`12A1C96DA966A9D31…`、`v3-t4-game-alive.txt` 2,406 B/`4349166963D9144A…`、`MANIFEST.txt` 列全 6 文件 + 两脚本源码副本。

### 边界（不因 v3 自检通过而越界宣称）
- v3 预检是**操作员就绪性检查**：证明防火墙/接口/完整性/游戏端口前提被机械核对过，**不**证明双机联机、不勾 E2-A/E2-B/E3、不移动 Gate A/B。
- 独立审计未完成仍是发布阻断备注，须在 README v1.37 如实写明"审计报告三次派发失败，最终定版由自查主导，v1 送审件哈希为历史快照"。