# E2-B 角色 tag 机制与更正文书 · 独立审计报告

- 审计对象：`docs/E2B-EXECUTION-PACK.md`（v1.1）、`M0A/pcb-kit/PC-B-操作单.md`、`M0A/pcb-kit/MANIFEST-sha256.txt`、桌面交付包 `pcb-kit.zip` 及解压副本 `pcb-kit\`
- 审计方式：只读。仅用 PowerShell 读取文件、计算哈希、遍历日志、解压到 `%TEMP%` 比对（比对后删除临时目录）。未改动任何被审计文件。
- 审计立场：不采信提交方结论，全部从源码、二进制配套文件、磁盘实测与 Windows 语义独立复核。
- 审计时间：2026-11-16 21:39–21:52（本机时间）

---

## 0. 裁定

> **裁定：有条件通过（PASS with must-fix，必改 4 项）**
>
> 本轮更正的**技术前提完全成立**：`civtrace.dll` 在目标进程内读 `CIVTRACE_TAG`，注入器不传递，
> 从 Steam 启动的游戏只继承 Steam 进程的环境。三处（§2 门禁 / §3 步骤 2 / §7 失败模式）口径一致，
> 无越界宣称，包与清单哈希全等。
>
> 但**不能直接签发执行**：`做法 B` 的命令路径在本机实测不存在（缺两级目录，照抄必失败），
> 交付包里的《PC-B 交接文档》仍在教已被否定的 `set` 写法，且《PC-B 操作单》§2 的哈希校验片段
> 字段错位（实测对真实文件篡改不计数，等于没有校验）。以上 4 项修完即可通过。

| 统计 | 数量 |
|---|---|
| 阻断 | 1 |
| 高 | 1 |
| 中 | 5 |
| 低 | 5 |
| 信息 | 2 |
| **必改** | **4** |

---

## 1. 核心机制复核（本轮争议的技术事实）

### 1.1 逐条核对

| # | 待核事实 | 结论 | 证据（文件:行号 / 实测值） |
|---|---|---|---|
| T1 | tag 在**目标进程内**读取 | **成立** | `CivLink-M0A-audit/civtrace/trace_dll.cpp:287`：`wchar_t t[40]; DWORD n = GetEnvironmentVariableW(L"CIVTRACE_TAG", t, 40);` |
| T2 | 注入器**没有**把 tag 传进目标进程 | **成立** | `injector.cpp` 全文无 `SetEnvironmentVariable` / `CreateEnvironmentBlock` / `CreateProcess`；注入路径只有 `VirtualAllocEx`→`WriteProcessMemory`→`CreateRemoteThread(LoadLibraryW)`（`injector.cpp:462-474`）；命令行仅解析 `-x` / `-p` / `-u` 和 DLL 路径（`injector.cpp:269-272`），无 tag 选项 |
| T3 | 全仓库仅此一处读 tag | **成立** | 对 `CivLink-M0A-audit/` 与 `M0A/pcb-kit/` 全量 grep `CIVTRACE_TAG`：源码命中仅 `trace_dll.cpp:287` 与日志模板 `trace_dll.cpp:1366`（后者只是横幅文案），二进制命中为字符串常量，无第二条传递通路 |
| T4 | 字符过滤 | **成立** | `trace_dll.cpp:289-292`：仅接受 `A-Z a-z 0-9 - _`，`j < 24` 截断 |
| T5 | 长度限制 | **成立** | `trace_dll.cpp:288`：`if (n > 0 && n < 32)`（原始长度必须 <32；缓冲区 40，超长时 `GetEnvironmentVariableW` 返回所需长度 ≥40，同样被拒） |
| T6 | 文件名格式 | **成立** | `trace_dll.cpp:295-297`：`civtrace_%04u%02u%02u_%02u%02u%02u_pid%lu%s%s.log`，tag 非空时前缀 `_` |
| T7 | 历史日志「86 份、0 份带 `_host`/`_client`」 | **成立** | `%LOCALAPPDATA%\CivLink\M0A\logs\*.log` 实测 **86** 个文件；`_(host\|client\|c3)\.log$` 匹配 **0**；`Desktop` + `%TEMP%` 下另有 0 个 `civtrace_*.log`，故 86 即全集 |
| T8 | Windows 环境继承语义（Steam 路径） | **成立** | 见 §1.2 本机实验 |

### 1.2 环境继承语义的本机实验（不是引经据典，是实测）

同一台机器、两个独立进程：

1. 先启动 P1（延迟 5 s 再读环境），此时父进程**尚未**设置变量；
2. 父进程执行 `$env:DSHAUD='probe-zz'`；
3. 再启动子进程 P2，读同名变量。

实测输出：

```
P1_started_before_set=[]            # 已运行进程看不到后设的值
P2_child_created_after_set=[probe-zz]   # 新建子进程继承创建时刻的快照
```

结论：环境块在 `CreateProcess` 时**拷贝**给子进程；已运行进程（Steam）不会因为别处 `setx`/`$env:` 而改变。
Steam 启动 Civ6 时 `lpEnvironment=NULL`，游戏拿到的是 **steam.exe 自己被创建时的那份环境**。
所以「在另一个 PowerShell 窗口 `$env:CIVTRACE_TAG='host'` 再从 Steam 启动」必然无效——提交方结论正确。

### 1.3 一条应当补进结论的正面证据（对提交方叙述的修正，不是反对）

86 份日志里有 **6 份带 `_rev002` 后缀**（如 `civtrace_20261111_010155_pid35720_rev002.log`）。
这证明 **tag 机制本身工作正常**（小写、非 host/client 的 tag 都能落到文件名），
失败的环节**只是环境变量没进目标进程**。这个区分很重要：

- 它排除了「DLL 读 tag 有 bug」这一可能；
- 它把问题精确定位到「Steam 启动路径的环境继承」，与本轮更正一致。

另有 **3 份**日志的 `exe=` 行指向 Steam 库中的游戏本体，全部是
`E:\SteamLibrary\steamapps\common\Sid Meier's Civilization VI\Base\Binaries\Win64Steam\CivilizationVI_DX12.exe`，
这 3 份**无一**带 `_host`/`_client` 后缀——与「Steam 路径从未生效」一致（v0.4.1 时代的日志头部不打印 `exe=`，故 3 份是可识别下限，不是 Civ6 会话总数）。

### 1.4 顺带核实到的机制细节（文档未写，建议补）

- 过滤是**静默**的：若 tag 写成 `主机` 或 `host team`，非法字符被丢弃，`tag` 可能变成空串，
  文件名就**没有后缀**；执行者会误判为「方法无效」。文档应写明允许字符集。
- `setx CIVTRACE_TAG ""` 写入空值后 `GetEnvironmentVariableW` 返回 0，等价于「无 tag」——可用于收尾清理。

---

## 2. 文档质量项逐项判定

### A. 正确性

| 项 | 判定 | 证据 / 说明 |
|---|---|---|
| A1 机制描述（进程内读、注入器不传、Steam 继承） | **PASS** | `E2B-EXECUTION-PACK.md:81-86`；与 §1 复核一致 |
| A2 做法 A（`setx` + 彻底退出并重启 Steam） | **PASS**（有边界条件） | `:88-101`。`setx` 只写 `HKCU\Environment` 并广播 `WM_SETTINGCHANGE`，对已运行进程无效（§1.2 实测）；重启后的 Steam 由 explorer 拉起并读到新值，游戏再继承之。文档已明确要求「从开始菜单/桌面启动 Steam」（`:100`），这正是该做法的必要条件，写法正确 |
| A3 做法 B（窗口内直接起 exe）命令 | **FAIL（阻断）** | `:107` 写的是 `...\Sid Meier's Civilization VI\CivilizationVI_DX12.exe`；本机实测游戏根目录**没有**该 exe（根目录只有 `2KLauncher/ Base/ CTP/ Debug/ DLC/ LaunchPad/` 六个目录），真实路径是 `...\Base\Binaries\Win64Steam\CivilizationVI_DX12.exe`（21,420,896 B）。照抄必然 `not recognized` |
| A4 做法 B 工作目录 | **FAIL（中）** | 同上命令用 `&` 调用，子进程 CWD 仍是 PowerShell 当前目录；Steam 启动时 CWD = exe 目录。未加 `-WorkingDirectory` / 未 `Set-Location`，与 Steam 路径不等价 |
| A5 做法 B 的 DRM 断言（「Steam 后台运行即可，DRM 走后台 Steam」） | **未在本机验证（中）** | `:110-111`。本机可核实的只有：`Base\Binaries\Win64Steam\steam_api64.dll` 存在；整棵游戏目录**没有** `steam_appid.txt`；Steam 进程当前在运行（1 个）；直接启动的进程不会被 Steam 注入 `SteamAppId` 环境变量（当前会话为空）。这意味着直接起 exe 时 SteamAPI 能否拿到 AppID **存在失败风险**，我无法在不启动游戏的前提下证明它可用，**不为其背书**。建议文档加一句「未在本机验证；若直接启动后游戏秒退，回做法 A」 |
| A6 「Steam 默认启动 DX12 版」 | **PASS**（附条件） | 3 份 Steam 会话日志的 `exe=` 全部是 `CivilizationVI_DX12.exe`，与本机事实一致；但 Civ6 有启动器记忆选项，属「本机默认」而非普遍规律，`:123-124` 已给出 `Get-Process CivilizationVI*` 兜底，可接受 |

### B. 完整性（三处口径）

| 项 | 判定 | 证据 |
|---|---|---|
| B1 §2 门禁条目 | **PASS** | `:41`：「已分别设为 host/client，且该变量**已进入游戏进程自己的环境**（见 §3 步骤 2 的两种正确做法；仅在某个 PowerShell 窗口 `$env:` 里设不算）」 |
| B2 §3 步骤 2 正文 | **PASS** | `:81-119`：机制说明 + 做法 A/B + 自证，与 B1 同口径 |
| B3 §7 失败模式表 | **PASS** | `:287`：「tag 没进游戏进程的环境（Steam 启动继承 Steam 环境，另一窗口 `$env:` 无效）」→ 指向 A/B 并「退出游戏重来」 |
| B4 是否残留旧说法 | **PASS** | 全文 `$env:` 仅 4 处：`:3`（自陈 v1.0 错法）、`:41`（明确「不算」）、`:106`（做法 B 的正确用法）、`:117`（误打进 A 机窗口的说明）。没有「`$env:` 设了再从 Steam 启动」的残留 |
| B5 「自证 = 日志名带 `_host`/`_client`」是否可执行 | **PASS**（建议加强，低） | `:113-115` 给出期望文件名并规定「没有后缀就停下重来」，`:138` 给出日志目录；可执行。建议补一条可直接粘贴的命令（见 §4 建议 S6） |

### C. PC-B 操作单一致性

| 项 | 判定 | 证据 |
|---|---|---|
| C1 步骤 6 新增 tag 说明与 pack 同口径 | **PASS** | `PC-B-操作单.md:191-202`：进程内读、注入器不传、Steam 继承、86/0 证据、A/B 二选一、自证格式，逐项与 pack `:81-115` 对应 |
| C2 与 §0 硬规则冲突？ | **PASS** | `:12-18` 三条硬规则（不自行让联机成功 / 不改脚本编码 / 每步报哈希）均不涉及 tag；做法 A 要求「彻底退出 Steam」不是「强杀游戏进程」，与 `:274` 禁止项 4 不冲突 |
| C3 与 §6 禁止事项冲突？ | **PASS** | `:269-277` 七条禁止中，第 6 条禁止「在项目目录里跑 `civinject.exe`」，做法 B 在游戏目录起**游戏**，不冲突 |
| C4 与 §5 步骤 5（E2-A）的残留 | **PASS**（低） | `:171` 仍写「注入 civtrace（tag=host）」而没给环境变量设法。E2-A 已结案、且该步 PC-B 不注入，影响有限，但属同一类旧写法残留，建议加一句「tag 设法同步骤 6」 |
| C5 文书时效与权威指针 | **FAIL（中）** | `PC-B-操作单.md:3` 自declared「**已过期：不得按本文件直接执行**」并把新步骤指向「当前交接文档」；而 `PC-B-交接文档.md:3` 也自称「已过期」并指向 `PROJECT-SCOPE-WIN-STEAM-2P.md`。`E2B-EXECUTION-PACK.md:302` 仍把操作单列为「本包 §3 与之对应」且**未标注其已过期**。三份文书互相指认，执行端无法判断以谁为准 |
| C6 同一交付包内的相反口径 | **FAIL（中）** | `PC-B-交接文档.md:111`「只设环境变量 `CIVTRACE_TAG=client`」、`:122`「先用 `set CIVTRACE_TAG=client`」——正是本轮被证伪的写法，而该文件**在 zip 内**（8,741 B）。PC-B 会同时收到「正确」与「错误」两套指令 |

### D. MANIFEST / 包一致性

| 项 | 判定 | 证据（实测） |
|---|---|---|
| D1 pack 元数据（14,670 B / sha256） | **PASS** | Size=14670；SHA256=`2A918E55F518949EF65EA3C9AE2E5F8F13E7396FA43E3BB5DFB43BA8D802AEE5`；BOM=False；UTF-8 严格解码通过 |
| D2 pack 行尾 `LF=314` | **FAIL（低）** | 实测换行符 **313** 个（`LF_only=313, CRLF=0, CR=0`，文件以单个 `0A` 结尾）；`(Get-Content).Count = 313`。声称多 1 |
| D3 版本行 v1.1 | **PASS**（附注） | `:3` 版本：v1.1；但其中写的「2026-11-16 21:50」晚于文件 mtime `2026-11-16 21:37:38`（信息级不一致） |
| D4 操作单元数据（12,952 B / sha256） | **PASS** | Size=12952；SHA256=`36D7F4B7F613E9401966AE8731940D7D45C3EEEF6EC91F68B6BB12139F2F4026`；无 BOM |
| D5 MANIFEST 22 条哈希 | **PASS** | 逐条 `Get-FileHash` 比对：OK=22，MISMATCH=0，MISSING=0；`PC-B-操作单.md` 一行确为新哈希 `36D7F4B7…` |
| D6 MANIFEST 是否含 size 列 | **FAIL（信息）** | 格式为 `HASH␠␠文件名`，**没有 size 字段**。因此「其余 21 条哈希+size 全命中」中的 size 半句无法由该文件成立；size 只能另证（我另证了包内 24 文件与源目录全等） |
| D7 MANIFEST 覆盖率 | **FAIL（低）** | 包内 24 个文件，清单 22 条：未登记 `civinject.exe.bak-4DCC9557`（171,520 B，sha256 `4DCC9557…EC72`，与 `civinject.exe` 不同文件）与 `MANIFEST-sha256.txt` 自身 |
| D8 MANIFEST 生成日期 | **FAIL（低）** | `:2` `generated: 2026-11-13`，实际内容于 2026-11-16 21:38 改写，未更新 |
| D9 zip 身份 | **PASS** | 355,493 B；SHA256=`3B66E22829F38E99334B2B548A26391D4E2FA253A0323DEF945119B8F0F10034`；可正常打开，24 个条目，无目录条目、无越界路径 |
| D10 zip 内容 vs 源目录 | **PASS** | 解压到 `%TEMP%` 后逐文件 sha256：24/24 全等，diffs=0（CRC 亦通过，`ExtractToDirectory` 未抛错） |
| D11 桌面解压副本 | **PASS** | `C:\Users\dd\Desktop\pcb-kit\` 24 文件，与 zip 解压结果 24/24 全等 |
| D12 操作单 §2 哈希校验片段 | **FAIL（高）** | `PC-B-操作单.md:82-87` 假设三字段 `$p[0]=文件名、$p[2]=哈希`，而清单是**两字段** `哈希 文件名`。实测：真实 22 条全部报 `Cannot find path <64位哈希>` 而**不计数**；清点文本头 3 行反被计为 MISMATCH，输出 `mismatches = 3`；我在 `%TEMP%` 副本里篡改 `netpath.ps1` 后仍输出 `mismatches = 3`（对真实文件**fail-open**）。这条是工具箱唯一的完整性关卡，等于既误报又漏报 |
| D13 操作单 §2 文件数 | **FAIL（中）** | `:54`「工具包（16 个文件）」，实际包内 **24** 文件、清单 **22** 条；`PC-B-交接文档.md:30` 同样写 16 |

### E. 无越界

| 项 | 判定 | 证据 |
|---|---|---|
| E1 是否出现「E2-B 已完成/已验证」 | **PASS** | `:310` 状态仍为「就绪，等 PC-B 在线」；`:311-313` 记录 PC-B 离线阻塞事实 |
| E2 是否出现「Gate A 已批准」 | **PASS** | `:44`「Gate A 仍未批准、M0-B 仍冻结」；操作单 `:7`、`:283-284` 同；`:272` 明确禁止写「M0-B 已验证」 |
| E3 更正是否引入新的越界表述 | **PASS** | 新增内容限于机制解释与操作法；`:85-86` 的「从未生效」有 86/0 实测支撑，属事实陈述而非实验结论 |

---

## 3. 缺陷清单

| ID | 级别 | 位置 | 问题 | 证据 | 必改 |
|---|---|---|---|---|---|
| D1 | **阻断** | `E2B-EXECUTION-PACK.md:107` | 做法 B 的 exe 路径缺 `Base\Binaries\Win64Steam`，照抄必失败 | 根目录无该 exe；真实文件 21,420,896 B 在 `...\Win64Steam\` 下 | 是 |
| D2 | **高** | `PC-B-操作单.md:82-87` | §2 校验片段字段错位：真实文件漏报（篡改后仍 0 增计），清单头文本误报 3 条 | 实测 `mismatches = 3`；篡改 `netpath.ps1` 后仍 3 | 是 |
| D3 | 中 | `E2B-EXECUTION-PACK.md:110-111` | 「Steam 后台运行即可满足 DRM」未验证即断言 | 无 `steam_appid.txt`；直接启动进程无 `SteamAppId`；未启动游戏故无法证实 | 否（须标注「未在本机验证」+ 回退指引） |
| D4 | 中 | `E2B-EXECUTION-PACK.md:107` | 做法 B 未设工作目录，与 Steam 启动的 CWD 语义不一致 | `&` 调用保留 shell CWD | 否（随 D1 一并修） |
| D5 | 中 | `PC-B-操作单.md:54`；`PC-B-交接文档.md:30` | 「16 个文件」与实际 24 文件 / 22 条清单不符 | 目录实测 24；清单实测 22 | 否 |
| D6 | 中 | `PC-B-操作单.md:3`；`PC-B-交接文档.md:3`；`E2B-EXECUTION-PACK.md:302` | 三份文书互指且都自称过期，pack 未标注操作单已过期，执行端无权威来源 | 见 C5 | 是 |
| D7 | 中 | `PC-B-交接文档.md:111,122` | 交付包内仍教 `set CIVTRACE_TAG=client` 后注入（已证伪） | 该文件在 zip 内（8,741 B） | 是 |
| D8 | 低 | `PC-B-操作单.md:171` | E2-A 步骤仍写「tag=host」而未给设法 | 同类旧写法残留 | 否 |
| D9 | 低 | `E2B-EXECUTION-PACK.md:41` | 门禁要求「已设 tag」，而做法 B 是启动的瞬间才设，时序上对 B 不成立 | 措辞层面 | 否 |
| D10 | 低 | `E2B-EXECUTION-PACK.md` 头部 | 声称 `LF=314`，实测 313；版本行时间 21:50 晚于 mtime 21:37:38 | 见 D2/D3 | 否 |
| D11 | 低 | pack `:81-115`；操作单 `:193-202` | 未写 tag 允许字符集（`[A-Za-z0-9_-]`，≤24）与「非法字符被静默丢弃」的坑 | `trace_dll.cpp:289-292` | 否 |
| D12 | 低 | `MANIFEST-sha256.txt` | 24 文件中 2 个未登记；`generated` 日期未更新 | 见 D7/D8 | 否 |
| D13 | 信息 | `E2B-EXECUTION-PACK.md:88-101` | 做法 A 用 `setx` 持久化，未给收尾清理指引；后续单机实验会带着 `_host` 污染 | 环境变量持久生效 | 否 |
| D14 | 信息 | 日志目录 | 目录内存在单份 **2,984,933,272 B** 的日志（`civtrace_20261115_124917_pid12420.log`），§4.1 要求回传 SHA256 与体积，若 E2-B 再现同类量级会不可操作 | 实测文件大小 | 否 |

**缺陷计数**：阻断 1、高 1、中 5、低 5、信息 2；必改 4（D1、D2、D6、D7）。

---

## 4. 修法（可直接采用）

### M1（对应 D1/D4）做法 B 的整段替换

> **做法 B（免重启 Steam，适合只想跑一次）** —— 直接从 PowerShell 启动游戏 exe：
>
> ```powershell
> $env:CIVTRACE_TAG = 'host'   # PC-B 用 'client'
> $exe = "E:\SteamLibrary\steamapps\common\Sid Meier's Civilization VI\Base\Binaries\Win64Steam\CivilizationVI_DX12.exe"
> Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe)
> ```
>
> 游戏作为该窗口的子进程启动，**直接继承** `$env:` 值（本机实测继承语义成立）。
> Steam 客户端保持后台运行作为 DRM 宿主；**该 DRM 行为未在本机验证**，若直接启动后游戏秒退，
> 改用做法 A。`Win64Steam\` 下的 `CivilizationVI.exe` 是 DX11 版，与 DX12 版择一即可，但 `-x` 的进程名必须与之一致。

### M2（对应 D2）操作单 §2 校验片段替换

```powershell
$bad = 0
Get-Content MANIFEST-sha256.txt | ForEach-Object {
  if ($_ -match '^([0-9A-Fa-f]{64})\s+(\S.*)$') {
    $h = $Matches[1].ToUpper(); $n = $Matches[2].Trim()
    if (-not (Test-Path -LiteralPath $n)) { $bad++; "MISSING: $n"; return }
    $a = (Get-FileHash -LiteralPath $n -Algorithm SHA256).Hash
    if ($a -ne $h) { $bad++; "MISMATCH: $n" }
  }
}
"mismatches = $bad"
```

（该逻辑我已用同一清单实跑：22/22 命中，输出 `mismatches = 0`。同时建议删掉 §2 里「取前 3 行」的演示。）

### M3（对应 D6）权威指针

在 pack §8 表格中给操作单加一列或脚注：**「该文件头部自述已过期（G2/Radmin 归因早于 2026-11-12 范围决议），E2-B 只以本包 §3 为准」**，并把《PC-B 交接文档》一并列入，注明「历史记录，不得据其执行」。

### M4（对应 D7）交接文档 tag 语句

`:122` 改为「先用做法 A/B 让 tag 进入游戏进程（见操作单步骤 6 注）」，`:111` 改为「E2-A 不注入、无需设 tag」。或直接从交付包中移除该历史文件并在 MANIFEST 说明。

### 建议（非必改）

- **S1**（D3）在做法 B 后加粗一句「DRM 未在本机验证」。
- **S2**（D5）把两处「16 个文件」改为「24 个文件」，或说明「本单只涉及其中 16 个」。
- **S3**（D9）§2 门禁改为「tag 设法已确定（A：已 `setx`；B：启动命令里已带 `$env:`）」。
- **S4**（D11）在机制说明后加一句：tag 只接受 `A-Z a-z 0-9 - _`，最多 24 字符，非法字符会被**静默丢弃**（写中文 tag 会退化成无后缀）。
- **S5**（D13）在步骤 8 收尾加：实验结束后 `setx CIVTRACE_TAG ""`（或 `reg delete HKCU\Environment /v CIVTRACE_TAG /f`），避免后续单机实验带错 tag。
- **S6**（B5）自证给一条可直接粘贴的命令：
  ```powershell
  Get-ChildItem "$env:LOCALAPPDATA\CivLink\M0A\logs\*.log" |
    Where-Object Name -match '_(host|client)\.log$' |
    Sort-Object LastWriteTime | Select-Object -Last 1 Name,Length,LastWriteTime
  ```
- **S7**（D12）把 `civinject.exe.bak-4DCC9557` 移出交付包，或补进 MANIFEST；`generated` 日期改为 2026-11-16。
- **S8**（D10）把「LF=314」改为 313。

---

## 5. 未在本机验证 / 未做项（明确声明，不代为背书）

1. **Steam DRM 在做法 B 下是否放行**：未启动游戏，无法验证。仅记录可核实的风险信号（无 `steam_appid.txt`、直接启动进程无 `SteamAppId`）。**不为「Steam 后台运行即可」背书。**
2. **做法 A 的端到端效果**（`setx` → 重启 Steam → 起游戏 → 日志带后缀）：需要重启 Steam 并启动游戏，属破坏性操作，只读审计不做。语义层已由 §1.2 实测 + §1.1 源码证据支撑。
3. **`analyze-h6-window.ps1` 回归 20/20**（`E2B-EXECUTION-PACK.md:19`）：本轮未复跑（与 tag 更正无关），不作判定。
4. 未运行 `civinject.exe`、未注入、未启动 Civ6、未改任何被审计文件；临时解压目录与实验目录已删除。

---

## 6. 附录：实测原始数据

### 6.1 四个被审计对象的身份

| 对象 | 实测字节 | 实测 SHA256 | 声称值 |
|---|---|---|---|
| `docs/E2B-EXECUTION-PACK.md` | 14,670 | `2A918E55…D802AEE5` | 一致 |
| `M0A/pcb-kit/PC-B-操作单.md` | 12,952 | `36D7F4B7…9F2F4026` | 一致 |
| `M0A/pcb-kit/MANIFEST-sha256.txt` | 2,198 | `618B8293…3E1EAA20` | 未声称 |
| `Desktop/pcb-kit.zip` | 355,493 | `3B66E228…F0F10034` | 一致 |

### 6.2 包内容

- 源目录 `M0A/pcb-kit\`：24 文件
- zip 条目：24（无目录条目）
- zip 解压 vs 源目录：24/24 全等
- `Desktop/pcb-kit\` vs zip 解压：24/24 全等
- MANIFEST：22 条 → 22 命中、0 不匹配、0 缺失

### 6.3 日志总体

- `%LOCALAPPDATA%\CivLink\M0A\logs\*.log`：86
- 带 `_host` / `_client` / `_c3`：0
- 带 `_rev002`（证明机制可用）：6
- 可识别为 Steam 启动 Civ6（`exe=` 指向 `Win64Steam\CivilizationVI_DX12.exe`）：3，其中带后缀 0
- 写入时间跨度：2026-11-10 21:42:43 – 2026-11-15 20:01:40

### 6.4 关键源码行（原文）

```
trace_dll.cpp:287  wchar_t t[40]; DWORD n = GetEnvironmentVariableW(L"CIVTRACE_TAG", t, 40);
trace_dll.cpp:288  if (n > 0 && n < 32)
trace_dll.cpp:289-292  for (DWORD i = 0, j = 0; i < n && j < 24; ++i) ... [A-Za-z0-9_-]
trace_dll.cpp:295-297  _snwprintf(fname, 96, L"civtrace_%04u%02u%02u_%02u%02u%02u_pid%lu%s%s.log", ...)
injector.cpp:269-272   argv: -x <proc> | -p <pid> | -u | <dll>（无 tag 选项）
injector.cpp:462-474   VirtualAllocEx → WriteProcessMemory → CreateRemoteThread(LoadLibraryW)
```
