 CivLink M0-A 审计工具包 · 实验手册

> 版本：**1.47**（2026-11-23） · 首版范围决议见 `docs/PROJECT-SCOPE-WIN-STEAM-2P.md`。
> **当前有效状态（REV-014 / P2 复核 / Phase 0 / F1 / F2 / F3 / F4 / F5）**：首版范围仍为 Windows + Steam + 双人；S1 非发布原型可继续（只读诊断、离线 fixture 解析、mock UI），不修改网卡、不接管 Civ6 流量。P2 主实验的本机限定时序结果已复核；不等于真实 20–50 ms Relay RTT 验证。Phase 0 的 `--broadcast-path` 故障已确认与 EXE 所在路径相关，具体系统机制待取证；源码尚未修改。**F1 两个子项（观测、集成）已复核为「限定通过」，F2 非发布原型 S1–S5 已完成（Fake-IP 会话映射 crate、62056 数据面观测、真机"加入"观察）**，详见 §3B.3/§3B.3b/§3C 与 `docs/F1-INTEGRATION-REVIEW-20261114.md`、`docs/F2-DATAPATH-REVIEW-20261114.md`。**F3 五子项（A 直连/B Relay/C 退避/D 压力/E 故障注入）全部完成且审计闭环**，详见 §3D 与 `docs/F3?-*.md`；**F4 发布候选单机模拟房主验收已通过（F4-BETA PASS 9/9，证据 `M0A\captures\F4-beta-20261114-174214`）**——可发布为"模拟对端/发现助手测试版"，**NOT 双人真实联机**（详见 v1.20 修订记录与 `docs/F4-BETA-ACCEPTANCE-20261114.md`）。**F5 LAN 模拟房主（`--sim-lan-listen`）完成且审计闭环，双机核验包 `C:\Users\dd\Desktop\civlink-f5-kit\` 就绪**——模拟房主→真实客户端跨机发现链路（详见 v1.21 修订记录与 `docs/F5-LAN-SIMULATED-HOST-20261115.md`）；**NOT 双人真实联机、不勾 E2-A/E2-B/E3**。E2-A 部分完成，E2-B/E3 未完成；Gate A 未批准。**M0-B 双机验证已执行（2026-11-17，审计裁定：有条件通过）——发现链路段通过（B 见真实房名），加入/数据面段待验证（M-1，PC-B 恢复后）**，详见 v1.32 修订记录与 docs/M0B-DUALMACHINE-VERIFICATION-20261117.md、docs/M0B-DUALMACHINE-REVIEW.md。**M0-C 双角色（v0.4.6）：C1 A 机房主模式整合（`--reserve-62900`，根治 m25442 建房卡住）已完成审计闭环；C2 B 客户端定向网卡（`civlink_client.dll` + `--iface`，9 场景/47 runner/62 in-process 含变异实证）第三轮审计有条件通过（docs/M0C-C2-REVIEW-3.md，**C2-a 记账层通过、C2-b 机制层跨机验证完成（探针级）、真实游戏跨机对局待验证**）——按拆分口径登记，禁称完整验证、禁勾 E2-A/E2-B/E3。详见 v1.33/v1.34 修订记录。**P1 GUI（产品级 WinForms 托盘助手 civlink_tray.exe）实现完成、两轮审计通过（首轮 NOT PASS 的 N-A..N-G 七项全关、复审 docs/M0D-GUI-IMPL-REVIEW-2-20261118.md 13,666B/F9623EBD… PASS），headless 自检 33/33 + 真实窗口冒烟 PASS；白名单注入、Redactor 无条件脱敏、零遥测/零日志；机械证据≠双人验证，不勾 E2-A/E2-B/E3。详见 v1.35 修订记录。**
> **REV-012 补充**：PC-B metric 修改及改后 600 个 WLAN 源发现包目前是执行端报告，原始日志/备份/E0 待回传复核；按 REV-012 独立复核，E2-A/H4、E2-B、E3 已获限于 M0-A 的顺序执行授权，不含新的网卡修改授权。详见 `docs/reports/REV-012-REVIEW.md`。REV-013 对 H4 与单机合成响应实验的最新裁定见上方状态及 `docs/reports/REV-013-REVIEW.md`。
> **纠错声明**：旧 v1.7 摘要把相关性过度写成 InterfaceMetric 根因，并把“首包 WLAN”归因为 ARP 缓存；这些结论已被 `REV-005-E2A-REVIEW.md` 撤回。Radmin 客户端当前离线这一用户事实也必须纳入后续判断；网卡残留、地址或路由不等于 VPN 隧道在线。
> **新增双机现象（执行者口述，待原始证据归档/复核）**：房主 A 建房后，B 五次刷新中第一次 WLAN 路径能显示房间，随后四次呈现 Radmin 源且未显示房间。该观察支持“本次发现结果与报文呈现路径相关”，尚不能证明 InterfaceMetric 是原因，也不能证明报文经在线 Radmin 隧道传输。
> **交接入口**：`docs/CODEX-HANDOVER-M0A.md`。本 README 是 M0-A 工具手册；其历史实验步骤可能早于范围决议，执行新任务前先读交接文档与范围决议。
> v1.1 变更（第二轮技术审查落地）：E2 拆 A/B（修 H6 取证）、E4 改三台电脑三端抓包五轮对照、
> E0 构建基线独立目录化、Defender 措辞改"先观察实际拦截"、注入操作全表、Wireshark 采集/显示
> 过滤器分离、H3 判据改结构化字段、civtrace 扩至 31 API。
> **v1.2 变更（REV-002 v0.4.4 验收落实，强制）**：`-u` 语义改为「停用 Hook + 结束日志会话」，
> **不再卸载 DLL**（审计运行模式，B2 方案②）；同一进程再次注入会被重复注入检查跳过且
> **Hook 不会重新启用** → 重复实验/切换注入状态**必须完全退出并重启 CivilizationVI**。
> §2 操作全表与 §3 E1 对照流程已按此改写。详见 §2.1「停用与重启」。
> **v1.3 变更（E1 实机执行后补录，强制）**：①新增 §1.3b——**不得在项目目录内运行 `civinject.exe`**，
> 该项目目录存在进程可见性限制（实机只枚举到 29 个进程，中立目录 361+；该结论为执行者归因，
> 根因未经独立取证证实）；②新增 §1.4 降级抓包方案
> `scripts\lanprobe.ps1`（无 Wireshark/无管理员时可用，但明确其能力边界）；③§2.1「停用时机」由
> "建议"升为**硬性要求**——实机首次 `-u` 因 hook 未在 5 s 内排空返回 2，静止后重试才成功；
> ④注入命令修正——civinject **无 `-i` 参数**（`-x <exe>` 即注入，`-u` 为停用），全篇移除误用的 `-i`；
> ⑤操作表更正——**不存在"仅查询"模式**，`-x <exe>` 无动作参数即注入（预检查也会改变目标状态）。
> 依据：`docs\reports\M0-A-协议行为报告-E1-20261111.md` 与 `docs\reports\REV-002-E1-REVIEW.md`。
> **v1.4 变更（pcapng 补抓落地，强制）**：①§1.4 改为一键 `pcapng-capture.ps1` + `抓包-以管理员身份运行.cmd`
> （agent 侧无提权路径，**必须用户手动点 UAC**；含 PS 5.1 编码坑与 `pktmon` 多捕获点重复采样伪影说明）；
> ②**pcapng 归并方法（v1.4 修订）**——同一帧被 pktmon 在多个 NDIS 捕获点记录 4 份副本，不归并会把 300 包读成 1204 包；
>   **归并键 = `(源 IP, IPv4 Identification, UDP 源端口, UDP 目的端口, 载荷)`**，并须同时满足"同身份副本整帧一致 + 时间戳相差微秒级"；
>   **IPv4 ID 一律按网络字节序（大端）读取**（v1 曾用小端误读得出"同轮递增 256"，该结论已作废）；
> ③E1「完整抓 UDP」Gate A 缺口**已关闭**（`E1-pcapng-20261111_201146.pcapng`，2 991 164 B，
>   sha256 `41D96595…43C0584`，3 轮 × 100 端口全谱、突发 0.690/0.726/0.811 ms）；
>   **接口归属限定表述**：300 个数据报身份中 299 个为 Radmin 源、1 个（轮1 端口 62900）为 Hyper-V 源，
>   WLAN 源未出现——**不得**据此断言"统一经 Radmin 出口"，**不得**据此推定 M0-B Relay 绑定硬约束
>   （均经 `docs\reports\REV-002-E1-PCAPNG-REVIEW.md` 复核纠正）；
> ④`lanprobe.ps1` 降级为兜底，新增"日志须等监听进程结束再算 SHA256"规则（E1 已踩过一次）。
> 依据：`docs\reports\M0-A-协议行为报告-E1-20261111.md` §3.2、`M0A\captures\E1-pcapng-ANALYSIS.md`（v2）。
> 定位：**只观察、不改写、不干预**——civtrace 与 M0-B 的 Hook 实现（改写路径）严格区分。

---

## 0. 工具包组成与边界

| 文件 | 说明 |
|------|------|
| `civtrace/trace_dll.cpp` | 追踪 DLL v0.3：Hook **31 个** API——Winsock 基线 21 个（`socket`/`WSASocketA`/`WSASocketW`/`bind`/`sendto`/`WSASendTo`/`recvfrom`/`WSARecvFrom`/`select`/`closesocket`/`ioctlsocket`/`setsockopt`/`connect`/`getsockname`/`getpeername`/`WSAEventSelect`/`WSAAsyncSelect`/`WSAPoll`/`WSASend`/`WSARecv`/`WSACleanup`）+ H3 专项 7 个（`getsockopt`/`WSAIoctl`（SIO_GET_EXTENSION_FUNCTION_POINTER GUID 解码 ConnectEx/WSARecvMsg 等）/`WSAGetOverlappedResult`/`WSAWaitForMultipleEvents`/`WSACreateEvent`/`WSACloseEvent`/`WSAEnumNetworkEvents`）+ kernel32 IOCP 三件套（`CreateIoCompletionPort`/`GetQueuedCompletionStatus`(Ex)，限流记录）。只记录、全部透传 |
| `civtrace/injector.cpp` | 注入器 **v0.4.4** `civinject.exe`：注入 / 重复注入检测 / **停用**（远程调 `CivTraceShutdown` 确认 0/1 后**不执行 FreeLibrary**，模块保留映射至目标进程退出——审计运行模式）。反复实验必须重启游戏，见 §2.1 |
| `civtrace/build-msvc.cmd` | MSVC 构建（本机首选；自动定位 vcvars64.bat + 自动 clone MinHook **v1.3.4**） |
| `civtrace/Makefile` | MinGW-w64 构建备选 |
| `.github/workflows/build.yml` | GitHub Actions 云构建 |
| `scripts/collect-baseline.ps1` | E0 构建基线一键采集（独立目录 + Build ID + SHA256 + VersionInfo） |
| `scripts/analyze-trace.ps1` | 日志速查分析（发现计数 / H3 字段 / socket 生命周期） |
| `docs/report-template.md` | 协议行为报告模板（M0-A 验收交付物格式） |

**实现级保证**（对应审查 3.1–3.3，已在源码落实）：
1. **错误码事务**：每个 Hook 在 real 调用后立即取 `WSAGetLastError()`，日志动作后恢复原
   last-error——日志不改变游戏的错误状态；
2. **Overlapped 三态**：`ov=done`（立即完成可读输出）/ `ov=PENDING`（`WSA_IO_PENDING` 时
   **绝不读取** from/bytes 缓冲）/ `ov=err`——杜绝异步竞态误读；
3. **日志不阻塞游戏线程**：固定事件入有界队列（满则丢弃并计 `drops`，绝不等待），独立
   刷盘线程 150ms 批量写；`session end seq=N drops=M` 落盘，缺日志可归因；
4. **DllMain 极简**：加载期只起延迟初始化线程；停用走导出 `CivTraceShutdown`
   （禁钩→等执行体退出→刷盘→**保持 MinHook 初始化、不 `MH_Uninitialize`**）——
   模块**保留映射至目标进程退出**，注入器不执行 `FreeLibrary`（v0.4.4 审计运行模式，B2 收敛）。

**v0.4.4 停用语义（必读，与历史版本不同）**：

| 动作 | 历史版本（≤v0.4.3） | **v0.4.4（当前）** |
|------|---------------------|---------------------|
| `-u` 停用 | 停钩 + 刷盘 + `MH_Uninitialize` + `FreeLibrary` | 停钩 + 刷盘，**不 Uninitialize、不 FreeLibrary** |
| 停用后 DLL 是否还在 | 否（已卸载） | **是**（保留至进程退出） |
| 停用后能否再注入 | 可以，Hooks 重新安装 | **不可以**——重复注入检查会跳过，Hooks 不会恢复 |
| 恢复追踪的唯一方式 | 重新注入 | **完全退出 CivilizationVI → 重新启动 → 重新注入** |

**边界声明**：
1. civtrace 只追加日志，不改任何参数与返回值——但 Hook 有调用开销，**可能改变游戏时序**；
   因此 E1/E4 均设"注入 vs 不注入"对照，结论只表述为"观察到相关性"；
2. 所有时延类测量（H6）以 **Wireshark 时间戳 + QPC 本地单调时钟**为准（日志每条含
   `qpc=` 与会话头 `wall↔qpc` 对应关系），**不跨机直接比较系统时间**；
3. civtrace/civinject 属"远程线程注入"特征，可能被 Defender 告警（F12）——**先不加任何
   排除项，观察实际拦截行为**（见 §1.4）；仅供审计使用，**禁止随 CivLink 正式版本分发**；
4. 日志文件：`%LOCALAPPDATA%\CivLink\M0A\logs\civtrace_日期_时间_pid<N>[_TAG].log`
   （可用环境变量 `CIVTRACE_TAG=host|client|c3` 区分角色；DLL 目录不可写时回退）。
   每条含 `#序号 / 本地时间 / qpc / tid / 调用者模块+偏移`。

日志行示例：
```
19:23:01.204 qpc=18765432100 #000042 tid=8124 socket af=2 type=2 ret=0x1a4 caller=civilizationvi.exe+0x1f2c3a
19:23:01.205 qpc=18765433100 #000043 tid=8124 bind s=0x1a4 af=2 type=2 addr=0.0.0.0:62056 ret=0 caller=...
19:23:05.117 qpc=18790123400 #000201 tid=8124 WSARecvFrom s=0x1a4 af=2 type=2 NB bound=0.0.0.0:62056 ret=-1 cnt=1 ov=no [WSAEWOULDBLOCK] caller=...
19:23:05.118 qpc=18790124400 #000202 tid=8124 WSASendTo s=0x1a4 dst=255.255.255.255:62905 len=4 ret=0 data=01 00 00 00 caller=...
```

---

## 1. 一次性准备

### 1.1 构建

- **路 A（本机首选，已验证）**：`civtrace\build-msvc.cmd` —— 自动定位 vcvars64.bat
  （环境变量 `VCVARS` 可覆盖）、自动 clone MinHook v1.3.4、一次产出 `civtrace.dll +
  civinject.exe`（`/MT` 静态 CRT 无运行库依赖）。
  2026-11-10 本机验证（历史，v0.3 时期）：MSVC 14.51.36231 @ `D:\MSVC\BuildTools`，31/31 Hook 全装，
  注入/重复注入拦截/卸载链冒烟通过。**注**：该条"卸载"指当时的 `FreeLibrary` 路径，
  v0.4.4 起已改为停用+保留映射（见 §2.1），二进制身份以 REV-002 报告 §2 哈希为准。
- **路 B（MinGW）**：根目录 `git clone --depth 1 --branch v1.3.4 https://github.com/TsudaKageyu/minhook.git deps\MinHook`，civtrace 目录 `mingw32-make CXX=g++`。
- **路 C（云构建）**：push 到 GitHub，Artifacts 下载产物（workflow 已 pin v1.3.4）。
- **免构建分发**：把 `civtrace\civtrace.dll + civinject.exe` 直接拷到另一台实验机（静态链接）。

### 1.2 E0：构建基线（先于一切实验，每次实验独立执行）

```powershell
# 单机（E1 等）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\collect-baseline.ps1 `
    -GameDir "E:\SteamLibrary\steamapps\common\Sid Meier's Civilization VI" -Tag E0-A

# 双机 E2：两端都必须带 -PeerIp，脚本才会采集对端可达性与选路
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\collect-baseline.ps1 `
    -GameDir "<本机库>\steamapps\common\Sid Meier's Civilization VI" -Tag E2-A -PeerIp <对端IP>
```

脚本自动生成 `M0A\baseline\<实验号>-<日期时间>\`。**v1.5 起输出 8 类文件**（此前只有 SHA256 /
版本 / 环境三项，不足以回答 E1 遗留的"接口归属"问题）：

| 文件 | 内容 | 用于 |
|------|------|------|
| `<label>-sha256.csv` / `<label>-version.txt` | 每个 exe/dll 的 SHA256 与 FileVersion | 二进制身份 |
| `environment.txt` | OS/UBR/machine/user/admin/timezone/网卡/IP/DNS | 环境差异 |
| **`interfaces.txt`** | `ifIndex / status / alias / MAC / MTU / speed / IP+前缀 / 网关` | **E2 接口归属取证** |
| **`routes.txt`** | 默认路由（按 Windows 优选顺序，含 ifMetric/routeMetric/nextHop）+ 全部 IPv4 路由 | **E2 选路取证** |
| **`firewall.txt`** | 三个 profile 的开关/默认动作 + 名称含 Civilization/Civ6/2K/Steam/Epic 的规则 + 已启用的入站 Block 规则 | E2 差异对比 |
| **`dlc.txt`** | DLC 目录清单（含是否有 `.modinfo`）+ `appmanifest_289070.acf` 的 buildid/installdir/StateFlags/LastUpdated | 两端内容一致性 |
| **`lan-reachability.txt`** | （仅 `-PeerIp`）`Test-Connection` ×4 + `Find-NetRoute`（Windows 实际选用的接口/IP）+ `tracert -d -h 5` | **E2 同网可达前置** |
| `summary.md` | 以上关键项的人读汇总 | 归档/复核 |

**注意**：`summary.md` 与各 txt 只记录测量值，**不对"广播从哪块网卡发出"下任何结论**——
E1 的 pcapng 显示 299/300 走 Radmin、1 个走 Hyper-V，该差异**未裁决**，必须由 E2 两端同时抓包回答。

**steam-buildid.txt 仍需人工核对补录**（从 `appmanifest_289070.acf` 的 buildid 或 Steam 库页面），
不用 exe FileVersion 代替。本机实测 `buildid = 26407122`、`StateFlags = 4`、`LastUpdated = 1794055862`。
**热修复背景**：周报称 2026-11-05 Windows 安全热修复（Steam Build 26407122）——该信息未经
独立公开佐证；无论真伪，E0 基线使我们始终知道"审计结论对应哪个二进制"。

### 1.3 Defender 处理（先观察，不预防）

1. **第一次注入前不加任何排除项**，直接运行 `civinject`，观察是否被拦截；
2. 若 Defender 拦截：优先在专用实验环境操作；确需排除时**只排除两个二进制文件**
   （`-ExclusionPath` 指向 `civinject.exe` 与 `civtrace.dll` 各自路径），**不排除整个目录**；
3. 每次实验结束**立即移除**排除项并复查（`Get-MpPreference | Select -Expand ExclusionPath`）；
   记录"加过什么、何时移除"；
4. **不要关闭实时保护**。

### 1.3b 执行目录要求（v1.3，**实机验证的必要条件**）

**不要在本项目目录内直接运行 `civinject.exe`。** 2026-11-11 E1 实测发现：

- 位于 `C:\Users\dd\Desktop\injciv6-v0.3.3\...` 下的 `civinject.exe`，枚举进程只得 **29** 个，
  对 `CivilizationVI_DX12.exe` / `notepad.exe` / `explorer.exe` 一律报 `not found`；
- 同一 exe 复制到 `C:\Users\dd\Desktop\` / `Documents` / `%TEMP%` / `ProgramData` 后，
  枚举得 **361–366** 个，注入立即正常；
- 已排除：提权不足（`EnableDebugPrivilege` 告警是**无害**的）、令牌完整性级别（Medium RID=4096）、
  AppContainer、restricted SID、Smart App Control、Defender 实时保护、计划任务、WMI 启动、父子进程关系；
  `NtQuerySystemInformation` 同样只返回 29 → **是目录级环境限制，不是本工具缺陷**。
   （注：此结论为 E1 执行者的归因/推断——排除项与诊断过程未归档可复核的原始输出；
   本机可按此规避操作，但根因机制未经独立取证证实。）

**标准做法**：

```powershell
# 每次构建后，把两个二进制复制到中立目录再执行
$run = "$env:USERPROFILE\Desktop\civlink-run"
New-Item -ItemType Directory -Force -Path $run | Out-Null
Copy-Item civtrace\civtrace.dll,civtrace\civinject.exe $run -Force

# 之后所有注入/停用命令都用 $run 下的副本
& "$run\civinject.exe" -x CivilizationVI_DX12.exe
```

日志位置不受影响（仍写 `%LOCALAPPDATA%\CivLink\M0A\logs\`）。

### 1.4 抓包：一键 pcapng 脚本（需用户手动提权），lanprobe 仅作兜底

**首选：`pcapng-capture.ps1`（Windows 内置 `pktmon`，输出 pcapng，含 SHA256）**

2026-11-11 实测确认：**agent 自身无法提权**——`Start-Process -Verb RunAs` 会挂起，
`consent.exe` 虽然启动但 UAC 对话框在**安全桌面**上（`PromptOnSecureDesktop=1`、
`ConsentPromptBehaviorAdmin=5`），截图 API 返回 `CONTROL_UNAVAILABLE`；`sudo.exe` 存在但已禁用；
`schtasks /rl HIGHEST` 报 `Access is denied.`；`AdjustTokenPrivileges` 返回 `err=1300`；
`whoami /groups` 显示 Administrators 是 **deny-only**（UAC 过滤令牌）。
→ **必须由用户亲手点一次 UAC「是」**。

因此抓包做成一键形态：

1. 双击/右键 `CivLink-M0A-audit\scripts\抓包-以管理员身份运行.cmd` →「以管理员身份运行」；
2. 窗口显示 `Admin: True` 后，**5 秒预备**内把游戏切到「多人游戏 → 局域网」；
3. 窗口提示"开始抓包"后 **30 秒内点【刷新】3 次**；
4. 结束后窗口打印 pcapng 路径、字节数、SHA256，按回车关闭。

产物（`M0A\captures\`）：

| 文件 | 说明 |
|------|------|
| `E1-pcapng-<时间戳>.pcapng` | 最终抓包文件（pcapng v1.0 小端） |
| `<时间戳>-E1.etl` | `pktmon` 原始 ETL（`etl2pcap` 输入） |
| `E1-pcapng-capture.log` | 逐步日志（Admin/PID/时间/ETL/PCAP/SHA256） |

- `--pkt-size 128`：只截前 128 B，UDP 头与 4 B 发现载荷完整保留，体积可控；
- **已知伪影（务必归并）**：`pktmon` 会在 NDIS 多个捕获点重复记录同一帧，同一 (轮, 端口)
  会出现 **4 份副本**（个别身份 8 份）。副本跨度按整数 tick 统计为 0/1/2/5/14 tick（1 tick = 1 µs，`if_tsresol` 未提供取默认 6），**最大 14 µs**；帧 SHA256 逐身份校验 300/300 一致。
  **归并键 = `(源 IP, IPv4 Identification, UDP 源端口, UDP 目的端口, 载荷)`**；
  三条确认依据：①同身份副本**整帧字节一致**（除时间戳）②时间戳相差微秒级
  ③每个 (轮, 端口) 在身份级**只出现 1 次**。
  ⚠ **IPv4 ID 必须按网络字节序（大端）读取**，`[BitConverter]::ToUInt16` 是小端，会把
  `f6 e4`(63108) 读成 `e4 f6`，进而伪造出"同轮递增 256"——v1 曾犯此错，经复核纠正并作废；
  正确工具：`scripts\analyze-pcapng-datagrams.ps1`（已入仓，导出 300 行 CSV 明细）。
  详见 E1 报告 §3.2 与 `M0A\captures\E1-pcapng-ANALYSIS.md`（v2）；
- **PS 5.1 脚本编码坑**：中文 `.ps1` 必须存为 **UTF-8 带 BOM**（否则按 GBK 解码导致语法错误、
  窗口闪退）；`.cmd` 必须存为 **GBK(936)**；`$ErrorActionPreference` 用 `Continue`，
  所有原生 `pktmon` 调用加 `*> $null`（否则 stderr 抛 `NativeCommandError` 中止脚本）。

**兜底：`scripts\lanprobe.ps1`（无管理员时）**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\lanprobe.ps1 `
  -OutFile "..\..\M0A\captures\<实验号>\listen.log" -Seconds 180
```

- 纯用户态 `UdpClient` + `ReuseAddress` 绑定 62900–62999 全部 100 端口，**无需管理员**；
- 记录 `时间 / 目标端口 / 长度 / 源地址:端口 / hex 载荷`；
- **能力边界**：只能看到**本机发出的发现广播**，看不到单播数据面（62056）、
  看不到 socket 级调用、看不到二层 MAC、时间分辨率仅 ~20 ms（不能用来测突发时长）。
  因此它**替代不了 pcapng**。
- 注意：`& script.ps1` 会因执行策略报 `AuthorizationManager check failed`，
  必须用 `powershell -NoProfile -ExecutionPolicy Bypass -File`；
  后台作业不要用 `Select-Object -First N` 接管道（会提前终止脚本），改用 `*> file`；
  **日志必须在监听进程结束后再算 SHA256**（否则得到中途哈希，E1 已踩过一次）。



### 1.5 Wireshark（采集与显示分离）

- **采集过滤器：留空（完整抓取）**——第一轮不预设端口白名单，防止游戏使用了清单外端口时
  丢证据（审查 4.2）；
- **显示过滤器（事后筛选）**：
  `(udp.port >= 62900 and udp.port <= 62999) or (udp.port == 62056) or (udp.port == 47584)`
- 抓包文件命名：`E0\captures\<实验号>-<角色>.pcapng`（两端/三端各抓各的完整接口流量）。

### 1.6 设备与环境要求（按实验）

| 实验 | 最低设备 | 备注 |
|------|---------|------|
| E0 | 1 台 | 每台实验机都要做 |
| E1 | 1 台 | |
| E2-A / E2-B | 2 台 | 双机部分按本节与 REV-013 裁定执行；E2-A 双机条目仍部分完成，E2-B 未完成；获批的本机合成响应试验不能替代双机判据 |
| E3 | 2 台 | |
| E4 | **3 台** | 三台有线接同一交换机；**第一轮不用 Wi-Fi**（AP 隔离/客户端隔离干扰拓扑判定） |
| E5 | 1 台 Epic 环境 | 无 Epic 构建则标记"未验证"，**不得用 Steam 结果替代** |

统一条件：文明6 同版本同 DLC、同 Steam 账号状态、Windows 防火墙设置一致；E4 各轮次顺序
随机化（避免时间顺序成为隐藏变量）。

### 1.7 E2-A 历史提交结果（2026-11-12；根因结论已撤回）

> 本节原提交曾把统计相关性写成根因，并将首包差异归因于 ARP。该解释已由 `docs/reports/REV-005-E2A-REVIEW.md` 否定；请以本节顶部纠错、REV-005 复核和 `docs/PROJECT-SCOPE-WIN-STEAM-2P.md` 为准。以下原始数值保留作历史记录，不代表现行结论。

> 完整报告：`docs\reports\M0-A-协议行为报告-E2A-20261112.md`；证据：`M0A\captures\E2-A-20261112\`（A 端）+ `M0A\captures\E2-A-20261112\PC-B-回传\`（B 端，SHA256SUMS 24/24 一致）。

**历史观察（因果解释已撤回）**：本次窗口内大量发现签名报文呈现 Radmin 源地址，也观察到少量 WLAN 源报文；双端曾各观察到 WLAN 广播到达。REV-005 独立复核认为这些数据不能证明 InterfaceMetric 是唯一原因，也不能支持“ARP 邻居缓存解释首包”的机制归因。两端 Radmin 客户端离线；虚拟网卡/地址/路由残留不证明 VPN 隧道在线。具体结论和证据边界见 `docs/reports/REV-005-E2A-REVIEW.md`。

**跨机确证**：A 端 pcapng 捕获到 B 端唯一 WLAN 包（`dstport=62900`、`srcip=192.168.31.214`、
`srcport=53787` 随机端口双端独立观测全等，IP ID=12255，5 副本帧 SHA256 一致），WLAN 广播链路双向可用。

**结论边界（勿扩大解读）**：
- ✅ 有限观察：给定抓包窗口和配置下，出现了不同源地址/接口的发现签名报文；部分 WLAN 广播跨机到达。
- ❌ 未证实：InterfaceMetric 是唯一因果因素；Radmin 客户端离线时这些报文实际经过在线隧道；metric 修改能让 Civ6 稳定发现或成功联机。
- 项目负责人补充的“五次刷新，一次 WLAN 找到房间、四次 Radmin 源未找到”目前标为待归档复核观察，详见 `docs/PROJECT-SCOPE-WIN-STEAM-2P.md`。

**方法学教训（强制，后续实验必须遵守）**：
1. **G2 通过 ≠ Civ6 能发现**——G2 工具发包只能证明工具自身路径；要判断游戏发现必须由游戏本体发包并关联房间列表/响应。
2. **跨机时间戳先 NTP 校准**——实测 A/B 墙钟差 1.344s，非网络延迟，不得直接作延迟分析。
3. E2-A→E2-B 切换注入状态须**完全退出并重启 CivilizationVI**（同 §2.1）。

### 1.8 REV-013：H4 当前样本结案与单机合成响应授权（2026-11-13）

- 本机构建、本次房间公告的 22 页完整样本中未发现房主 IPv4 字段；仅结案当前样本，不外推为所有版本的协议事实。不要把“本次观测到回复源 IP”扩大为“客户端只能从源 IP 得知地址”。证据见 `docs/reports/E2A-H4-REPLY-EVIDENCE-20261113.md` 与 `M0A/captures/E2A-H4-reply-20261113/`。
- “0 房主回复”是筛选条件漏掉 `srcPort=62900 → 客户端临时端口` 的工具盲区；E2-A 报告 §10–§11 已更正。§10 的截断判断为历史记录，以 §11 完整样本分析为准。
- E2-A 整体只记为**部分完成**：本机自收提供本机包级证据，负责人双向互见为 D 级手测；双机同步关联与 Gate A E2-A 条件仍未满足。
- 已批准一次有界本机合成响应试验。执行限制和证据要求见 `docs/reports/REV-013-REVIEW.md` §4。试验成功也只证明本机构建客户端在该合成条件下显示公告，不替代 E2-B/E3，不启动 M0-B。
- `REV-005-E2A-SUBMISSION.md` 保留历史原文；后续更正通过复核记录追加，不回写历史提交。

### 1.9 单机合成响应实验复核（2026-11-13）

- 实验已在 REV-013 §4 授权范围内闭合：R4 监听 99 个可用端口，捕获 99/99 请求，响应 1 次并发送 22 页；截图显示匿名房间列表项。独立探针另捕获 100/100 端口。
- 可引用的限定结论为：“本构建客户端在本机合成响应条件下接受该公告并显示列表项。”这不等于 E2-B、E3、联机验证或 M0-B。
- 此前“刷新只发送 1 包”的结论作废。已确认的 T-class 工具缺陷是 `ReceiveMessageFrom` 的 `[ref]` 出参跨调用复用导致后续调用异常，被旧 `catch` 静默中断。
- responder v2.2 已修复通用异常不落盘的问题；错误路径回归 9/9 通过。此前具体 `[ref]` 出参复用缺陷及其 1/99 结果已纠正。详见 `docs/reports/E2B-SYNTHETIC-CLIENT-REVIEW.md` 和 `docs/reports/REV-014-REVIEW.md`。
- 本轮不要求补 pcapng/UAC。若后续需要链路层接口归属或帧级独立证据，再单独安排抓包。

### 1.10 REV-014 范围裁定（2026-11-13）

- S1 **非发布原型**获准：只读接口诊断、离线 fixture 解析和 mock UI。首版承诺仍是 Windows + Steam 双人，不据此降 Gate。
- 不实现 metric 自动修改；不做实时网络响应/流量接管；不注入产品 DLL。
- P2 历史授权：主菜单下 civtrace 观察工具与合成 responder 组合一次；执行前须补 `Socket.Select` 异常日志。授权边界见 `docs/reports/REV-014-REVIEW.md` §4，实验结果与范围偏差见下节。
- PC-B E0 与原始 metric 日志尚未归档到本机；Gate A 基线项仍未完成。E2-B/E3、Gate A、M0-B 状态不变。

### 1.11 P2 H6 响应窗口复核（2026-11-13）

- 主实验 3 轮数据已由复核方用仓库分析器重算：每轮 100 个发现包、22 页 × 1104 B 收到；`T_window=2016.987–2024.513 ms`，最后响应到 socket close 为 `1619.696–1691.612 ms`。
- 结论限定为“本机合成即时响应后 socket 未提前关闭”。未注入 20–50 ms 延迟，因此不能称作 Relay RTT 已验证或 H6/E2-B 已通过。
- 主实验遵守最多 3 次响应；之后另开的观察轮发送 2 次响应，超出本次一次性授权，已保留并披露，不并入主实验结果。
- S1 Phase 0 可按 `docs/reports/REV-014-REVIEW.md` 继续；Gate A 未批准、M0-B 冻结。
- 复核详情：`docs/reports/P2-H6-REVIEW-20261113.md`。

### 1.12 Phase 0 `--broadcast-path` 故障（2026-11-13，**已定位并闭环**）

- 同一份 `cmd_test.exe`（SHA256 相同）从 `%TEMP%` 运行成功、从 `prototype` 目录运行失败；同一哈希的 `civlink-diag.exe` 从原型目录失败、复制到 `%TEMP%` 后成功。复测工作目录相同，因此差异随**父可执行映像位置**变化，而非 Cargo/rustc 版本或 Base64 编码。
- **根因（已取证）**：项目目录树继承了 **Low 完整性标签**——`icacls` 显示根目录 `Mandatory Label\Low Mandatory Level:(OI)(CI)(NW)`，并继承到子目录与 `target\debug\*.exe`；`%TEMP%` 副本无该标签。从该目录启动的进程与子 PowerShell 为 **Low IL（S-1-16-4096）**，而 `%TEMP%` 运行为 **Medium IL（S-1-16-8192）**。在该 Low IL 下，`Find-NetRoute`（NetTCPIP 的 CDXML 实现）返回 `HRESULT 0x80041003 / PermissionDenied`。
- **结论限定**：仅限该命令路径。同类级直接 `Get-CimInstance root/StandardCimv2 MSFT_NetRoute` 在 Low IL 下仍返回 74 条正常，**不得**推广为“所有 WMI/CIM 都要求 Medium IL”。事件日志无 WDAC/AppLocker 事件（IL 降级不落这些日志）。**未修改项目目录 ACL。**
- **已完成的源码整改**：错误可见化（`-ErrorAction Stop` + `FullyQualifiedErrorId`）、候选去重、失败退出码 1、专属 Low-IL 提示仅在识别到 `0x80041003`/`PermissionDenied`+`MSFT_NetRoute` 时给出、`json_array_len` 局限写入注释、`DBG`/`debug_encode` 删除。
- 取证与整改证据：`prototype/PHASE0-FORENSIC-RESULT.md`、`prototype/PHASE0-REMEDIATION-EVIDENCE.md`。环境级复核由负责人从中立目录执行回传（命令见 `prototype/README.md`）。

### 1.13 metric 环境观测（2026-11-13，**不是待办，不需授权动作**）

> **2026-11-13 修订**：本节初版写作"metric 前置条件"，把"环境状态变化"升级成了"任务阻断、需获授权修复"。这个升级是错的，已降级为事实记录。metric 如何取值是本项目的**外部环境**，不归本项目改动；当前没有任何在办工作依赖它（S1 Phase 0 完全离线）。

- **机制**：`255.255.255.255/32` 在每块网卡上各有一条等价本地路由（`RouteMetric=256`），Windows 取 `InterfaceMetric` 最小者。虚拟网卡（Radmin/ZeroTier/Hyper-V/WSL）度量若小于 WLAN，广播就从它出去。
- **事实**：本机 2026-11-13 19:03 重启后 **Radmin VPN 的 `InterfaceMetric` 由 1045 变为 1**（注册表 `...\Tcpip\Parameters\Interfaces\{CED510FD-…}\InterfaceMetric = 1` 为**持久值**），`255.255.255.255` 的**预测**出口变为 `if21 Radmin VPN`，而对端 `192.168.31.214` 的路径是 `if11 WLAN`。
- **不是本项目所为**：`C:\Users\dd\civlink-metric-backups\` 内只有 `kind=snapshot` 的记录，**没有任何 apply 备份**（apply 会写 `keep`/`changed`）。metric=1 来自本项目之外的改动，来源未确认，**也不由本项目追查**。
- **索引同样漂移**：`if10/if15/if18` → `if11/if16/if21`。**索引与 metric 都是运行时观测值，跨重启或软件更新会变**；历史文档里写死的 `if10`/`if18` 不能当常量引用。
- **不影响已完成的验证**：2026-11-12 的 metric 调整与双机验证结论仍然成立、不需要重做（当时 PC-A `WLAN=if10/45`、`Radmin=if18/1045`，PC-B `WLAN 35→10`、`Radmin 1→5000`，两端广播都走 WLAN；用户 m08332 的"各自建房对方刷新都能看到房间"是 D 级口述证据）。**E2-B 当前受阻的原因是 PC-B 不在线，不是 metric。**
- **只在真正要跑 E2-B/E3 时**，实验窗口内需满足：`W-1` **真实发包确认出口**（权威判据，路由预测在 PC-A/PC-B 已被反证两次）+ `W-2` 对端 ARP 可达 + `W-3` 双端 v0.4.4 工具身份 + `W-4` 路由预测作交叉检查。约束的是"实验窗口内"，不是"系统长期状态"。
- **绕开路径不改网卡**：负责人手动调适配器优先级/临时禁用 Radmin；或探测工具 `bind 192.168.31.59`（E1 已实测 100/100 走 WLAN）。**不建议**用 helper 执行 `apply`（REV-008 R-3b 未解决、`apply` 路径从未验证）。
- **产品落点**：`civlink-diag` 指出"广播会从 Radmin 出去"是 REV-014 批准给 S1 的合法输出形态——作为**诊断规则**（检测→告知→建议），而不是产品替用户改网卡。
- 事实与快照见 `docs/METRIC-PRECONDITION-20261113.md`；快照 `M0A\captures\metric-precondition-20261113\`。metric 修改仍未获授权，本项目也不申请该授权。

---

## 2. 注入与停用操作全表（含异常处理）

> **术语（v1.2）**：`-u` 不再叫"卸载"，准确说法是**停用**（停止 Hook + 结束日志会话），
> DLL 保留在目标进程内直到该进程退出。见 §2.1。

| 步骤 | 操作 | 必须的结果 |
|------|------|-----------|
| 注入（含进程匹配） | `civinject.exe -x CivilizationVI.exe`（管理员；无动作参数=**注入**） | 先打印全部匹配 PID + 完整镜像路径（`[*] matched N process(es)`），随后 `[+] OK @ <模块基址>`。**注意：不存在"仅查询"模式——无 `-u` 即注入，预检查也会改变目标状态** |
| 多进程消歧 | `civinject.exe -x CivilizationVI.exe -p <pid>` | 只对指定 PID 操作（先匹配校验，再注入） |
| 位数检查 | 自动（IsWow64Process） | 32 位目标直接拒绝并报错 |
| 验证 | 查日志会话头 | `%LOCALAPPDATA%\CivLink\M0A\logs\civtrace_...log` 出现，含 `hooks installed ok=31 fail=0` |
| 重复注入 | 再执行一次（无动作参数） | 报 `already loaded @ ...` 并跳过（不重复装钩） |
| 执行实验 | 日志 + Wireshark 同时运行 | 两端/三端文件齐全 |
| 停用 | **回到主菜单后** `civinject.exe -x CivilizationVI.exe -u` | `CivTraceShutdown confirmed` + `[+] B2 audit-run mode: ... intentionally LEFT MAPPED until pid=N exits`，退出码 **0** |
| 停用后确认 | 再执行一次 `-u` | 退出码 **0**（`== already shutting down / complete ==`，幂等）；再执行注入命令（无动作参数）报 `already loaded`——**证明 Hooks 未恢复** |
| 恢复追踪 | **完全退出 CivilizationVI 进程 → 重新启动 → 重新注入** | 新 PID、新日志文件、`hooks installed ok=31 fail=0` |
| 异常退出 | 游戏崩溃/卡死 | **保留日志与现场**，不对失效进程强行卸载；崩溃时机 + 日志尾 50 行是有效数据 |

时机规则：只在主菜单注入；不在房间/对局中注入或停用；实验结束回主菜单再停用；直接退出
游戏也允许（进程退出路径自动收尾刷盘）。**同一进程内不可重复启停追踪**。

### 2.1 停用与重启（v0.4.4 强制流程）

`-u` 在 v0.4.4 是「停止 Hooks 并结束日志会话」，**不是从进程卸载 DLL**。原因是
REV-002 的 B2 审计整改选择了「审计运行模式」：目标进程退出前不释放 DLL 代码页与
MinHook trampoline，从根上消除"关闭线程排空判断之后仍有线程进入 detour"的
use-after-free 面。代价就是**同一进程内无法热重启追踪**。

因此每一个需要重新开始的实验阶段都必须走完整重启：

```
[1] 回到主菜单（不在对局中）
      civinject.exe -x CivilizationVI.exe -u          # 停用：exit 0 + LEFT MAPPED
[2] 确认停止生效
      civinject.exe -x CivilizationVI.exe               # 应报 already loaded（Hook 未恢复）
      日志尾部出现 "=== shutdown complete; ... LEFT MAPPED ... ===" 与 session-end 行
[3] 完全退出 CivilizationVI（任务管理器确认无 CivilizationVI.exe 残留）
[4] 重新启动游戏 → 等待进入主菜单
[5] 重新注入（新 PID）：civinject.exe -x CivilizationVI.exe
[6] 校验新会话头：新的 civtrace_..._pid<新PID>.log + hooks installed ok=31 fail=0
```

**记录要求**（对应验收意见 §2.2）：每轮实验记录中必须写明 `PID / 轮次编号 /
注入状态（injected | stopped-but-mapped | fresh-restart）`。E2-A→E2-B、E4 的五轮、
以及"注入 vs 原生"对照之间，**一律按上述流程重启**，不得仅靠 `-u` 后再次注入。

**禁止事项**：
1. 不得在活动进程内对目标执行外部 `FreeLibrary`（会触发 DllMain detach，本工具契约
   不保证抵抗外部强制卸载）；
2. 不得把 `-u` 的退出码 0 解释为"模块已卸载"——它只表示"停用+刷盘完成"；
3. 不得在日志 `session-end` 之后继续引用该会话的 trace 作为实时证据——关闭日志只代表
   "观察会话停止并尝试刷盘"，不等于所有并发调用的绝对完整边界（验收意见 §3）。

**停用时机（v1.3：硬性要求，不是建议）**：必须在**主菜单/静止阶段**停用。
2026-11-11 E1 实机验证：在局域网界面直接 `-u`，因 `WSAEnumNetworkEvents`/`WSAWaitForMultipleEvents`
高频调用（steamclient64.dll 每 33 ms 一轮）导致 `in-flight hooks=1`，**5 s 内未排空 → 首次 `-u` 返回 2**：

```
15:24:51.727 #460400 !!! in-flight hooks=1 did NOT drain within 5s - closing chain ABORTED;
                         MinHook/log/queue resources KEPT; state=FAILED; retry CivTraceShutdown
```

B1 设计在此生效（资源全部保留、进程无损），静默 12 s 后重试即 `code 0` 成功。
→ **操作规则**：`-u` 返回 2 时**不要惊慌、不要外部强卸**，回到主菜单静止 10 s 以上再执行一次 `-u`；
连续两次失败才按"保留现场 + 上报"处理。

---

## 3. 实验 E1：单机发现（F1 复证 + 注入对照）

> **E1 需要一次进程重启**（v1.2）：注入组与原生组不能在同一个游戏进程内完成对照，
> 因为 v0.4.4 停用后 DLL 仍保留映射、Hooks 不会重新启用。
>
> **v1.4 执行状态**：2026-11-11 完成单机发现观测，报告见
> `docs\reports\M0-A-协议行为报告-E1-20261111.md`。原生对照已补做**完全退出、重启、未注入**（300 包/3 轮），
> 证据见 `M0A\captures\E1-20261111_1510\clean-restart-native-2.log`；并已补抓 pcapng
>（`M0A\captures\E1-pcapng-20261111_201146.pcapng`，完整抓 UDP，3 轮×100 端口）。
> 因而 E1 的原生对照与完整抓包缺口已补；本实验仍是**单机无房主场景**，不能替代 E2/E3/E4 或证明联机行为。

| 步骤 | 操作 |
|------|------|
| 1 | E0 基线 → 启动游戏 → 主菜单注入 civtrace（CIVTRACE_TAG=host），核对 `hooks installed ok=31 fail=0`，记录 PID（**从 `civlink-run\` 目录执行**，见 §1.3b） |
| 2 | **Wireshark 完整抓包（采集过滤器留空）**；无 Wireshark 时开 `lanprobe.ps1` 兜底 |
| 3 | 游戏内进「多人游戏 → 局域网」点一次"刷新"；**每点一次 = 一轮 100 包**，重复 3 次以上；停抓保存 `E1-host-inj.pcapng` |
| 4 | `-u` 停用（exit 0 + LEFT MAPPED）→ **完全退出 CivilizationVI** → 重新启动到主菜单 → **不注入**，记录新 PID |
| 5 | 重复第 2~3 步（原生对照），保存 `E1-host-native.pcapng` |
| 6 | 对比两组：100 个 `sendto dst=255.255.255.255:629xx len=4` 是否一致（F1）；socket 创建/选项/关闭时序是否一致（civtrace 无副作用佐证） |

**判据**：F1 → C 级证据；两组行为一致 = 追踪工具未改变发现行为。

### 3.1 已知实测基线（2026-11-11，用于判定"行为是否变化"）

| 项 | 实测值 |
|----|--------|
| 每轮包数 | **100**（目标端口 62900–62999 全谱、无缺无重）；pcapng 数据包级独立确认 = 3 轮 × 100 = **300 个数据报身份**（原始 1204 条 EPB 含 pktmon 多点重复采样，需归并） |
| 包长 / 载荷 | **4 B** / `8d e8 fc 70`（恒定）；UDP 长度 12、以太网帧 46 B、目标 MAC `ff:ff:ff:ff:ff:ff` |
| 突发时长 | **1.0 / 3.8 / 4.1 ms**（civtrace QPC，含 hook 开销）；**pcapng 更精确：0.690 / 0.726 / 0.811 ms**——一次性突发，无周期重发 |
| 发现 socket 序列 | `socket` → `setsockopt` → 100×`sendto` → `select` 轮询 → `closesocket`；**全程无 `bind`** |
| `select` 次数 | **134 次/轮**，单机无房主时 **ret 恒为 0** |
| **T_window**（closesocket − 首包） | **2021 / 2019 / 2014 ms**（≈ 2 s） |
| `recvfrom` 次数 | **0**（发现阶段不使用 recvfrom） |
| 广播出口接口（**限定表述**） | 该主机该配置该次抓包：300 个数据报身份中 **299 个** = Radmin VPN `26.74.126.98` / `02:50:ad:ad:4a:dd`，**1 个**（轮1 端口 62900）= Hyper-V `172.27.112.1` / `00:15:5d:91:c3:2e`；WLAN 源未出现。**不得**断言"统一经 Radmin 出口"，**不得**推定 Relay 绑定硬约束（复核纠正） |

> **对后续实验的三条硬性影响**：
> 1. 规范 §10.3「按发现周期重发」假设**不成立**——Agent 必须自建重试，不能等游戏重发；
> 2. 游戏**不 bind** 本地端口 → CivLink 出向捕获不能依赖"游戏已占用的本地端口"；
> 3. F2 的"原 socket 上阻塞 recvfrom"应改为"**`select` 轮询原 socket**"，回复窗口约 2 s。

---

## 3A. F0：固定模拟房主夹具（REV-016 快速路线，当前主入口）

> **为什么有这个**：`REV-016` 起不再等待第二台装有 Civ6 的电脑，改用"单台真实 Civ6 +
> 模拟房主"作为开发夹具。F0 的目标是把"游戏能稳定发现这个模拟房间"变成可复现、可校验、
> 带哈希的回归基线；之后 F1（DLL + Agent 发现链路）才有地基。

### 3A.1 目录与文件身份

全部在 `scripts\F0\`：

| 文件 | sha256 | 字节 | 作用 |
|---|---|---|---|
| `F0-run.cmd` | `18BBE233B71DE77239CBF6FCD49568B767E4D929534DEC6DD1B8D3A01291426D` | 5 367 | **唯一启动入口**（启动 responder + 等端口就绪） |
| `F0-verify.ps1` | `1B24AD557A9959452DE61063959B4024CCE5CAB0320610B6C06D0837B1DC3DF1` | 16 424 | 机器校验 8 节，退出码 0/1/2 |
| `test-f0-verify.ps1` | `453F552A43F9240F6764B6D4BE07AFF0A58F1A83D0C1B80149B7FD23E15F2F3E` | 8 049 | 变异测试（17 条断言），证明校验器真会抓错 |
| `F0-selftest.cmd` | `C3D3295F86921B4135A7D53E2DAD2DD8AE59EF0F024658705DBE3122A8A6A935` | 4 469 | 无 Civ6 端到端自检（纯环回） |

> 哈希按本表记录时点计算；文件一改即失效，复核方以自己重算为准。

### 3A.2 标准流程（一次 F0 回归）

```
1) 不需要 Civ6 时先跑自检，确认夹具链没坏：
      scripts\F0\F0-selftest.cmd
   期望：replies=22/22 from_probe_port=22 wrong_length=0
         MACHINE CHECKS: ALL PASS
         F0-SELFTEST: PASS

2) 启动模拟房主（保持这个窗口开着，默认监听 30 分钟）：
      scripts\F0\F0-run.cmd
   期望先看到 READY <pid>（UDP 62900 已被 responder 绑定）。
   NOT-READY 表示 20 s 内没绑上，通常是有 Civ6 房主大厅正占着这个端口段，
   脚本会以退出码 3 中止，不会强杀也不会复用。

3) 打开 Civ6 → 多人 → 局域网（客户端窗口，不要自己建房）→ 刷新，连续 20 次，
   每次间隔约 6 s（落在 3 s 突发窗口内会被视为合并而不回复）。每次记录：
   是否看到 CivLink-Test-Room-2222 / 本次是否超时 / 有无报错。

4) 不用自己收尾：F0-run.cmd 会等余波 30 s 结束、summary.txt 落盘，然后自动调用
   F0-verify.ps1 打印逐节结果与 `--- F0 result ---`，并以校验器退出码退出。
   想手工复核时再跑：
      powershell -NoProfile -ExecutionPolicy Bypass -File scripts\F0\F0-verify.ps1 ^
          -EvidenceDir M0A\captures\<F0 证据目录>

5) 回传：证据目录路径、verify-report.txt、以及逐次刷新记录。
   期望机器部分为 `MACHINE CHECKS: ALL PASS (0 failures, 0 warnings)`。
```

### 3A.3 校验器实际检查什么（`F0-verify.ps1` 8 节）

1. **必需文件**：6 个证据文件 + 22 张 `sent-reply-NN.bin`；缺任一 → 退出码 2 并打印报告。
2. **页镜像**：每页 1 104 B、magic `59-60-69-9B`、`[156]`=22、`[160]`=自身 0 基索引、
   `[1102..1103]`=`00-00`。
3. **fixture-hashes.txt**：22 行格式正确；每页 sent 摘要与磁盘重算一致；变更偏移必须落在
   `24..45`（房间名字段）。**不断言偏移个数=22**——匿名名可能与原名共享字节，实测真实证据为 21 个。
4. **summary.txt**：responses/budget/bound/requests/receive errors/select errors 六项；
   缺 `select errors` 行只 WARN（v2.3 以前的历史证据），但"声明有错 + 日志为空"是 FAIL。
5. **requests.log**：每个 `RESPONSE #N` 块必须 22 行 page 行、顺序 01..22、每条 1 104 B、
   源端口等于该块 dstPort、摘要与 `sent-reply` 一致；超预算或与 summary 不一致即 FAIL。
6. **receive-errors.log**：0 字节且两个 unexpected 计数为 0；只有 3 字节 BOM 会被判 FAIL
   （"only a UTF-8 BOM"）。
7. **precheck.txt**：回显绑定前的端口占用决策。
8. **F0 退出条件**：机器部分逐条指向上面的小节；**人力部分（20 次刷新都看到房间）只能由人确认**。

### 3A.4 变异测试（证明校验器不是橡皮图章）

```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\F0\test-f0-verify.ps1
```

以 `M0A\captures\E2B-synthetic-v22-real-20261113-122548` 为种子复制到 scratch 后逐项变异，
断言校验器给出指定判决。8 组共 17 条断言全部 PASS：A 健康（退出 0）/ B 零响应（退出 1）/
C 缺文件（退出 2）/ D 篡改页内容（摘要不符）/ E 页索引被改（99 != 6）/
F BOM-only 错误日志 / G 超预算 / H 缺页镜像（退出 2）。

> **为什么必须有这一步**：只会在好输入上通过的校验器等于没有。改动 `F0-verify.ps1` 后
> **两个脚本都要重跑**；变异测试挂了说明校验器退化，不能只改测试去迁就它。

### 3A.5 边界（必须照抄进任何引用本节的报告）

- F0 证明的是"模拟房主按设计工作、公告页逐页可校验、真机刷新请求被接收并完整响应"，
  **不是**两台真实 Civ6 对局。
- **不是** E2-B、**不是** M0-B、**不是**多人联机验证，**不移动任何 Gate**。
- 允许的表述：「本构建客户端在本机合成响应条件下接受该公告并显示列表项」（仅在确实观察到时）。
- 允许的表述：「模拟房主在真机回归中收到并响应了 20/20 次刷新，证据链通过机器校验」。
- 不允许的表述：「20 次刷新每次都看到了房间」（本轮观察为"有时看得到、有时看不到"，
  逐次可见性未记录）。
- 不允许的表述：「联机已验证」「Relay 可用」「M0-B 通过」。

### 3A.6 真机回归结果（2026-11-14 00:04–00:08，`F0-run-20261114-000141`）

一次完整回归已执行：真实 Civ6（`CivilizationVI_DX12`）停在局域网列表作客户端，
responder 预算 20 / 突发窗口 3 s。

```
responses sent  : 20 (budget 20)
bound ports     : 62900..62999 (100 bound, skipped none)
request ports   : 62900..62999   ← 全部 100 个端口都出现过
requests logged : 480        post-response datagrams: 2680
receive errors  : 0 unexpected, 0 expected(would-block)
select errors   : 0 unexpected, 0 expected(abort)
```

`F0-verify.ps1` → `MACHINE CHECKS: ALL PASS (0 failures, 0 warnings)`，
逐块断言了 20 个 RESPONSE（22 页 / 顺序 01..22 / 1 104 B / 源端口 62900 / 摘要一致）。

**本轮两个新观察（F1 必须考虑）**：

1. **客户端不只"点刷新才发"**。`post-response-traffic.log` 按 500 ms 聚类得到 **27 组突发**
   （跨度 82–112 ms）：20 组为 99 包（触发响应的那一组，请求包记入 `requests.log`、其余 99 包
   记入 post-response），7 组为 100 包（未触发响应）。
   对账：20×99 + 7×100 = 2 680 = summary 的 `post-response datagrams`。
   7 组未触发的间隔为 2.40/2.49/2.57/2.48/2.89/2.62/4.13 s；前 6 组落入 3 s 窗口记为
   `coalesced, no extra reply`（2 481 条），第 7 组到达时预算已尽记为
   `MATCH but budget exhausted`（199 条），2 481+199=2 680 二次对账吻合。
   → **Hook 计数闭合必须按"每次突发"对齐，不能按"每次用户操作"对齐**，也不能假设
   两次刷新之间没有流量。约 2.5 s 后补发整组的行为与"客户端重试"模式相符，但本轮数据
   **不足以区分**"客户端重试"与"用户连点两次"，不得写成结论。
2. **机器侧 20/20 全收到并全回，但操作者口述"有时看得到、有时看不到"**。机器只能证明
   "请求被收到、22 页被发出"，**不能**证明客户端是否把公告画进列表；两者不冲突也不互相否定。
   待验证假设：客户端对同一房间公告的处理/去重带时序敏感性，而非模拟房主漏回。
   **该假设未验证，不得写成结论**；F1 接 Hook 后需同时记录"客户端收包时刻"与"列表项出现/消失时刻"。

---

## 3B. F1：Hook + Agent 本机发现链路（2026-11-14）

> **入口**：`civlink\run-f1-selftest.ps1`（可重复机械自检，不需游戏）、
> `civlink\run-f1-live.ps1`（真实 Civ6 客户端注入观测）。
> **详细报告**：`docs/F1-HOOK-AGENT-MECHANICAL-20261114.md`。

### 3B.1 交付物

| 文件 | 作用 |
|---|---|
| `civlink\civlink_hook.dll` | 观测态 Hook：挂 `sendto` / `WSASendTo` / `closesocket`，**原样透传**，把发现端口的载荷按 CVLH2 帧送出 |
| `civlink\civlink-agent.exe` | 独立 Agent：绑定 `127.0.0.1:34718`，解码 CVLH2，逐帧记录并对账 |
| `civlink\civlink_ctl.exe` | 控制器：`inject` / `status` / `counters` / `shutdown` |
| `civlink\hook_selftest.exe` | 自检程序：23 项断言，证明透传与计数正确 |

### 3B.2 机械自检（当前状态：PASS）

```powershell
cd CivLink-M0A-audit\civlink
powershell -NoProfile -ExecutionPolicy Bypass -File .\run-f1-selftest.ps1
```

最近一次结果（`M0A\captures\F1-selftest-20261114-003638`）：

- `hook_selftest.exe` → **HOOK-SELFTEST: PASS (0 failure(s))**，23/23；
- Agent `summary.txt` → `datagrams 4 / received 4 (processed 3, rejected 1) /`
  `reconciliation processed + rejected = 4 == received = 4 / seq gaps=0`、
  `dst ports=3 (min 62905, max 62908)`；
- 驱动 → `hook.sent (3) == agent.processed (3)`、`dst = 255.255.255.255,127.0.0.1,...`、
  `ports = 62905,62907,62907,62908`；
- 最终 **F1-SELFTEST: PASS**，exit 0。

> **关键性质（自检真正证明了什么）**：Hook 不改写返回值、不改写 last error、
> 不吞包（`4/4/4/1400` 原样返回）；超长载荷不静默截断（改发 notify 帧并两侧计数）；
> `closesocket` 后 socket 摘除正确；shutdown 语义为 0 干净 / 1 已关 / 2 有在途，
> 且 shutdown 后计数不再增长。

### 3B.3 真实客户端观测（F1-live）

```powershell
# 前置：Civ6 已启动并停在 多人游戏 > 局域网 列表；无残留 Agent 占用 34718
# 必须从中立目录运行（项目目录树带 Low Mandatory Label，会把 ctl 降为 Low IL，
# 导致 OpenProcess 权限不足 err=5 - 见 3B.5）
cd C:\Users\dd\Desktop\civlink-f1
powershell -NoProfile -ExecutionPolicy Bypass -File .\run-f1-live.ps1 `
    -ProcessId <pid> -AutoStopSeconds 300 `
    -OutRoot C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures
```

脚本会启动 Agent → 注入真实 Civ6 → 每 2 s 打印 `sent/fail/oversize/ignored` →
提示操作者点几次**刷新** → 按 ENTER（或创建 `STOP` 文件、或用 `-AutoStopSeconds`）收尾 →
读 `counters` 与 Agent `summary.txt` 做对账，输出 `F1-LIVE: PASS/FAIL`。

判据：Hook 至少捕获一次发现发送、`hook.sent` 增量 == `agent.processed`、
`sendFail == 0`、所有目标端口在 62900–62999、且出现多于一个端口。

**当前状态：2026-11-14 10:55 更新——「观测子项通过 + 集成链路通过」。**
观测子项（2026-11-14 09:22:57，`F1-live-20261114-092257`）：
单台真实 Civ6（pid 46368）注入后，操作者点击刷新期间捕获 **1400 次发现发送（14 组 × 100 包）**，
Agent 收到 1400 帧，`hook.sent 1400 == agent.processed 1400`，`sendFail 0`、`rejectOversize 0`、
`seq gaps 0 duplicates 0 out_of_order 0`、目标端口覆盖 62900–62999 全部 100 个、
`via_wsasendto=0` 全部走 `sendto`。游戏进程保持 `Responding=True`。
证据 `M0A\captures\F1-live-20261114-092257`；报告
`docs\F1-LIVE-REAL-CLIENT-20261114.md`。

集成链路（2026-11-14 10:42/10:55，`F1-integration-20261114-104235` / `-105026`）：
重启后的真实 Civ6（pid 44832）注入 hook + 运行 `civlink-agent.exe --simulate` 后，
操作者分别点击 **3 次 / 7 次刷新**，模拟房主 `CivLink-Test-Room-2222` 的 22 页公告
经 DLL→Agent 链路（CVLH2 127.0.0.1:34718）注入回客户端并**显示在房间列表**；
两轮均 9/9 机器断言 PASS（300/300 与 700/700 帧对账闭合、0 失败、0 缺口、
回复 socket 3/7、页数 66/154），操作者两轮口述均确认房间可见。
证据目录见上；报告 `docs\F1-INTEGRATION-REAL-CLIENT-20261114.md`。
另有第二轮/第三轮 void（`-104534`/`-104723`）为操作者时序问题（窗口先于指令结束），
非产品故障，详见报告 §3。

> **复核边界（2026-11-14 codex 复核 + 集成链路补充）**：以上「观测子项」只证明
> 「真实客户端 Hook→Agent 观测」子项。按 REV-016，F1 还要求模拟房主接入 DLL/Agent 链路
> 并由真实客户端显示模拟房间——该「集成链路」子项已由
> `F1-integration-20261114-104235`（3/3 回复）与 `-105026`（7/7 回复）完成并获操作者
> 口述确认（见 §3B.3b）。两子项齐备，F1 两个要求均已覆盖；但仍非联机 / E2-B / Gate A 结论。

两个由此确立的设计输入（F2 前必须处理）：

- **每次刷新都用全新 socket**（14 次刷新 = 14 个 logical_socket_id + 14 个不同临时源端口，
  首发 100 包后即关闭）。会话表必须以"刷新"为单位，不能假设 socket 长期存活。
- **每个 socket 首帧 `src=0.0.0.0:0` 属预期**（UDP 首次 `sendto` 前未绑定，
  `getsockname` 返回端口 0）；Hook 不把它当已知端点，下一帧即取得真实端口。
  `src unknown` 恰等于 socket 数。

若 `hook.sent` 为 0，先确认**操作者在本窗口内点过刷新**，再怀疑 API 覆盖。

### 3B.3b 集成链路（模拟房主 → 真实客户端显示，2026-11-14）

`run-f1-integration.ps1`：启动带 `--simulate` 的 Agent（模拟房主，房间名默认
`CivLink-Test-Room-2222`，回复源自动探测出口接口 IP:62900）→ 注入真实 Civ6 →
提示操作者点 3 次刷新 → 轮询 `sent` → 收尾对账 → 断言 `hook.sent 增量 == agent.processed`、
`sim replied ≥ 1`、`pages == 22 × replied`、`sendFail == 0`、`bindFail == 0`。

```powershell
# 前置：Civ6 已启动并停在 局域网 列表；无残留 Agent 占用 34718；必须从中立目录运行
cd C:\Users\dd\Desktop\civlink-f1
powershell -NoProfile -ExecutionPolicy Bypass -File .\run-f1-integration.ps1 `
    -BinDir C:\Users\dd\Desktop\civlink-f1 -OutRoot C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures `
    -RefreshSeconds 150 -SimMaxReplies 10
```

**结果（2026-11-14）**：第一轮 PASS 9/9（3 次刷新，300 帧，3 socket 回复，66 页，
操作者口述"可以看到房间"）；第二轮/第三轮 void（90 s/150 s 窗口先于点击指令结束，
操作者时序问题，非产品故障）；第四轮 PASS 9/9（300 s 窗口，7 次刷新，700 帧，
7 socket 回复，154 页，操作者口述"第一轮和第四轮，我实际操作的时候都显示"）。
证据 `F1-integration-20261114-104235` 与 `-105026`；报告
`docs\F1-INTEGRATION-REAL-CLIENT-20261114.md`。

**复核（2026-11-14 codex，`docs/F1-INTEGRATION-REVIEW-20261114.md`）**：**限定通过**——
请求方向为 DLL 捕获 Civ6 发现请求并经 CVLH2 本机通道交给模拟房主 Agent；**回复方向是
Agent 从本次选定地址 `26.74.126.98:62900` 向游戏临时端口单播 fixture 公告，不经 Hook
回送，不是远端 Peer/Relay/真实房主**；源地址不证明任何远端可达性。REV-016 F1 两个子项
（观测、集成）记为「限定通过」；**批准开始 F2 非发布原型**（Fake-IP 会话映射 + 62056 数据面
模拟验证，继续用模拟 Peer，不需第二台 Civ6）。Gate A 未批准、正式 M0-B/Gate B 仍冻结。

> **F2 切换前置**：修改/重链 Hook DLL 前，须先对当前 Civ6 执行 `CivLinkShutdown` 保存
> 状态/计数回读，然后**正常退出 Civ6 并确认进程结束**（B2 审计运行模式下 DLL 保持映射，
> 进程存活时不能覆盖/重链），再构建并启动新测试进程。

> **教训**：驱动窗口必须覆盖"指令发出 + 操作者响应"的完整延迟；90 s/150 s 对人工操作
> 太短（中间轮次会占送达时间），300 s 才稳定成功。

### 3B.4 边界（强制）

- **允许**："Hook 在自检进程中挂住三个 API 并原样透传"；
  "发现端口载荷按 CVLH2 逐帧到达本机 Agent，两侧计数闭合、无序号缺口"；
  "在单台真实 Civilization VI (DX12) 客户端上，发现广播发送被 Hook 捕获 1400 次并逐帧到达 Agent"；
  "本构建下模拟房主（CivLink-Test-Room-2222）经 DLL→Agent 链路被真实客户端显示在房间列表，
  两轮 PASS（3/3、7/7 回复），操作者口述确认"。
- **不允许**："文明6 的发现已被接管"（自检是构造调用；集成链路是模拟房主+Agent 本机单播，
  从未改包、从未向远端发送）；"已实现发现转发 / 已能联机 / M0-B 可行 / Gate A 通过"；
  "Agent 已参与联机"；"真实双机发现已验证（E2-B/E3 未做）"；
  "回复经 Hook 回送 / 是远端 Peer / Relay / 真实房主"（实际是 Agent 从本机地址单播给
  游戏临时端口，不经 Hook 回送）。
- Agent 本阶段**只观测 + 本机 CVLH2 上行 + 对本机临时端口单播回复**，不向任何远端发送、
  不跨进程转发。
- F1 两个子项（观测、集成）均有机器+操作者证据，但只回答"真实客户端的发现发送是否
  经过这些 API、帧是否闭合、模拟房主公告能否经此链路显示"，**不**回答联机、
  不回答 E2-B、不移动任何 Gate。

### 3B.5 运行位置要求（Low IL 陷阱）

`C:\Users\dd\Desktop\injciv6-v0.3.3` 带
`Mandatory Label\Low Mandatory Level:(OI)(CI)(NW)`，会继承给其下所有 exe。
从项目树启动的程序因此运行在 **Low IL**，无法 `OpenProcess` 打开 Medium IL 的游戏进程
（表现为 `SeDebugPrivilege not granted` + `OpenProcess failed err=5`）。

**解法：把 `civlink_hook.dll` / `civlink_ctl.exe` / `civlink-agent.exe` / `hook_selftest.exe`
与脚本复制到中立目录（如 `C:\Users\dd\Desktop\civlink-f1\`）后在那里运行。**
不要用 UAC 自提权绕过——实测只会弹出 "Open File - Security Warning" 并卡住。

另注：DLL 注入后**保持映射直到游戏进程退出**（B2 审计运行模式），
因此其间无法重新 link `civlink_hook.dll`（`LNK1104`）。
只改控制器时用 `set CIVLINK_SKIP_DLL=1 && build-msvc.cmd` 复用已映射的 DLL。

### §3C F2 数据面（Fake-IP 会话映射 + 62056 观测，2026-11-14 完成 S1–S5）

> **F2 范围**：codex 裁定（docs/F2-DATAPATH-REVIEW-20261114.md）D1–D5 限定——
> Agent 不得 bind :62056、D4 最多 1 个 20B 本机探测、FakeEndpoint 候选段 127.0.127.1..100 仅内存、
> 观测不得吞包/改包。**Gate A 未批准、正式 M0-B/Gate B 冻结；本阶段全是模拟 Peer + 本机证据。**

- **S1 Agent `--simulate-datapath`**（agent 0.3.0）：`--bind-ip` fail-closed、回环自检强制 127.0.0.1、
  D4 一次性 20B 固定探测（`CVLD` 载荷）、七计数器。自检 PASS（F2-datapath-selftest-20261114-115013）。
- **S2 Hook DLL 扩展**（civlink_hook.dll 0.2.0-f2）：新增 bind/recvfrom/WSARecvFrom detour（纯观测，
  `WSA_IO_PENDING` 只记状态不读缓冲——探针证明挂起时内核重写整个 WSABUF 是 Windows 正常语义）；
  出向转发扩展 OBSERVED 帧（0x20）；分层计数 14 项（raw_*/bind62056/recvfromOn62056/cvlh2_*/channelDown）。
  机械自检 PASS（F1-selftest-20261114-121044，28+13 项）。
- **S3 `civlink-fakeip` crate**（0.1.0）：FakeEndpoint 双向映射表，键含 session_id+logical_socket_id+
  socket_generation，127.0.127.1..100 纯内存池，发现期 TTL 600 ticks、IN_ROOM/IN_GAME 固定保留，
  17 项单测 + 7 变异全捕获（FAKEIP-SELFTEST PASS，result.txt EEF14395…）。
- **S4 机械自检**（F2-mechanical-selftest-20261114-124842，22/22 PASS）：hook_selftest 覆盖
  bind/recvfrom/WSARecvFrom/WSA_IO_PENDING canary + D4 正向（绑定 socket 发 62056 → reply sent 1）；
  Agent datapath 回环自检 + 分层对账（hook sent+observed == processed）。
- **★S5 真机"加入"观察**（docs/F2-S5-JOIN-REAL-CLIENT-20261114.md，证据 F2-S5-join-20261114）：
  点击加入后游戏 **bind 0.0.0.0:62056（F6 通配绑定）、经 WSASendTo 向房主:62056 发 8B 数据面出向帧**
  （payload 前 6 字节 `17 32 00 00 FF FF` 固定、后 2 字节变化），无响应时**指数退避重试**
  （+0.5/1/2/4/8/16/32/64/128s，观测 10 帧），期间对 62056 以 ~1.6M 次/秒忙轮询 WSARecvFrom
  （WSAEWOULDBLOCK 非重叠）；模拟房主按 D4 不回应 → 游戏停在"正在检索创建人信息"。
  **限定**：本机模拟、src=0.0.0.0 触发 D4 not_local 拒绝；真实双机路径不适用此限定。
  本实验不证明双机加入/对局/Relay RTT/H2/R1。
- **F2 数据面设计输入（S5 实测）**：数据面出向=8B 小载荷 + 指数退避重试（Relay 须在 0.5s 首窗响应）；
  游戏对 62056 忙轮询收包；F3/F4/F6 规范假设获本机证据支持。
- 构建：`vcvars64.bat` 后 `build-msvc.cmd`；产物哈希见 docs/F2-* 报告 §6。

### §3D F3 直连与 Relay 路径（模拟数据面对端，2026-11-14 五子项审计闭环）

> **F3 范围**：REV-016 §F3 + 规范 v2.1 §4.2 Design I（出向吞包）留 M0-B。本阶段为
> **loopback 模拟对端**原型（明文、无 Noise、无状态机），**全部证据不得宣传为联机验证**；
> Gate A 未批准、正式 M0-B/Gate B 冻结。F3 判据（设计 §5.2）分两半：分层计数对账 + **Hook
> 观测路径在 62056 忙轮询下不丢帧（后者归 M0-B 前后真机工作，见 v1.18 Gate 登记）**。

- **F3-A 直连转发**（agent `--forward-to`/`--forward-listen`，62056 护栏三重、发现帧 AND 语义、
  `skip rejected` 计数入恒等式）：`run-f3a-forward-selftest.ps1` 31 站点/35 次执行，采信
  `F3A-forward-selftest-20261114-155041`；审计闭环（F3A-REVIEW-5 通过，前置 F3A-REVIEW-4 有条件
  通过 6 项低已全落地）。文档 `docs/F3A-DIRECT-FORWARD-20261114.md`。
- **F3-B Relay 转发**（civlink-relay 0.1.0：20B CVLR 信封、fnv1a64 三方对账、fail-closed sender、
  62056 护栏、fatal→exit 3）：revision 3 68/68，采信 `F3B-relay-selftest-20261114-152821`；
  审计闭环（F3B-REVIEW-3 通过）。文档 `docs/F3B-RELAY-FORWARD-20261114.md`。
- **F3-C 退避语义**（S5 十帧 0.5×2ⁿ 时序 + F11/F12/F13 三负向对照）：26/26，采信
  `F3C-backoff-selftest-20261114-160454`（v3，F3-A 重建后转正）；审计闭环（F3C-REVIEW-3 通过）。
  文档 `docs/F3C-BACKOFF-20261114.md`。
- **F3-D 压力**（40,000×2 帧高压分层计数闭合：Agent 8,035==8,035、Relay 13,214==13,214）：
  采信 `F3D-pressure-selftest-20261114-151218`；审计 F3D-REVIEW 有条件通过 12 项、8 项转正
  条件全落地（含 Gate 登记，见 v1.18 修订记录②）。文档 `docs/F3D-PRESSURE-20261114.md`。
- **F3-E 故障注入**（23/23，采信 `F3E-fault-injection-selftest-20261114-163533`）：E-1 **fatal/exit 3
  真实用例**（对端退出→ICMP 10054→summary 先写盘→exit 3，F3B-REVIEW-3 E5 承接项）、E-2 对端
  退出无流量后 relay 存活+干净退出、E-3 relay 硬杀、E-4 通道 down 无伪应答；审计闭环
  （F3E-REVIEW.md 第一轮有条件通过 10 项必改 + F3E-REVIEW-2.md 修订复核通过）。
  文档 `docs/F3E-FAULT-INJECTION-20261114.md`。
- **REV-015 归档**（D1–D6 历史材料，`docs/REV-015-ARCHIVE-20261114.md`）：codex 未逐条裁定；
  执行顺序以 REV-016 为准（模拟夹具路线）；不替代裁定、不移动 Gate。
- **F4 发布候选**（REV-016 §F4）：`dist\civlink-beta-20261114\` 已复制中立目录
  `C:\Users\dd\Desktop\civlink-f4\`（agent 0.3.0 / relay 0.1.0，均支持 `--version`）；
  `check-f4-package.ps1` 自检全 PASS；**单机模拟房主验收已通过（2026-11-14，F4-BETA PASS 9/9，
  证据 `M0A\captures\F4-beta-20261114-174214`，`docs/F4-BETA-ACCEPTANCE-20261114.md`）**，
  产出只能标"模拟对端/发现助手测试版"，不得标"双人真实联机已通过"。


---

## 4. 实验 E2：建房 + 发现（拆分为 A/B，修 H6 取证）

> **进程重启要求（v1.2）**：E2-A 与 E2-B 之间，**两端都必须完全退出并重启 CivilizationVI**
> 再按新状态注入/不注入。不能在同一进程内从"A 注入"切到"双端注入"再切回。
> 原因：v0.4.4 的 `-u` 只停用 Hook 并结束日志会话，**DLL 保持映射直到进程退出**（B2 审计运行模式）；
> 同一进程重复注入会被重复注入检查跳过，且 **Hook 不会重新启用**。

> **E2 执行前置（v1.5，两端各做一次，缺一不可）**
>
> 1. **两端各跑 E0**，且都带 `-PeerIp`（对方的局域网地址）：
>    ```powershell
>    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\collect-baseline.ps1 `
>        -GameDir "<本机库>\steamapps\common\Sid Meier's Civilization VI" -Tag E2-A -PeerIp <对端IP>
>    ```
>    产出的 `interfaces.txt` / `routes.txt` / `firewall.txt` / `dlc.txt` / `lan-reachability.txt`
>    是 E1 遗留"接口归属未裁决"问题的**唯一可采信证据来源**。
> 2. **两端必须能互相 ping 通、且在同一可达网段**（`lan-reachability.txt` 中 `Test-Connection` 全 0 丢包、
>    `Find-NetRoute` 指向预期接口）。不满足则本轮 E2 无效，不得计入。
> 3. **抓包在"点刷新之前"启动**，两端同时。抓包脚本见 §1.4；`pktmon` 需管理员，必须用户手动点 UAC。
> 4. 两端 `CIVTRACE_TAG` 分别设为 `host` / `client`，便于日志对号。
> 5. **不改包**：E2 全程只做被动观测；受控改包属 M0-B。

### E2-A：被动基线（A 注入，B 不注入）

| 步骤 | 操作 |
|------|------|
| 1 | A 建房（注入，tag=host，记录 PID）；B 不注入（记录 PID） |
| 2 | B 点刷新；**两端完整抓包** |
| 3 | A 端日志：建房时是否立即 `bind ...:62900`（或其它端口）并开始 `recvfrom`——**房主发现监听端口以实测为准** |
| 4 | **H4 被动阶段**：Follow UDP Stream 提取 1104B JSON——房主地址在**源地址**还是**载荷字段**？完整保存 JSON 样本（多环境多台机器各存一份）。**不改包**（受控改包验证留 M0-B） |
| 5 | 结束：两端回主菜单 `-u` 停用 → **完全退出游戏** → 记录本轮 `PID/轮次/注入状态`，再进行 E2-B |

### E2-B：双端注入（A、B 都注入，看 B 端 socket 生命周期）

| 步骤 | 操作 |
|------|------|
| 1 | **两端重启游戏后**都注入（A tag=host、B tag=client，各自记录新 PID）；重复 E2-A 流程 |
| 2 | **B 端日志记录**：首包广播时刻 / 最后广播时刻 / select 调用与返回 / recvfrom 成功次数 / 最后一次房间响应时刻 / `closesocket` 时刻 |
| 3 | 计算（以 B 端本机 QPC 为主）：`T_window = t_closesocket − t_first_broadcast`；`T_response = t_first_response − t_first_broadcast`；最后一响应与关闭的时间差。**用 `scripts\analyze-h6-window.ps1` 自动算，不要手读日志**（见 §9） |
| 4 | 重复 10 次刷新，取分布；同时保留 Wireshark 网络时间戳做交叉验证 |

> **执行包**：完整前置检查、逐步命令、回传清单与失败模式见 `docs\E2B-EXECUTION-PACK.md`（v1.0）。
> 本节是判据定义，执行包是它的可执行化展开；两者冲突时以本节判据为准。

**判据**：F2 复证（1104B×多包 JSON）；H4 = JSON 是否携带地址字段（被动结论）；
H6 = 发现 socket 存活窗口分布（是否容纳 +20~50ms 中继 RTT——CivLink 可行性关键输入）；
E2-B 先做 E2-A，确认追踪不改变发现行为（审查 2.1）。

---

## 5. 实验 E3：加入 + 开局（F3/F4/F6 复证，H3 五分类裁决）

| 步骤 | 操作 |
|------|------|
| 1 | 两端都注入（A 建房 B 加入），全程完整抓包 |
| 2 | **H8/H2 素材**：两端日志找 62056 socket 创建参数（af/type/WSA_FLAG_OVERLAPPED）、`setsockopt`（SO_REUSEADDR / SO_EXCLUSIVEADDRUSE / 其它）、`bind 0.0.0.0:62056`（F6）、`bind` 顺序与返回值 |
| 3 | **F4 复证**：数据面 API 集、顺序（bind → 先收后发）、首包约 120B |
| 4 | **H3 五分类裁决（按结构化字段，不靠文本猜测）**：`scripts/analyze-trace.ps1 -H3` 输出——①`ov=yes` 是否出现（仅说明传入了 OVERLAPPED，不等于真异步）②`[WSA_IO_PENDING]` 是否出现（真 Pending）③`WSAGetOverlappedResult`/`WSAWaitForMultipleEvents`/事件对象（完成路径=事件）④`WSAIoctl SIO_GET_EXTENSION_FUNCTION_POINTER` 及解码出的 GUID（ConnectEx/WSARecvMsg 等旁路）⑤`CreateIoCompletionPort(...(sock))`/`GQCS`（IOCP 路径）。**五项全无 + 只有 `[WSAEWOULDBLOCK]` 轮询** = 纯非阻塞轮询成立（injciv6 同款，M0-B 前提最简） |
| 5 | 进对局 2~3 分钟，记录包速率/包长/方向分布（§10.3 R 实测素材；广播/单播分开统计） |
| 6 | 退出对局回主菜单，观察 `closesocket` 清理时序（H10），再停用（`-u`，DLL 保留映射） |

**判据**：H3 = I/O 模型归入五分类之一（含旁路路径排除）；H8 = 62056 socket 选项与数量清单。

---

## 6. 实验 E4：三人原生对照（三台电脑 + 三端抓包，五轮对照）

> **长期多人验证项，不属于 Windows + Steam + 双人首版 Gate。** 首版不宣称三人拓扑或三人以上支持；本节仅供未来扩大玩家数时参考。

**设备**：A/B/C 三台电脑，有线接同一交换机。**三端同时完整抓包**——交换机下 A 看不到
B↔C 单播，只抓房主会把 mesh 误判成星型（审查 2.2）。

> **轮间必须重启（v1.2，强制）**：五轮之间**每台机器都要完全退出并重启 CivilizationVI**，
> 不能在活动进程内切注入状态（v0.4.4 停用后 Hooks 不会恢复）。每轮开始前逐台记录
> `PID / 轮次 / 注入状态`，落进 `M0A\captures\E4-roundlog.txt`。

五轮角色对照（顺序随机化，配置固定）：

| 轮 | A | B | C | 目的 |
|----|---|---|---|------|
| 1 | 原生·建房 | 原生加入 | 原生加入 | 纯原生基线 |
| 2 | civtrace | 原生 | 原生 | 房主端注入影响 |
| 3 | 原生 | civtrace | 原生 | 玩家端注入影响 |
| 4 | 原生 | 原生 | civtrace | 第三方注入影响 |
| 5 | civtrace | civtrace | civtrace | 全员追踪对照 |

**H7 三端方向矩阵**（对局 2~3 分钟后，**逐台**从各自 Wireshark `Statistics → Conversations →
UDP` 统计 62056 流量后汇总）：

| 源\目的 | A(房主) | B | C |
|---------|---------|---|---|
| A → | — | A 端证据 + B 端证据 | A 端证据 + C 端证据 |
| B → | B 端证据 + A 端证据 | — | **B 端 + C 端证据**（A 端通常不可见） |
| C → | C 端证据 + A 端证据 | **C 端 + B 端证据**（A 端通常不可见） | — |

- B↔C 直发（B、C 两端都能证明）显著 > 0 → mesh（H7=mesh，CivLink 交换机设计天然支持）；
- 三端一致显示 B↔C≈0 且全走 A → 星型（H7=star）；
- **H11 结论措辞（只允许三种，审查 2.3）**：
  ①原生成功 + 注入失败 → 追踪环境可能影响行为，须定位（查轮 2/3/4 哪个角色触发）；
  ②原生失败 + 注入也失败 → 原生基线在该条件下失败，原因待排查（防火墙/AP 隔离/Steam
  会话/DLC 版本/接口优先级），**不得断言"游戏自身缺陷"**；
  ③原生成功 + 注入成功 → 当前条件下未复现三人问题。

---

## 7. 实验 E5：EOS 构建审计

> **长期兼容性验证项，不属于首版范围。** 首版仅支持 Steam；获得 Win64EOS 构建后再按本节验证，Steam 结果不能代替 EOS 证据。

有 Epic 构建才执行；同一套流程在 `Base\Binaries\Win64EOS` 重跑 E0/E1/E2-A/E3（可跳过 E4）。
**未测即标"未验证"——Steam 结果不得替代 EOS 验证**（规范 §11 E5）。

---

## 8. 观测指标采集对照表（规范 §10.5 落地）

| 观测项 | 采集来源 |
|--------|---------|
| 发现请求发送次数 / 收到响应次数 | `analyze-trace.ps1 -Discovery`（sendto 计数）+ Wireshark |
| 发现请求 → 响应时延 | **Wireshark 时间戳**（trace 有开销偏移） |
| 每 Peer 收发包数量与方向矩阵 | Wireshark Conversations（E4 三端汇总） |
| 每 socket 收发计数差 | trace 日志按 `s=0x…` 过滤累计（`analyze-trace.ps1 -Socket 0x…`） |
| 每分钟丢包率与延迟 P50/P95 | Wireshark io,stat（M0-C 起由中继六类计数器提供——I/O 图表不作丢包依据） |
| Socket 创建/关闭/映射变化计数 | trace 日志（含 gen 代次） |
| 每轮进程身份与注入状态 | **人工记录**：`PID / 轮次 / injected·stopped-but-mapped·fresh-restart`（v1.2 新增，验收意见 §2.2） |

---

## 9. 日志与抓包分析速查

```powershell
# 日志位置（CIVTRACE_TAG 按角色区分）
dir "$env:LOCALAPPDATA\CivLink\M0A\logs"

# 一键分析（推荐）
powershell -ExecutionPolicy Bypass -File scripts\analyze-trace.ps1 -Log <日志路径> -H3
powershell -ExecutionPolicy Bypass -File scripts\analyze-trace.ps1 -Log <日志路径> -Discovery
powershell -ExecutionPolicy Bypass -File scripts\analyze-trace.ps1 -Log <日志路径> -Socket 0x1a4

# E2-B / H6：发现 socket 存活窗口（T_window / T_response 逐轮 + 分布 + 中继 RTT 判定）
powershell -ExecutionPolicy Bypass -File scripts\analyze-h6-window.ps1 -Log <日志路径> -RelayRttMs 50
# 退出码：0=找到轮次；2=日志里没有广播（角色/时机不对）；3=文件不存在

# H6 分析器自身的回归测试（不需要游戏、不需要网络，20 条断言）
powershell -ExecutionPolicy Bypass -File scripts\test-analyze-h6.ps1

# 手工速查
Select-String -Path <日志> -Pattern "sendto .*dst=255\.255\.255\.255"      # 发现请求计数（一次刷新=100 条）
Select-String -Path <日志> -Pattern "WSA_IO_PENDING|ov=yes|SIO_GET_EXTENSION|CreateIoCompletionPort"  # H3 素材
Select-String -Path <日志> -Pattern "WSAEWOULDBLOCK" | Select-Object -First 30
```

**注意**：civtrace 只 hook 了 `sendto`/`recvfrom`/`WSASend*`/`WSARecv*`，
**普通 `send`/`recv` 未被 hook**。所以日志里搜 `recv` 只会命中 `recvfrom`/`WSARecv`/`WSARecvMsg`，
"搜 recv 没有结果"不等于"没收到包"，要看 `recvfrom`。

Wireshark：Conversations→UDP 方向矩阵（H7）；Follow→UDP Stream 提取 1104B JSON；
**I/O Graph 仅看速率形态，不作为丢包统计**（审查六）。

---

## 10. 交付物

按 `docs/report-template.md` 填写《M0-A 协议行为报告》：F 表复证（证据等级升级 D→C）、
H 裁决（H3 五分类/H4/H6/H7 三端矩阵/H8/H9/H10/H11）、R 实测（广播/单播分开）、
异常记录、数据清单（pcapng + trace 日志 + E0 基线目录）。

目录约定：
```
M0A\
├── baseline\    （E0 输出，每实验一个子目录）
├── captures\    （pcapng，命名 <实验号>-<角色>.pcapng）
├── logs\        （trace 日志副本，或直接引用 %LOCALAPPDATA% 原件）
└── reports\     （协议行为报告）
```

完成报告 → 更新规范 §2.1/§2.2 证据等级 → **Gate A 验收（规范 §11.1）** → 申请 M0-B。

> **README 版本对齐记录**：v1.2（2026-11-11）落实 REV-002 v0.4.4 验收强制项——
> `-u` 语义改为"停用 Hooks + 结束日志会话，DLL 保留映射至进程退出"；新增 §2.1
> 「停用与重启」；E1/E2/E4 加入进程重启要求与 `PID/轮次/注入状态` 记录要求。
> 工具验收结论见 `docs/reports/REV-002-ACCEPTANCE-v0.4.4.md`（限定 M0-A 审计运行模式，
> **非** Gate A 通过，M0-B 仍冻结）。
>
> **v1.4 修订记录（2026-11-11 20:35，依 `REV-002-E1-PCAPNG-REVIEW.md` 复核纠正）**：
> ①**IPv4 Identification 字节序**——pcapng 分析器 v1 用 `[BitConverter]::ToUInt16`（小端）读取，
> 得出"同轮不同端口 IP ID 递增 256"，并据此论证"每端口只发一个包"；按网络字节序重算后该数字不正确，
> **结论已作废**，改为 Radmin 接口 63108–63406 共 299 个**连续、无缺口无重叠**的 IP ID 段。
> ②**接口归属**——v1 称"广播统一经 Radmin VPN 网卡发出（/8 最宽前缀匹配）"并称"对 M0-B Relay 绑定是硬约束"，
> 复核指出样本内实际为 299 个 Radmin + 1 个 Hyper-V（轮1 端口 62900），且无路由表证据；两处表述**均已删除**，
> 改为"该主机该配置该次抓包的实测计数"，M0-B 绑定设计改由 E2 端到端 + 显式接口绑定实验决定。
> ③**解析器入仓**——原 `C:\Users\dd\Desktop\civlink-run\parse-pcapng.ps1` 位于仓外不可复核且含上述缺陷，
> 已退役；现行解析器 `scripts/analyze-pcapng-datagrams.ps1` v3（sha256 `DB4520DF…56C06`）与
> 逐数据报明细 `M0A\captures\E1-pcapng-datagrams.csv`（300 行 / 16 列，sha256 `EA5517CC…955A0BFD`）**已入仓**。
> ④**零回复的采信范围**——单机无房主窗口内的零回复仅为**该次实验的有限负向观测**，
> 不能证明房主在场时的回复路径（须 E2 重测）。
> ⑤**仍未关闭**：Gate A 未批准、M0-B 冻结（复核方明确）；E2/E3/E4 需第二/三台机器、E5 需 Epic 构建。
>
> **v1.5 修订记录（2026-11-11 20:48，依 `REV-002-E1-PCAPNG-REVIEW-2.md` 三项非阻断跟进）**：
> **N-1 时间戳精度**——解析器 v3 改为解析 IDB 的 `if_tsresol`（本文件未提供，默认 6 = 微秒，输出首行打印
> `if_tsresol = 6`），保留 **Int64 整数 tick**，CSV 增加 `FirstTick / LastTick / SpanTicks / SpanUs` 四列，
> 不再用浮点科学计数法表达微秒差。实测副本跨度分布 **0 tick×78 / 1 tick×216 / 2 tick×3 / 5 tick×2 / 14 tick×1**，
> **最大 14 µs**（轮1 端口 62900 的 8 副本 Hyper-V 身份）；此前"0.1–2 µs / 最大 ≤1 µs"表述**已更正**。
> **N-2 帧一致判据落地**——v3 对每条记录的捕获帧（不含 EPB 头/时间戳）计算 SHA256，逐身份断言
> `UniqueFrameHash == 1`，输出 `✅ 全部 300 个数据报身份：副本帧 SHA256 去重后 = 1`；"整帧字节一致"
> 由**断言实现**而非仅文字声称，他人可用同脚本复现。
> **N-3 撤回过度表述**——删除"63107 是缺失 IP ID"与"不同接口各自分配 IP ID 空间"两处（均未取证）；
> 改为"轮1 端口 62900 的**单个身份**显示 Hyper-V 源（172.27.112.1 / 00:15:5d:91:c3:2e，IP ID=59639），
> 其余 99 个显示 Radmin 源，其接口/源地址**差异原因未裁决**"，列为 E2 待观察项；两端 E2 均须保留
> 完整 pcapng + 接口清单 + 路由快照，**只报实测不归因**。
> **E2 授权（复核给出）**：两项 P1 关闭后可开始 E2-A/E2-B，无需等 N-1..N-3；但 E2 **不能替代** E3 的
> 62056 socket 归属，也**不能替代** E4 的三机 H7/H11。**Gate A 仍未批准、M0-B 继续冻结**；
> 若最多两台电脑，E4/H7/H11 在现行 v2.1 验收范围内仍不满足。
> **v1.6 修订记录（2026-11-11 21:00，E2 双机准备 + 三项 N 跟进）**：
> ①**E0 采集扩容**——`scripts\collect-baseline.ps1` 由 3 类输出扩到 **8 类**，新增
> `interfaces.txt`（ifIndex/status/alias/MAC/MTU/speed/IP+前缀/网关）、`routes.txt`（默认路由按
> Windows 优选顺序 + 全部 IPv4 路由，含 ifMetric/routeMetric/nextHop）、`firewall.txt`（三 profile
> 状态 + 相关规则 + 已启用入站 Block 规则）、`dlc.txt`（DLC 目录 + `appmanifest_289070.acf` 的
> buildid/StateFlags/LastUpdated）、`lan-reachability.txt`（`-PeerIp` 时的 ping/Find-NetRoute/tracert）、
> `summary.md`。脚本 sha256 `674E0AFD0C307A2EE4183911CDB6F52290ADD738CE5109F3529BB66AD99ADA6A`。
> ②**E2 执行前置（§4）**——两端各跑 E0 且带 `-PeerIp`、必须同网可达、抓包在刷新前启动、
> `CIVTRACE_TAG` 分 host/client、全程不改包。
> ③**解析器 v3 落地三项 N**（详见 `docs/reports/REV-002-E1-PCAPNG-REVISION-RESPONSE.md`）：
> `if_tsresol` 解析 + Int64 整数 tick + 逐身份 `UniqueFrameHash` 断言（300/300 通过）+
> 撤回"63107 缺失""不同接口各自分配 ID 空间"两处过度表述（改为"62500 单个身份接口/源地址差异未裁决"）。
> ④**本机 E0 实测（E2-A 待用）**：Windows 10 Pro 26100.4946（注册表 ProductName 仍为 Windows 10 Pro）、
> `buildid=26407122`、Steam 构建无 Win64EOS；默认路由优选顺序 WLAN(ifMetric=45,routeMetric=0) →
> Radmin VPN(ifMetric=1,routeMetric=9256) → ZeroTier(ifMetric=35,routeMetric=9999)；Radmin 的
> `AutomaticMetric=Disabled` 且度量被手工设为 1。
> ⑤**仍未关闭**：Gate A 未批准、M0-B 冻结；E4/H7/H11 需三台真实端。
>
> **v1.7 历史修订记录（2026-11-12 18:10；其中因果解释已被 REV-005 撤回）**：
> **后续更正**：下列历史记录中的“InterfaceMetric 根因”“ARP 首包机制”“Radmin 隧道不通所以必须中继”均不是现行结论。REV-005 撤回了 metric/ARP 因果；项目负责人确认两端 Radmin 客户端当时离线，因此也不能据旧探测推广出在线 Radmin 隧道必然不通或产品必须中继。现行范围及结论见 `docs/PROJECT-SCOPE-WIN-STEAM-2P.md` 与 `docs/reports/REV-012-REVIEW.md`。
> ①**E2-A 已完成并归档**〔v1.7 历史状态，现已更正：E2-A 仅部分完成；H4 当前样本已结案，双机条目仍未完成，见 §1.8 与 REV-013〕（`docs\reports\M0-A-协议行为报告-E2A-20261112.md`，sha256 `289F6080…FF6A68F`；
> 证据 `M0A\captures\E2-A-20261112\`，B 端回传 ZIP sha256 `3FA0E85E…E2A1C`，SHA256SUMS 24/24 核对一致）。
> ②**根因机制锁定（与 PC-B 端独立复核一致）**〔REV-005/REV-012 已撤回，本段仅存历史〕：`255.255.255.255/32` 每网卡各一条等价路由
> （RouteMetric 均 256），Windows 按 `InterfaceMetric` 最小者选出口；PC-B 的 Radmin VPN metric=1（手工
> Disabled）< WLAN=35（Enabled）→ 发现广播 99.8% 走 Radmin（`lanprobe`/`pktmon`/`netpath` 三层互证，
> 500 包 Radmin 499/WLAN 1，首轮 800 包全 Radmin）；WLAN 链路双向可用（跨机确证随机源端口 53787）；
> "首包 WLAN 穿透"机制 = ARP 邻居缓存为空时首包按 `192.168.31.0/24` 最长前缀走 WLAN，缓存建立后粘 Radmin
> ——即"房间时有时无"的物理机制。
> ③**方法学修订（强制）**：a) G2 判据若用于 Civ6 可比，**必须游戏本体发包**，不得用工具 bind 发包代替
> （G2 通过 ≠ Civ6 能发现）；b) 跨机时间戳差值**必须先 NTP 校准**再作延迟分析（实测 1.344s 为时钟不同步）；
> c) E2-A/E2-B 轮次间切换注入状态**必须完全退出并重启 CivilizationVI**（同 §2.1）。
> ④**Radmin 隧道实际不通**（独立发现）〔已撤回：两端客户端离线，不能推广为在线隧道不通或必须中继〕：ping 100% 丢包 / ARP Incomplete / tracert 绕公网默认路由
> （192.168.31.1→192.168.2.1→113.225.0.1→218.25.3.77），未走 Radmin 二层。 〔REV-012：该"必须立项中继"推论已撤回，在线 Radmin 场景未验证〕
> ⑤**E2-B 暂缓**〔已撤回：REV-012 批准按全新游戏进程执行 E2-B〕：原记"根因已锁定、有污染基线风险"。E3 62056 socket 归属、
> E4/H7/H11 三机、E5 Win64EOS 仍未关闭。**Gate A 未批准、M0-B 冻结**；不得把单机/VM/双机广播证据宣传为联机验证。

> **v1.10 修订记录（2026-11-13，依 REV-016 快速路线）**：
> ①**新增 §3A「F0 固定模拟房主夹具」**——不再等待第二台装有 Civ6 的电脑，改用"单台真实 Civ6 +
> 模拟房主"作为开发夹具；F0 交付四件（F0-run.cmd / F0-verify.ps1 / test-f0-verify.ps1 /
> F0-selftest.cmd），**唯一启动入口是 F0-run.cmd**。
> ②**机器可验证部分已完成**：F0-selftest.cmd 实测 replies=22/22 from_probe_port=22
> wrong_length=0、MACHINE CHECKS: ALL PASS (0 failures, 0 warnings)、F0-SELFTEST: PASS；
> 变异测试 17/17 PASS，证明校验器在篡改页内容、改页索引、BOM-only 错误日志、超预算、
> 缺文件、零响应六类场景都真的报错。
> ③**未完成部分只有人的那一步**：负责人跑 F0-run.cmd 后在游戏内连续刷新 20 次、每次看到
> CivLink-Test-Room-2222，并回传 verify-report.txt 与逐次记录。
> ④**表述边界（强制）**：F0 通过 = "模拟房主按设计工作、公告页逐页可校验"，
> **不等于**两台真实 Civ6 对局，不是 E2-B、不是 M0-B，不移动任何 Gate；
> 允许表述为"本构建客户端在本机合成响应条件下接受该公告并显示列表项"。
> ⑤旧 M0-A 真实双机证据（E2-A/E2-B/E3）仍为待验证，模拟测试不能勾掉它们；
> DLL 绑定矩阵、Design I ≥1000 次确定性投递、Hook API 覆盖仍是发布前门槛。

> **v1.11 修订记录（2026-11-14，F0 真机回归已执行）**：
> ①**人力步骤已完成**：真实 Civ6（`CivilizationVI_DX12`）停在局域网列表作客户端，responder
> 预算 20 / 突发窗口 3 s，00:04:19–00:08:28 收到并响应 **20/20** 次刷新，00:08:58 自然收尾；
> 证据目录 `M0A\captures\F0-run-20261114-000141`，`F0-verify.ps1` → **ALL PASS
> (0 failures, 0 warnings)**，逐块断言 20 个 RESPONSE（22 页 / 顺序 / 1 104 B / 源端口 / 摘要）。
> ②**新观察一（F1 必须考虑）**：客户端不只"点刷新才发"。`post-response-traffic.log` 按 500 ms
> 聚类得 **27 组突发**（跨度 82–112 ms）：20 组 99 包（触发响应的那些）、7 组 100 包（未触发）；
> 20×99 + 7×100 = 2 680 = summary 的 post-response 计数。7 组间隔 2.40/2.49/2.57/2.48/2.89/2.62/4.13 s，
> 前 6 组落入 3 s 窗口记 `coalesced`（2 481 条），第 7 组预算已尽记 `budget exhausted`（199 条），
> 二次对账吻合。→ **计数闭合必须按"每次突发"对齐，不能按"每次用户操作"对齐**，也不能假设
> 两次刷新之间无流量；约 2.5 s 补发整组与"客户端重试"相符，但**不足以区分**重试与用户连点，
> 不得写成结论。
> ③**新观察二**：机器侧 20/20 全收到并全回，但操作者口述"有时看得到、有时看不到"。机器只能
> 证明"请求被收到、22 页被发出"，**不能**证明客户端是否把公告画进列表；两者不冲突也不互相否定。
> 待验证假设＝客户端对同一房间公告的处理/去重带时序敏感性；**未验证，不得写成结论**；
> F1 需同时记录"客户端收包时刻"与"列表项出现/消失时刻"。
> ④**结论降级（强制）**：F0 记为"**夹具与证据链通过，客户端可见性未逐次确认**"；
> 不得表述为"20 次刷新每次都看到了房间"。详见 §3A.6 与
> `docs/F0-FIXTURE-BASELINE-20261113.md`。>
> **v1.12 修订记录（2026-11-14，F1 机械链路接通）**：
> ①**新增 §3B「F1：Hook + Agent 本机发现链路」**——在 F0 夹具之上，真正的产品侧 DLL 与独立 Agent
> 首次跑通。交付 `civlink_hook.dll` / `civlink-agent.exe` / `civlink_ctl.exe` / `hook_selftest.exe`
> 四件，源码在 `CivLink-M0A-audit\civlink\`（`/MT` 静态 CRT，MinHook v1.3.4 pin，x64）。
> ②**本机 IPC 帧（CVLH2）已定稿并实现**：42 字节头 + 载荷，含 `seq` / `session_id` /
> `logical_socket_id` / `socket_generation` / 双向标记 / flags / `payload_len`（上限 1280）；
> `logical_socket_id` 不使用 SOCKET 句柄值（句柄会复用）。
> ③**机械自检 PASS（可重复）**：`run-f1-selftest.ps1` → `HOOK-SELFTEST: PASS (0 failure(s))` 23/23、
> Agent `received 4 (processed 3, rejected 1)`、`hook.sent (3) == agent.processed (3)`、
> `seq gaps=0`、`F1-SELFTEST: PASS`。**自检证明的是"透传正确 + 计数闭合"**：
> 返回值与 last error 原样（`4/4/4/1400`）、超长不静默截断（改发 notify 帧）、
> shutdown 后计数不再增长。
> ④**首跑两处真缺陷已修**（保留记录）：未绑定 socket 的 `getsockname` 返回 `0.0.0.0:0`
> 曾被当作有效端点缓存 → 改为"未绑定不算已知、下一帧重试"；驱动端口断言写死 `127.0.0.1`
> 漏掉广播帧 → 改 `([\d.]+)` 并**新增**"首帧必须是广播地址"断言。
> ⑤**真实客户端观测（F1-live）已在次轮执行并通过**——见文末 v1.13 修订记录；
> 本轮仅交付脚本 `run-f1-live.ps1`（启动 Agent → 注入 → 轮询计数 → 提示点刷新 → 收尾对账）。
> ⑥**表述边界（强制）**：F1 机械证据**不等于**"文明6 发现已被接管"，更不是联机 / E2-B /
> Gate A 结论；Agent 本阶段**只观测不转发**，不向任何远端发送。详见 §3B 与
> `docs/F1-HOOK-AGENT-MECHANICAL-20261114.md`。

> **v1.13 修订记录（2026-11-14，F1-live 真实客户端执行）**：
> ①**§3B.3 状态改为"已执行并 PASS"**——单台真实 Civ6（pid 46368）注入后，操作者点刷新期间
> 捕获 **1400 次发现发送（14 组 × 100 包）**，Agent 收到 1400 帧，`hook.sent 1400 ==
> agent.processed 1400`，`sendFail 0`、`rejectOversize 0`、`seq gaps 0 duplicates 0
> out_of_order 0`、目标端口覆盖 62900–62999 全部 100 个、`via_wsasendto=0`（全部走
> `sendto`）。游戏进程保持 `Responding=True`。证据 `M0A\captures\F1-live-20261114-092257`。
> ②**新增 §3B.5「运行位置要求（Low IL 陷阱）」**——项目目录树的
> `Mandatory Label\Low Mandatory Level` 会继承给 exe，使 `civlink_ctl.exe` 跑在 Low IL
> 而无法 `OpenProcess` 打开 Medium IL 的游戏（`err=5`）。必须从中立目录运行；
> **不要用 UAC 自提权绕过**（实测只弹 "Open File - Security Warning" 并卡住）。
> 另记：DLL 注入后保持映射至游戏退出（B2 审计运行模式），期间无法重 link DLL，
> 只改控制器时用 `set CIVLINK_SKIP_DLL=1 && build-msvc.cmd`。
> ③**两个新设计输入（F2 前必须处理）**：每次刷新都用**全新 socket**
> （14 次刷新 = 14 个 logical_socket_id + 14 个不同临时源端口，发完 100 包即关闭）。
> 会话表必须以"刷新"为单位，不能假设 socket 长期存活；每个 socket **首帧
> `src=0.0.0.0:0` 属预期**（未绑定，`getsockname` 返回端口 0），`src unknown` 恰等于 socket 数。
> ④**修掉证据字段污染**：`civlink_ctl inject` 曾把 DLL 模块基址当作 `session=` 打印
> （与 Agent 的真实 `session=0xb557b20a47f6` 混淆），已分离为 `dll base` 与指向 `counters` 的提示。
> ⑤**排除一个误判**：首窗口 153 s 收到 0 个数据报，原因是**窗口早于操作者开始点击刷新**
> （Agent 时间戳为 UTC：`01:22:24` = 北京时间 `09:22:24`），不是 Hook 未覆盖 API。
> ⑥**未观察到 F0 记录的 ~2.5 s 自动重发**（本轮 13 个间隔全部 ≥ 4.878 s），
> 但**无法区分**"这次点得慢"与"自动重发只在特定条件下发生"，不得据此否定 F0 观察。
> ⑦**复核后更正（codex 2026-11-14）**：①该轮证据只算「真实客户端 Hook→Agent 观测子项通过」，
> **F1 集成链路未通过**（模拟房主未接入、Agent 未转发）；②收尾时序澄清——`counters-after.txt`
> 是采集结束瞬间（running:1）抓的，shutdown 之后单独执行；复核后已把
> `shutdown-evidence-20261114-100926.txt`（sha256 `5106B6DD…`，事后 status=-1 / counters
> running:0 shutdown:1 in-flight:0）补入证据目录，见报告 §4.4。
> 详见 `docs/F1-LIVE-REAL-CLIENT-20261114.md`（现 sha256 `94C716BA…`）。
> **v1.15 修订记录（2026-11-14，F1 集成链路通过）**：
> ①**§3B.3 状态更新**——复核边界改为"观测子项 + 集成链路子项均通过"；新增 **§3B.3b
> 「集成链路（模拟房主 → 真实客户端显示）」**：run-f1-integration.ps1 启动带
> --simulate 的 Agent（模拟房主 CivLink-Test-Room-2222，回复源出口接口 IP:62900）
> 并注入真实 Civ6。第一轮 PASS 9/9（3 次刷新，300 帧，3 socket 回复，66 页，
> 操作者口述"可以看到房间"）；第二轮/第三轮 void（90 s/150 s 窗口先于点击指令结束，
> 操作者时序问题，非产品故障）；第四轮 PASS 9/9（300 s 窗口，7 次刷新，700 帧，
> 7 socket 回复，154 页，操作者口述"第一轮和第四轮，我实际操作的时候都显示"）。
> ②**教训**：驱动窗口必须覆盖"指令发出 + 操作者响应"的完整延迟（90 s/150 s 对人工
> 操作太短，300 s 才稳定成功）。
> ③**§3B.4 边界更新**：允许列表增加"模拟房主经 DLL→Agent 链路被真实客户端显示"；
> 不允许列表增加"真实双机发现已验证（E2-B/E3 未做）"；Agent 定位改为
> "只观测 + 本机回环注入，不向远端发送、不跨进程转发"。
> ④**新报告** docs/F1-INTEGRATION-REAL-CLIENT-20261114.md；证据
> F1-integration-20261114-104235（PASS）与 -105026（PASS），void 轮次
> -104534/-104723 如实记录于报告 §3。
> ⑤F1 两个子项（观测、集成）均已覆盖；仍非联机 / E2-B / Gate A 结论；下一步按
> REV-016 进入 F2（Fake-IP + 62056 数据面），F2 设计输入已在 3B.3/3B.3b 与交接文件记录。
> **v1.16 修订记录（2026-11-14，F1 集成复核「限定通过」+ F2 批准）**：
> ①**§3B.3b 追加复核结果**——codex 裁定（docs/F1-INTEGRATION-REVIEW-20261114.md）：
> REV-016 F1 两个子项（观测、集成）记为「限定通过」；准确路径澄清：请求方向为 DLL 捕获
> Civ6 发现请求并经 CVLH2 本机通道交给模拟房主 Agent，**回复方向是 Agent 从本次选定地址
> 26.74.126.98:62900 向游戏临时端口单播 fixture 公告，不经 Hook 回送，不是远端
> Peer/Relay/真实房主**；源地址不证明任何远端可达性。机器校验不读取游戏 UI，
> 房间可见性按负责人观察采信（m14428、m14466）。
> ②**§3B.4 边界修正**——不允许列表增加"回复经 Hook 回送 / 是远端 Peer / Relay / 真实房主"；
> Agent 定位改为"只观测 + 本机 CVLH2 上行 + 对本机临时端口单播回复"。
> ③**批准开始 F2 非发布原型**（Fake-IP 会话映射 + 62056 数据面模拟验证，继续用模拟 Peer，
> 不需第二台 Civ6）；Gate A 未批准、正式 M0-B/Gate B 仍冻结。
> ④**F2 切换前置**：修改/重链 Hook DLL 前须先 CivLinkShutdown 保存状态/计数回读，
> 再正常退出 Civ6 并确认进程结束（B2 审计运行模式下 DLL 保持映射，进程存活时不能覆盖/重链）。
> ⑤头部「当前有效状态」更新为含 F1/F2；执行报告
> docs/F1-INTEGRATION-REAL-CLIENT-20261114.md 已同步修正表述（sha256 7D9D5DD7…）。
> **v1.17 修订记录（2026-11-14，F2 S1–S5 完成）**：
> ①新增 §3C「F2 数据面」小节（S1 Agent --simulate-datapath / S2 Hook DLL 扩展 /
> S3 civlink-fakeip crate / S4 机械自检 / S5 真机"加入"观察）。
> ②S5 实测发现：点击加入后游戏 bind 0.0.0.0:62056（F6）、经 WSASendTo 向房主:62056 发
> 8B 数据面出向帧（payload 前 6 字节 17 32 00 00 FF FF 固定、后 2 字节变化），无响应时
> 指数退避重试（+0.5/1/2/4/8/16/32/64/128s 共 10 帧），期间 ~1.6M 次/秒忙轮询 WSARecvFrom；
> 模拟房主按 D4 不回应 → 停在"正在检索创建人信息"。限定：本机模拟，不证明双机加入/对局。
> ③F3/F4/F6 规范假设获本机证据支持；新设计输入：Relay 须在 0.5s 首窗响应。
> ④证据 docs/F2-S5-JOIN-REAL-CLIENT-20261114.md（sha256 见文件 §6）；报告
> docs/F2-DATAPATH-SIMULATED-PEER-20261114.md（设计 v0.2）与提交件
> docs/F2-DATAPATH-SUBMISSION-20261114.md 保持不变。
> ⑤Gate A 未批准、正式 M0-B/Gate B 冻结；F2 全部为模拟 Peer + 本机证据，不得宣传为联机验证。
> **v1.18 修订记录（2026-11-14，F3 直连/Relay 四子项完成，F3-D 审计登记）**：
> ①新增 §3D「F3 直连与 Relay 路径（模拟数据面对端）」（F3-A 直连转发 31 站点/35 次、
> F3-B Relay 68/68、F3-C 退避 26 项、F3-D 40,000 帧压力），全部 loopback 模拟证据。
> ②**Gate 登记（F3D-REVIEW 第⑧项转正条件）**：设计 §5.2 的 F3-D 判据
> 「62056 忙轮询 ~1.6M/s 下 **Hook 观测路径不丢帧** ｜ 分层计数对账」——本轮 F3-D
> **只完成后半句（分层计数在高压下闭合）**；前半句（Hook detour 在真实游戏进程内、
> 每秒百万次 WSARecvFrom 下不丢帧）**仍属未验证**，归 M0-B 前后真机工作，不得因
> F3-D PASS 视为已勾掉。此登记同时进入 CODEX-HANDOVER 与 F3D-PRESSURE 文档。
> ③F3-A/F3-C/F3-D 证据在项目根 `M0A\captures\`，F3-B 证据在审计树
> `CivLink-M0A-audit\M0A\captures\`（两棵 M0A 树并存，见 F3B-REVIEW-3 E2）。
> ④Gate A 未批准、正式 M0-B/Gate B 冻结；F3 全部为模拟对端 + 本机证据，不得宣传为联机验证。
> **v1.19 修订记录（2026-11-14，F3 五子项审计闭环，F4 发布包就绪）**：
> ①**F3 五子项审计闭环**：F3-A 直连转发（第五轮通过，F3A-REVIEW-5）、F3-B Relay
> （第三轮通过，F3B-REVIEW-3）、F3-C 退避（第三轮通过，F3C-REVIEW-3）、F3-D 压力
> （F3D-REVIEW 修正落地 + Gate 登记，见 v1.18）、F3-E 故障注入（F3E-REVIEW.md 第一轮
> 有条件通过 10 项必改 → 修订落地 → F3E-REVIEW-2.md 复核通过）——详见新增 §3D。
> ②F3-E 四场景：E-1 fatal/exit 3、E-2 对端退出无流量后 relay 存活 + stop-file 干净退出、
> E-3 relay 硬杀（Gone=True）、E-4 通道 down 无伪应答；23/23 断言，证据
> `M0A\captures\F3E-fault-injection-selftest-20261114-163533`（16 文件 + E4/ 空目录）。
> ③**F4 发布候选**：`dist\civlink-beta-20261114\`（agent/relay 已加 `--version`；
> agent 0.3.0 = 93F17516…，relay 0.1.0 = 9E323F81…），`check-f4-package.ps1` 自检
> **全 PASS（14 项检查，含版本检测/62056 负向护栏/哈希/非平凡体积）**，包已复制中立目录
> `C:\Users\dd\Desktop\civlink-f4\`；单机验收（需真实 Civ6 点刷新）待用户排期。
> ④**REV-015 归档**：`docs/REV-015-ARCHIVE-20261114.md`——D1–D6 裁定请求整理为历史
> 材料（codex 未逐条裁定；REV-016 已以模拟夹具路线取代"等第二台电脑"的执行顺序；
> E2-A/E2-B/E3 真实双机仍待验证）。
> ⑤Gate A 未批准、正式 M0-B/Gate B 冻结；F3/F4 全部为模拟对端 + 本机证据，不得宣传为联机验证。
>
> **v1.20 修订记录（2026-11-14，F4 单机模拟房主验收通过）**：
> ①**F4-BETA PASS（9/9 断言）**：真实 Civ6 客户端（pid=48664，DX12）在局域网大厅三次刷新，
> Hook 捕获发现广播 300 帧（每次刷新 100 帧，seq 连续无缺口）→ Agent 模拟房主应答 3 个刷新
> socket、每 socket 22 页公告（pages=66 == 22×replied，页 1104B 与 fixture 一致）；数据面 join
> 尝试 9 个 dst=62056 帧被观测不改（Agent 不 bind 62056、D4 reply sent=0）；干净收尾
> CivLinkShutdown exit=0（clean drain，B2 审计运行模式 DLL 保持映射）；分层对账闭合
> hook.sent 300 + observed 9 == agent.processed 309。证据
> `M0A\captures\F4-beta-20261114-174214`（39 文件，身份表见验收文档 §6）；首跑
> `-173307` FAIL 4 项为脚本断言/正则缺陷（锚旧标签/缺 observed 对账项/62056 误判/无 UTF-8 BOM
> 致 label 中文乱码），产品行为正确，修复后重跑采信。验收文档
> `docs/F4-BETA-ACCEPTANCE-20261114.md`；审计见 `docs/F4-BETA-REVIEW.md`。
> ②**发布边界（如实声明）**：本验收为单机模拟对端/发现助手测试版，**NOT 双人真实联机**；
> 不证明双机发现/加入/对局、Relay RTT、H2/R1 绑定语义、Noise 加密、跨网、长稳；
> 不得据此勾掉 E2-A/E2-B/E3，不移动 Gate A/B。
> ③**审计闭环（F4-BETA-REVIEW，有条件通过）**：必改 1 项 H1=验收文档 §5 两值转录错位
> （raw bind 4→1、state queries 2→3，值 4/2 出自首跑与 before 文件），已修正；
> 独立重算 A1-A4/B1-B6/C1-C3/D1-D3 全 PASS（39/39 文件全 64 位哈希逐项吻合、
> 300+9==309 成立、无双人真实联机正面宣称）；报告 `docs/F4-BETA-REVIEW.md`。
>
> **v1.21 修订记录（2026-11-15，F5 LAN 模拟房主完成 + 双机核验包就绪）**：
> ①**F5（REV-016 双机发现路径）**：Agent 新增 `--sim-lan-listen IP`（LAN 模拟房主）——
> 绑定 0.0.0.0 上全部发现端口 62900..62999，直接接收 Civ6 客户端发现广播（magic 8D-E8-FC-70），
> 从 `<ip>:62900` 应答 22 页 fixture；不依赖原生广播选路/接口 metric/防火墙手工放行。
> 三类机械证据全 PASS：回环自检 12/12（`F5-lan-selftest-20261114-192000`）、真实广播
> 22/22（`F5-lan-broadcast-selftest-20261115-b`/-c，客户端侧 22 页 24,288B 逐字节留存）、
> B 侧探测机械验证（`F5-bprobe-mechanical-20261115`）。文档 `docs/F5-LAN-SIMULATED-HOST-20261115.md`；
> 审计闭环（F5-LAN-SIMULATED-HOST-REVIEW.md 有条件通过→必改 4 项修正→REVIEW-2 复审通过）。
> ②**双机核验包**：`C:\Users\dd\Desktop\civlink-f5-kit\`（agent 194E6E8A…/404,992B、
> run-f5-b-probe.ps1 FF4DDF3F…、run-f5-dualmachine-a.ps1 D909D16F…、PC-B-操作单.md），
> B 机一次性核验（UAC 一次机械探测或直接 Civ6 局域网刷新看 `CivLink-Test-Room-2222`）。
> ③**civinject 版本统一审计通过**（`docs/CIVINJECT-UNIFY-REVIEW.md`）：三处 civinject.exe
> 54627EAB…/171,520B 一致、备份两处齐全、字节级差分证明新旧版仅 COFF 构建时间戳不同；
> E2 双机验证可直接用当前三处二进制。
> ④**边界（如实声明）**：F5 覆盖**模拟房主→真实客户端**跨机发现链路；**不证明**双人真实对局、
> E2-B 双端注入、62056 数据面、Relay RTT、Fake-IP、Noise、跨网/长稳；不得据此勾掉
> E2-A/E2-B/E3，不移动 Gate A/B（Gate A 未批准，M0-B 冻结）。
>
> **v1.22 修订记录（2026-11-15，F5 单机真实客户端验证 + DLL 稳定性准备材料 + GUI）**：
> ①**F5 单机真实客户端验证 PASS**（方案 C，用户 m19535 选定）：A 机 agent
> `--sim-lan-listen 0.0.0.0`（600s 窗口、fixture-reply-set、房名 CivLink-Test-Room-2222），
> 同一台机器真实 Civ6 大厅点刷新 → 用户两次口述确认看到房间；agent summary
> requests seen=100/replied=1/pages=22/失败全 0/exit 0；证据
> `M0A\captures\F5-singlehost-20261115-1235`（30 文件，summary sha256 A6892BB0…）；
> F5 文档补 §3.4（E860914F02B5296383576AA0F1C5278460E9A32E11CE9785209F5631DA7010C8，155 行）。B 机核验包（§4）保留用于最终双机确认。
> F5 文档再补 §3.5 跨机核验（1EFC475193013A5AA10369838632AD2734C5E3275152463F85D03058567784FE，181 行）：
> **B 侧（VM + Radmin VPN 同房间）2026-11-15 23:33 跑 run-f5-b-probe.ps1 → `F5-B-PROBE: PASS (4 checks)`**，
> 应答源 26.74.126.98:62900（A 机 Radmin 接口），证据 `M0A\captures\F5-dualmachine-20261115-pcb3\b-side-probe-out\`（24 文件）
> ——模拟房主→跨机客户端发现链路验证通过；VMware 桥接广播双向不通、Radmin VPN 通道可用（详见 v1.23 修订记录）。
> ②**M0-B 准备材料：DLL 注入稳定性观察**（`docs/M0B-PREP-DLL-STABILITY-20261115.md`）：
> civlink_hook.dll 注入真实 Civ6 DX12（pid 12420），60s×5 采样点：sent 100→500
> 全部转发成功（cvlh2 ok==try）、所有失败计数 0、62056 忙轮询 3.88M 次收包稳定、
> 内存 12:52 后 3.70–3.71GB 平稳；**性质声明：M0-B 准备材料非验收，不勾 Gate A/B，
> 不证明双人联机/62056 转发正确性**。证据 `M0A\captures\M0B-prep-stability-20261115\`
> （inject-hook.txt/samples.csv）。
> ③**控制端 GUI v0.1.0-gui**：C# WinForms `civlink\ctl\civlink_ctl_gui.cs` →
> `civlink_ctl_gui.exe` A0EB830B…/8,704B，封装 ctl inject/status/counters/shutdown +
> 进程探测，部署 `C:\Users\dd\Desktop\civlink-gui\`（与 ctl/hook 同目录）提权运行。
> ④**边界**：①②均不构成 M0-B 验收或双人真实联机证据；E2-A/E2-B/E3 仍待 PC-B
> 在线执行；Gate A 未批准、M0-B 冻结维持。

> **v1.23 修订记录（2026-11-16，F5 跨机核验 PASS——Radmin VPN 通道）**：
> ①**跨机核验完成**：2026-11-15 23:33，B 侧（VM + Radmin VPN 同房间，装
> civlink-f5-kit）跑 `run-f5-b-probe.ps1` → **`F5-B-PROBE: PASS (4 checks)`**
> （burst 100 sent / 22 pages × 1104 B 收到 / head 59 60 69 9B / room
> `CivLink-Test-Room-2222`）；应答源 `26.74.126.98:62900`（A 机 Radmin 接口）
> ——跨机发现链路铁证；证据 `M0A\captures\F5-dualmachine-20261115-pcb3\b-side-probe-out\`
> （24 文件，result.txt EBAB7833…）；F5 文档 §3.5 登记（新哈希
> 1EFC475193013A5AA10369838632AD2734C5E3275152463F85D03058567784FE，181 行）。
> ②**替代通道结论**：VMware 桥接 255.255.255.255 广播双向不通（VM 不可作第二台
> 机器）；**Radmin VPN 同房间可用**（虚拟网卡支持广播转发）——回答了 m20096。
> ③**A 侧计数缺口**：该窗口 agent 未写 summary（捕获脚本缺陷+主 socket 提前退出
> 路径，与 2126/2130 同症状），以 B 侧证据为准；用户决定不修复。
> ④**边界**：模拟房主→真实客户端**跨机发现链路**验证通过；不证明双人真实对局/
> E2-B/62056/Relay RTT/Fake-IP/Noise/跨网长稳；不勾 E2-A/E2-B/E3；Gate A 未批准、
> M0-B 冻结维持。

> **v1.24 修订记录（2026-11-16，★F5 真实双机核验 PASS——真实物理机 + 真实客户端可见）**：
> ①**真实双机核验 PASS**：2026-11-16 16:58:23，B 机为**真实第二台物理机**（非 VM），
> 跑 `run-f5-b-probe.ps1` → **`F5-B-PROBE: PASS (4 checks)`**；应答源
> `192.168.31.60:62900`（A 机 **WLAN** 接口）——走真实同 WLAN 局域网广播路径
> （§3.5 是 Radmin 隧道，本轮是 WLAN，更贴近"同 WLAN 双机"目标）。
> ②**逐字节对账**：B 侧 22 页 vs A 机 `lan-page-01..22.bin` → **22/22 完全一致**；
> vs fixture 每页仅 21 字节差异且全部落在 24..45（房名匿名化，预期内）。
> ③**真实 Civ6 客户端可见**：B 机真实客户端 多人→局域网→刷新，大厅出现
> `CivLink-Test-Room-2222`（**用户口述确认**，记录 `real-client-visibility-oral.txt`
> F6658EF6…，等级=口述确认，无截图/抓包，与 §3.4 同级；该文件已按复审必改项
> 删除无工件支撑的 PID 并留「更正（审计 F-1）」注，边界段补「不勾 E2-A/E2-B/E3、
> 不移动 Gate A/B」（R3-3））。
> ④**A 侧完整计数首次拿到**：1800.2s 窗口自然到期（**未走编排脚本，故未留存
> `exit.txt`/`agent-pid.txt`，不宣称退出码与 PID**；到期由 `summary.txt` mtime
> `2026-11-16 17:22:53`（精确 `17:22:53.177` = 起点 `16:52:52.977` + 1800.2s，差
> 0.177s 为向下取整到秒；R3-2）佐证），`summary.txt` B6D00F8E…
> ——`requests seen`=**384**（分解 `100×3+84` 属**推断**，证据只有总数与 4 个应答源）、
> `replied sockets`=**4**、`pages sent`=**88**（恒等式 `88 == 4×22` 成立）、
> `send fail`/`no endpoint`/`max reached`/`bind fail` 全 0（据 `bind fail=0`
> **推断** 100/100 端口绑定成功，本轮未单独留存绑定清单）；CVLH2 `datagrams`=0
> （LAN 广播不走 CVLH2 通道，符合设计）。
> ⑤**通道无关性（回答原始 Radmin metric 问题，附适用域）**：A 机 Radmin metric=1
> < WLAN metric=45（故 Radmin 优先级**高于** WLAN），但本路径不受影响——agent 在每个
> 发现端口全接口 bind（`main.rs:544-556`），客户端广播从任一接口到达都能收到，应答按
> 观测 `(ip,port)` `send_to(page, from)` 单播回发（`main.rs:636-674`）；**故 F5 不依赖
> InterfaceMetric**。适用域限定：本轮 A/B 同一 on-link 网段（192.168.31.0/24），metric
> 本不参与该路径选路，属"结果级支持"；入站可达性由 B 侧实收 22 页证实，但防火墙规则
> 来源未逐条取证；不得外推到 62056 数据面。
> ⑥证据：`M0A\captures\F5-dualmachine-20261116-realmachine\`（`b-side-probe-out-real\`
> **25 文件** = 24 个探针产物 + `MANIFEST-sha256.txt` 自身 A754E417…，清单
> `total_bytes`=24,909 可还原；§3.5 的"24 文件"口径不含清单，勿混比）+ 父目录
> `real-client-visibility-oral.txt` F6658EF6…/2,167B + `summary.txt` B6D00F8E… +
> `frame-log.txt` 9BD9FD25…）；
> F5 文档 §3.6 登记（当前哈希
> B96DC3DEFC6C5D238DA3BE538E75E1A4A1907E9FB91D522E3685E235ECB78FDE，260 行；
> 其前版 B9D7F592…、3CD4F0EE…、879A1A80…、965271E8… 均系审计前版本，已作废）。
> ⑦**边界**：模拟房主→真实客户端**跨机发现链路 + 客户端可见性**验证通过；仍
> **不证明双人真实对局**（未建房/加入对局、未验 62056 数据面）、不证明 E2-B/E3、
> 不证明 Relay RTT/Fake-IP/Noise/跨网长稳；模拟房主有意不响应"检索创建人信息"
> （D4 约束），B 机点入房间停在检索页属预期；不勾 E2-A/E2-B/E3；Gate A 未批准、
> M0-B 冻结维持。
> **v1.25 修订记录（2026-11-17，civtrace v0.4.5 日志限流修复闭环 + B1 真实广告页捕获）**：
> ①**v0.4.5 日志爆盘修复（审计闭环）**：civtrace 31 Hook 无条件 Emit + 62056 忙轮询
> ~1.6M/s 导致单轮日志 15.4GB（C 盘爆盘，b460 根因）→ 新增 per-socket 限流
> （discovery socket 全记录；其余 200ms 窗口至多 1 条；`g_throttled` 计数），
> 修复期还发现并修掉两个真 bug（失败 sendto 误标 discovery 豁免限流；句柄复用继承
> discovery 标志），详见 `docs/CIVTRACE-LOGBOUND-20261116.md`
> （15,591B/`69C6D923…`，限流自检 PASS 11/11 `run-20261117-000112`：busy_calls
> 13,935,251、throttled 13,935,201、delta=0、broadcast 100 零丢失、日志量
> 471,187,542→24,167 B = **19,497× 降幅**；REV-002 39/39 断言在最终 DLL 上复跑）。
> ②**最终身份**：`civtrace.dll` 247,296B/`ade54435fcc2af37d8d5c5731f7b3c3edbb0dbe98f15f22ac20731a7f79cea0e`、
> `civinject.exe` 171,520B/`eacde79727fca730fb04b29e1a0f173ea0a4e37f930b386cda7cfcd84d0aa71d`
> （R-1 `g_lastGlobalLogMs` 原子化 + CAS；初审 26328A91 有条件通过 → 复审 2591dfd6
> **通过**）；核验包三处同步（`M0A\pcb-kit\`、`Desktop\pcb-kit\`、`pcb-kit.zip`
> 481,836B/`FD84E80A…`，MANIFEST 24 条/`068EC1F5…`，自校验 mismatched=0）。
> ③**B1 真实广告页捕获（方案 B 第一阶段）**：agent 新增 `--sim-real-capture`（默认关
> =零回归）——从 P1（Hook 链 CVLH2 帧）与 P2（LAN 监听直收，本机广播回环已验证）
> 捕获 Civ6 真实广告页（1104B/`59 60 69 9B` 头，与 4B magic 长度互斥），满 22 页后
> 应答用真实页替代匿名 fixture（不足时 fixture 兜底），落盘 `real-page-*.bin` +
> `real-ad-manifest.txt` + summary real-ad 块；重复页计 `duplicates` 不膨胀集合。
> 设计见 `docs/B1-REAL-ADVERTISEMENT-CAPTURE-20261117.md`
> （v1.1，10,202B/`F57BB5AD…`）；机械证据 `docs\reports\b1\run-20261117-005925`
> **PASS 13/13**（captured=22/rejected=2/duplicates=1/noise=23/replies real=1/
> active=yes；C1 P2 回环逐字节一致、C2 P1 帧去重、C3 应答升级、C4 负向）；
> agent `main.rs` 119,618B/`3F9A7549…`、`civlink-agent.exe` 867,328B/`1A5548D6…`
> （debug）。**B1 子代理审计进行中**（f8918c50，→`docs/B1-REAL-ADVERTISEMENT-CAPTURE-REVIEW.md`），
> 通过前不宣称「捕获能力已验收」；B1 只证明"agent 能捕获真实广告页并用其应答"，
> **不证明双人真实联机、不勾 E2-A/E2-B/E3、不移动 Gate A/B**（Gate A 未批准、M0-B 冻结）。
> **v1.26 修订记录（2026-11-17，B1 审计修正闭环）**：
> ①**B1 子代理审计（f8918c50）裁定「有条件通过」**（报告 `docs/B1-REAL-ADVERTISEMENT-CAPTURE-REVIEW.md` 146 行）：
> A 机制正确；B 证据两处语义错标；C 边界四登记全部正确；D 脚本无自指断言、A6 判别力真实；E 代码
> 生产路径无 unwrap/panic、单线程无竞态。必改 3 项已落实：
> **R-1（高）P1 单播覆盖高估** → 设计文档 §3 降级（删单播表述与「确定性」；如实声明
> `hook.cpp` `IsDiscoveryTarget`（L257-268）只对目标端口 62900..62999 或 255.255.255.255 广播命中，
> 单播到请求者临时端口 flags=0 不转发；P1/P2 只覆盖发现窗口期/广播目标，单播不可捕获；双机验证前置
> 须实测 A 机主机广告页发送形态）；**R-2/R-3（中）语义错标**（noise 实为 21 合法页+2 C4 噪声；
> replies fixture=99 实为去重跳过）→ 代码三态返回（`CaptureOutcome`/`ReplyOutcome`，
> 仅 NotAPage 计 noise、仅满集后新页计 rejected、去重/无端点/上限/无 socket/发送失败计 skipped）。
> ②**B1 机械证据新采信轮 `docs\reports\b1\run-20261117-012424` PASS 17/17**（R-2/R-3 修正后重跑）：
> `requests seen=100 / replied sockets=1 / pages sent=22 / captured=22 / rejected=0 / duplicates=1 /
> noise on disc=2 / replies real=1 / replies fixture=0 / replies skipped=99 / active=yes`；
> 断言 A0-A14c（A6 全 22 页逐字节比对、A13 恒等式 captured+rejected+duplicates+noise==25、
> A14 三态恒等式）；证据目录 51 文件（顶层 3 + agent 48；evidence-sha256 列 49 条不含自身与 stop）。
> ③**代码身份（修正后）**：`main.rs` 121,851B/`2687401CECDF2D5679F037DDCA6E4434685EFABF6A4FF94A6E9DBCABE8A419E7`、
> debug `civlink-agent.exe` 868,352B/`69CD012E24AC6758550348D4EB5D46C5EA6CB86E667D205F454416BE1187D2AC`、
> release `civlink-agent.exe` 417,792B/`033D7741617828B4CF34F1812DD94AF48AE9E3E644BBC0DB9AEBAC3A6B35BFB7`
> （旧 78D71DE7… 作废）；设计文档定稿 `docs/B1-REAL-ADVERTISEMENT-CAPTURE-20261117.md`
> 12,915B/`BB39E5A2A79C6F6ECCADBCEC387993C3A47E27ABA4E44B6CD21C4C7BA5C34DFE`。
> ④**下一步**：B1 复审子代理待启动 → 双机验证前置实测 A 机主机广告页发送形态（R-1 前置）→
> B1 双机验证（用户操作 B 机）。E2-B 重跑（v0.4.5 限流后安全长跑）仍挂起（方案 B 优先）。
> 边界维持：B1 只证明"agent 能捕获真实广告页并用其应答"，**不证明双人真实联机、不勾 E2-A/E2-B/E3、
> 不移动 Gate A/B**（Gate A 未批准、M0-B 冻结）。
> **v1.27 修订记录（2026-11-17，B1 §0 发送形态取证 + hook socket-身份改造 + ★P1 端到端验证）**：
> ①**§0 发送形态取证完成（run-20261117-095336，证据 M0A\captures\B1-triggerad-20261117-095336\）**：
> 真实 Civ6 房主广告页为**单播应答到请求者源地址:源端口**（本机模拟客户端 54322 发 100 个 4B magic
> 广播 → 房主 22 条 sendto s=0x13f0 bound=0.0.0.0:62900 dst=26.74.126.98:54322 len=1104，页头
> 59 60 69 9b）。**不是广播、目标端口不是 62900-62999** → P2（agent 绑发现端口直收）对真实房主
> 无效；且真实 A 机上 agent --sim-lan-listen 绑 100 端口会 bind fail: 1 port（Civ6 房主占 0.0.0.0:62900）。
> ②**hook socket-身份改造（civlink_hook.dll 0965154A…）**：IsDiscoveryTarget(SOCKET s, sin, flagsOut)
> 新增「socket 曾 bind 62900..62999 → 其所有 sendto 无论目标端口都置 FLAG_DISCOVERY」——
> 使单播到请求者临时端口的广告页也能被转发捕获；纯观测不吞包。selftest 新增 4 用例全 PASS
> （bind 127.0.0.1:62905 → sendto 127.0.0.1:54322 → sent==4/observedFrames==3）。
> ③**★P1 端到端真实验证 PASS（run-20261117-102852，证据 M0A\captures\B1-p1-e2e-20261117-102852\，
> 51 文件）**：A 机 Civ6 建房（注入 0965154A hook）→ trigger 发 magic → 房主单播应答 → hook
> socket-身份判定捕获 → agent 落盘 real-page-01..22.bin（各 1104B）+ real-ad-manifest.txt
> （22 页 sha256，独立复核 0/22 不匹配）；summary captured=22/rejected=0/duplicates=0/
> noise on disc=0/active=yes、datagrams=22=received=processed=22、discovery_flag=22；
> real-page-01 头 16B 与 §0 取证 sendto data 逐字节一致、房间名区域为真实房主名
> （非 fixture 匿名）→ 捕获确认真实。关键哈希：summary.txt 4F6279A5…、real-ad-manifest.txt
> 2C3879F3…、real-page-01 DDC8CD34…。
> ④**文档更新**：B1 设计文档 docs/B1-REAL-ADVERTISEMENT-CAPTURE-20261117.md
> 15,945B/B041757CAF3C3AFF318B09FB4927777AB4832900717566E17D32AF1F56B36800（§3 P1/P2
> 结论更新、新增 §5.1 P1 端到端）；双机操作单 v3 docs/B1-DUALMACHINE-RUNBOOK-20261117.md
> 4,988B/E14350321D991D0F8990F79C561AB7BECE90723171F409EC36D4DC6858D7D3C4（固定走 P1、
> 先注入后建房、无 --sim-lan-listen）。
> ⑤**下一步**：P1 端到端审计子代理 e1f7ebaf 运行中（→docs/B1-P1-E2E-REVIEW.md）→ 按裁定修正 →
> B1 双机验证（A 机先注入后建房 + agent --sim-real-capture；B 机刷新看真实房名）。
> 边界维持：B1 只证明"agent 能捕获真实广告页并用其应答"，**不证明双人真实联机、不勾 E2-A/E2-B/E3、
> 不移动 Gate A/B**（Gate A 未批准、M0-B 冻结）。
> **v1.28 修订记录（2026-11-17，B1 双机操作单判定口径修正）**：
> ①**双机操作单升版 v4**（docs/B1-DUALMACHINE-RUNBOOK-20261117.md 6669B/36E2767D5060FBD323B47B4C0E67C99011946ECDE9A53774E9ED9FEB4030B90F）：修正 v3 的判定矛盾——
> B1 双机模式 agent 以 --sim-real-capture（无 --sim-lan-listen）运行，**不绑定发现端口、不参与应答**，
> replies real / replies fixture / replies skipped 与 LAN 块 requests seen / replied sockets 仅在 --sim-lan-listen 时由 LanSimState::poll/consider 递增（无该参数恒 0）；F1 块同名计数仅对 hook 帧中的 4 字节 discovery magic 递增（SimState::consider），双机场景 A 机 Civ6 只收不发 magic 同样恒 0（run-102852 实测 discovery_magic=0）；B 机看到房间靠 **A 机 Civ6 房主
> 自身的单播应答**（§0 取证形态），agent 纯观测。新判定：PASS = B 见真实房名 + A 侧 captured=22/active=yes；
> 部分 = captured<22/active=no；FAIL = 先查 agent/hook 注入/建房时序，再查 **A 机 Civ6.exe（游戏）UDP 入站规则**
> （B→A magic 到达靠游戏 socket，非 agent.exe）。
> ②**hook 引用更新**：注入用 civlink_hook.dll 为审计必改落实后最新构建 39D6735D…（run-102852 当时所用 0965154A…
> 保留为历史）；B1 设计文档当前 17,531B/CD28C3428956EAAF40B435096FD466E7496AEEF220C4471F189B1365549279B3
> （§5.1 审计段含 P1 审计 e1f7ebaf 有条件通过 + 必改落实 + Civ6 关闭后复跑 55 项全绿）。
> ③**下一步**：B1 双机验证（按 RUNBOOK v4：A 机先注入 39D6735D 后建房 + agent --sim-real-capture；
> B 机刷新看真实房名）。
> 边界维持：B1 只证明"agent 能捕获真实广告页并观测应答可见性"，**不证明双人真实联机、不勾 E2-A/E2-B/E3、
> 不移动 Gate A/B**（Gate A 未批准、M0-B 冻结）。

> **v1.29 修订记录（2026-11-17，项目负责人授权解除冻结、启动最终程序 M0-B）**：
> **授权（负责人 m24348）**：项目负责人明确"忽略各种冻结，基础问题数据已拿到，直接开始最终程序的编写；
> 需要重新规划可交由负责人审批"。据此 Gate B/M0-B 冻结正式解除，进入 M0-B 最终程序（Design I/II）实施。
> **授权范围**：Discovery Adapter（A 机 Agent 绑全 100 发现端口稳定接收 B 请求 + 真实广告页应答，消除
> 1/100 窗口与广播丢包）与 Game Data Adapter（62056 数据面双向转发）的编写与双机真实联机验证。
> **依据数据（已齐备）**：广告页=单播应答到请求者源地址:源端口（run-095336）；真实广告页 22 页捕获
> （B1-p1-e2e-20261117-102852）；F5 全端口监听应答有效（384/400≈96% 到达、任意 1 包命中即成功）；
> E2-B 失败根因（1/100 窗口 + 6~34% 丢包 + 70s socket 生命周期）。Agent 与 DLL 均已有实现基础。
> **执行模式维持**：每完成一步立即启子代理审计、并行做下一步（m16220/m16222）；审计文档/登记链纪律不变；
> 工具级/模拟证据仍不得宣传为双人真实联机验证，双人结论以 E2-A/E2-B/E3 真实双机为准。

> **v1.30 修订记录（2026-11-17，M0-B 步骤 1-5：授权登记 / 计划 / A 机启动脚本 / 本机自检 / 双机操作单）**：
> **Discovery Adapter 机制（实测确证）**：A 机 agent --sim-lan-listen 0.0.0.0 --sim-real-capture --simulate <fixture> 绑
> 62900..62999；游戏占 62900 → agent bind fail=1 跳过 → 实际绑 **62901..62999（99 端口）**（LanSimState::new
> main.rs:541-560，bind 失败跳过+reply_sock 回退 567-576，代码已支持无需改动）；B 的 100 包 magic 里目标 62900 那包
> 由游戏 socket 收（游戏自身单播应答真实页 run-095336 形态）、其余 99 包由 agent 收（真实页捕获优先、fixture 兜底）→
> **双路应答，命中率 1/100 → ~99/100**。数据面：广告页无 IP/端口字段 → B 向应答源 IP:62056 直连 A 机 Civ6（agent 转发为备选）。
> **本机机械自检 PASS 10/10（run-20261117-131441，exit 0）**：游戏占 62900 模拟、agent 绑 99 端口、客户端 100 magic
> → 收 22/22 页应答（源 26.74.126.98:62901=agent）、bind fail=1、replied sockets=1、pages sent=22、运行时 bind
> 0.0.0.0:62056 探测成功（agent 不占数据面端口）。summary 关键值 requests seen=99/replied=1/pages=22/bind fail=1/
> captured=0/replies fixture=1/skipped=98/active=no（无 hook 链无真实页捕获，符合预期）。证据目录
> M0A\captures\M0B-adapter-selftest-20261117-134539（30 文件=22 页+8 附属，锚点：顶层 `M0A\captures\` 非审计树）。
> **文档**：计划 docs/M0B-FINAL-PROGRAM-PLAN-20261117.md v1.1（6269B/4866784B…）；双机操作单
> docs/M0B-DUALMACHINE-RUNBOOK-20261117.md（6561B/76FC2165DE7E395DECE72EFC42C63BE8960132CBB314537EFC471001E4415060，含防火墙双路径：civlink-b1 需修复 / civlink-f1 零 UAC…，含 §5.5 证据采集+B 侧 civtrace 助手）；A 机启动脚本
> civlink-b1\start-m0b-adapter-a.ps1（封装组合参数）。**审计运行中**（→docs/M0B-ADAPTER-SELFTEST-REVIEW.md）。
> **下一步**：审计返回修正 → 双机真实验证（E2-A/E2-B/E3 结案，先测数据面直连）→ Gate A 复核+结案登记。
> 边界维持：双路应答可能双条房间记录；本轮=真实双机发现+加入链路，对局完整性/长稳/跨网/加密不在本轮；
> 机械证据不得宣传为双人验证。

> **v1.31 修订记录（2026-11-17，S-2/S-4 建议项落实，agent 重编译）**：
> 审计建议 S-2（agent summary reply source 打印实际绑定 socket 而非配置 62900）与 S-4（自检脚本
> PASS5 正向断言 + 精确计数器断言 99/1/98/1）已落实；agent release 重编译
> **418,816B/033D7741617828B4CF34F1812DD94AF48AE9E3E644BBC0DB9AEBAC3A6B35BFB7**
> （旧 DDAF5453… 417,792B 作废），已同步 civlink-b1 运行目录；自检重跑
> **14/14 PASS**（新增 requests-seen-99/replied-sockets-1/replies-skipped-98/replies-fixture-1 四项精确断言），
> 新采信轮 M0A\captures\M0B-adapter-selftest-20261117-134539（30 文件；
> summary 3,240B/DE9F79F2…，reply source 实测 0.0.0.0:62901 回退端口）。
> S-2/S-4 改动草案 docs/M0B-S24-DRAFT-20261117.md；执行计划 docs/M0B-FINAL-PROGRAM-PLAN-20261117.md v1.1。
> 下一步：双机真实验证（等负责人执行 RUNBOOK：A 机 agent 新 033D7741 + hook 39D6735D 先注入后建房；
> B 机刷新+加入），随后 E2-A/E2-B/E3 结案与 Gate A 复核。

> **v1.32 修订记录（2026-11-17，M0-B 双机真实验证执行 + 审计裁定登记）**：
> **执行结果（2026-11-17）**：按 RUNBOOK 完成双机验证——A 机 agent（pid 32348，--listen-seconds 1800，out-dir
> civlink-f1\m0b-adapter-a-20261117-202853，窗口 20:28:53→20:58:53 本地）+ 游戏建局域网房（持 0.0.0.0:62900 与 62056，
> agent bind fail=1 佐证）+ B 机刷新**看到真实房名**（用户口述 m26254/m26306，D 级证据）。agent summary：
> requests seen=1179 / replied sockets=12 / pages sent=264（12×22）/ replies fixture=12 / send fail=0 / captured=0。
> **审计裁定：有条件通过**（docs/M0B-DUALMACHINE-REVIEW.md，17,975B/E024B832D1970E99）：发现链路段**通过**
> （B 见真实房名+agent 计数内部自洽+bind fail=1 佐证）；加入/数据面段**未验证**（M-1，B 机离线前未加入）。
> 验证报告已填写：docs/M0B-DUALMACHINE-VERIFICATION-20261117.md。证据归档 M0A\captures\M0B-dualmachine-20261117\
> （4 文件：agent-32348-summary.txt 85E72E63…/agent-32348-console.txt E3B0C442…（空）/agent-32348-stderr.txt 4CBDFD55…
> /user-observations.txt 76BC00FC…）。
> **关键登记（边界）**：①虚拟房间同 IP 去重=Civ6 客户端行为（m26472：A 有真实房→B 看不到虚拟房；A 无→可见），
> 非 civlink 缺陷，agent 应答链路本身正常；②本轮真实房可见性来自**游戏自身应答**（62900 socket），agent 12 次应答
> 全为 fixture 页（captured=0，真实页应答未演示，能力依赖 B1 轮证据）；③agent 增量贡献未量化（m26254「即使不需要
> Agent，B 依旧可以搜到 A 创建的真实房间」）；④机械证据≠双人验证；⑤E2-B 结案仅限「发现链路段通过」，加入/数据面
> （M-1）完成后才可宣称全结案；⑥A 侧 hook 注入状态未归档（datagrams=0）；⑦summary「run time」=UTC 退出时刻。
> **下一步**：M-1 加入/数据面验证（PC-B 恢复后）→ 开新一轮修订块；M0-C 双角色联机助手（v0.4.6）规划见 m26512。
> 边界维持：不证明对局完整性/长稳/跨网/Noise；机械证据不得宣传为双人验证。

> **v1.33 修订记录（2026-11-18，M0-C 双角色 v0.4.6 的 C1/C2 登记 · 拆分口径）**：
> **C1（A 机房主模式整合）**：agent 新增 `--reserve-62900`，跳过 62900 端口永久留给《文明6》房主 socket，根治 m25442「先启动 agent 占满 100 端口致游戏 bind 0.0.0.0:62900 失败、建房卡住」。自检 PASS 12/12（`M0A\captures\C1-reserve-selftest-20261118-0930`）+ combo PASS 14/14（`-0930`）；关键断言「agent 运行时测试自身 bind 62900 成功」证明建房永不阻塞。agent release 421,376B/`4390AF9D…`。
> **C2（B 客户端定向网卡）**：新增 `civlink_client.dll`（`--iface <IP>` 严格定向 / `--iface ALL` 零干预），唯一副作用 = `setsockopt(IPPROTO_IP, IP_UNICAST_IF=31, htonl(ifIndex))` 且保存/恢复 last error，不吞包/不改载荷/不复制包。三轮审计后采信轮 `M0A\captures\C2-iface-selftest-20261118-1015`（39 文件）`PASS 47/47 runner + 62 in-process`，`ifprobe: before=0 after=1`；变异测试（`M0A\captures\mutation-test-20261118-1016`，删 setsockopt 只留计数）恰 3 条 FAIL + after=0，证明套件确有判别力。第三轮审计 `docs\M0C-C2-REVIEW-3.md`（19,759B/`FF055640…`）裁定**有条件通过**。
> **★拆分口径（强制）**：①**C2-a 记账层通过**——9 场景 A–I、47 runner、62 in-process、变异实证、6 detour in-flight 语义一致；②**C2-b 未验证**——真实跨机出口（IP_UNICAST_IF 是否真把广播送出指定网卡，需 PC-B 恢复后按 `docs\M0C-C2-CROSSMACHINE-RUNBOOK-20261118.md` 看 A 侧 agent 日志源 IP）与真实《文明6》进程内注入（脚本 `civlink\run-c2-real-game-check.ps1` 已备未执行）均未完成。**不得据此宣称 C2 完整验证或联机通过，不得勾 E2-A/E2-B/E3，不移动 Gate A/B。**（v1.33 历史口径；v1.34 已按复审 PASS 升级 C2-b，见下方 v1.34 修订记录。）
> **已知遗留项（不阻塞本轮登记，后续修订）**：N-2 `civlink_ctl.cpp` inject-client 写配置早于 OpenProcess/注入，注入失败会残留 iface 配置（审计接受"如实登记"处置，本版不改代码以保护采信哈希链）；N-3 client_selftest.cpp 头注释场景 H 叙述与 §7.3 冲突；N-4 ps1/result 模板残留"eight"（实 9 场景）；N-5 设计文档旧叙述与不存在符号 `ResolveIfIndexForIp`；N-6 `-1015` 文件数口径（39 根 vs 递归 42）。以上均为低优先级文档/注释项。
> **开源方向**：docs/M0D-OPENSOURCE-PLAN-20261118.md（方案 D 混合，v1.0 收敛为纯自研发现 + 文档引导组网 + 用户自建 relay + 零遥测 + 零日志 + Steam Win64 双人闭环，负责人 7 决策点见 §9.1）。
> **v1.34 修订记录（2026-11-18，C2-b 口径升级登记 · 复审 PASS）**：
> 复审 `docs\M0C-C2-EGRESS-REVIEW-2-20261118.md`（11,220B/`F1DFF00A…`）裁定**通过（PASS）**——C2 跨机出口验证报告（首轮审计 `docs\M0C-C2-EGRESS-REVIEW-20261118.md`，20,209B/`EBF717AA…`）的 4 项阻断 N-1..N-4 全部关闭，无新增阻断，允许 C3 升级登记。
> **C2-b 升级口径**：从「未验证」升级为「**机制层跨机验证完成（探针级）；真实游戏跨机对局待验证**」。两半证据：①真实《文明6》进程内注入（A 机 pid 44124，`M0A\captures\C2-real-game-20261118-1104\counters.log` 2,036B/`633334F4…`：init error 0 / raw sendto 200 / ignored 200 / sent 0 / bind 62056 0，ALL 模式零干预符合设计）；②跨机出口三组对照（报告 `docs\M0C-C2-EGRESS-20261118.md` 8,619B/`0403AFBA…`，证据 `M0A\captures\C2-egress-v3-20261118-1707`）：baseline/radmin/wlan 三组 `setsockopt(IPPROTO_IP, IP_UNICAST_IF=31, htonl(ifidx))` 均 `pinret=0`、A 侧 seen=10/10/8、B 收 22 页 1104B，agent 回发源 IP 随 pin 在 192.168.31.60（WLAN）与 26.74.126.98（Radmin）间严格切换 → IP_UNICAST_IF 定向在探针级跨机生效，两条通道均可送达。
> **边界（强制保留）**：replySrc 判据属**间接证据**（A 侧回发 IP / 对称路由假设 / 非 B 侧线上抓包）；仅证明探针级发现闭环，**不证明真实双人对局**；对局期未抓包且游戏进程已重启，**无法确定「刚才那局」实际走 Radmin 还是 WLAN**；不勾 E2-A/E2-B/E3，不移动 Gate A/B。首轮 marker bug（改 magic 尾字节致误判「Radmin 不达」）已坦白并作废，v3 用单组隔离+统一正确 magic `8D-E8-FC-70` 重做。已知遗留项 N-2（注入失败残留 iface 配置）/N-3~N-6 维持登记，不改代码护采信哈希链。
> **v1.35 修订记录（2026-11-18，P1 GUI 产品级实现登记 · 两轮审计闭环）**：
> 无 SDK 构建链实测：WinForms csc 直编成功；WPF 纯代码 + csc /nostdlib+ + 手写 runtimeconfig + dotnet 启动 + WPF 类型加载全链实测通过但分发成本高（需 Desktop Runtime 8.0.3、纯代码 UI 无 XAML）。设计子代理产出 docs/M0D-GUI-DESIGN-20261118.md（终稿 55,952B/698E413C…），设计审计有条件通过（阻断 0，N-1..N-7 全关）。构建路径择定 A=WinForms + csc 直接编译（civlink/gui/build-gui.ps1，产物 civlink_tray.exe）；GUI 输出哈希在缺官方 .NET Framework ref assemblies 的机器上不可复现（22 字节 PE/MVID 差异），验收以 source_sha256 稳定 + 输出字节稳定 + exit=0 为准，不得把哈希变化当篡改。
> 实现范围：五页签（注入向导/状态/计数/设置/诊断）+ 进程托盘三态；白名单进程名（CivilizationVI_DX12/CivilizationVI/CivilizationVI_DX11）不接受手动 PID；A 角色 inject -m civlink_hook.dll、B 角色 inject-client -m civlink_client.dll --iface <IP|ALL>；ctl 子进程复用 CLI 不重写 IPC；Redactor 无条件脱敏所有 room 字段（含 LAN 段）与 CIVTRACE_TAG；AgentSupervisor 高级 LAN 路径补 --simulate，stop-file 纪律=写 ASCII stop→WaitForExit(20000)→超时才 Kill，34718 占用检测；普通 A 房主默认只注入 hook、不启 agent/模拟。实现报告 docs/M0D-GUI-IMPL-20261118.md（9,375B/561B8EEF…）。
> 审计闭环：首轮 docs/M0D-GUI-IMPL-REVIEW-20261118.md（19,788B/60C15128…）裁定 NOT PASS，N-A（status/counters/shutdown 缺 -x 必返 ctl exit 2）、N-B（agent 高级 LAN 路径缺 --simulate 致启动必失败）、N-C（变异 M2 漏检）、N-D（句中房名绕过/tag 多 token）、N-E（超时注释不实）、N-F（iface 八位组不校验）、N-G（报告文件数 5→6）七项全部自修；重建后 civlink_tray.cs 35,707B/2DFFBFAA…、civlink_tray.exe 26,112B/9B480FE0…；自检 PASS 33/33（M0A\captures\gui-fix-20261118-1852\gui-selftest-fixed.txt），真实窗口冒烟 PASS（仅证 UI 构造链无异常）。变异判别力实证：M1 failed=3、M2 failed=1 精确命中 N-C 判别断言、M3 failed=2（首轮 M2 漏检缺口已关）。复审 docs/M0D-GUI-IMPL-REVIEW-2-20261118.md（13,666B/F9623EBD…）裁定 PASS，允许登记；新发现 N2-1~N2-3 为低优先部署/设计差距观察，不阻断。
> 边界（强制保留）：零遥测/零日志/无持久化、asInvoker、白名单 fail-closed、不内嵌第三方组网；headless 自检与窗口冒烟不是真实游戏注入端到端、更不是双人真实联机，不得写成 E2-A/E2-B/E3 通过；Gate A 仍未批准。诊断包仅内存预览、写文件路径对话框尚未接入；白名单最终清单与普通 A 房主默认流程待负责人确认。
> 开源发布骨架：根 LICENSE（MIT，署名 2026 shengtong（负责人 2026-11-18 确认））、docs/LICENSE-DOCS.md（CC BY 4.0）、THIRD-PARTY-NOTICES.md（MinHook v1.3.4 BSD-2、Rust 零外部依赖、MSVC/.NET 系统提供）、CONTRIBUTING.md、SECURITY.md 已落盘。
> **v1.36 修订记录（2026-11-19，M0-E 发现补全器登记 · 复审 PASS 有条件通过）**：
> **M0-E（loopback 重放发现补全器，用户 m29860「不要虚拟房、要真实房间应答」的落地）**：agent 新增 --discovery-completion —— 房主侧 agent 只绑 62901–62999（--reserve-62900 强制），收到客户端 magic 后经 loopback 127.0.0.1:62900 向本机游戏重放、收 22 页真实广告、钉源回发客户端；**不缓存/不伪造/fail-closed**（游戏静默则不应答）。B-1（回包源 IP 钉住）用零依赖手写 ws2_32 FFI（WSARecvMsg/WSASendMsg + IP_PKTINFO）实现并经真实游戏三接口实测 pinned=true（WLAN 192.168.31.60 / Radmin 26.74.126.98 / ZeroTier 192.168.191.3，首包 38.96/73.33/69.26 ms）；B-2（去重/预算/墙钟）修复前 replays 99/pages 2178 → 修复后 replays 1/duplicate 98/forwarded 22。设计 docs/M0E-DISCOVERY-COMPLETION-20261118.md（v2.1，22,505B/7AF86CB4…）；首轮审计 NOT PASS（2 阻断）全修后复审 docs/M0E-REVIEW-2.md（16,824B/5ABAFEBE…）**PASS 有条件通过**，N-1/N-2/N-6 三项文档放行条件已落实（v2.1）。自检 45/45（采信 M0A\captures\M0E-completion-20261119-003732，证据在审计仓库内，N-1 口径）、变异 5/5（M0E-mutation-20261119-003243）、三接口 pin M0E-B1-egress-20261119-0055、B2 对照 M0E-B2-probe-20261118-2350/M0E-B2-fixed-20261119-0002。代码身份：civlink/agent/src/main.rs 176,308B/E56A3056…、civlink-agent.exe 464,384B/15321D49…。
> **GUI 接入真实房间模式**：civlink_tray.cs（39,608B/F1A4B7E4…）注入向导新增「回真实房间（M0-E）」复选框（默认勾选）→ AgentSupervisor.BuildArgs 拼 --discovery-completion 且不拼 --simulate、始终 --reserve-62900、通配 0.0.0.0（B-1 学被探测地址钉源，一个 bind 服务所有子网）；自检 40/40、变异 M6 3 FAIL 精确命中。civlink_tray.exe 27,648B/F49CE006…；文档 docs/M0E-GUI-INTEGRATION-20261119.md（5,091B/A63D143F…）。产品可执行物打包为 nightly：dist/civlink-20261119-nightly/ + zip（600,458B/CC5A5DBA…，MANIFEST 36/36 复核一致），旧包 dist/civlink-beta-20261114/ 留档不删（对应 F4-BETA 采信证据）；登记文档 docs/NIGHTLY-PACKAGE-20261119.md（2,850B/8F01E954…）。
> **回归收尾**：hook_selftest.exe 加 62056 占用前置守卫（游戏建房时给出 FATAL 提示 exit 3）后，游戏退出重跑 **PASS (0 failure(s))** 52 条全绿（证据 M0A\captures\hook-selftest-recheck-20261119-1015）；client_selftest.exe A..I 九场景三参调用全 PASS（此前 exit=2 是我调用方式错非产品缺陷）；C1 两自检脚本补"真实游戏占 62900 时外来页不计入"修正后 PASS 12/12 与 14/14（C1-*-20261119-0041）。triage 登记 M0A\captures\regress-20261119-0055\TRIAGE.txt（CCFAF851…，结论 No product regression found）。
> 边界（强制保留）：M0-E 全部证据为**本机 loopback + 真实游戏进程**；未证明跨机可用、真实 Civ6 客户端可加入、端到端加入、62056 数据面、长跑稳定性、同子网多归属/非对称路由/双网关（设计 §8 八项）；不勾 E2-A/E2-B/E3，不移动 Gate A/B；反射放大 4B→24KB（≈6,072×）属已知特性（设计 §7），--completion-cooldown-ms 0 等效禁用去重已在设计 §5.1 用户须知标注。

> **v1.37 修订（2026-11-19）——M0-E 双机预检三件套定版**：新增只读就绪检查工具 `civlink\run-m0e-preflight.v3.ps1`（24,386B/0224B231…）与提权修复脚本 `civlink\fix-m0e-preflight.v3.ps1`（10,242B/6387CBAA…），文档 `docs\M0E-PREFLIGHT-20261119.md` 升 v2.0（8,492B/A8B81A17…）。**独立审计连续三次失败**（92c682bf 无产物、4cec1d46 两次：空骨架 / 采证中断）→ 改「自查主导定版」：P-1~P-15 全部逐条实测并修正（C1.1 文件名+MZ 双守卫消除假 PASS、包内缺 MANIFEST 改 FAIL、C2.2/C2.3 恒输出 WARN 并点名 CAVEAT、检查数 12/11 三分支 verdict、布局无关无写死日期、参数校验、只读介质备份回落、caveat 层变异判别力在覆盖路径证明）；最后精简机械复核 `docs\M0E-PREFLIGHT-REVIEW-3-20261119.md`（3,127B/D34EE45A…）**裁定 PASS**（6 点全成立、磁盘哈希一致、无待核残留）。证据：v3 四基线 `M0A\captures\M0E-preflight-v3-selftest-20261119-1156\`、caveat 变异 `M0E-preflight-v2-mutation-20261119-1135\`（M3/M4 仅断言层、control 退出码层，禁止笼统写“变异被捕获”）、自查记录 `docs\M0E-PREFLIGHT-SELF-AUDIT-NOTES.md`（39,445B/2D5AC016…）。操作单升 v1.2（`docs\M0E-DUALMACHINE-RUNBOOK-20261119.md` 8,043B/FC15D7A9…）在步骤 0 引用预检。边界（强制）：预检是**只读就绪检查**，只说明防火墙路径/Profile、62900/62056 前提、metric 竞争、完整性等机械条件；`READY WITH CAVEATS` 的 caveat 是被点名的未验证项，**A caveat is not a pass**；不构成双机联机可用结论，不勾 E2-A/E2-B/E3，不移动 Gate A/B；机械证据≠双人验证。
> **交付包更新（2026-11-19）——civlink-20261119-ready**：在原 nightly 包基础上新增定版预检脚本 `run-m0e-preflight.ps1` / `fix-m0e-preflight.ps1` 与最短操作说明 `OPERATE-FIRST.md`，并按 39 条目重生成 MANIFEST（39/39 校验一致）。目录 `dist\civlink-20261119-ready\`、zip 614,428B/`264700AC9FB808425C0E8708F4BCFE2EF2B491F6349A4254753B2FF1BAF58371`。旧包 `dist\civlink-20261119-nightly\`（CC5A5DBA…）保留不删（对应 M0-E 采信证据）。**先跑 `run-m0e-preflight.ps1` 至 READY（读 caveat），先建房后启 agent**——详见 OPERATE-FIRST.md。
> **v1.38 修订（2026-11-19）——VM 跨机发现链路 + M0-E 真实房间应答双实验（PC-B 离线期间的替代验证）**：用户要求用虚拟机 192.168.31.176（SSH dd/公钥 id_ed25519_civlink，两机 Radmin metric 均=1）做联机实验。**实验一（F5 跨机发现链路）**：A 机 agent --sim-lan-listen 0.0.0.0 --simulate fixture（模拟房主）→ VM 广播 magic → A 
equests seen=401（A3 到达验证）与 =100/replied=1/pages=22（A4 完整双向）、VM 收 22 页源 26.74.126.98:62900——**Radmin VPN 二层房间承载 255.255.255.255 广播**（与 2026-11-15 VMware 桥接双向不通的结论不同），报告 M0A\captures\vm-bcast-test-20261119\RESULT.md。**实验二（M0-E 真实房间应答）**：用户真实建房（CivilizationVI_DX12 pid 8164 持 0.0.0.0:62900+0.0.0.0:62056）+ agent --discovery-completion --reserve-62900（pid 16856 绑 62901-62999）→ VM 发 magic → VM PAGES=44（游戏 62900×22 + agent 62901×22）且页内容 ROOMNAME=dingzihan2022的游戏（真实房名非 fixture）；agent summary 
equests seen=109 / replays sent=2 / replays failed=0 / pages collected=44 / forwarded=44 / duplicate magic=107（B-2 去重生效）/ egress unpinned=44（probe=广播地址，钉源不启用，符合设计）。证据 M0A\captures\m0e-realroom-vm-20261119\（9 文件，RESULT.md 8677991A19BDEB54、summary.txt 370A10BA6683B776）。**边界（强制）**：VM 为 PowerShell 模拟客户端（无游戏），只验证发现链路（广播→监听→真实应答），**不证明**双人对局/62056 数据面加入/E2-A/E2-B/E3/Gate A/B；不勾任何 E2 项；机械证据≠双人验证。待办不变：M-1 加入验证、C4 E2 结案、Gate A。
> **v1.39 修订（2026-11-19）——GUI 现代化改版（P1-GUI-v2）**：按用户要求把 civlink\gui\civlink_tray.cs（45,078B/10682ACA…）UI 层改为现代简约深色主题（Theme 类单一色源：Bg #1E2228 / Card #262B33 / Accent #4FC3F7 / Ok #66BB6A / Warn #FFA726，Segoe UI + Consolas 等宽日志区）；所有 TabPage 深色化、Tab 头 owner-draw（选中态青蓝下划线条）、按钮扁平化（FlatStyle.Flat + 手型光标 + hover 色）、ComboBox/TextBox 深色无 3D 边框、设置页增加"隐私与行为"分节标题与绿色要点行。**逻辑层零改动**：Whitelist/ExitCodeMapper/Redactor/CtlRunner/AgentSupervisor/SelfTest 与全部 40 条自检断言保持原样；重编译 BUILD_OK（civlink_tray.exe 31,232B/8F622E128F6376A691F14AB0D672A168D29D0827C18A279DC84051FE98DE406B），自检 **PASS 40/40**，变异 M6（real-room 分支换 --simulate）恰 3 条 FAIL、恢复后 40/40——判别力未破坏。证据 M0A\captures\gui-restyle-20261119-1500\（4 文件：源码副本/exe/build-manifest/selftest-and-mutation.txt）。边界：UI 改版不改变任何联机行为与既有验收结论；机械证据≠双人验证，不勾 E2/Gate A。
> **v1.40 修订（2026-11-19）——M0F：GUI 迁移 Tauri（前端现代化第二轮）**：用户裁定 WinForms 版观感不足（v2/v3 两轮深色主题仍不满意），四选一（Tauri/WPF/Avalonia/Electron）选定 **Tauri 2**（Rust 内核 + Web 前端，体积小、与 agent 同 Rust 生态、开源友好）。新工程 civlink\gui-tauri\：前端 vanilla JS + window.__TAURI__（零打包器，index.html 5 标签页 + style.css 现代深色主题 #14171c/#4fc3f7 圆角卡片），Rust 后端 lib.rs 六命令（run_ctl 轮询超时+kill、list_processes tasklist 白名单解析、list_ifaces Get-NetIPAddress 过滤、start_agent Mutex 单例+stop-file+watcher emit agent-exited、stop_agent、save_diag UTF-8 无 BOM），capabilities 白名单 shell:allow-execute 仅 civlink_ctl.exe/civlink-agent.exe。**构建踩坑 6 项全修**（withGlobalTauri 在 app 段/icon.ico 须 PNG-in-ICO 262B/lib.rs parent() 与 wait_with_timeout map_err/main.rs crate 名 civlink_gui）。产物：debug 	arget\debug\civlink-gui.exe 17,285,120B/0F33C46CE07985E8B80331109BD034C51CE187C519EAA59B043FD4E8460158E5；release **11,299,840B/42AA1E883788030EB0665481BBFB3B864A7C68DCF763480112108E2730A9F675**（部署 civlink_ctl.exe+agent 同目录）。边界：冒烟启动因 UAC 取消未执行，窗口渲染待用户双击验证；功能对齐待逐项测试（对照 WinForms 版 40 条自检语义重写自检未做）；WinForms v3 保留不删（回退路径）。
> **v1.41 修订（2026-11-20）——M0-G：助手互发现 + 多路径质量探测（peer-discover）**：按用户 m32997 四点需求实现 agent 新模式 `--peer-discover`（全网卡周期广播发现/对端互见/多路径 RTT-抖动-丢包评分推荐/IPv4 MVP）。设计 docs/M0G-PEER-DISCOVER-DESIGN-20261120.md v1.3（三轮审计 NOT PASS→NOT PASS→PASS，18 轮跨机实测证据）；代码 peer_discover_core.rs（零依赖纯逻辑 31 checks 自检）+ peer_discover_net.rs（feature gate 网络 IO）+ main.rs（CLI 7 参数+互斥校验）；依赖 if-addrs 0.15+socket2 0.6 仅在 `--features peer-discover` 下启用，cargo vendor 固化 + Cargo.lock v3（`cargo +1.75.0 generate-lockfile --offline`，禁 stable 重生成）。
> **跨机端到端 PASS**（A 物理机 ↔ VM 192.168.31.176，Radmin+WLAN 双网，证据 M0A\captures\m0g-dual-20261120-{1015..1332}）：发现（CLPD 广播）→ 应答（CLPR per-NIC）→ 地址学习（双地址）→ TWAMP-Light 探测 100 seq → 评分 → RECOMMENDED 输出全链路成立；A 侧 `RECOMMENDED: WLAN -> 192.168.31.176:63011 (score 0.0777)`、2×WLAN 路径 sent=100 recv=100 / p50=11.3ms / J=0.52-0.90ms / loss=0.00%。
> **实现层关键修订（v1.3，跨机实测推翻设计 v1.2 三处）**：①收包=单通配 socket 0.0.0.0:63010 + IP_PKTINFO + 跨子网兜底（逐卡 bind 单播 IP 的 socket 在 Windows 收不到远程定向广播）；②发包=双 socket（pinned IP_UNICAST_IF 发 directed + 默认路由发 limited——绑源 IP+pin 后 limited 不出机器）；③响应=encode_discovery_resp CLPR magic（响应误用 CLPD 会被请求端拒收、对端地址学不到）；④探测期必须落在对端监听窗内（反射循环在主循环内）。
> **自检与变异**：core selftest 31 checks（含 resp 3 断言）；civlink\run-peer-discover-selftest.ps1 变异 5/5 捕获（RTT 公式/响应 magic/反射时延/VPN 过滤/丢包判定），PD-SELFTEST: PASS（%TEMP%\pd-selftest-125039）。判别力陷阱登记：变异不得破坏 selftest 自身断言（M4 首版全局替换 IfClass::Vpn 自我隐藏）；判定变异结果前必须核对 exe mtime vs src mtime（stale exe 伪造 baseline 失败）。
> **★双警告（M5 可验收项，强制保留）**：①**无鉴权**：peer-discover 无任何认证，同一广播域内任何同款助手/嗅探者都能发现你、伪造应答；**仅限信任网络使用**。②**VPN=二层广播域**：勾选 VPN 网卡（如 Radmin）时，发现包进入该二层广播域，同房间其他成员也会收到（本机 VM 实验已证实 Radmin 承载 255.255.255.255 广播）；仅在信任的房间内勾选。GUI「助手发现」页实现时必须包含这两条警告文案。
> **边界（强制保留）**：peer-discover 是"助手间发现+路径探测"，**不是双人对局**；无真实 Civ6 客户端加入、无 62056 数据面、无公网跨网；不勾 E2-A/E2-B/E3，不移动 Gate A/B；机械证据≠双人验证。
> 下一步：GUI「助手发现」页（双警告+逐卡勾选）→ 登记 HANDOVER；M-1 加入验证（PC-B 恢复后）；C4 E2 结案 + Gate A 复核。

> **v1.42 修订（2026-11-20）——GUI「伙伴发现」页 UI 修订（用户 m34135 九条裁定）**：
> ①`注入向导`→`注入`（去滑动条）；②`目标进程`→`进程`并与`角色`互换位置（进程在前）；③删除`回真实房间`勾选——真实房间应答是核心能力，不做开关；④所有日志容器改为**单层** + `pre` 独立滚动（`max-height:260px`）；⑤`助手发现`定名 **`伙伴发现`**（发现的是另一台机器的玩家/助手，不是房间）；⑥删除常驻黄色警告块——两条警告（无鉴权 / VPN 即二层广播域）改为点击「开始发现」时**逐行写入日志区**，仍在 GUI 内逐字可见，**M5 验收项不丢失**（证据与理由见 `docs/M0G-GUI-PEERS-TAB-20261120.md` §3）；⑦「参与发现的网卡」改为**可折叠**（`选择网卡 ▾`）、**默认不勾选**，每项显示 **网卡名称（IP）**；⑧后端新增命令 `list_ifaces_named`（`Get-NetIPAddress` + `Get-NetAdapter -InterfaceIndex` 拼 `ip|name`）并注册进 `generate_handler!`。
> 产物 `civlink\gui-tauri\src-tauri\target\release\civlink-gui.exe` **11,419,648 B / sha256=`B2EACC95A7C503B5BC9861BBFCCA4963A018BA649525082131543BB42A5C78B1`**，部署副本 `C:\Users\dd\Desktop\civlink-gui\civlink-gui.exe` 同字节；`cargo build --release` exit 0、`node --check main.js` exit 0、JS 引用的元素 id 与 HTML 全对齐（无缺失）。
> **边界不变**：本次为 UI 层改动，不改 agent 协议/端口/边界声明；伙伴发现仍为同广播域 P2P 发现工具，**不构成双人对局验证，不勾 E2-A/E2-B/E3，不移动 Gate A**。
>
> **历史编号勘误**：v1.41（M0-G peer-discover 登记）落盘时漏改第 3 行版本行，导致版本行长期停在 1.40；本次一并更正为 1.42。


> **v1.43 修订（2026-11-20）——GUI「节点发现」页第二轮（用户 m34203 六条）+ 探针反射两处跨机缺陷修复**：
> ①`伙伴发现`定名 **`节点发现`**（发现的是对端进程/节点，既不是游戏房间也不是"伙伴"这种口语称呼）；②**布局契约改为窗口永不滚动**——`html,body{height:100%}` + `body{flex column;overflow:hidden}` + `.logcard{flex:1 1 auto;min-height:0}` + `.logcard>pre{height:100%;overflow-y:auto}`，日志只在栏内滚动并自动滚底（`log()` 追加后 `scrollTop=scrollHeight`）；③压缩「连接设置」为行式布局（`.row`/`.rowlabel` 固定 92px 标签列）把高度让给日志；④修复「选择网卡」点击无效：`.hidden{display:none !important}`（此前 `.pd-ifaces{display:flex}` 定义在后，层叠覆盖了前面的 `.hidden`，折叠容器恒可见），列表默认**折叠且全不勾选**；⑤网卡列表**实时刷新**：`#pd-refresh` 手动 + `#pd-autorefresh` 5 秒定时（仅当节点发现页处于激活状态才请求）+ 展开面板时刷新 + 切换 tab 时刷新，`pdChecked` 用 Set 跨刷新保留勾选、消失的 IP 自动剔除；⑥每块网卡显示**优先级**（`InterfaceMetric`）并按**由高到低排序**（metric 越小越优先）：后端 `list_ifaces_named() -> Vec<IfaceNamed{ip,name,metric}>`（`Get-NetIPInterface -AddressFamily IPv4` 建 index→metric 映射）并 `out.sort_by_key(|i| i.metric)`。

> **★缺陷一（勾选未生效，隐私承诺名不副实）**：修复前 GUI 只把勾选 IP 用来判断是否加 `--include-vpn`，**从不传给 agent**，agent 仍按自己枚举的全部网卡广播。修复：`main.rs` 新增 `--ifaces <逗号分隔 IPv4>`（空值或 `ALL` 表示不过滤），`peer_discover_net.rs` 的 `enumerate(include_vpn, ifaces_filter)` 循环内不命中即 `continue`；GUI 传 `["--ifaces", ips.join(",")]`。实测：`--ifaces 26.74.126.98`→仅 Radmin；`--ifaces 192.168.31.60`→仅 WLAN；`--ifaces ALL`→四卡全参与；`--include-vpn` + `--ifaces <WLAN>` 仍只出 WLAN（过滤优先于 include-vpn）。

> **★缺陷二（探测阶段无人应答 → 永远 `RECOMMENDED: none`）**：反射原本只在主循环内做，而 `probe_paths` 在**主循环退出后**才运行；两机监听窗相同 → 几乎同时进入探针阶段 → 双方反射器均已停 → 各自测到静默对端 → 全路径 100% 丢包。修复：`probe_paths` 增加 `reflector: Option<&UdpSocket>` 参数，在自身探测等待间隙调用 `reflect_pending(...)` 应答对方；两侧同时启动实测双向 PASS（A `recv=98 loss=2.00%`、B `recv=100 loss=0.00%`，各自给出 `RECOMMENDED: WLAN(...)`）。证据 `M0A\captures\m0g-reflector-fix-20261120\`（README 2,368B/`6D58F24268B44974…`）。

> **★缺陷三（错开启动 → 后启动侧全 100% 丢包，常态场景）**：两人不可能同时按「开始发现」；先启动的一侧探针阶段结束即 `write_outputs` 退出，后启动一侧开始探测时对端已不存在（实测 A 早 2 秒：A `recv=100 loss=0.00%`，B `sent=100 recv=0 loss=100.00% recommendable=false`、`RECOMMENDED: none`，而 peers.jsonl 证明双向发现本身是通的）。修复：新增 `PEER_GRACE_MS = 30_000` 与 `grace_answer(sock, abort, budget_ms, start) -> u64`，自身探针阶段结束后继续应答 30 秒（墙钟受限、可被 abort 中断），`reflect_pending` 改为返回应答计数累加进 `stats.probe_reflected`。错开后启动 2 秒复验**双向 PASS**：A `discovery 45/72`、`peers 1`、`probes reflected 100`、`p50=11.0ms p95=28.6ms J=7.00ms loss=0.00% score 0.2278`；B `45/71`、`probes reflected 100`、`p50=4.1ms p95=12.8ms J=2.73ms loss=0.00% score 0.0901`（Radmin 路径 `26.74.126.98:63011` loss=100% 因两侧未开同房间，预期），两侧均给出 `RECOMMENDED: WLAN(...)`。证据 `M0A\captures\m0g-grace-20261120\`（README 3,568B/`C56C65C60D287B94…`，含双侧 summary 与 peers.jsonl）。

> **监听窗与宽限窗协调**：GUI 原传 `--listen-seconds 120`，加 30 秒宽限后全程可达 150 秒以上、用户会以为卡死；现改 `--listen-seconds 60`，界面提示"监听 60s + 30s 应答宽限（约 95 秒全程，请勿关闭窗口）"。

> **产物（本轮）**：`civlink-agent.exe`（`--features peer-discover`）**605,696 B / sha256=`EBDB09E06F5FA939EC84387443C9FBF0A0B87997DFAA0CF58FC096759AB84D5B`**（A 部署目录 `C:\Users\dd\Desktop\civlink-gui\` 与 B 机 `D:\Desktop\` 同哈希）；`civlink-gui.exe` **11,449,344 B / sha256=`6C0C8A6832907E3CEF564AA581A09C9D640B3B4FB2C208DFAD44F0B4BB7C87B2`**。构建：agent `cargo +1.75.0 build --release --offline --features peer-discover` exit 0；GUI `cargo build --release`（**必须用 stable**，`cargo +1.75.0` 不认 `gui-tauri\src-tauri\Cargo.lock` v4）exit 0；`node --check main.js` exit 0。自检 `run-peer-discover-selftest.ps1` → `PD-SELFTEST: 6 checks, 0 failed` + `PASS - all mutations caught`。文档 `docs/M0G-GUI-PEERS-TAB-20261120.md` 重写为 R1/R2 双轮 + 三缺陷记录（7,612B/`79D3BF3076389FDE…`）。

> **边界（强制保留）**：本轮为 UI 层与**助手间**发现质量探测层改动，不改变 agent 的 62056 数据面约束、不改变注入语义；节点发现仍是同广播域 P2P 工具，**不构成双人对局验证，不勾 E2-A/E2-B/E3，不移动 Gate A/B**；30 秒宽限是使用约定而非协议保证（后启动侧晚于 30 秒才开始探测仍会测到静默对端）；机械证据≠双人验证。

> **下一步**：GUI 端到端复测（用户点「开始发现」验证勾选生效 + 结果目录回填）；测试 2 = M-1 加入/数据面验证（A 注入→建房→启发现补全，顺序不可反；B 刷新见真实房名→加入）；C4 E2 结案 + Gate A 复核。
> **v1.44 修订（2026-11-20）——节点发现页「发现结果」面板：设备端直接显示在页面（用户 m35241）**：
> 用户逐字要求「让它在开始发现的页面中可以直接显示发现的设备端，以及它的基础信息，而不只是通过日志」。实现为**结构化数据源 + 页面渲染**，而非解析日志：
> ①agent 每 500ms 整体重写 `<--peers-dir>/peers-live.json`（小文件整体重写，GUI 不会读到半截 JSON），主循环写 `phase="listening"`、进入探针前写 `phase="probing"`、探针与宽限结束后写 `phase="done"` 并附 `paths`；②字段契约 `self{uuid,short}` / `phase` / `elapsed_s` / `peers[{uuid,short,addrs[],probe_port,last_seen_s}]` / `paths[{iface,local_ip,peer,sent,recv,p50_ms,p95_ms,jitter_ms,loss_pct,score,ok}]`；③**`last_seen_s` 语义修正为「距今多久」**（`Instant::now().saturating_duration_since(*seen)`）——早期写成"第几秒见到的"会随运行时间单调增大、误导用户；④GUI 后端新增 `#[tauri::command] fn peer_live() -> String`（读 `LAST_PEER_OUT` 目录下的 `peers-live.json`，无文件返回空串）；⑤GUI 前端每 700ms `invoke("peer_live")` 轮询，`raw === pdLastJson` 时**不动 DOM**（防抖动），所有对端字符串经 `escapeHtml()` 输出（对端内容来自网络，属不可信输入）；⑥面板构成：「发现结果」卡片（阶段药丸 + `本机 <8hex>` + `设备 N · 路径 M` + 清空）、设备列表（对端 short / uuid / 地址 / 距今秒，空态提示双方都点开始发现）、路径表（路径 / 收发 / p50 / p95 / 抖动 / 丢包·评分，可推荐绿底、不可推荐红底）、推荐行；⑦**日志卡保留**（用户要求是"不只是通过日志"，不是"去掉日志"）。
>
> **双机实测（A 先起 1 秒，两端 `--listen-seconds 40` + 单网卡过滤）**：A `self=5479f084`、对端 `5a06fda8 @ 192.168.31.214:63344`、`last_seen_s=33`、路径 `WLAN 192.168.31.60→192.168.31.214:63011` 100/100、p50 12.02ms、p95 21.18ms、抖动 4.34ms、丢包 0.00%、评分 0.1690、可推荐；B `self=5a06fda8`、对端 `5479f084 @ 192.168.31.60:63732 / 26.74.126.98:63734`、`last_seen_s=48`、WLAN 路径 100/100、p50 5.84ms、p95 20.25ms、抖动 1.31ms、丢包 0.00%、评分 0.0795、可推荐；B 的 Radmin 路径 `26.74.126.98:63011` 100/0、丢包 100.00%、评分 10.0500、不可推荐——**两端 Radmin 未加入同一虚拟房间，属预期结果**，推荐行正确选 WLAN。两侧均为 `RECOMMENDED: WLAN(...)`。证据 `M0A\captures\m0g-peers-live-panel-20261120\`（README + A 侧 peers-live/summary/peers.jsonl + B 侧经 SSH base64 回传三件）。
>
> **产物（本轮）**：`civlink-agent.exe`（`--features peer-discover`）**614,912 B / sha256=`C51C4FA3EA201B2A5A811B584A03A148C613B9506FC76EB968B622A0AA43FE62`**（A 部署目录 `C:\Users\dd\Desktop\civlink-gui\` 与 B 机 `D:\Desktop\` 同哈希）；`civlink-gui.exe` **11,395,072 B / sha256=`907CF7523D8B73D3892F71ED28BAD96325E6614F79F881128E60DA7A6740F129`**。构建：agent `cargo +1.75.0 build --release --offline --features peer-discover` exit 0；GUI `cargo build --release`（**必须用 stable**）exit 0；`node --check main.js` exit 0。文档 `docs/M0G-GUI-PEERS-TAB-20261120.md` 增至 §6「发现结果面板」（137 行）。
>
> **边界（强制保留）**：面板只证明**发现链路的数据呈现**，不证明双人对局、不证明 62056 数据面、不勾 E2-A/E2-B/E3，不移动 Gate A/B；`short` 是 uuid 前 8 位十六进制，**不是稳定设备名**（发现协议包仅 24B、无名称字段，显示机器名需扩协议，本轮未做、登记为后续项）；GUI 端"用户点开始发现→面板出现设备卡"的目视验收仍待用户确认；机械证据≠双人验证。


> **v1.45 修订（2026-11-20）——P0-A/B/C/D：探针零样本原因枚举（D-1 判定）+ GUI 节点发现页改造 + 监听网卡固定 0.0.0.0 + 仓库整理（依据交接文档 docs/HANDOVER-TO-NEXT-AI-20261120.md）**：
> ①**D-1 判定**：用户在 60s 监听窗内按「停止」→ abort 置位 → 探针 seq 循环立即 break → `sent=0` → 「无可用路径」兜底误导；`err.txt` 空、排除 send 失败与 deadline。修复：新增 `ProbeCancel` 枚举（None/Stopped/Deadline/SendError）写入 `peers-live.json paths[].reason` 与 `summary.txt` 路径行 `reason=`；`RECOMMENDED: none` 分支改「no probe was actually sent - stopped/deadline/send error; see per-path reason」；GUI 零样本显示「探针未发出（已停止/时间不足/发送失败）」。
> ②**remain_s 三阶段倒计时**：`peers-live.json` 新增 `remain_s`（listening=listen_secs-elapsed / probing=listen+45-elapsed / answering=listen+45+30-elapsed / done=0），agent updater 线程 500ms 续写使探测/应答阶段倒计时持续；GUI 阶段药丸显示「剩余 Ns」。
> ③**GUI 节点发现页改造（P0-B）**：「开始发现」→「开始广播」，广播中「正在广播」置灰互斥（`setPdBroadcastUi`）、「停止」初始禁用；`PD_PHASE_LABEL` 增 answering；「发现网卡」→「网卡选择」；删「自动刷新（5s）」开关（定时刷新恒开、仅删 UI）；`button:disabled` 样式；启动日志改「监听 60s + 探测 45s + 应答宽限 30s（全程最多约 135 秒）」。**双警告（M5）保留**：点「开始广播」仍逐行写入日志。
> ④**监听网卡固定 0.0.0.0（P0-C）**：删注入页「监听网卡」下拉，改静态文案「全部网卡（0.0.0.0，绑定 62901–62999，62900 留给游戏建房）」；`agentstart` 直传 `--sim-lan-listen 0.0.0.0`；B 端「发送网卡」与 `--iface` 注入参数不变。
> ⑤**P0-D 仓库整理**：删根目录 15 个散落日志与 civlink 杂物（clean/guibuild/mut/restore/fakeip 日志、obj/lib/exp 产物）、12 个 pd-* 测试目录；build-hook*.txt 5 件移 `docs\archive\build-hook-20261117\` 并登记哈希（12B22ECC/37E6325D/885EEE55/DC34B999/827DBC60）；新建 `.gitignore` 与 `docs\LOGGING-CONVENTION.md`（5,141B/C9D2B6E6…）。
> **产物（本轮）**：`civlink-agent.exe`（`--features peer-discover`）**628,736 B / sha256=`EE7309CFEA2A5E9A34CB9CD9601EAC9A5C5ACD328DA6EBB8F7AD1269CF076F80`**（A 部署目录与 `civlink\deploy-b\` 同哈希，供 PC-B 投递）；`civlink-gui.exe` **11,409,408 B / sha256=`97AB99ED41249216DBDD465DF7EB9E186B0115C98952BE281D15A8A27FB12224`**。构建：agent `cargo +1.75.0 build --release --offline --features peer-discover` exit 0；GUI `cargo build --release`（stable）exit 0；`node --check main.js` exit 0。自检 `run-peer-discover-selftest.ps1` → `PD-SELFTEST: 6 checks, 0 failed` + `PASS - all mutations caught`（%TEMP%\pd-selftest-234952）；部署产物直跑 `--peer-discover-selftest` 31 checks 0 failed。D-1 实证：伪造 CLPR 对端（127.0.0.1:63010）→ 监听期写 stop.now → `paths[0].reason="stopped"`、`remain_s=53`（`agent-out\fake-*`/`repl-*`，副本 `M0A\captures\p0a-d1-evidence-20261121\`）。GUI 目视确认：2026-11-21 用户确认**基本满意**（UI 细节调整另开修订）。文档：`docs/M0G-GUI-PEERS-TAB-20261120.md` 补 §9「布局契约根因（D-6）」（10,661B/968406B4 → 11,512B/690D0674…）；`docs/CODEX-HANDOVER-M0A.md` 第 32 项；交接文档 `docs/HANDOVER-TO-NEXT-AI-20261120.md`（29,518B/39F2B675…）随本修订入登记链。
> **边界（强制保留）**：不勾 E2-A/E2-B/E3，不移动 Gate A/B；M-1 加入/62056 数据面验证待 PC-B/VM 开机；双警告 M5 保留；`short` 仍为 uuid 前 8 位、非稳定设备名（显示机器名需扩协议，维持后续项）；D-8（SECURITY.md 发布前补联系渠道）维持登记；机械证据≠双人验证。
> **v1.46 修订（2026-11-21）——换网卡重注入状态机修复（CivLinkReactivate）+ GUI 五轮迭代与 4-tab 合并 + Brooks-Lint 严格审计**：
> ①**换网卡重注入 exit 5 修复（D-1 延伸）**：用户报告「卸载注入→换网卡→再注入」报 `hooks not active within 20 s`（exit 5），日志含 `civlink_client.dll already loaded ... not injecting twice`。根因=DLL 状态机缺陷：ctl 检测 DLL 已加载即跳过 `LoadLibraryW`、`client-iface.txt` 只在首次 `DllMain→InitThread` 读一次、`CivLinkShutdown` 置 `g_state=-1` + `MH_DisableHook` 但按 B2 审计模式故意不卸载模块、第二次注入无代码恢复→20s 轮询恒得 -1。修复：client.dll 增第 5 导出 `CivLinkReactivate`（`LoadConfig` 幂等重置 + `initError` 清零 + `MH_EnableHook(MH_ALL_HOOKS)` + `g_state=1`，`g_reactivating` 防重入）；ctl 在「已加载」分支仅 inject-client 经 `ResolveLocalPe/RemotePeIdentity/RemoteCallInt` 远程调用（host hook.dll 无此导出、不调），旧 DLL 提示需重启游戏。
> ②**GUI 五轮迭代**（哈希链 `97AB99ED`→`43064E3C`→`C5520C55`→`5DA136EA`→`11AB85D8`→`2C33FA51`→`71DF48FA`→`152142C7`）：令牌化 Navy 设计系统（六 tab Phosphor 图标、D-6 结果卡 `overflow-y:auto`）；删 5s 自动轮询与启动时结果面板兜底（改会话内语义）；网卡选择改常驻行列表（去括号显名称+IP、优先级徽标、全选/取消全选、250px 滚动）；修「点停止后冻结在『探测中 剩余 Ns』」（pd-stop 只写 stop.now、保留轮询至 agent 写 phase=done）。
> ③**注入页改造 + 4-tab 合并**：注入日志加「清空」按钮（`injectlog-clear`）；发送网卡下拉复用 `list_ifaces_named` 显示 `IP（接口名）`；删标题栏橙色徽章与长提示小字；「设置」改名「发现补全」，状态/计数/诊断合并为「排障」三分区（按钮与日志 id 不变，main.js 零改动）。M5 双警告保留。
> ④**Brooks-Lint Full Sweep 严格审计**：五维（PR 跳过：非 git 仓库；review/test/debt/audit/health，两子代理失败由主代理自扫补齐）。Applied Safe 三项：T5 场景 J 接入 harness（`run-c2-iface-selftest.ps1` 加 J 行、ExpectChecks 47→50）、T2 变异静默跳过改 fail-closed（`run-fakeip-selftest.ps1`）、R4 孤儿 `agent\t.rs` 移 `M0A\captures\audit-20261121-removed-orphans\`（可恢复）。R3 重复判为有意（client/hook 两 DLL 独立编译、B2 模式保持独立）；v1/v2 预检脚本为登记链历史、不删。健康分≈85/100。
> **产物（本轮，桌面实际运行副本实测）**：`civlink-gui.exe` **11,411,968 B / sha256=`152142C72BF52D8B54BC4EE528B8EF3AF5C6969C1A89F22D6D67EA5B5BB6DCEB`**；`civlink_ctl.exe` **189,440 B / sha256=`B356031E60D79C562CDEFE68BC34A4C498CFEC02499847ED78AF5047318FEB15`**；`civlink_client.dll` **150,016 B / sha256=`EB6903C8FFC12DAFE4F0D867403A9961E3BA96FC885E03DBE3794759E12B6A34`**（第 5 导出 CivLinkReactivate）；`civlink_hook.dll` **119,808 B / sha256=`FE80AF34733C907BE5580CD2CF3F82F6E31AEE6FBECFEBD0CDED4645010A2608`**；`civlink-agent.exe` **628,736 B / sha256=`EE7309CFEA2A5E9A34CB9CD9601EAC9A5C5ACD328DA6EBB8F7AD1269CF076F80`**（未变）。构建：`build-msvc.cmd` exit 0（dumpbin 5 导出）；`cargo build --release`（默认 1.99，Cargo.lock 保持 v3）exit 0；agent `cargo check --offline` exit 0。自检 C2 harness PASS 50/50 runner + 74 in-process（A–J，J9 config re-read PASS）；client_selftest A–J 全绿；hook_selftest PASS。审计脚本 `run-c2-iface-selftest.ps1`（15,859B/1751A7FC…）、`run-fakeip-selftest.ps1`（4,946B/BF1F489A…）。GUI 目视 2026-11-21 用户确认「没问题，继续」。
> **边界（强制保留）**：换网卡重注入的真机复验属 M-1（待双机）；不勾 E2-A/E2-B/E3、不移动 Gate A/B；M5 双警告保留；D-8（SECURITY.md 发布前补联系渠道）维持登记；Cargo.lock 必须 v3（1.99 构建未升级依赖树）；机械证据≠双人验证。

> **v1.47 修订（2026-11-23）——3-tab 重组与关于页 + 智能补全 + 节点发现质量重构 + 两轮深查 6 bug + Brooks-Lint Full Sweep 10 项 Safe 修复**：
> ①**3-tab 重组与关于页**：六/四 tab 收敛为「注入 / 节点发现 / 关于」三 tab；删「发现补全」独立页，改注入页服务端专属勾选框（`#agentenable`，客户端隐藏）；「关于」页只留版本 0.1.0 / 作者 shengtong / 项目地址 `https://github.com/ShengTong1/Civ6-Link`，删许可与第三方清单；图标换原创六边形+网络节点多尺寸 ICO（56,606B，`make_icon.py` 留 `src-tauri\icons\`）；诊断导出含 status+counters+脱敏日志，融进关于页。
> ②**智能补全（方案 A，用户 m01839 确认）**：勾选框=启用开关，勾上后全自动——注入成功→后台每 2s 检测 UDP 62900 游戏房间→自动启动发现补全 agent（1800s），无需点按钮；卸载注入时一并停止。取消勾选即停监视+停 agent。用户 m03377 决定**保留勾选框**（自动的是启动动作，不是启用决定）。**2026-11-23 按用户要求删除「启动补全/停止补全」两个手动按钮**（`agentstart`/`agentstop` 零残留，勾选后只显示「已启用自动补全」状态文字；取消勾选再勾一次可重触发房间检测），本轮 GUI 最终哈希 `F9CFF40D…2260`（原 `FDF1EFDB…30C` 为删按钮前版本）。
> ③**节点发现面板简约化**：删结果卡下方 `#pd-note` 日志栏（错误走阶段药丸 `pdErr`）；路径表「丢包 / 评分」→「丢包」，推荐行去评分；探测期留空不再误导「无可用路径」；零样本 p50/p95/抖动/丢包显示 `—`。**M5 双警告按项目负责人 m02344 以负责人身份明确指令删除**（授权变更，登记留痕；删自 `PD_WARNINGS`/`#pd-warn`/`.pd-warn`，`pdErr` 保留）。
> ④**节点发现质量重构（用户 m01913 自检 8 项）**：agent `loss_x100` 分母由计划数 100 改为实际 `sent`（中途停止不再假 60% 丢包），`is_recommendable(stats)` 去掉 max_seq；自检 32/0（后增至 36/0）。GUI 设备行去恒定「探测端口」与临时端口噪声、网卡名统一 `pdCleanName` 去括号。
> ⑤**快速配对（取消模式二分，用户 m02119/m02158）**：重构 `run_peer_discover`——**60s 持续广播不中断**，发现对端 3s 后**内联探测**（几秒出路径数据），删 tail 线程，grace 后置；死路径连续 15 根无应答（约 2s）提前放弃；`--listen-seconds` 回 60，启动文案「持续广播最多 60 秒，发现对端后立即探测」。
> ⑥**勾选约束根本修复（用户 m02344）**：新增 `limited_egress_checked()`——受限广播 `255.255.255.255` 未绑定 socket 的出口由 Windows InterfaceMetric 决定，若 OS 选定源 IP 不在勾选网卡内则**抑制发送**（避免 B 只勾 ETHERNET0 却从 Radmin 泄漏）；`probe_sock` 开 `IP_PKTINFO`，主循环反射/`reflect_pending`/`grace_answer` 均按到达网卡∈勾选集过滤；`probe_paths` 每路径 socket 加 `pin_egress`（`IP_UNICAST_IF`），杜绝 weak-host「Radmin 源从 WLAN 出去」造成假路径。
> ⑦**计时修复（用户 m02490）**：`write_live` 增 `frozen_elapsed: Option<u64>`，done 阶段冻结为结果发布时间（不再「已用 59s」虚长）；probing/answering 倒计时基准统一到 `listen_secs` / `listen_secs+15`（不再跳 20s）。
> ⑧**两轮手工深查 6 bug**：(1)`grace_answer` 非阻塞 socket 忙等 15s→`sleep(10ms)`；(2)补全 agent 退出误停节点发现面板→`pdAgentPid` 过滤；(3)agent 单槽静默冲突→pd-start 前先停补全、补全侧明确提示；(4)勾选 VPN 卡被 agent `classify_iface` 二次剔除→显式勾选优先；(5)`pdSessionStarted` 置 true 后从不重置→agent-exited 严格 pid 守卫 + 置 false；(6)watcher 旧 agent 退出无条件清空 `AGENT_PID` 竞态→compare-and-clear。
> ⑨**DX11/DX12 兼容核对（用户 m03048）**：`list_processes()` 白名单三 exe（`CivilizationVI_DX12`/`CivilizationVI`/`CivilizationVI_DX11`）全识别；注入按 PID、与 exe 名无关；MinHook 挂 Winsock 通用 API 与渲染分支无关；ctl 拒 WOW64 32 位进程；Civ6 DX11/DX12 均 x64。结论**全兼容、无需改码**。
> ⑩**Brooks-Lint Full Sweep（用户 m03083 质疑后正式重跑）**：四维（review/test/debt/architecture；PR 跳过：非 git 仓库），健康分≈89。Applied Safe 10 项：删 `AGENT_STOP` 写而不读死标志与 `LOSS_HARD_NS` 死常量；core selftest 加 `score` 钉死 0.545 + stability-penalty + `gate-bad-samples`/`gate-bad-loss`（checks 32→36）；`run-peer-discover-selftest.ps1` baseline 改下限断言≥36、变异加 applied 守卫（no-op 直接 FAIL）、M1 改打生产、M5 签名改 `sent:u64`；`run-c2-iface-selftest.ps1` 无活动网卡改 exit 2 setup error、J 场景注释与 result 计数派生。验证：core selftest 36/0、变异 harness 6/0、C2 harness 50/50 + 74 in-process、agent/GUI `cargo build --release` exit 0。**残余（Residual，未改）**：hook.dll `Real_sendto/WSASendTo/closesocket` 在 `g_inFlight--` 之后调用（与 client.dll H-1 模式不一致，shutdown drain 理论竞态）；CVLH2 线协议跨 C++/Rust 重复（`cvlh2.h` 假注释指向不存在的 `agent\src\frame.rs`）；GUI↔agent 手拼 JSON 契约无 schema；`main.rs` 4240 行 god module。
> **产物（本轮，桌面实际运行副本实测）**：`civlink-gui.exe` **11,522,560 B / sha256=`F9CFF40DCEA948721E35D306A08B3E46D2A7E82013EFD8BB2D2A862BED6A2260`**；`civlink-agent.exe` **615,936 B / sha256=`A3905D09FC75832A91C2026F2AC1EEACCE4461A53C2962B564ADB5DBBFA5B5CA`**（桌面 + `civlink\deploy-b\` 同哈希）；`civlink_ctl.exe` 189,440B/`B356031E…8F15`、`civlink_client.dll` 150,016B/`EB6903C8…6A34`、`civlink_hook.dll` 119,808B/`FE80AF34…2608`（三者未变）。GUI 哈希链 `591C502D`→`A0FE478C`→`624AF629`→`F9CFF40D`；agent 哈希链 `219EA5D4`→`B15374CF`→`A3905D09`。构建：agent 1.75 固定工具链 `--features peer-discover --target-dir target-175` exit 0；GUI `cargo build --release`（cargo 1.99，Cargo.lock 保持 v3）exit 0；`node --check main.js` exit 0；core selftest 36/0 + 变异 6/0 + C2 50/50。
> **边界（强制保留）**：不勾 E2-A/E2-B/E3、不移动 Gate A/B；**M5 双警告按 m02344 负责人授权删除（授权变更留痕）**；发现补全勾选框按 m03377 保留；M-1 加入/62056 数据面真机验证待双机；D-8 维持登记；Cargo.lock 必须 v3；节点发现仅同广播域 P2P 工具、不构成双人对局验证；机械证据≠双人验证。

> **v1.48 修订记录（2026-11-23，Brooks-Lint 残余落地 + README 重构）**：
> ①**hook.dll in-flight 窗口对齐（R3 残余）**：`Hook_sendto`/`Hook_WSASendTo`/`Hook_closesocket` 三处 detour 的 `g_inFlight.fetch_sub(1)` 移到 `Real_*` 调用**之后**（含 tlsInHook 重入分支，改 rc 捕获模式）——与 client.dll H-1 一致，CivLinkShutdown drain 真正覆盖原始调用。bind/recvfrom/WSARecvFrom 原本已是 rc 模式、未动。
> ②**cvlh2.h 假引用修正（F1 残余）**：删除「SINGLE definition…update agent/src/frame.rs」注释（frame.rs 不存在），改为说明 agent 侧常量手抄于 `agent/src/main.rs` §4.4 帧块、无独立 frame.rs；单源抽取（frame.rs）为跟踪 remedy，改动须同步两份。
> ③**删 GUI 死命令 `list_ifaces()`（S3 残余）**：`gui-tauri/src-tauri/src/lib.rs` 删除 powershell 枚举裸 IP 的死命令（main.js 实际只用 `list_ifaces_named`），invoke_handler 注册表同步移除——避免启动 panic。
> ④**README 重构（用户 m03786：GitHub 观感太乱）**：README.md 改为项目简介（功能/快速开始/构建/测试/文档索引/许可），版本行升 **1.48**；原 1571 行实验手册全文移至 `docs/M0A-MANUAL.md`（章节 0–10 与 v1.1–v1.47 修订记录原样保留，历史文档「README §X」引用仍可落位）；本块即 M0A-MANUAL.md 的 v1.48 登记。
> ⑤**用户决定**：跳过 M-1 真机验证与 SmartScreen（用户 m03786 明示「1，3.1 我早已经测试过了」）；M-1 视为用户已自测。
> **产物（本轮，桌面实际运行副本实测）**：`civlink-gui.exe` **11,490,816 B / sha256=`09B27773A866C0D90469EDE326744C9FE022407FAF6E0366BCA849E36F57B40A`**（3-tab + 本轮残余修复）；`civlink_hook.dll` 119,808B/`EA593FD2AAAC4A82B1C07FDE5D5EA48FAAD220F1046C9C3139DD5461D0E456B8`（in-flight 修复后）；`civlink_client.dll` 150,016B/`75B30ECAD3DC53E80037CD0D2D3F84CD6F9A4E48D7E5393C27CF0371BC2C3037`（未改语义，与 v1.47 相同源码）；`civlink_ctl.exe` 189,440B/`7F405492CB4A2BE0D2C57C160141439CE6A288B76C6AA41FFE831C597BC525E5`。agent 未动（615,936B/`A3905D09…5CA`，deploy-b 同步）。验证：build-msvc.cmd exit 0 + dumpbin 导出校验 PASS；`hook_selftest` PASS（0 failure）；`run-c2-iface-selftest.ps1` **50/50 runner + 74 in-process** 全绿；GUI `cargo build --release` exit 0（civlink-gui v0.1.0，lib.rs 变更已编译）。
> **边界（强制保留）**：不勾 E2-A/E2-B/E3、不移动 Gate A/B；**M-1 由用户自测跳过（m03786）**；Cargo.lock 必须 v3；README 重构不改变登记链语义（版本行仍在 README，修订历史在 M0A-MANUAL.md）；机械证据≠双人验证。

> **v1.49 修订记录（2026-11-23，用户 m03960 驱动：仓库打磨）**：①**清理**：`docs/M0E-DISCOVERY-COMPLETION-20261118.md.v1-backup`、`civlink/gui-tauri/src-tauri/icons/icon.old.ico`、`scripts/_tmp/txblock.txt` 三个零引用垃圾移至 `M0A/captures/audit-20261123-cleanup/`（可恢复）；`.bak-*`/`.v2-candidate`/`.v3` 预检脚本与 c2-cfg-*.txt 因被登记链引用保留；无跟踪 *.log。②**配图**：新增 `docs/images/architecture.png`(96,534B)/`usage-flow.png`(97,997B)/`topology.png`(92,624B)，生成脚本 `scripts/_tmp_gen/draw_diagrams.py`（PIL+微软雅黑，Navy 配色，1560px 宽，PIL getbbox 验证标签不溢出）。③**README v1.48→1.49**：重写为标准开源项目 README（徽章/简介/快速上手/功能/工作原理/图文并茂三图/构建/测试/仓库结构/文档索引/FAQ/许可），7,813B/`E8816E27913DEE278A428B09495065BFEF25F427C4BD585407B29E213B1CD726`/136 行/无 BOM/纯 CRLF。④**CI 现状**：`.github/workflows/build.yml` 仍仅构建 civtrace（windows-latest+msys2 gcc+MinHook clone+mingw32-make）；主产品 civlink（agent cargo 1.75 离线 vendored 构建 + GUI cargo 1.99）未接入 CI——保持登记为后续项。⑤**边界**：登记链语义不变（README 版本行 1.49 为顶层，修订历史在本文件 v1.1–v1.49）；M-1 由用户自测跳过；Cargo.lock v3；机械证据≠双人验证。
