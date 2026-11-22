# M0D — P1 GUI 实现首轮 NOT PASS 修复轮 · 独立复审裁定（REVIEW-2）

- 日期：2026-11-18
- 复审对象：首轮审计报告 `docs/M0D-GUI-IMPL-REVIEW-20261118.md`（裁定 NOT PASS，N-A..N-G 七项）的修复轮
- 被审源码：`civlink/gui/civlink_tray.cs`（修复后，35,707 B / sha256=2DFFBFAA50CC73045AD9F1224EC098AD738EBCD105B3061693CBE8ABFF9C774A）
- 方法：全部结论来自磁盘实读与实运行；未采信任何口述；未做真实游戏 / 双人验证（PC-B 对局期不干扰）。
- 说明：本轮为**修复轮复审**，只裁定首轮七项的关闭状态；不重复论证首轮已关闭的 N-1..N-7。

---

## 1. 总裁定

**裁定：PASS**（允许进入 README v1.35 / HANDOVER 第 22 项登记）。

依据：
1. 首轮 N-A..N-G 七项**全部关闭**：六项「已关闭」、一项（N-B）附带部署注意项但不影响关闭。
2. 八项实算哈希/字节数**全部与期望一致**；exe 以源码哈希 + 26112 字节 + exit=0 为验收口径（output_sha256 本机不稳定，按已知 TimeDateStamp/MVID 22 字节差异处理，不判篡改）。
3. 三项变异（M1/M2/M3）经复审员**亲自重编译复核**，自检均能检出；首轮「删 LAN 段正则仍 24/24 PASS」的漏检缺口（N-C）已精确关闭。
4. 硬约束（零遥测/零日志/无配置持久化、asInvoker、白名单不接受手动 PID、ctl 子进程复用、agent 不绑 62056/不 SO_REUSEADDR、机械证据≠双人验证/Gate A 未批准）**均未违反**。
5. 新发现 3 项均为低优先级观察/部署项，**无一阻断登记**。

**边界保留（必须随登记传递）**：本裁定仅覆盖机械自检与静态证据；`gate=双人验证未完成（Gate A 未批准）` 仍为真。不得把模拟 / headless 证据写成真实联机验证，不得越界宣称 Gate A 已批准。

---

## 2. N-A..N-G 逐条关闭表

| 编号 | 首轮问题 | 裁定 | 源码/契约行号证据 |
|---|---|---|---|
| N-A【阻断】 | status/counters/shutdown 缺 -x 必返 ctl exit 2 | **已关闭** | `civlink_tray.cs:133-143` `CtlRunner.BuildArgs` 的 `needsTarget` 于 `:137-138` 覆盖 inject/inject-client/status/counters/shutdown 五子命令；`:141-143` 经 `Whitelist.Contains` 校验后拼 `a.Append(" -x \"").Append(processName).Append("\"")`。调用链实走 BuildArgs：`DoCtl :463-481`，`:469 string proc = SelectedProcName()`、`:470 CtlRunner.BuildArgs(cmd, proc, null, null)`、`:472 CtlRunner.Run(cmd, args, timeout)`，无裸命令旁路。契约 `civlink_ctl.cpp:337-343`（Usage 五子命令均须 -x）、`:354-361`（仅 -x 设 exeArg）、`:393-394`（`ResolveTarget` 失败 `return 2`）。自检 `:613-618` 三条 `status/counters/shutdown carries -x`。 |
| N-B【高】 | 高级 LAN agent 从不拼 --simulate 致启动必失败 | **已关闭**（附部署注意项 N2-2） | `AgentSupervisor.BuildArgs :221-239` 增第 4 参 `fixtureDir`；`:226-235`：listenIp 非空时 `:228` 走 `IsDottedQuad` 校验、`:230` 拼 `--sim-lan-listen`、`:231` 拼 `--reserve-62900`、`:232-233` fixtureDir 空抛 `ArgumentException`、`:234` 拼 `a.Append(" --simulate \"").Append(fixtureDir).Append("\"")`。`StartAgent :498-526`：`:510 fixture=Path.Combine(BaseDirectory,"fixture-reply-set")`、`:511-515` 目录不存在则 Log 并 return（fail-closed）、`:516` 传入。自检 `:628-635`：`:630` 正向 `ag.Contains("--simulate \"C:\\fixture-reply-set\"")`，`:634-635` 普通 A 路径断言不含 sim-lan-listen/reserve/simulate（旧反向断言已改）。契约 `main.rs:1627-1639`：`args.simulate.as_deref().ok_or("--sim-lan-listen requires --simulate (fixture directory)")?`。 |
| N-C【中】 | 变异 M2（仅删 LAN 段正则）漏检 | **已关闭** | `Redactor :55-72` 规则(2) `:64 s = Regex.Replace(s, @"(?im)^.*simulated host.*$", "<redacted simulated-host line>", RegexOptions.Compiled);`。自检 `:590-602`：`:591` 判别样本 `LAN simulated host endpoint=HiddenTokenXYZ`（**无 room 关键字**，只有整行规则能遮蔽）；`:598 Check(!red.Contains("HiddenTokenXYZ"), "redact LAN-only token (N-C mutation discriminator: only rule (2) catches it)")`。M2 变异复核：`failed=1`，精确失败在本断言。 |
| N-D【中】 | 句中房名绕过 + CIVTRACE_TAG 多 token 残留 | **已关闭** | 规则(3) `:66 s = Regex.Replace(s, @"(?i)\b(room(?:[_ ]?name)?|sim_room_name)\b[^\r\n]{0,80}", "$1=<redacted>", ...)`（句中/变体兜底）；规则(5) `:70 s = Regex.Replace(s, @"(?i)(CIVTRACE_TAG\s*=\s*)[^\r\n]+", "$1<redacted>", ...)`（遮蔽至行尾）。自检 `:593` 句中 room + `:595` 多 token tag 样本；`:600 redact in-sentence room (N-D)`、`:602 redact multi-token tag (N-D)`、`:603 redact tag value`。M3 变异复核：`failed=2`，含 `:600` 一项。 |
| N-E【中】 | 超时注释称查询状态实际直接 Kill | **已关闭** | `CtlRunner.Run :167-207` 超时分支 `:187-202`：`:191 try { if (p.HasExited) exited = true; } catch (Exception) { }`；`:194 try { exited = p.WaitForExit(2000); } catch (Exception) { }`；`:196 r.TimedOut = !exited;`（已退出则清标志）；`:197-201` 仍未退出才 `Kill()+WaitForExit`。话术诚实：`:38` 注释、`:457` 日志均不宣称真实查询。 |
| N-F【低】 | iface 八位组不校验 ≤255 | **已关闭** | `:122 private static readonly string Octet = @"(25[0-5]\|2[0-4]\d\|1?\d?\d)";`；`:123-127 IsDottedQuad` 以 `^`+Octet+`(\.`+Octet+`){3}$` 逐段校验。自检 `:624-625 Check(threw,"reject iface octet >255 (N-F)")`（999.999.999.999 抛异常）、`:626 dotted-quad range check (N-F)`。（正则中的 `\|` 为 Markdown 表格转义，`:122` 源码原文为 `(25[0-5]|2[0-4]\d|1?\d?\d)`。） |
| N-G【低】 | 实现报告文件数 5→6 | **已关闭** | `docs/M0D-GUI-IMPL-20261118.md:32` §6 已改「6 文件：build-gui.ps1 / build-manifest.txt / civlink_tray.cs / civlink_tray.exe / gui-selftest / gui-window-smoke.txt」。首轮证据目录 `M0A/captures/gui-impl-20261118-1830/` 实读为 6 文件（29605 B cs / 23552 B exe / 97 B selftest / 949 B smoke / 4005 B ps1 / 2740 B manifest），与修正一致。 |

---

## 3. 哈希 / 证据抽查结果表（实算值 vs 期望值）

所有值由复审员用 `Get-FileHash -Algorithm SHA256` 与 `Get-Item .Length` 在磁盘实算。

| 文件 | 实算 sha256 | 期望 sha256 | 实算字节 | 期望字节 | 结论 |
|---|---|---|---|---|---|
| `civlink/gui/civlink_tray.cs` | 2DFFBFAA50CC73045AD9F1224EC098AD738EBCD105B3061693CBE8ABFF9C774A | 同左 | 35,707 | 35,707 | ✓ |
| `civlink/gui/civlink_tray.exe` | 9B480FE0C8183B8D523E8B749111EDC403962F31F832381CE50C75378DD52B46 | 同左 | 26,112 | 26,112 | ✓ |
| `docs/M0D-GUI-IMPL-20261118.md` | 561B8EEFB035219964A69A843722976544F18F845DF0CD3AD036197E50158654 | 同左 | 9,375 | 9,375 | ✓ |
| `M0A/captures/gui-fix-20261118-1852/gui-selftest-fixed.txt` | 259206473068A1A8AE1203852E68AB1122AFD9632181C64740A13C6C125342E6 | 同左 | 97 | — | ✓ |
| `docs/M0D-GUI-IMPL-REVIEW-20261118.md`（首轮审计） | 60C1512835D531E4E9019B66F3E98EA7507149ACA2F2CC3A3F7DDF18F3B6A23E | 同左 | 19,788 | — | ✓ |
| `civlink/gui/build-gui.ps1` | 21E3EDC868A761BB1EABBC3B87C87A76923FCBA078826D4F07D393CA922754A0 | 21E3EDC868A7…（前缀） | 4,005 | 4,005 | ✓ |
| `docs/M0D-GUI-DESIGN-20261118.md`（设计终稿） | 698E413CA0DCC43794B0FE2AA74DB768FCBEC95DD6145870CB4E376E7AAF8F74 | 698E413C…（前缀） | 55,952 | 55,952 | ✓ |
| `civlink/gui/build-manifest.txt`（补充） | 5670FE3D90E7D1BA29533ED65F6FB362861A9AC6EB3AE31AD8A92E38D07C2332 | — | 2,740 | — | ✓ |

自检输出实读为 3 行：`CivLink GUI SELFTEST PASS` / `checks=33 failed=0` / `gate=双人验证未完成（Gate A 未批准）`，gate 边界随产物落地。build-manifest.txt 内记录的 `source_sha256`、`output_bytes=26112`、`output_sha256` 与实算一致。

**exe 哈希口径声明**：本机无官方 .NET Framework reference assemblies，`output_sha256` 因 PE TimeDateStamp + MVID 22 字节差异不稳定；验收以 `source_sha256` + `output_bytes=26112` + `exit=0` 为准，**不把哈希变化误判为篡改**。本次实值巧合一致，仅作记录。

---

## 4. 变异判别力裁定

父 agent 声称在 `%TEMP%/civlink-mutation/` 做了 M1/M2/M3 三变异（failed=3/1/2）。复审员**未采信该口述**，在 `C:\Users\dd\AppData\Local\Temp\civlink-mutation\` 用 `csc /target:exe`（console 版，以便捕获完整 stdout，winexe 的 FAIL 名只写 stdout 不写入 outfile）**亲自逐项重编译复核**：

| 变异 | 改动 | 实测结果 | 与父 agent 声称一致 | 裁定 |
|---|---|---|---|---|
| M1 | `Whitelist.Contains` → `return true; // MUTATION M1`（:24） | exit=1，stdout：`FAIL whitelist rejects notepad` / `FAIL whitelist rejects empty` / `FAIL reject non-whitelist`；`checks=33 failed=3` | 是（failed=3） | ✓ 检出 |
| M2 | **仅**删 `:64` simulated-host 整行规则 | exit=1，stdout：`FAIL redact LAN-only token (N-C mutation discriminator: only rule (2) catches it)`；`checks=33 failed=1` | 是（failed=1，精确失败在 N-C 判别断言） | ✓ 检出 |
| M3 | 删规则(1):60 与规则(3):66 两条 room 正则 | exit=1，stdout：`FAIL redact normal room` / `FAIL redact in-sentence room (N-D)`；`checks=33 failed=2` | 是（failed=2） | ✓ 检出 |

说明：
- 三个变异的 outfile（M1-out/M2-out/M2-out2/M3-out.txt）均仅 3 行汇总、不写 FAIL 名，与 failed 计数一致；FAIL 名只在 stdout 可见，故用 console 重编译取证。
- 控制台重编译时 gate 行显示乱码（`˫...`）为 **GBK 控制台显示层假象**，非产物缺陷：原始 `gui-selftest-fixed.txt`（UTF-8 无 BOM）实读 gate 行中文正常。
- **裁定：三项变异足以证明自检具备判别力**，覆盖白名单 fail-closed、LAN-only 整行正则、room 兜底三条独立防御层。首轮「M2 仅删 LAN 段仍 24/24 PASS」的漏检已精确关闭（N-C）。未改动任何被审源码，仅用临时副本。

---

## 5. 新发现（N2-1..N2-3）

三项均**不阻断登记**；严格区分真实缺陷与显示层/环境假象。

| 编号 | 严重级别 | 发现 | 性质 | 阻断登记 |
|---|---|---|---|---|
| N2-1 | 低（观察项） | `shutdown` 子命令在源码中仅由 `BuildArgs :137-138/:467`、超时表 `:81/:88`、自检 `:615/:618/:637` 覆盖，GUI 无 UI 按钮直接调用它（设计 §112 有"关闭注入按钮调 shutdown"设想，P1 未接 UI）。 | **设计-实现差距**，非首轮 N-A..N-G 范围；N-A 要求是"BuildArgs 覆盖五子命令 + DoCtl 用 BuildArgs"，已满足。不影响首轮问题关闭。 | 否 |
| N2-2 | 低（部署注意项） | `StartAgent :510` 期望 `BaseDirectory/fixture-reply-set`；当前 `civlink/fixture-reply-set` 与 `dist/civlink-beta-20261114/fixture-reply-set` 均实存，但发布时须随 exe 部署该目录；缺失时 `:511-515` fail-closed（Log+return），不会误启动。 | **部署/环境项**，非源码缺陷。 | 否 |
| N2-3 | 低（观察项） | N-B 的 `fixtureDir` 仅校验非空目录存在（`:232-233`），未校验 fixture 内容；不影响契约——`--simulate <dir>` 由 agent 侧 `main.rs:1627-1639` 自行读取。 | 边界契约由 agent 承担，**非 GUI 缺陷**。 | 否 |

**明确排除的假象**：① 重编译 console 版 gate 行乱码 = GBK 显示层假象（非缺陷）；② exe output_sha256 波动 = 本机缺 ref assemblies 的 PE/MVID 差异（非篡改）；③ 首轮修复轮中 `SendKeys`/`ProcessStartInfo verb` 等 grep 命中为误匹配（`:53 "verbatim"` 注释、`:256 netstat "-p UDP"`），不构成提权或手动 PID 证据。

---

## 6. 硬约束核验（须确认未被违反）

| 约束 | 核验结果 | 证据 |
|---|---|---|
| 零遥测 / 零日志 / 无配置持久化 | **未违反** | 无 `HttpWebRequest`/`WebClient`/Sentry（grep 0）；`File.WriteAllText` 仅 `:271` stop 文件与 `:648` selftest outfile（均无 BOM/ASCII）；设置页 `:381-384` 明示不持久化。 |
| asInvoker 不提权 | **未违反** | exe 内嵌 manifest 实读 `<requestedExecutionLevel level="asInvoker" uiAccess="false"/>`，无 requireAdministrator；源码无 runas/Verb。 |
| 白名单注入不接受手动 PID | **未违反** | `:20 Names` 三项；`:22-28 Contains`；`:331-332 procBox DropDownList`；`:433-439 SelectedProcName`；`:444` 二次校验；源码无 ctl `-p` 拼接（唯一 `-p ` 是 netstat `:256`）。 |
| ctl 作为子进程复用不重写 IPC | **未违反** | `:115-117 CtlPath`；`:167-207 Run` 用 `ProcessStartInfo`+`civlink_ctl.exe`，`UseShellExecute=false`（:172）。 |
| agent 永不 bind 0.0.0.0:62056 / 永不 SO_REUSEADDR | **未违反** | `62056` 仅自检断言 `:627/:632`（实际绑定 0 命中）；`SO_REUSEADDR`/`0.0.0.0` 均 0 命中。 |
| 机械证据≠双人验证、Gate A 未批准不得越界宣称 | **未违反** | `:99-100 Boundary.State/Mechanical`；托盘文案 `:312/:530-531`；自检 gate 行恒定；裁定 §1 保留边界。 |
| 不做真实游戏/双人验证（PC-B 对局期不干扰） | **遵守** | 本轮仅磁盘实读 + 临时副本变异重编译，未启动真实游戏、未联机。 |

---

## 7. 复审签署

- 复审裁定：**PASS** —— 首轮七项全部关闭，允许进入 README v1.35 / HANDOVER 第 22 项登记。
- 强制保留边界：`gate=双人验证未完成（Gate A 未批准）`；机械证据不得升级为双人验证结论；模拟/headless 证据不得写成真实联机验证。
- 复审员：独立复审审计员（CivLink M0D）；所有证据经磁盘实读与实运行，无口述采信。