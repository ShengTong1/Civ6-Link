# E2-B TAG 机制复审报告（第二轮）

- 审计对象：CivLink E2-B 执行包 CIVTRACE_TAG 机制修正闭合性复审
- 复审审计员：独立复审审计员（CivLink 项目）
- 复审时间：2026-11-16
- 依据：首轮审计 `E2B-TAG-MECHANISM-REVIEW.md`（277 行，裁定"有条件通过，必改 4 项"）所列必改项 D1/D2/D6/D7
- 方法：全部期望值独立重算（字节数、SHA256、行数/换行/BOM、关键字 grep、逐条哈希比对、zip 解压逐文件比对），未复用任何既存计算结果

**复审裁定：通过（PASS）**，必改 0 项

原必改 4 项（D1/D2/D6/D7）全部闭合。另发现 2 处纯文字/排版级观察（标题字面串"24 个文件"、加粗符打断字面串），语义完全满足，不影响闭合，详见 C/F。

---

## A 身份核验表（全部独立重算）

| 文件 | 期望字节 | 实测字节 | 期望 SHA256 | 实测 SHA256（独立重算） | 行数 | 换行 / BOM |
|---|---|---|---|---|---|---|
| `CivLink-M0A-audit\docs\E2B-EXECUTION-PACK.md` | 16,160 | 16,160 | `E10A0270…DBA1` | `E10A0270EF1EF3ACA4F6C7F44F49B78B17ABD4345A9F45123F7122FDF001DBA1` | 331 | LF（CRLF=0），无 BOM |
| `M0A\pcb-kit\PC-B-操作单.md` | 13,174 | 13,174 | `9740A2F4…144A` | `9740A2F4E417C5EBCFFBD5A9F2CBAA96D1F3E3C6376F4CD7FACA8D26FEA9144A` | 293 | CRLF，无 BOM |
| `M0A\pcb-kit\PC-B-交接文档.md` | 8,970 | 8,970 | `908BDABF…E0A4` | `908BDABFB429D14926E6CCF556326E4FAC30C41270C31AF6CB89C1516BB2E0A4` | 164 | LF，无 BOM |
| `M0A\pcb-kit\MANIFEST-sha256.txt` | 2,301 | 2,301 | （任务未给期望值） | `55A7C017FE7E6E3307D1708C2CD34B7AC6740C0948249E0E1BF317D670A74E49` | 28（5 头 + 23 条目） | LF，无 BOM |
| `Desktop\pcb-kit.zip` | 355,796 | 355,796 | `FE8BD1E1…26C6` | `FE8BD1E1C27AB9F631B4104E3CADC64E4689FCB597D8F7BCC0AA779302D026C6` | — | — |

全部与期望值一致（含"无 BOM"要求；E2B 包 LF 行数 331 精确命中）。

---

## B 必改项逐项闭合情况

### D1（阻断）— PASS
证据（`E2B-EXECUTION-PACK.md` §3 步骤 2）：
- **L107**：`$exe = "E:\SteamLibrary\steamapps\common\Sid Meier's Civilization VI\Base\Binaries\Win64Steam\CivilizationVI_DX12.exe"` —— 真实完整路径，含 `Base\Binaries\Win64Steam` 段 ✓
- **L108**：`Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe)` ✓
- **L112–113**：`**该 DRM 行为未在本机验证**——若直接启动后游戏秒退，请改用做法 A` ✓
- L106 的 `$env:CIVTRACE_TAG` 仅在"从该窗口直接启动 exe"（做法 B）语境出现，语义正确（该窗口启动的子进程确实继承 `$env:`）。

### D2（高）— PASS
证据（`PC-B-操作单.md` §2，L54–93）：
- **L80** 注释明示：`清单格式为两字段：HASH  文件名` ✓
- **L83**：`if ($_ -match '^([0-9A-Fa-f]{64})\s+(\S.*)$')` —— 两字段正则 ✓
- **L84**：`$h = $Matches[1].ToUpper()`（大写归一后比对）✓
- **L85**：`if (-not (Test-Path -LiteralPath $n)) { $bad++; "MISSING: $n" }` —— 文件缺失显式计数（fail-closed）✓
- **L86–87**：`(Get-FileHash -LiteralPath $n -Algorithm SHA256).Hash` + `if ($a -ne $h) { $bad++; "MISMATCH: $n" }` ✓
- **L93**：`**期望 mismatches = 0。** 不是 0 就停下来报告，不要继续。` ✓
- 残留：`$p[0]` / `$p[2]` / `Cannot find path` 全文档 0 命中 ✓
- 注：片段内 `return` 位于 `ForEach-Object` 脚本块中，仅跳出当前元素，MISSING 计数不受影响，行为正确。

### D6（中）— PASS
证据（`E2B-EXECUTION-PACK.md` §8，L313–320）：
- **L319**（操作单行）：`**该文件头部自述已过期（G2/Radmin 归因早于 2026-11-12 范围决议）——E2-B 只以本包 §3 为准**` —— 含「头部自述已过期」+「E2-B 只以本包 §3 为准」✓
- **L320**（交接文档行）：`历史记录，**不得据其执行**（其中 tag 设置等语句已被本包 v1.1 更正取代）` —— 含「历史记录」+「不得据其执行」✓（期望字面串"历史记录，不得据其执行"因加粗符 `**` 插入而不连续，见 F 观察②）

### D7（中）— PASS
证据（`PC-B-交接文档.md`）：
- **L108**：`你（PC-B）**不注入**（E2-A 无 tag 需求；tag 只在 E2-B 注入时才需要）` ✓（语义含「PC-B 不注入（E2-A 无 tag 需求）」）
- **L120**：`**tag 必须已进入游戏进程**（在启动游戏的那个 PowerShell 窗口先 $env:CIVTRACE_TAG='client' 再直接启动 exe，或 setx + 重启 Steam；详见操作单步骤 6 注与 E2B-EXECUTION-PACK §3 步骤 2）` —— 机制结论 + 两种正确做法 + 双指针齐全 ✓（机制细节 `trace_dll.cpp:287 GetEnvironmentVariableW` 由指针落在操作单 L197–199 与包 L81–86）
- **L111 / L122**：分别为"抓包自然结束（脚本自带窗口），收集："与"**你点刷新 10 次**（每次间隔约 2-3 秒）。"，**不再教 set 写法** ✓
- 残留：`set `（含尾空格）0 命中；`setx` 仅 L120 修正后说明 ✓

---

## C 残留检查

| 检查项 | 期望 | 实测 |
|---|---|---|
| v1.0 / v1.1 版本头行 | 0 | **0**（L3 为 v1.2 版本行内 changelog 提及 v1.1/v1.0；L86 为历史证据说明——均非版本头残留）|
| 旧 exe 路径（缺 `Base\Binaries\Win64Steam` 段） | 0 | **0**（L107 已含完整段；L114/141/149/188 为进程名/`-x` 参数引用，非路径）|
| 旧哈希字段假设 `$p[0]` / `$p[2]` | 0 | **0** |
| 旧 set 写法（交接文档） | 0 | **0** |
| 版本行含 v1.2（2026-11-16 21:53，注明 v1.1 按审计修正） | 存在 | **L3**：`> 版本：v1.2（2026-11-16 21:53；v1.1 按 E2B-TAG-MECHANISM-REVIEW 审计修正：做法 B 用真实 exe 路径 + Start-Process -WorkingDirectory、补 DRM 未验证声明与 tag 字符集、§8 权威指针标注操作单/交接文档为历史记录；v1.0 的 $env: 设 tag 写法在 Steam 启动路径下不生效，已更正为 setx+重启 Steam 或直接起 exe，见 §3 步骤 2）` ✓ |
| 步骤 2 尾含 setx 清理 | 存在 | **L134–136**：`收尾清理（若用过做法 A 的 setx）：实验结束后执行 setx CIVTRACE_TAG ""（或 reg delete HKCU\Environment /v CIVTRACE_TAG /f）` ✓ |
| 自证命令含 `Where-Object Name -match '_(host|client)\.log$'` | 存在 | **L122–124**：`Get-ChildItem "$env:LOCALAPPDATA\CivLink\M0A\logs\*.log" | Where-Object Name -match '_(host|client)\.log$' | Sort-Object LastWriteTime | Select-Object -Last 1 …` ✓ |

---

## D MANIFEST 23 条逐条核对（23/23 全命中）

`MANIFEST-sha256.txt` 共 28 行 = 5 行头部说明（L1–5，非哈希条目）+ 23 条 `64位哈希 空格 文件名`。逐条对 `M0A\pcb-kit\` 目录实文件独立重算 sha256：

| # | 文件名 | MANIFEST 哈希 | 实测哈希 | 结果 |
|---|---|---|---|---|
| 1 | 1-capture-pcapng.cmd | `BDEECEEEFFED5EED4B43B05ACD275540941215F0098F81E4490B469259BA5614` | 一致 | OK |
| 2 | 2-netpath.cmd | `4675D5481A6588F4BBDA83CC2B7ACBCC7625017F50ED10C9A418AAE8AA0C881D` | 一致 | OK |
| 3 | 3-e0-baseline.cmd | `722B32A87B19E979F8372133531BCE2F269D9FF16F9C62CFBD3C91F0F87ED741` | 一致 | OK |
| 4 | 4-lanprobe.cmd | `C1207A0814063B19E0DB7EBA1D29760A42229104326D633E7441FF5AAFC4066C` | 一致 | OK |
| 5 | 5-broadcast-status.cmd | `5E26A0E75369412E474230E0E2AE0DF71C31133CEB6EE5C5824349FD25414192` | 一致 | OK |
| 6 | 6-broadcast-apply.cmd | `9EF3EAB840D6F92C20854EFDD23D42CC6050141639CF4A8868C47250D6AD28DF` | 一致 | OK |
| 7 | 7-broadcast-restore.cmd | `D27C87461E604A44A4BCA6F4B1C355691C0BF071A501C84D79293CB5AC288C30` | 一致 | OK |
| 8 | analyze-discovery-handshake.ps1 | `A01EEFB69AFB96A7B6445BF77CD730E920B0A9A12EA3D3F492D91F1B089D99F2` | 一致 | OK |
| 9 | analyze-pcapng-datagrams.ps1 | `DB4520DF0164C35D6D434355CB830720DCB59C271BFB2C961D865901A5D56C06` | 一致 | OK |
| 10 | **civinject.exe.bak-4DCC9557**（新增） | `4DCC95578A5E0D85F0F6D4BA3C5EBED24CA0EE34D5EBF50A80F70C7FAA99EC72` | 一致 | OK（171,520B ✓）|
| 11 | civinject.exe | `54627EABB15E203DE6112C8908B74E0714F0B8FA04567E2298B395534A700DF6` | 一致 | OK |
| 12 | civtrace.dll | `19196FF7A6CE36AD49C00AF7FCA74EFDE868F87A6BFB49BAB342F4CADF4BFEDE` | 一致 | OK |
| 13 | collect-baseline.ps1 | `674E0AFD0C307A2EE4183911CDB6F52290ADD738CE5109F3529BB66AD99ADA6A` | 一致 | OK |
| 14 | lanprobe.ps1 | `FB06239D01BE1A422C688E1B3B133F66C066E75A4CCBCFFF6BA958B0745606E5` | 一致 | OK |
| 15 | lanprobe-reverse-g2.log | `E20068666695115947AEF8DDC063323B5A3E3AF1F9F53747C0CD8689B7EE1FE6` | 一致 | OK |
| 16 | netpath.ps1 | `A3706572ECEECB1090B67E4DBC81A461FCEBBBE5BA8C8E0CD0701AC81987F39C` | 一致 | OK |
| 17 | pcapng-capture.ps1 | `5E0835864789F0DBE0C9F58A70D2EC4376EF3C659E408EDBC71261B93B822B31` | 一致 | OK |
| 18 | pcapng-capture-full.ps1 | `CE0775C2E6CCDF75CF3EDBC9843E97D694DFF47C3370596D42E87A296C6A8D5B` | 一致 | OK |
| 19 | PC-B-操作单.md | `9740A2F4E417C5EBCFFBD5A9F2CBAA96D1F3E3C6376F4CD7FACA8D26FEA9144A` | 一致 | OK |
| 20 | PC-B-单机metric修复与自证-v3.md | `770C077440228E096FC7A6D08FC93309F5092AF14DEB20B9F38D7312918D0CEA` | 一致 | OK |
| 21 | PC-B-交接文档.md | `908BDABFB429D14926E6CCF556326E4FAC30C41270C31AF6CB89C1516BB2E0A4` | 一致 | OK |
| 22 | RUN-pcapng-full.cmd | `510C060C1D6A94B89AF66E66BAA5DD0A839C68BA2512A359B820FEC4EA2314D9` | 一致 | OK |
| 23 | set-broadcast-path.ps1 | `76DD95B067C36AC6CEA268300807FB642BC5B62F6E122A5443016D6DABC86AF2` | 一致 | OK |

- **23/23 全命中**，无 MISMATCH、无 MISSING。
- 新增条目 `civinject.exe.bak-4DCC9557` 哈希与字节（171,520B）与期望完全一致 ✓。
- 无多余条目：kit 目录共 24 个文件 = 23 条清单 + `MANIFEST-sha256.txt` 自身（清单**不含自身** ✓）；`.bak` 文件仅此一个 ✓。

---

## E zip 一致性（PASS）

- `pcb-kit.zip`：355,796B / sha256=`FE8BD1E1C27AB9F631B4104E3CADC64E4689FCB597D8F7BCC0AA779302D026C6`，与期望一致。
- **zip 顶层结构：扁平**——24 个文件全部直接位于 zip 根，**无任何子目录**，不存在 `civlink-f5-kit\` 之类嵌套。
- 逐文件比对：kit 目录 24 个文件与解压文件按相对路径一一对应，**sha256 全部全等（ok=24，fail=0）**；解压总数 24，无多余、无缺失。
- zip 内 `MANIFEST-sha256.txt`（`55A7C017…`）与 kit 内一致，即 zip 装载的是更新后的 23 条版本 ✓。

---

## F 边界与总结

**边界**：
1. 本次仅核验 D1/D2/D6/D7 四项必改与任务指定的 6 组期望值；首轮报告中非必改的建议项未重新审计。
2. `C:\Users\dd\Desktop\civlink-f5-kit\` 按任务说明跳过（F5 核验包，本轮无关）。
3. 所有哈希独立重算（SHA256）；行数/换行/BOM 以字节级分析为准。

**观察（不影响闭合，如实报告）**：
- ① 操作单 §2 标题实际为「工具包（**24 个文件**，先核对哈希）」（L54），字面串"24 文件"不存在（中间多"个"字）；语义（24 个文件数）满足。
- ② 包 §8 交接文档行（L320）为「历史记录，**不得据其执行**」，因加粗符 `**` 插入使字面串"历史记录，不得据其执行"不连续；语义完整。同类的「PC-B 不注入（E2-A 无 tag 需求）」在交接文档以 L103/L108「PC-B 不注入」+「（E2-A 无 tag 需求…）」分段呈现。
- ③ 若希望"字面串可 grep 命中"，可去掉上述两处加粗标记——纯排版选择，不影响执行语义。

**总结**：4 项必改全部闭合；5 个文件身份（字节/SHA256/行数/BOM）、MANIFEST 23 条逐条哈希、zip 24 文件一致性全部与期望值一致；**无任何哈希不符或未闭合项**。**复审裁定：通过（PASS），必改 0 项。**
