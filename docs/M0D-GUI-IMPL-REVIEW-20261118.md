# M0D P1 GUI 产品级实现审计报告（T2–T5 + T6 headless 自检）

- 审计日期：2026-11-18（Asia/Shanghai）
- 审计角色：独立审计员（实现方之外）
- 被审对象：`civlink/gui/civlink_tray.cs`（29,605 B / SHA-256 `0DC34A3FD7C010828F25C715C4915CCED513BBEEC5426BF9A4F6C1D690ECBFC8`）、`civlink/gui/build-gui.ps1`、`civlink/gui/civlink_tray.exe`、`docs/M0D-GUI-IMPL-20261118.md`
- 依据：设计终稿 `docs/M0D-GUI-DESIGN-20261118.md`（`698E413C…`）、设计评审 `docs/M0D-GUI-DESIGN-REVIEW-20261118.md`、ctl 真实契约 `civlink/ctl/civlink_ctl.cpp`、agent 真实契约 `civlink/agent/src/main.rs`
- 证据目录：`M0A/captures/gui-impl-20261118-1830/`（现有 **6** 文件，见 N-7）
- 方法：磁盘权威逐字节哈希核对 + 源码逐行静态审计 + ctl/agent 契约交叉验证 + 对抗性正则探针 + 3 组变异测试（临时副本编译，未触碰被审文件）

---

## 0. 总裁定

**不通过（NOT PASS）**。不允许进入登记阶段（README / HANDOVER）。

理由（两个阻断项，均使 P1 产品级 GUI 的核心页面不可用）：

- **N-A（阻断）**：状态页 / 计数页 / shutdown 调用链必然返回 exit 2。`DoCtl`（`civlink/gui/civlink_tray.cs:421-434`）把裸命令本身当作参数传给 `CtlRunner.Run`（:425 `CtlRunner.Run(cmd, cmd, timeout)`），而 `BuildArgs`（:138）对非 inject 命令不拼 `-x`；ctl 侧 `ResolveTarget`（`civlink/ctl/civlink_ctl.cpp:318-331`）无目标时返回 0，`:394` 直接 `return 2 "target process not found"`。T3 两个页面永远显示"未找到目标进程"，与实现报告 §15-18 宣称的可用状态冲突。
- **N-B（高）**：agent 高级启动（模拟 LAN host）必然失败。`AgentSupervisor.BuildArgs`（`civlink/gui/civlink_tray.cs:182-197`）只拼 `--sim-lan-listen` + `--reserve-62900`，从不拼 `--simulate`；agent `main.rs:1627-1637` 明确 `ok_or("--sim-lan-listen requires --simulate (fixture directory)")?`。更严重的是自检 `SelfTest:558` 用 `Check(!ag.Contains("--simulate"), ...)` 把这个缺陷**固化为断言**，修好功能反而会让自检失败。

附带问题：24 项自检对上述两个阻断项完全无感（它只测参数字符串构造，不测调用链装配），且对 LAN 段正则单 mutation 无判别力（见 §7）。因此"24/24 PASS"**不能**作为产品级可用的证据。

哈希核对结论：10 项被审/依据文件与审计委托书给出的 SHA-256 **全部一致**，审计结束后再次核对仍一致；变异测试全部在 `%TEMP%` 临时副本上进行，被审源码、exe、报告、设计文档**未被修改**。

---

## 1. 逐条关闭表（问题 1–8）

| # | 问题 | 结论 | 关键证据（路径:行号） |
|---|---|---|---|
| 1 | 白名单真 fail-closed；无任意 PID；BuildArgs 所有拼接点有校验 | **通过** | `civlink/gui/civlink_tray.cs:20`（三项白名单）、`:22-28`（OrdinalIgnoreCase、空名拒绝）、`:289`（procBox DropDownList，无手工输入）、`:402`（DoInject 二次校验）、`:118-120`（BuildArgs 校验后拼 `-x`）、`:125-128`（iface 锚定正则）、`:133-135`（module 锚定正则）。所有拼接点（:120/:128/:135）均在白名单/格式校验之后。GUI 全程无 `-p` 拼接点，无法注入 PID。 |
| 2 | Redactor 真正无条件脱敏；room/room name/sim_room_name 两段落；大小写/空格/句中；用户路径与 CIVTRACE_TAG | **不通过** | 常规段与 LAN 段基本成立：`:57` 匹配大小写 + 多余空格 + 下划线变体（探针验证 `ROOM NAME : X`、`  room   = X`、`sim_room_name:X` 均遮蔽）；`:58` 遮蔽整个 `simulated host…room…` 段（含 header 分行、大小写变体，基线探针验证）。用户路径 `:60` 覆盖 C:/d: 大小写。**但**：句中自然语言房名 `In the sentence the room is SentenceRoomValue here` 原样输出（`:57` 强制要求 `room` 后有 `[:=]`）；`civtrace_tag = tagged value here` 仅遮蔽首 token，残留 `value here`（`:61` 用 `\S+`）。详见 N-D。 |
| 3 | ctl 参数注入防护（--iface / -m 空格、引号、分号） | **通过** | `civlink/gui/civlink_tray.cs:126` `^\d{1,3}(\.\d{1,3}){3}$`、`:133` `^[A-Za-z0-9_\-\.]+\.dll$` 均 `^…$` 锚定且不含空白/引号/分号字符集；`:146` `UseShellExecute=false`；`:125-127` 拒绝 `8.8.8.8;evil`（自检 :551-552 覆盖）。失败即抛异常（:127/:134），非静默降级。附注 N-F 的八位组范围问题不构成注入。 |
| 4 | 超时 ≥ ctl 内部等待；Kill 前先查状态；话术诚实 | **部分不通过** | 超时数值通过：`:69-72` inject/status=20000 ≥ ctl 15s（`civlink/ctl/civlink_ctl.cpp:301`/`:501`）、counters=15000 ≥ ctl 10s（`:620`）、shutdown=15000；自检 :560 覆盖。**话术诚实通过**：`civlink/gui/civlink_tray.cs:415` 明示"超时，远程线程状态未知，请导出诊断包"。**Kill 前查状态不通过**：`:163` 注释声称 `query state first (design N-4)`，但 `:164` 紧接直接 `p.Kill()`，无任何状态查询。详见 N-E。 |
| 5 | stop-file 纪律；34718 检测；不绑 62056；无默认 --simulate；reserve 仅随 sim-lan-listen | **通过（字面），但功能后果见 N-B** | `civlink/gui/civlink_tray.cs:229` 写 ASCII `stop`（`new ASCIIEncoding()`）→ `:231` `WaitForExit(20000)` → `:234` 超时才 `Kill()`，顺序正确；`:199-210` netstat UDP 34718 检测，`:455` 占用即拒绝；`:182-197` 无 `62056`、无 `--simulate`、`:192` reserve 仅随 sim-lan-listen（自检 :555-557 覆盖）。**注意**：正因"无默认 --simulate"与 agent 契约冲突，该路径实际必然启动失败（N-B）。 |
| 6 | 状态/计数/诊断页无"已联机/已验证"过度承诺；exit 4 隐藏计数；Gate A 话术稳定 | **通过** | `civlink/gui/civlink_tray.cs:90` `Boundary.State = "双人验证未完成（Gate A 未批准）"`、`:91` Mechanical 话术；`:270`/`:322`/`:345` 页面写入该话术；`:427` exit 4 时用 `(计数数据不可信，已隐藏 — exit 4)` 替换输出；`:38` exit 0 明确"不代表已联机"；`:476-477` 托盘 text 恒带 Boundary.State；探针输出文件 gate 行恒为 `Gate A 未批准`。无越界承诺。 |
| 7 | 24 项自检有判别力；≥2 变异测试；前后哈希一致 | **不通过（判别力有缺口）** | 变异测试已完成（见 §7）：M1（Whitelist→true）与 M3（删两条 room 正则）被抓到 FAIL；**M2（仅删 :58 LAN 正则）仍 24/24 PASS**，输出哈希与基线完全相同 `606E3C09…`。此外自检完全没有覆盖 `DoCtl` 参数装配，故对 N-A 无感。变异后源码哈希恢复为 `0DC34A3F…`，与权威一致。 |
| 8 | 未覆盖项如实登记；未勾 E2/Gate A | **通过** | `docs/M0D-GUI-IMPL-20261118.md:35-39`：明确未做真实游戏端到端、未做真实双人跨网、不勾 E2/E2-B/E3、不动 Gate A；`:23` 诊断导出"实际写文件…后续补丁接入（如实登记）"；`:38` 白名单清单待负责人确认、A 房主默认流程待确认；`:7` 全边界声明。无虚假完成宣称。 |

---

## 2. 新发现（N-1..N-7，按严重度编号）

### N-A【阻断】状态 / 计数 / shutdown 调用链必然失败，T3 页面不可用
- 证据：`civlink/gui/civlink_tray.cs:425` `CtlResult r = CtlRunner.Run(cmd, cmd, timeout);` —— 第二参数 `args` 直接等于裸命令；`:138` `return a.ToString();`（非 inject 命令分支只返回 cmd 本身）；对照 `civlink/ctl/civlink_ctl.cpp:341-343` 用法串要求 `-x <process.exe>`；`:354-361` 参数解析只在出现 `-x` 时设置 `exeArg`；`:393-394` `const DWORD pid = ResolveTarget(...); if (!pid) { ... return 2; }`。GUI 页面入口 `civlink/gui/civlink_tray.cs:320`（status）、`:329`（counters）。
- 后果：点击"查询状态""读取计数"必定显示 exit 2 与"未找到目标进程"，实现报告 §15-18 的 T3 交付实际不成立；`:428-429` 的 Redactor 与 exit-4 隐藏逻辑永不触发。
- 修法：`DoCtl` 为三条命令复用 `SelectedProcName()`（:393）经白名单二次校验后，调用 `CtlRunner.BuildArgs(cmd, proc, null, null)` 生成 `-x "<白名单名>"`，再把结果作为 `args` 传入 `Run`；或在 `BuildArgs` 中为 status/counters/shutdown 增加同样的 `-x` 装配分支。并补一条自检断言验证三条命令的 args 含 `-x`。

### N-B【高】模拟 LAN host 启动必失败，且被自检断言反向锁死
- 证据：`civlink/gui/civlink_tray.cs:182-197` 的 `AgentSupervisor.BuildArgs` 只拼 `--listen-seconds 0 --out-dir … --sim-lan-listen <ip> --reserve-62900 --quiet --stop-file …`，**没有任何 `--simulate`**；agent 契约 `civlink/agent/src/main.rs:1627-1637`：`args.sim_lan_listen` 为 Some 时，`:1629-1631` `args.simulate.as_deref().ok_or("--sim-lan-listen requires --simulate (fixture directory)")?`，无 `--simulate` 即返回 Err；`:1405` `simulate: None` 为默认。启动点 `civlink/gui/civlink_tray.cs:462-468` 会记录日志但进程立即退出，GUI 仍把 `p.Id` 记为存活。
- 更严重：`SelfTest:558` `Check(!ag.Contains("--simulate"), "default host does not start sim agent")` 把缺陷固化为"必须不含 --simulate"，修复后自检反而失败。
- 修法：`BuildArgs` 增加 fixture 目录参数，在 `listenIp` 非空时追加 `--simulate "<fixture-dir>"`；把 :558 改为验证"普通 A 房主路径（无 LAN IP）不含 --sim-lan-listen/--simulate，高级 LAN 路径含 --simulate"。注意设计 N-5 的本意只是"普通 A 房主默认不启 agent"，不等于"agent 永远不得带 --simulate"。

### N-C【中】headless 自检判别力缺口：删掉 LAN 段正则仍 24/24 PASS
- 证据：变异 M2 仅删除 `civlink/gui/civlink_tray.cs:58` 的 `simulated host…room…` 正则，自检输出仍 `CivLink GUI SELFTEST PASS / checks=24 failed=0`，哈希 `606E3C09…` 与基线逐字节相同。原因：自检样本 `SelfTest:535` 的 `LAN simulated host room=SecretHostABC` 中 `room` 后有 `=`，被 `:57` 通用正则先行遮蔽，`:538` 的断言因此恒真。
- 后果：N-1 的核心防御层（LAN 段无条件遮蔽）失去回归保护。
- 修法：在 `SelfTest` 增加一条 ":57 无法命中、只有 :58 才能遮蔽" 的样本，例如 `LAN simulated host room name is HiddenToken here`（room 后无 `[:=]`）或把房名放在 LAN 头行且与 room 同行但不含 `[:=]`，断言输出不含 `HiddenToken`。变异 M2 应因此 FAIL。

### N-D【中】Redactor 句中房名绕过；CIVTRACE_TAG 带空格值残留
- 证据：`civlink/gui/civlink_tray.cs:57` 的模式要求行内 `\b(room|room[_ ]?name|sim_room_name)\b … [:=]`，句中自然语句 `In the sentence the room is SentenceRoomValue here` 与 `room without any colon or equals SentenceOnlyRoom` 经探针（临时反射调用 `Redact`）均**原样输出**；`:61` `(CIVTRACE_TAG\s*=\s*)\S+` 对 `civtrace_tag = tagged value here` 只遮蔽首个 token，输出 `civtrace_tag = <redacted> value here`。
- 影响：若 agent/ctl 错误文本以自然语言句子输出房名（非 `room=` 形式），或 tag 值含空格，PII 可能进入诊断包。基线对标准格式（`room : X`、`CIVTRACE_TAG=host`）遮蔽正确，属"防御不完整"而非"当前已泄露真实房名"。
- 修法：增加兜底规则 `Regex.Replace(s, @"(?i)\b(room(?:[_ ]?name)?|sim_room_name)\b[^\r\n]{0,80}", "$1=<redacted>", …)` 覆盖句中形式（注意与 :57/:58 的先后顺序与重复遮蔽）；tag 值改为行尾截断 `(CIVTRACE_TAG\s*=\s*)[^\r\n]+` → `$1<redacted>`。补自检断言。

### N-E【中，诚实性】超时 Kill 前未查询状态，注释与行为不符
- 证据：`civlink/gui/civlink_tray.cs:163` 注释 `// Last resort only: query state first (design N-4). We record timeout honestly.`，紧接 `:164` `try { p.Kill(); } catch (Exception) { }` —— 中间无任何状态查询或二次等待。设计 N-4 的"先查询状态再决定清理"未实现。
- 注：对外话术（`:415`）与 ExitCodeMapper（:38-44）本身诚实，未把超时说成成功；问题在代码注释误导维护者。
- 修法：实现 `p.HasExited` 复查 + 短二次 `WaitForExit`，或把注释改为"超时直接终止子进程，远程线程状态未知（见 :415 话术）"，避免与设计 N-4 措辞冲突。

### N-F【低】iface 校验不检查八位组范围 0–255
- 证据：`civlink/gui/civlink_tray.cs:126` 只检查点分四段与位数，不约束每段 ≤255；`999.999.999.999` 可通过 GUI 校验。
- 影响：无注入风险（锚定正则），ctl 侧 `ResolveIface` fail-closed 返回 exit 1（`civlink/ctl/civlink_ctl.cpp:375-379`）兜底，不会造成错误配置落盘。属纵深防御改进。
- 修法：把正则改为逐段 `(25[0-5]|2[0-4]\d|1?\d?\d)`，或解析后逐段检查。

### N-G【低】实现报告证据文件数与实际不符
- 证据：`docs/M0D-GUI-IMPL-20261118.md:32` 称 `gui-impl-20261118-1830/` 为"5 文件"；实际目录现有 6 文件（新增后补 `gui-window-smoke.txt`，949 B，记录 UI 构造 smoke：窗口句柄非零、可关闭、PASS，且明确注明不证明注入/联机/Gate A）。
- 修法：把 §32 改为"6 文件（含后补 gui-window-smoke.txt）"，并把 smoke 的性质（仅 UI 构造层）纳入报告，避免 reader 误读为端到端证据。

---

## 3. 变异测试证据

所有变异在 `%TEMP%\civlink-mutation-85d9b82b\` 的**源文件副本**上进行，用 `D:\MSVC\BuildTools\MSBuild\Current\Bin\Roslyn\csc.exe`（`net40` 引用自 `C:\Windows\Microsoft.NET\Framework64\v4.0.30319`）编译为 winexe。被审源文件全程未被写入。

| 变体 | 变异内容 | 变异源码 SHA-256 | 变异 exe SHA-256 (B) | selftest 退出码 | 输出 SHA-256 |
|---|---|---|---|---|---|
| BASE | 未变异副本 | `0DC34A3FD7C010828F25C715C4915CCED513BBEEC5426BF9A4F6C1D690ECBFC8`（与权威一致） | `97C2B665C2B9D8D035B1928A7B86BA594959696E610755911DE8E159DD5174EE` / 23552 | **0** / 24 PASS | `606E3C0973D1105F20CB6719C36D87291388A2CF87BEC8043F4FE150A8419BDB`（与官方证据逐字节一致，构建保真） |
| M1 | `Whitelist.Contains` 改为 `return true` | `DF76463D516581D7906B42398B44E245422E02CEEC42279AE96BA6336630A8B9` | `3717EB51D6EF14087AB04A6CAF304B05449750CE2F2774ECF0C06AEFB864A955` / 23552 | **1** / FAIL 3 项（whitelist rejects notepad / rejects empty / reject non-whitelist） | `C858CB342690B13C16FCD1979E6A98AFA9CCDEA9EA09E1821E6D2AC2685F1A78` |
| M2 | 仅删除 `:58` LAN 段正则 | `BDB969B015C0C3F37150DE5F6C992C7C4FD7CA24CC417FC2CB879A39A1331DD7` | `FB4CB9763B5608A1D213D5183CAFD40DB3CD0FF04AF8B6550AFBB622A59D457A` / 23552 | **0** / **24 PASS（漏检！）** | `606E3C0973D1105F20CB6719C36D87291388A2CF87BEC8043F4FE150A8419BDB`（与 BASE 相同） |
| M3 | 同时删除 `:57` 与 `:58` 两条 room 正则 | `3F8D691175229C08112B8BD50572B7FD0FC2B48DC3C4E6C14E399B1B5A3F0B12` | `062EC6786CFCEACFEA6090602B5A95CCAE0EC614B43132EFF09A935FBAD29546` / 23040 | **1** / FAIL 2 项（redact normal room / redact LAN room (N-1)） | `02A53D8A468B0CE77C838AC52EA271E232E776832749BC5E3326217FD5251A03` |

输出文件原文（BASE / M1 / M2 / M3，UTF-8，中文 gate 行为 `双人验证未完成（Gate A 未批准）`）：

```
CivLink GUI SELFTEST PASS      CivLink GUI SELFTEST FAIL      CivLink GUI SELFTEST PASS      CivLink GUI SELFTEST FAIL
checks=24 failed=0             checks=24 failed=3             checks=24 failed=0             checks=24 failed=2
gate=双人验证未完成…           gate=双人验证未完成…           gate=双人验证未完成…           gate=双人验证未完成…
```

补充判别力探针（`ExtendedSelfTest`，`extended_ORIG.exe` = `08E8364B…`、`extended_M2.exe` = `867F954F…`，对真实 agent 风格输入 `LAN simulated host (F5)\n  room : 'PiiRoom_Alice'`，ORIG 与 M2 都输出 `room : <redacted>`，`PII_LEAK=False`）：这说明 M2 的漏检源于"删掉一层防御但样本仍被另一层遮蔽"，属**回归判别力**缺陷（N-C），而非当前版本已发生真实房名泄露。

**恢复核对**：审计结束时再次计算权威源码哈希仍为 `0DC34A3FD7C010828F25C715C4915CCED513BBEEC5426BF9A4F6C1D690ECBFC8`（与变异前一致）；exe / 报告 / 设计文档 / selftest 证据哈希均未变化。所有变异副本留在临时目录，未被拷回被审目录。

---

## 4. 哈希抽查（10 项，全部一致）

| 文件（相对 `CivLink-M0A-audit/`，除末行） | 字节 | SHA-256 | 结果 |
|---|---|---|---|
| `civlink/gui/civlink_tray.cs` | 29,605 | `0DC34A3FD7C010828F25C715C4915CCED513BBEEC5426BF9A4F6C1D690ECBFC8` | 一致 |
| `civlink/gui/civlink_tray.exe` | 23,552 | `73D24F50894446F00A55188866220655D5CAE1C08C83710DE70E2DA41DD44CAD` | 一致（output 不稳定性按已知口径，不计缺陷） |
| `civlink/gui/build-gui.ps1` | 4,005 | `21E3EDC868A761BB1EABBC3B87C87A76923FCBA078826D4F07D393CA922754A0` | 一致 |
| `civlink/gui/build-manifest.txt` | 2,740 | `06E37E6A67111CC6BB4396E638A5ADF9F0BD55469BB439202116C980024014E5` | 一致 |
| `docs/M0D-GUI-IMPL-20261118.md` | 5,422 | `9324368422243ED13F0913037561F4E1B63A7F926116DE38889F98AE6C0A7FCD` | 一致 |
| `docs/M0D-GUI-DESIGN-20261118.md` | 55,952 | `698E413CA0DCC43794B0FE2AA74DB768FCBEC95DD6145870CB4E376E7AAF8F74` | 一致 |
| `docs/M0D-GUI-DESIGN-REVIEW-20261118.md` | 17,489 | `0F705EAE7E6E415C8730D0A82444D4B3C3BE6E3D44D33DF8BCFF437703B8608F` | 一致 |
| `civlink/ctl/civlink_ctl.cpp` | 30,658 | `22EFEF52C19EDA8C1352F6B6B20ECEDFADE564D0AD447FAA2FBB032EC5584241` | 一致 |
| `civlink/agent/src/main.rs` | 127,146 | `E556B66F864D492763F944549E5BEC4F001CE3CD85B05D22910C38D374D6C4C2` | 一致 |
| `M0A/captures/gui-impl-20261118-1830/gui-selftest-20261118.txt`（相对项目根） | 97 | `606E3C0973D1105F20CB6719C36D87291388A2CF87BEC8043F4FE150A8419BDB` | 一致（与变异基线输出亦相同） |

---

## 5. 未采信口述 / 未做验证声明（诚实边界）

- **未采信任何口述**：所有结论均来自磁盘文件逐字节哈希、源码行号与可执行程序的实际运行输出；未把"实现方声称"当作证据。
- **未做真实游戏验证**：未在真实《文明6》进程上执行注入；未做真实双人跨网对局；未验证 GUI 与 ctl/agent 在运行时的实际联动（N-A/N-B 是静态推导 + 契约交叉验证得出，未在真机上复现点击行为）。
- **UI smoke 的边界**：`gui-window-smoke.txt` 仅证明 MainForm（五页签 + NotifyIcon + 白名单进程枚举 + 本地 IPv4 枚举）可构造、窗口句柄非零、可正常关闭；**不证明**注入成功、联机成功或 Gate A 状态变化。
- **24/24 PASS 的边界**：仅证明 24 条断言本身通过；变异测试证明它不能覆盖调用链装配（N-A）、LAN 正则单 mutation（N-C）与 agent `--simulate` 契约（N-B 被反向断言锁死）。
- **不改变 Gate A**：本次审计不批准任何双人联机结论，Gate A 维持未批准。
- **被审对象未被修改**：变异测试仅使用 `%TEMP%` 副本；审计前后哈希一致（§4）。

---

## 6. 修复与复审建议

1. 先修 **N-A** 与 **N-B**（阻断/高），并同步修正 `SelfTest:558`，再补三条 status/counters/shutdown 的 `-x` 断言与 agent `--simulate` 断言。
2. 修 **N-C**（补 LAN-only 判别样本）后重跑变异 M2，必须 FAIL。
3. 修 **N-D**（兜底 room 规则 + tag 行尾截断）、**N-E**（状态查询或改注释）、**N-F**（八位组范围）、**N-G**（报告 5→6 文件）。
4. 复审要求：重新出 exe、重新跑 24+ 项自检并附输出哈希、重做变异 M1/M2/M3；仅在阻断/高项全部关闭且自检判别力证明有效后，方可讨论进入 README/HANDOVER 登记阶段。
