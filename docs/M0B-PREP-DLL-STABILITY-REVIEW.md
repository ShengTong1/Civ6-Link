# M0-B 准备材料审计报告：DLL 注入稳定性观察 + GUI 编译

- 审计对象：M0-B **准备材料**（工具级证据），非 M0-B 验收
- 审计日期：2026-11-15
- 审计方式：只读；独立重算字节数/SHA-256；逐行比对文档与 CSV；核查注入日志、GUI 源码与 PE 产物
- 裁定：**有条件通过**（无阻断/高危缺陷；3 项低危必改 + 2 项信息建议）

---

## A 身份核查 —— PASS（逐项命中）

| 对象 | 声称 | 独立实测 | 判定 |
|------|------|----------|------|
| `CivLink-M0A-audit\docs\M0B-PREP-DLL-STABILITY-20261115.md` | 4,225B / 4BE4A62A4E531D9847CD9D7C31F66FD7EDFBB5FB524C9FB7B28277652E90CD79 | 4,225B / 4BE4A62A…（完全一致） | PASS |
| `M0A\captures\M0B-prep-stability-20261115\inject-hook.txt` | 1,547B / AD8B7A912152763668F30B17B99E216366C9EF70188959DA0F81261CE73E75ED | 1,547B / AD8B7A91… | PASS |
| `…\inject.txt` | 922B / 3EA96332F6BA7FD062A143EB11BB84CDCA14F0904B8221813019B8C98E1FE0CE | 922B / 3EA96332… | PASS |
| `…\samples.csv` | 520B / BDDB8A1813DF44E588A6654D18B1B3D4AED543A955E0A9944BB86ED08B187F30 | 520B / BDDB8A18… | PASS |
| `civlink-gui\civlink_ctl_gui.exe` | 8,704B / A0EB830BF26D4AFBAEF2AD719748660409ECAE4647BD1527B1649E838FD3B894 | 8,704B / A0EB830B… | PASS |
| `civlink-gui\civlink_ctl.exe` | 23923DFB… | 173,056B / 23923DFBAAB310F2BDAA1E1117110B92A74290E2C87396E5CB65EE0E4FEFEA30 | PASS |
| `civlink-gui\civlink_hook.dll` | 9424FC25… | 119,808B / 9424FC25FB45841FC6A31A0C9CD747067005D3FA32A06A18CD150B0C9CEBC10F | PASS |
| 文档字符卫生 | 无 BOM、无 tab/vt/ff | NO-BOM；tab=0、vt=0、ff=0（LF 行尾） | PASS |
| samples.csv 表头/数据 | 表头 + 5 行逐字 | 表头 19 列与 5 行数据逐字核对通过（见 B 节逐行比对） | PASS |

补充：文档 §7 身份表所列 civlink_hook.dll 119,808/9424FC25… 与 civlink_ctl.exe 173,056/23923DFB… 均与实测一致；§2 声称"civlink\ 与 dist\civlink-beta-20261114\ 两处一致"已复验（两处 hook.dll 均为 9424FC25…、ctl.exe 均为 23923DFB…，`CivLink-M0A-audit\civlink\` 与 `dist\civlink-beta-20261114\` 及 `civlink-gui\` 三处二进制一致）。
注：三个证据文件（inject-hook.txt/inject.txt/samples.csv）带 UTF-8 BOM——属工具输出正常形态；任务仅要求**文档**无 BOM，已满足，证据 BOM 不计缺陷。

## B 数据一致性 —— PASS（5 行全等；2 处表述略超证据粒度，见缺陷 D-1/D-2）

**§4 表格 ↔ samples.csv 逐列逐行比对（全部一致）：**

| 采样点 | 文档 §4 | CSV 实测 | 判定 |
|--------|---------|----------|------|
| 12:50:09 | sent=100, sendfail=0, oversize=0, ignored=0, raw sendto=100, raw bind=0, raw recvfrom=0, recv on 62056=0, bind 62056=0, cvlh2 try=100, cvlh2 ok=100, stateq=3, 内存=1659.8 | 100,0,0,0,0,0,100,0,0,0,0,0,0,0,100,100,3,1659.8 | 全等 |
| 12:51:09 | sent=100, …, 内存=4270.8 | 100,0,0,0,0,0,100,0,0,0,0,0,0,0,100,100,3,4270.8 | 全等 |
| 12:52:09 | sent=500, raw bind=4, raw recvfrom=3,884,931, recv on 62056=3,884,931, bind 62056=2, cvlh2 try/ok=500/500, 内存=3708.2 | 500,0,0,0,0,0,500,0,4,0,3884931,2,3884931,0,500,500,3,3708.2 | 全等 |
| 12:53:09 | raw bind=5, 内存=3707.9 | 500,0,0,0,0,0,500,0,5,0,3884931,2,3884931,0,500,500,3,3707.9 | 全等 |
| 12:54:09 | raw bind=5, 内存=3707.5 | 500,0,0,0,0,0,500,0,5,0,3884931,2,3884931,0,500,500,3,3707.5 | 全等 |

（文档以千分位显示 3,884,931 = CSV 3884931；sent 100→500、raw bind 4→5、内存 1659.8→4270.8→3708.2→3707.9→3707.5、state queries 恒 3 全部命中。）

**§5 结论与数据对应：**
1. sent==raw sendto==cvlh2 try==cvlh2 ok（100→500）——数据直接支撑 ✓
2. 零失败计数——sendfail/rejectoversize/sentnotify/ignored 四项在 5 个采样点全 0，sock overflow/cvlh2 fail/cvlh2 errno/channel down 四项**未纳入 samples.csv 采样列**，仅 inject-hook.txt 注入时点快照为 0（缺陷 D-1）
3. 真实流量覆盖——raw recvfrom=3,884,931 全部落在 62056（recon62056==rawrecvfrom==3,884,931）、bind 62056=2 ✓；"与 F2 S5 ≈1.6M/s 一致"为推断（缺陷 D-2）
4. 内存平稳——12:52 后 3 点 3.7075–3.7082GB 平稳 ✓；"12:50→12:51 增长为加载地图所致"为解释性归因（信息 I-1）
5. state queries 恒定 3 ✓

**§6 边界如实性：** 明确"不证明 62056 数据面转发正确性（只观察了忙轮询收包，未观察转发）"；并说明"本次 agent 未运行，Hook 计数反映的是截获+封装成功，不涉及转发投递"。inject-hook.txt/samples.csv 内容核对：只有 hook 侧分层计数（sent/raw*/cvlh2*/bind/recv），**无任何 agent 侧交付/投递字段**，与"agent 未运行、只证截获+封装"的边界声明一致 ✓。

## C 注入证据 —— PASS

- `inject-hook.txt`（12:49:50）逐行命中声明：`LoadLibraryW returned 0xeac60000`（成功基址，与 dll base 0x7ff9eac60000 低位一致）、`[+] hooks active (CivLinkHookState=1)`、`INJECT_EXIT=0`，并附 `hook state : 1 (running)` 及全零 counters 快照 ✓
- `inject.txt`（12:49:17）存在 ✓：首次误用 `civtrace.dll`（`LoadLibraryW returned 0xea6f0000` 但 `cannot resolve CivLinkHookState in …\civtrace\civtrace.dll`、`INJECT_EXIT=1`），随后两次 `civlink_hook.dll is not loaded (q=0)` —— 失败证据完整，且先失败后成功的时间线（12:49:17 → 12:49:50）与文档 §2 注入方式吻合 ✓
- 两文件 45 行/15 行内容与文档 §3 描述（LoadLibraryW 返回 0xeac60000、CivLinkHookState=1、exit 0）一致 ✓

## D GUI —— PASS（4 子命令封装正确；2 项低/信息级实现注记）

- **源码位置**：`CivLink-M0A-audit\civlink\ctl\civlink_ctl_gui.cs`（6,426B，NO-BOM）存在；同目录含 `civlink_ctl.cpp`（22,173B，ctl 本体）✓
- **四子命令封装**（源码逐行核对）：
  - 注入 → `civlink_ctl.exe inject -x <exe> [-p pid] -d <dll>`（`RunCtl("inject","-d",dllBox.Text)`，`-x` 用 TargetArgs 带引号）✓
  - 状态/计数/停止 → `status`/`counters`/`shutdown -x <exe> [-p pid]` ✓
  - 与 `civlink_ctl.cpp` 用法注释（`:13-16` 及 `main` 帮助文本 `inject -x <process.exe> [-p <pid>] [-d <dll>] [-w <sec>]`）参数一致 ✓；`-x`/`-p`/`-d` 解析（`:233-235`）匹配 ✓
- **csc 编译一致性**（PE 头 + 程序集引用核验）：
  - 源码头注释编译命令 `csc.exe /target:winexe /r:System.Windows.Forms.dll /r:System.Drawing.dll civlink_ctl_gui.cs`
  - 实测产物：PE32+（0x20B）托管程序集，含 BSJB 元数据，AssemblyName=`civlink_ctl_gui` v0.0.0.0，引用 `System.Windows.Forms 4.0.0.0` / `System.Drawing 4.0.0.0` / mscorlib / System —— 与 winexe+两引用一致 ✓
  - 产物字符串含 `inject/status/counters/shutdown/-x/-p/-d`、`civlink_ctl.exe`、`civlink_hook.dll`、"CivLink 控制端 GUI" —— 与源码字面量对应 ✓
- **部署位置**：`C:\Users\dd\Desktop\civlink-gui\` 中 `civlink_ctl_gui.exe` 与 `civlink_ctl.exe`（23923DFB…）、`civlink_hook.dll`（9424FC25…）**同目录**，哈希与声称一致 ✓；README v1.22 修订记录登记（`civlink_ctl_gui.exe` A0EB830B…/8,704B、部署 `civlink-gui\`）与实测一致 ✓
- 注记：源码注释称"非管理员启动时自提权"，但 `Main()` 无提权/自举代码（缺陷 D-3）；`Quote()` 对含引号路径转义方式为 `\"`（Windows 命令行常规，路径含空格时 `-d` 未加引号——默认路径 `civlink-gui\` 无空格，当前部署可用；信息 I-2）

## E 边界声明 —— PASS

- 文档开头"性质声明（必读）"：明示"本文档是 **M0-B 的准备材料（tool-level evidence）**，不是 M0-B 验收，不勾除 Gate A/B，不代表'双人真实联机已验证'。正式 M0-B 仍冻结；Gate A 未批准" ✓
- §6 不证明清单完整：双人真实联机、E2-A/E2-B/E3、对局稳定性、长时间（小时级）、多会话、跨进程、**62056 数据面转发正确性**、Relay RTT、Fake-IP、Noise、跨网 —— 11 项齐全，且写明"agent 未运行"缘由 ✓
- 全文检索无"验收通过/稳定性已验证"式越界结论；§5 标题为"观察结论"，措辞均为数据限定 ✓

---

## 缺陷分级

| 级别 | 编号 | 位置 | 描述 |
|------|------|------|------|
| 阻断 | — | — | 无 |
| 高 | — | — | 无 |
| 低 | D-1 | 文档 §5.2 | "sock overflow / cvlh2 fail / cvlh2 errno / channel down 全程为 0"：这 4 项**未在 samples.csv 采样**，仅注入时点快照为 0，"全程为 0"表述略超出采样证据粒度 |
| 低 | D-2 | 文档 §5.3 | "与 F2 S5 观察（≈1.6M/s）一致"为推断：60s 采样粒度下仅能支撑 3.88M 次 recvfrom 全部落在 62056（12:51→12:52 窗口平均 ≥64,749 次/s），**峰值速率未复测**；应表述为"忙轮询形态与 S5 一致，峰值速率未在本窗口粒度复测" |
| 低 | D-3 | GUI 源码头注释 | "非管理员启动时自提权"与实际实现不符：`Main()` 无提权代码；应删除该句或实现 runas 自举 |
| 信息 | I-1 | 文档 §5.4 | "12:50→12:51 的内存增长为游戏加载地图，非 DLL 所致"为解释性归因，证据目录无加载地图的直接记录；建议标注"推断" |
| 信息 | I-2 | GUI 源码 `RunCtl` | `-d` 参数未加引号、`Quote()` 对 `"` 使用 `\"` 转义；当前部署路径无空格可工作，建议对 `-d` 也引用以防含空格路径 |

## 必改项清单（复检前应落地）

1. **D-1**：§5.2 限定表述——"send fail/reject oversize/sent notify/ignored 在 5 个采样点全 0；sock overflow/cvlh2 fail/cvlh2 errno/channel down 仅注入时点快照为 0（未纳入采样列）"。
2. **D-2**：§5.3 改为"3.88M 次 recvfrom 全部落在 62056，忙轮询形态与 F2 S5 一致；60s 采样粒度下峰值速率未复测，不与 S5 ≈1.6M/s 直接对等"。
3. **D-3**：删除 GUI 源码"非管理员启动时自提权"注释，或补实现提权自举；README v1.22 登记"提权运行"措辞与之一并校准。

## 最终裁定

**有条件通过。**

- 身份（A）：全部字节数/SHA-256 独立重算命中声称值，文档无 BOM/无 tab/vt/ff，CSV 表头与 5 行逐字 —— 通过。
- 数据（B）：§4 表格 5 行与 samples.csv 逐列逐行**全等**，§5 结论与数据对应（除 D-1/D-2 两处表述粒度问题），§6 边界与证据内容（仅截获+封装、agent 未运行）如实 —— 通过（含 2 项低危修正）。
- 注入证据（C）：LoadLibraryW 成功、CivLinkHookState=1、exit 0 及首次 civtrace.dll 失败证据齐备 —— 通过。
- GUI（D）：四子命令封装与参数正确、csc 产物与命令一致、GUI exe 与 ctl/hook 同处且哈希命中 —— 通过（含 1 项低危注记）。
- 边界（E）：性质声明、11 项不证明清单、无越界结论 —— 通过。

材料真实、证据链完整、无伪造或篡改迹象；不存在阻断/高危缺陷。上述 3 项低危必改落地（或由负责人确认后）后，该准备材料可作为 M0-B 的前置工具级证据使用；其结论边界（不勾 Gate A/B、不证明双人真实联机/62056 转发正确性）必须维持。
