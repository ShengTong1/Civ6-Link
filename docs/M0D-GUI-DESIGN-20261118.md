# M0D — CivLink 开源版 GUI 详细设计（2026-11-18）

> 文档定位：把 `docs/M0D-OPENSOURCE-PLAN-20261118.md` §5 的 GUI 设想、`docs/survey-gui-quality-20261118.md` 的调研结论、`civlink/ctl/civlink_ctl_gui.cs` 的 WinForms 雏形与 `civlink/ctl/civlink_ctl.cpp`、`civlink/agent/src/main.rs` 的真实命令行契约，收敛为一份可落盘、可审计、可逐阶段实施的产品级设计。
>
> 证据口径：本文每个技术断言尽量给出「路径:行号」或调研文件出处；凡是本机未实测、或依赖外部下载的，一律显式标注「待验证」。本机环境结论均来自本次实际执行（含 `pwsh`、`read`），不是臆测。
>
> 范围纪律：本文只设计「GUI 层 + 进程编排层」。C++ 侧的 `/MT` 静态 CRT、MinHook pin v1.3.4 属于 hook/ctl 构建约束（见 `docs/M0D-OPENSOURCE-PLAN-20261118.md`），GUI 不改动也不重新实现，仅知晓即可。
>
> **修订记录 / 审计基线（N-7）**：设计初稿由子代理 4952d916 产出（48,999 B / 425 行）；父代理补齐 §3.1.1 ctl 实测契约后为审计基线 **52,207 B / 437 内容行 / LF=438 / SHA-256 `d9dcc5e282515a47a8a4deecd5cca7cca70d4202cc0b52a7bf5af38e456155a0`**（见 `docs/M0D-GUI-DESIGN-REVIEW-20261118.md` 实测）。本版据此审计裁定（有条件通过、阻断 0）逐条关闭 N-1（Redactor 无条件脱敏 room 含 LAN 段）、N-2（--bind-ip 本机性由 GUI 下拉保证）、N-3（T1 验收三准则，output_sha256 变化不算篡改）、N-4（GUI 超时 ≥ ctl 内部等待）、N-5（普通 A 房主默认只注入不启 agent，模拟收进高级页，待负责人确认）、N-6（gui.cs 行号实读修正）、N-7（本注记）。本版为修订后版本，SHA-256 以最终落盘实测为准。

---

## 0. 术语与参考基线

| 缩写 | 含义 | 依据 |
|---|---|---|
| ctl | `civlink/ctl/civlink_ctl.exe`，注入/状态/计数/关闭子命令宿主 | `civlink/ctl/civlink_ctl.cpp` |
| agent | `civlink/agent/civlink-agent.exe`，回环 UDP 取证/模拟主机进程 | `civlink/agent/src/main.rs` |
| 托盘主进程 | 拟定名 `CivLinkTray.exe`，常驻托盘、承载五页签窗口、编排 ctl 与 agent | `docs/M0D-OPENSOURCE-PLAN-20261118.md` §5（行 218–243） |
| 机械证据 | F1/F2/F3/F5 自检、模拟主机、回环自测产生的证据 | `README.md` 状态行（行 4）、§8.1（行 299–304） |
| 双人验证 | 真实 Steam Win64《文明6》两台机器一轮对局闭环（M-1/E2-A/E2-B/E3 + Gate A） | `README.md` 行 4、`docs/M0D-OPENSOURCE-PLAN-20261118.md` §8.1（行 299–304） |

端口基线（来自 `docs/M0D-OPENSOURCE-PLAN-20261118.md` 附录 A，行 362–368）：发现广播 `255.255.255.255` UDP `62900–62999`（100 个端口，4B magic `8d e8 fc 70`）；公告页约 1104B（magic `59 60 69 9B`，22 页/房）；数据面 UDP `62056`；Agent 回环 IPC `127.0.0.1:34718`；C1 `--reserve-62900` 把 62900 让给游戏建房 socket。

---

## 1. 执行摘要 + 构建路径务实决策

### 1.1 执行摘要

CivLink v1.0 的 GUI 目标不是「好看」，而是「在不破坏已有安全与表述纪律的前提下，把已验证的 ctl 子命令包装成普通玩家可用的产品」。因此本设计遵循五条不可协商的产品决策：

1. **零遥测、零持久化日志**（用户决策 d5/d6；`docs/M0D-OPENSOURCE-PLAN-20261118.md` §9.1 决策 5/6，行 344–358）：GUI 不得内置 Sentry、匿名 ID、崩溃上报，也不得写任何常驻日志文件；诊断信息只在用户显式点击时于内存中组装、以「一次性导出文件」形式落盘，且导出的内容必须脱敏（见 §4.1/§4.2）。
2. **asInvoker 普通权限运行**：GUI 运行时全部普通权限；唯一管理员操作是安装期写防火墙规则（安装器阶段，不属于 GUI 运行时）。ctl 注入依赖 `SeDebugPrivilege`，但 `civlink_ctl.cpp` 的 `EnableDebugPrivilege`（行 52–78）只是尝试调整令牌权限、无自提权，权限不足仅告警——这与「GUI 不提权」一致，GUI 侧不得尝试 `runas`（`civlink/ctl/civlink_ctl_gui.cs` 行 4 注释即「本版未实现自提权」）。
3. **1:1 复用 ctl，不重写 IPC**：数据绑定层 v1.0 直接以进程调用 `civlink_ctl.exe`，复用其全部参数解析、白名单校验、重复注入检测、PE 身份校验与退出码语义（`docs/M0D-OPENSOURCE-PLAN-20261118.md` §5 数据绑定条目，行 218–243）。GUI 不得另写一套注入逻辑或直连 agent 的新协议。
4. **机械证据 ≠ 双人验证**：状态页与诊断页一律使用「观察/探针/机械自检」措辞，禁止出现「联机已验证」「已双人对局」等断言，除非 `README.md` 行 4 记录的 M-1/E2-A/E2-B/E3 + Gate A 全部完成（§8.1，行 299–304）。当前 `README.md` 行 4 明确 E2-B/E3 未完成、Gate A 未批准，故本版 GUI 必须默认处于「未验证」话术状态。
5. **白名单注入，绝不通用化**：GUI 只提供「选择白名单进程（CivilizationVI_DX12.exe / CivilizationVI.exe / CivilizationVI_DX11.exe 等待验证的官方可执行名）」的下拉，绝不提供「注入任意 PID」输入框；`civlink_ctl_gui.cs` 现有的 `pidBox`（实读 :18；`ProbeProcess` 在 :107–124，审计 N-6 行号修正）是历史雏形，在新 GUI 中必须被「白名单发现列表 + 只读 PID 展示」替换（见 §2.2）。

### 1.2 三种构建路径的务实评估

> 前提事实（本机实测，2026-11-18）：
>
> - **无 .NET SDK**：`dotnet --version` / `dotnet --list-sdks` 均报「No .NET SDKs were found」。
> - **有运行时**：`Microsoft.NETCore.App` 6.0.11/8.0.3、`Microsoft.WindowsDesktop.App` 6.0.11/8.0.3（内含 PresentationFramework.dll / PresentationCore.dll / WindowsBase.dll / System.Xaml.dll / System.Windows.Forms.dll / System.Drawing.dll）在 shared 目录存在。
> - **有编译器**：`D:\MSVC\BuildTools\MSBuild\Current\Bin\Roslyn\csc.exe`，版本 `5.11.0-1.26424.5 (fcacacf82e2055472a6ec4060a4be88ebc0e1acf)`。
> - **无官方 .NET Framework 引用程序集**：`C:\Program Files (x86)\Reference Assemblies\Microsoft\Framework\.NETFramework` 不存在。
> - **无 .NET SDK ref pack**：`C:\Program Files\dotnet\packs` 不存在（无 `Microsoft.WindowsDesktop.App.Ref` / `Microsoft.NETCore.App.Ref`）。
> - **但有 Windows 自带 .NET Framework 4.8 运行时程序集可作编译引用**：`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\` 下有 `System.Windows.Forms.dll`（5,997,968B，4.8.9256.0）、`System.Drawing.dll`（596,288B，4.8.9032.0）、`mscorlib.dll`（5,445,664B，4.8.9310.0）、`System.dll`（3,540,040B，4.8.9310.0），共 276 个 DLL。
> - **实测（父代理 2026-11-18）：WinForms 雏形已用当前 csc 重编成功** —— `D:\MSVC\BuildTools\MSBuild\Current\Bin\Roslyn\csc.exe /nologo /target:winexe /optimize+ /r:System.Windows.Forms.dll /r:System.Drawing.dll civlink_ctl_gui.cs` → EXIT=0，产出 9,216 B；且裸 DLL 名即可解析（csc 默认 mscorlib），无需显式写 Framework64 路径。
> - **实测（父代理 2026-11-18）：WPF 纯代码（无 XAML）亦可用 csc 编译成功** —— `csc /nostdlib+` + 引用 `C:\Program Files\dotnet\shared\Microsoft.NETCore.App\8.0.3\{System.Private.CoreLib.dll,System.Runtime.dll,System.ObjectModel.dll,System.Console.dll}` 与 `C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App\8.0.3\{PresentationFramework.dll,PresentationCore.dll,WindowsBase.dll,System.Xaml.dll}`，最小 `Application`+`Window` C# → EXIT=0，产出 4,096 B。但这是 .NET Core 程序集，运行需同名 `.runtimeconfig.json`（指定 Microsoft.WindowsDesktop.App 8.0.3 framework），且无 XAML 编译器 → UI 必须纯代码构建。
> - **实测（父代理 2026-11-18，WPF 运行链完整打通）**：编译一个引用 `Type.GetType("System.Windows.Window, PresentationFramework")` 的控制台 exe + 手写 `typeprobe.runtimeconfig.json`（内容 `{"runtimeOptions":{"tfm":"net8.0","framework":{"name":"Microsoft.WindowsDesktop.App","version":"8.0.3"}}}`）→ `C:\Program Files\dotnet\dotnet.exe typeprobe.exe` → EXIT=0 且输出 `WPF_TYPE_OK=System.Windows.Window`。即「csc `/nostdlib+` 编译 + 手写 runtimeconfig + dotnet 启动 + WPF 类型加载」全链路已验证可行。
> - 当前磁盘 `civlink/ctl/` 只有 `civlink_ctl_gui.cs`（6,450B），**没有**预编译的 gui exe；用户口述曾编译出 8,704B 的 exe，属历史记录。本次已实测重编为 9,216 B（见上），验收以实际编译产物为准，不引用 8,704B 作为验收值。

| 路径 | 做法 | 前置条件 | 风险 | 结论 |
|---|---|---|---|---|
| **(A) 保持 WinForms + csc 直接编译** | 沿用 `civlink_ctl_gui.cs` 的 `csc /target:winexe /r:System.Windows.Forms.dll /r:System.Drawing.dll` 模式（行 3–4 编译注释） | 已满足且**已实测**：csc 存在、雏形用当前 csc 重编 EXIT=0（产出 9,216 B）、csc 默认 mscorlib 可解析裸引用名 | 低：UI 现代化程度不如 WPF；引用解析依赖 csc 默认行为（已实测通过） | **推荐（P1 主路径）** |
| **(B) WPF 纯 C# 无 XAML + csc 引用 WindowsDesktop.Ref** | 用 `csc` 直接编译纯 C# 构造的 WPF（不用 XAML 编译），`/nostdlib+` + 引用 shared 运行库实现 DLL | 阻塞（官方 ref pack 仍缺：`C:\Program Files\dotnet\packs` 不存在），但**已实测编译 + 运行全链路打通**：`/nostdlib+` + 8.0.3 CoreLib/System.Runtime/ObjectModel/Console + PresentationFramework/PresentationCore/WindowsBase/System.Xaml → EXIT=0（4,096 B）；手写 `typeprobe.runtimeconfig.json` + `dotnet typeprobe.exe` → `WPF_TYPE_OK=System.Windows.Window`。需额外承担：(a) 手写同名 `.runtimeconfig.json`（指定 Microsoft.WindowsDesktop.App 8.0.3）；(b) 纯代码 UI、无 XAML 设计器/静态资源；(c) 目标机须装 .NET Desktop Runtime 8.0.3 | 中高：编译/运行障碍均已实测消除，但运行分发多一层 runtimeconfig + 运行时依赖；无 XAML 使 DataBinding/MVVM 优势打折；目标机需预装 Desktop Runtime（WinForms 路径无此要求） | **不作为 P1；列为 P3 升级的备选实现（待产品确认）** |
| **(C) 下载 .NET SDK 走标准 WPF** | 联网下载 .NET SDK（如 8.0 SDK），用 `dotnet build` + 标准 WPF/XAML 项目，正规使用 `Microsoft.WindowsDesktop.App.Ref` | 未知：用户未确认可联网；下载体积大、时间成本高；SDK 到位后仍满足「与 ctl 同语言（C#）复用」约束 | 中：可执行但取决于网络与时间；引入 MSBuild/nuget 供应链（§6 企业级清单的供应链门禁项） | **推荐作为 P3 升级路径**（SDK 可得时再迁 WPF，见 §7.2） |

**推荐结论（纳入父代理实测后保持不变，且依据更充分）**：P1 仍采用 **(A) WinForms + csc**。理由：

1. **最短且已验证的可用路径**：雏形已用当前 csc + 裸 DLL 名重编成功（EXIT=0，9,216 B），无任何运行前置分发物（无 runtimeconfig、无目标机 Desktop Runtime 要求），csc 直接产出可跑 exe。
2. **为何放弃已验证的 WPF 全链路 (B)**：父代理已实测「csc 编译 + 手写 runtimeconfig + dotnet 启动 + WPF 类型加载」全链路可行（`WPF_TYPE_OK=System.Windows.Window`），这条链不再是「待验证」——放弃它**不是因为技术不可行，而是因为分发成本与收益不匹配**。B 路径要额外承担 (a) 手写 runtimeconfig.json、(b) 纯代码 UI（无 XAML 设计器，DataBinding/MVVM 优势大打折扣）、(c) 目标机必须安装 .NET Desktop Runtime 8.0.3（WinForms 路径的 exe 无需任何运行时分发）；而 v1.0 的优先级是「稳定、兼容、安全」而非 UI 现代化。对普通游戏玩家，「双击即跑、零依赖」比「更现代的控件外观」更有价值。因此把已验证的 WPF 链保留为 P3 升级的技术储备，不在 P1 引入这些分发变量。
3. **不违背调研结论**：WPF 是 `docs/M0D-OPENSOURCE-PLAN-20261118.md` §5 与调研文件（行 24–64）的「主选框架」，但那是产品目标而非当前构建现实；把 (C) 定为 P3 升级目标（走标准 SDK + XAML），(B) 作为 P3 的可行备选实现，既尊重调研也不臆测 SDK 已存在。

> **T1 前置条件（构建底座验证，必须先做）**：
> 1. 固定 csc 绝对路径 `D:\MSVC\BuildTools\MSBuild\Current\Bin\Roslyn\csc.exe`；
> 2. 编译命令参数顺序固定，沿用父代理已验证可行的形态：`/nologo /target:winexe /optimize+ /r:System.Windows.Forms.dll /r:System.Drawing.dll civlink_ctl_gui.cs`（csc 默认 mscorlib，裸引用名已实测可解析；如需进一步固化，可显式加 `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\` 前缀，该目录下 4 个核心 DLL 已实测存在：System.Windows.Forms.dll 5,997,968B / 4.8.9256.0、System.Drawing.dll 596,288B、mscorlib.dll 5,445,664B、System.dll 3,540,040B，共 276 个 DLL）；
> 3. 用现有 `civlink/ctl/civlink_ctl_gui.cs` 原样跑一次，确认零错误产出 exe（父代理实测 9,216 B，作为可复现校验值；历史口述 8,704B 不作验收依据）；
> 4. 产出可复现构建脚本（无环境变量依赖）与构建产物哈希（SHA-256），作为 §5 T1 的独立审计产物。
> 上述任何一步失败即停，不允许带着未验证的构建底座进入 T2。

---

## 2. 产品级 GUI 详细规格

### 2.1 总体架构：托盘主进程 + agent 子进程

进程模型严格遵循 `docs/M0D-OPENSOURCE-PLAN-20261118.md` §5（行 218–243）与 `docs/survey-gui-quality-20261118.md`（行 100–113）：

```
CivLinkTray.exe（asInvoker，普通权限，常驻托盘）
├── UI 主窗口：五页签（注入 / 状态 / 计数 / 设置 / 诊断）
├── CtlRunner：同步进程调用 civlink_ctl.exe（每次调用一个短命子进程）
├── AgentSupervisor：启动/停止 civlink-agent.exe 子进程（长命，回环 :34718）
└── DomainGate：白名单 / 表述纪律 / 零遥测零日志的集中拦截层

civlink_ctl.exe（短命子进程，继承普通权限；注入靠 ctl 自身 AdjustTokenPrivileges）
civlink-agent.exe（长命子进程，--out-dir 由 GUI 指定；仅回环监听）
```

- **托盘图标三态**（`docs/M0D-OPENSOURCE-PLAN-20261118.md` §5）：绿 = agent 运行中、黄 = 游戏已注入（注入命令返回 0）、红 = 错误（ctl exit 非 0 或 agent 异常退出）；托盘右键菜单：打开主窗口 / 启动或停止 agent / 退出。不使用 Windows 服务（调研文件行 100–113：托盘模型对普通玩家更可控，服务需管理员安装且无桌面交互）。
- **不使用 Windows 服务的额外理由**：服务安装需要管理员权限，违反「GUI 运行时全普通权限」硬约束。
- **托盘 asInvoker 清单**：可执行内嵌 manifest 的 `requestedExecutionLevel level="asInvoker"`，禁止 `requireAdministrator`（`docs/survey-gui-quality-20261118.md` 行 115–125）。
- **父子生命周期**：GUI 退出时先经 AgentSupervisor 写 stop-file 停 agent（§3.3），再退出；ctl 是短命进程，无需常驻管理。

### 2.2 页签 A：注入向导（Inject）

**定位**：把房主（A 角色）与客户端（B 角色）的两条 ctl 路径做成两步向导，避免玩家记命令。依据：`README.md` v1.34 修订（行 1477–1480）定义的双角色：`--reserve-62900`（A 房主侧 C1）与 `civlink_client.dll` + `--iface`（B 客户端侧 C2）。

**控件清单**：

| 控件 | 类型 | 行为/绑定 | 证据 |
|---|---|---|---|
| 角色选择 | RadioButton ×2 | 「A 房主（发现主机）」/「B 客户端（加入房间）」 | `README.md` 行 1471–1480 |
| 目标进程下拉 | ComboBox（只读数据绑定） | 由白名单发现填充：`Process.GetProcessesByName` 扫描 `CivilizationVI_DX12` / `CivilizationVI` / `CivilizationVI_DX11`（名称待产品确认）等官方名；显示 `名称 + PID + 启动时间`，**不接受手动输入 PID** | 雏形 `ProbeProcess`（`civlink_ctl_gui.cs` 行 107–124）；白名单约束见硬约束 |
| 刷新按钮 | Button | 重新枚举白名单进程；无匹配时显示「未发现《文明6》进程，请先以 Steam Win64 启动游戏」 | 硬约束「仅 Steam Win64」 |
| 模块下拉 | ComboBox | A 角色：`civlink_hook.dll`；B 角色：`civlink_client.dll`（`civlink_ctl.cpp` 行 363–364 默认模块）；路径默认取 ctl 同目录，允许浏览但限制在应用目录下（待验证：目录白名单策略） | `civlink_ctl.cpp` 行 363–364 |
| `--iface` 本机接口下拉 + ALL | ComboBox | B 角色必填：枚举本机 live IPv4（`NetworkInterface` + `UnicastIPAddressInformation`），排除 loopback（ctl 侧 `civlink_ctl.cpp` 行 380–385 拒绝 loopback，GUI 侧前置过滤），项格式 `IP（适配器名）`；含固定项 `ALL（不干预，零干预模式）` | `--iface` 语义见 `civlink_ctl.cpp` 行 206–246（`ResolveIface` fail-closed exit 1）、`README.md` 行 1471–1476（C2） |
| `--reserve-62900` 开关 | CheckBox | A 角色可见，默认**勾选**（对应 C1 根治建房卡住）；说明文字「把 62900 留给游戏建房 socket」 | `README.md` 行 1471–1476（C1）；附录 A 行 362–368 |
| 注入按钮 | Button | 组装命令（见下），调 `CtlRunner`，显示中文结果 | 复用 `civlink_ctl.cpp` 契约 |
| 关闭注入按钮 | Button | 调 `shutdown`（不 FreeLibrary，见 §2.3 状态页说明） | `civlink_ctl.cpp` 行 590–598 |

**命令拼装（唯一合法路径）**：

- A 房主：`civlink_ctl.exe inject -x "<白名单进程名>" -m civlink_hook.dll`（`-d` 旧接口仅保留兼容，新 GUI 优先用 `-m`；`civlink_ctl.cpp` 行 337–344 Usage）。`--reserve-62900` 是 **agent 侧参数，不属于 ctl**——GUI 在 A 角色启动 agent 时拼入 `--reserve-62900`（配合 `--sim-lan-listen`，见 §2.6/§3.3 与 `README.md` 行 1471–1476、`civlink/agent/src/main.rs` 行 1479/1547–1548）。
- B 客户端：`civlink_ctl.exe inject-client -x "<白名单进程名>" -m civlink_client.dll --iface <IP|ALL>`（`civlink_ctl.cpp` 行 363–364、行 206–246）。

**数据流**：

1. 用户选角色 → 显示/隐藏 `--iface`、`--reserve-62900` 控件；
2. 点「刷新」→ Process 枚举 → 绑定白名单列表（PID 只读展示）；
3. 点「注入」→ 先执行前置检查（重复注入检测、位数、PE 身份，均由 ctl 内部完成，GUI 只负责调用与结果呈现）→ `ProcessStartInfo` 调 ctl → 捕获 stdout/stderr + exit code；
4. exit 0 → 托盘转黄、状态页刷新；exit 非 0 → 按 §3.2 映射中文提示。

**错误处理与边界语**：

- 重复注入：ctl 以 `QueryRemoteModule==1` 报 "already loaded ... not injecting twice"（`civlink_ctl.cpp` 行 458–466），GUI 映射为「检测到目标已加载 CivLink 模块，已跳过重复注入，未做任何改动」；`q<0`（查询失败）映射为「无法确认模块状态，已拒绝盲目注入，请重试或检查权限」。
- 位数不符：`IsWow64Process` 检查失败（行 445–456）→「仅支持 64 位《文明6》，当前进程不符合，未注入」。
- PE 身份不符：`RemotePeIdentity`（行 166–180）→ exit 3 →「目标可执行文件与预期不符，已拒绝注入」。
- `--iface` 非法：ctl fail-closed exit 1（行 206–246、380–385）→「本机接口无效或为回环地址，请选择有效网卡或 ALL」。
- N-2 已知遗留：inject-client 写 `client-iface.txt` 早于 `OpenProcess`（`README.md` 行 1475），注入失败可能残留接口配置；GUI 在提示中如实告知「若注入失败，接口配置可能已写入，如需清除请手动删除 `%LOCALAPPDATA%\CivLink\client-iface.txt`」（该路径来自 `civlink_ctl.cpp` 行 262–293，**以实际运行为准，待验证**）。GUI 不自动删该文件，避免改动哈希链保护的代码行为。
- **边界语（强制）**：注入成功后只显示「模块已注入（机械动作完成）」，**不得**显示「联机成功」「已验证双人」；状态页话术见 §2.3。

### 2.3 页签 B：状态页（Status）

**控件清单**：

| 控件 | 类型 | 绑定/行为 | 证据 |
|---|---|---|---|
| 目标进程显示 | Label（只读） | 显示当前白名单目标名/PID，来自注入页选择 | 雏形 `-x` 参数约定（`civlink_ctl_gui.cs` 行 57–64） |
| 模块状态 | Label + 颜色 | 调 `status`，解析 stdout 的 `running` / `init` / `shutdown` 语义 | `civlink_ctl.cpp` 行 576–588：`CivLinkHookState` 返回 1=running/0=init/-1=shutdown（DWORD 转 int），state==1 → exit 0，否则 exit 1 |
| 自动刷新 | CheckBox + Timer | 默认每 3s 调一次 `status`（轮询策略见 §3.4） | `docs/M0D-OPENSOURCE-PLAN-20261118.md` §5 |
| 验证状态区 | Label（**固定话术**） | 恒显示：「本工具仅报告本机机械状态；联机是否成功需在游戏内确认。当前项目状态：双人验证未完成（Gate A 未批准）」 | `README.md` 行 4、`docs/M0D-OPENSOURCE-PLAN-20261118.md` §8.1（行 299–304） |
| 注入/关闭按钮 | Button | 与注入页共用同一命令入口（防止两套逻辑漂移） | — |

**数据流**：Timer → 若注入页已选定目标 → 调 `status` → 解析输出。注意 ctl 的 `status` 在未显式 `-m` 时自动探测已加载的 `hook.dll`/`client.dll`（`civlink_ctl.cpp` 行 415–423），GUI 可省略 `-m`，但为可审计性建议显式传 `-m` 与注入页一致。

**错误处理**：exit 1（模块未处于 running）不是「错误弹窗」，而是状态呈现为「初始化中/已关闭」；exit 2/3/4/5 按 §3.2 映射；超时按 §3.1 的超时策略处理。

**硬边界**：状态页任何元素都不得把 F1/F2/F3/F5 机械自检、`--sim-lan-listen` 模拟主机、探针证据显示为「联机已验证」。`README.md` v1.34（行 1477–1480）明确 C2-b 仅是「机制层跨机验证完成（探针级）；真实游戏跨机对局待验证」，replySrc 是间接证据——GUI 若展示 replySrc（诊断页），必须附同样说明。

### 2.4 页签 C：计数页（Counters）

**控件清单**：

| 控件 | 类型 | 绑定/行为 | 证据 |
|---|---|---|---|
| 计数器 DataGridView | 只读表格 | 调 `counters`，逐行解析 stdout 字段 | `civlink_ctl.cpp` 行 600–673 |
| 关键点高亮 | 条件格式 | `bind 62056` / `recv on 62056` / `cvlh2 ok/fail` / `sent` / `send fail` 等关键计数用颜色区分 | 同上 |
| 刷新按钮 | Button | 单次调用 | — |
| 可信度提示 | Label（常驻） | 「若 magic 校验失败，ctl 返回 exit 4『do not trust these numbers』，本页不显示任何数字」 | `civlink_ctl.cpp` 行 600–673（magic 校验） |

**数据流与字段**：ctl 从共享内存读 `CivLinkCounters` 结构并文本化，字段包括 version、session id、running、shutdown、shutdownLeft、init error、sent、send fail、reject oversize、sent notify、ignored、scatter-gather、sock overflow、src unknown、state queries、observed frames、raw sendto/wsasendto/bind/recvfrom/wsarecvfrom、bind 62056、recv on 62056、wsarecv pending、cvlh2 try/ok/fail/errno、channel down、accounted（依据：`civlink_ctl.cpp` 行 600–673）。GUI 的解析器需容忍字段增减（未知键原样展示为「其他」行），不因新增字段崩溃。

**错误处理**：exit 3（模块未加载）→「尚未注入，无计数可读」；exit 4 →「计数块校验失败，数据不可信，已隐藏」；exit 2/5 按 §3.2。**计数是本机 hook 的观测值，不是对端到达证明**——表格底部常驻说明：「以上为本机进程内计数，不代表对端收到」。

### 2.5 页签 D：设置页（Settings）

**控件清单与边界**：

| 控件 | 类型 | 行为 | 约束/证据 |
|---|---|---|---|
| ctl 路径 | TextBox（只读）+ 浏览按钮 | 默认 GUI 同目录 `civlink_ctl.exe`；浏览限制在应用目录内 | 雏形 `RunCtl`（`civlink_ctl_gui.cs` 行 71–105）同目录约定 |
| agent 路径 | TextBox（只读）+ 浏览按钮 | 默认 GUI 同目录 `civlink-agent.exe`（若随包发布；待验证：发布布局） | `civlink/agent/src/main.rs` |
| 白名单进程名 | 只读列表 | 展示支持的《文明6》官方进程名；**不可编辑** | 硬约束「绝不提供注入任意 PID」 |
| 接口刷新策略 | ComboBox | 控制注入页 `--iface` 列表的刷新时机（启动时 / 每次打开注入页） | `civlink_ctl.cpp` 行 206–246 |
| 状态轮询间隔 | NumericUpDown | 默认 3s，范围 1–30s | §3.4 |
| 遥测/日志开关 | **不存在** | 设置页不得出现任何「开启遥测 / 写日志 / 崩溃上报」开关；若未来有人加入，审计直接判失败 | 用户 d5/d6、`docs/M0D-OPENSOURCE-PLAN-20261118.md` §9.1 行 344–358 |
| 持久化 | 无 | v1.0 设置只在内存生效（程序退出即还原默认），不写配置文件——避免引入持久化日志争议；如确需记住 ctl 路径，v1.0 不做（待产品确认） | 零持久化日志硬约束 |

### 2.6 页签 E：诊断页（Diagnostics）

**定位**：一键导出「诊断包」，但内容必须脱敏且零常驻日志（§4.1/§4.2）。诊断页本身不显示日志窗口，而是显示「上次导出时间（内存）/ 导出结果」。

**控件清单**：

| 控件 | 类型 | 行为 | 证据 |
|---|---|---|---|
| 导出诊断包按钮 | Button | 在内存中汇总 counters + agent summary + 环境信息，脱敏后写用户选择路径的单个 `.txt`/`.zip`（格式待产品确认），写后立即释放内存缓冲区 | §4.2 |
| agent summary 预览 | ReadOnly TextBox | 若 agent 本次运行产生 `summary.txt`，按 §4.1 脱敏后展示；否则显示「本次未运行 agent，无 summary」 | `civlink/agent/src/main.rs` 行 2032–2250 |
| 环境信息预览 | ReadOnly TextBox |  OS 版本、.NET 运行时版本、csc/ctl/agent 文件版本与 SHA-256（对文件算哈希，不是日志） | §4.1 |
| 边界语 | Label（常驻） | 「诊断包为现场排障快照；机械计数与探针证据不构成双人联机验证」 | `README.md` 行 4/行 1477–1480 |

**agent summary 关键字段**（供解析与脱敏，来自 `civlink/agent/src/main.rs` 行 2032–2250）：版本、run time、listen window、datagrams、bytes、received frames(processed/rejected)、reconciliation、reject kinds、sessions（seq gaps/duplicates/out_of_order 等）、simulated host / LAN simulated host 段（room、reply source、pages sent 等）、real advertisement capture 段、datapath observation 段（含 `--loopback-selftest` 标注）。GUI 解析时按段落标签（`\nsimulated host`、`\nLAN simulated host`、`\nreal advertisement capture`、`\ndatapath observation`）切分，未知段落原样保留。

### 2.7 注入向导与 agent 的联动（A/B 角色完整流程）

本段把 `--reserve-62900`（A 侧）与 `--iface`（B 侧）如何落到 agent/ctl 上说清楚，避免 GUI 把 ctl 参数与 agent 参数混用：

- **A 房主路径（N-5 产品裁定，2026-11-18）**：
  1. **普通 A 房主默认流程 = 只注入 hook、不启 agent、不启用任何 `--sim-*` 模拟**：注入页选「A 房主」，模块 `civlink_hook.dll`，注入命令 `inject -x <白名单名> -m civlink_hook.dll`，然后在游戏内正常建房。理由：C1/C2 的 `--sim-lan-listen`/`--reserve-62900`/`--simulate` 整套是**模拟房主/自检能力**（用于 F1/F2/F5 机械验证），不是普通玩家建真实房所必需；真实建房时游戏自己占 62900 并应答发现，agent 模拟层反而会与游戏抢端口/制造虚拟房间（M0-B 已证实"真实房与虚拟房同 IP 去重致虚拟房不可见"）。GUI 默认不启动 agent，保证「三步即用」且不干扰对局。
  2. **模拟/自检能力收进「高级」页签**（非默认、显式标注「模拟模式，非真实对局」）：仅当用户主动进入高级页并勾选「启动模拟房主 agent」时，托盘才以 `civlink-agent.exe --listen-seconds 0 --out-dir <临时目录> --sim-lan-listen <LAN IP> --reserve-62900 --quiet --stop-file <文件>` 启动（`--reserve-62900` 仅在 `--sim-lan-listen` 时生效，plain `--simulate` 仍绑 62900：`civlink/agent/src/main.rs` 行 1547–1548；Usage 行 1522–1527）。此路径面向自检/调试，不作为普通玩家默认流程。
  3. `--reserve-62900` 让 agent 不绑 62900、留给游戏建房 socket（C1 修复 m25442 建房卡住，`README.md` 行 1471–1476）——该约束只在高级页模拟路径生效。
  4. **状态**：上述默认流程为本设计的裁定建议，**仍待项目负责人最终确认**；T2 实现按此默认（普通 A 不启 agent），高级页保留模拟入口，若负责人另有裁定再调整。
- **B 客户端路径**：
  1. 注入页选「B 客户端」，模块 `civlink_client.dll`，`--iface` 选本机 IPv4 或 ALL；
  2. 命令 `inject-client -x <白名单名> -m civlink_client.dll --iface <IP|ALL>`；ctl 在目标解析与接口校验通过后才写 `client-iface.txt`（`civlink_ctl.cpp` 行 398–403 顺序修复），路径 `%LOCALAPPDATA%\CivLink\client-iface.txt`（行 262–293）。
  3. GUI 在注入成功后只提示「客户端接口配置已写入（机械动作完成）」，**不得**提示「已连接房主」。

---

## 3. 进程调用与 IPC 设计

### 3.1 CtlRunner：ProcessStartInfo 契约

复用并强化 `civlink/ctl/civlink_ctl_gui.cs` 的 `RunCtl`（行 71–105）已验证模式：

```text
ProcessStartInfo psi = new ProcessStartInfo();
psi.FileName = ctlPath;                    // 同目录 civlink_ctl.exe
psi.Arguments = 拼装后的参数串;             // 见 §2.2/§2.3/§2.4
psi.UseShellExecute = false;               // 避免 Shell 提权与路径注入（雏形 :87）
psi.RedirectStandardOutput = true;         // 雏形 :88
psi.RedirectStandardError = true;          // 雏形 :89
psi.CreateNoWindow = true;                 // 雏形 :90
// 禁止 psi.Verb = "runas"：GUI 运行时全 asInvoker
```

- **参数转义**：复用雏形 `Quote`（行 66–69）的双引号包裹，对 `"`, `\` 做转义；`--iface` 与 `-x/-m` 的值一律经白名单/枚举校验后再拼接，不接受自由文本（防参数注入）。
- **读取顺序**：先 `ReadToEnd` 异步读取 stdout/stderr（避免管道缓冲区死锁），再 `WaitForExit`（雏形 :93–95 用同步 ReadToEnd + WaitForExit，P1 沿用；若出现大输出阻塞，P3 改异步——待验证）。
- **超时（审计 N-4 修正）**：GUI 超时必须 **≥ ctl 内部最大固定等待 + 余量**，否则提前 `Kill()` ctl 不会终止其已在游戏进程内 `CreateRemoteThread` 的远程线程，可能遗留半注入状态、触及「不干扰真实对局」硬约束。实读 `civlink_ctl.cpp:301`（RemoteCallInt 15s）/`:501`（LoadLibrary 15s）/`:620`（counters 10s），故超时设为 **inject/inject-client 20s、status 20s、counters 15s、shutdown 15s**（均为实测后的下限建议，待 T2/T3 实机微调）。超时处理顺序：先查询远程模块状态再决定是否清理，并在诊断包记录本次超时（内存态，不落盘）；`Kill()` 整个进程树仅作为最后手段，映射为「操作超时，已终止调用（远程线程状态未知，请导出诊断包）」。ctl 的 `-w` 参数（`civlink_ctl.cpp` Usage 行 12–18，状态等待秒数）仅在需要时显式传，避免无限等待。
- **exit code 不丢弃**：雏形已在输出末尾打印 `[exit code:N]`（雏形 :98），新 GUI 必须结构化保留 `ExitCode` 整数用于 §3.2 映射，而不是只展示字符串。

### 3.1.1 ctl 子进程实测契约（父代理 2026-11-18 实测，解析器设计依据）

> 被测产物：`civlink_ctl.exe`，188,416 B，SHA-256 前缀 `6FCE456E…`（完整值待 T1 构建清单固定，此处不臆造）。GUI 解析器应针对该形态设计，若换版本需重跑契约核验。

| 实测场景 | exit | 输出实测 | 对 GUI 解析器的含义 |
|---|---|---|---|
| 无参数调用 | 1 | stdout 533 B：`civlink_ctl v0.2.0-f2 ...` + Usage（列出 `inject` / `inject-client` / `status` / `counters` / `shutdown` 五个子命令及参数） | GUI 永远不应无参数调用 ctl；若收到含版本串 + Usage 的 stdout，视为「参数错误（exit 1）」而非崩溃；版本串 `v0.2.0-f2` 可在诊断包中记录（脱敏后） |
| 目标不存在 `status -x __no_such_game__.exe` | 2 | stdout 含 `[!] target process not found (or ambiguous)` | exit 2 的「目标未找到/歧义」以 stdout 关键字为准，可细化为「未发现该游戏进程」提示 |
| 显式 pid 无效 `status -x <name> -p 999999` | 2 | stdout 含 `[*] target pid=999999`、`pid=999999 -> (OpenProcess failed err=87)`、`[!] SeDebugPrivilege not granted - run elevated if the target is elevated`、`[!] OpenProcess failed err=87` | exit 2 也可能是「目标已提权导致 OpenProcess 失败」，不只是「找不到进程」；GUI 提示需覆盖两种情形（见 §3.2） |
| 全部场景 | — | **所有输出走 stdout，stderr = 0 B** | GUI 解析以 `StandardOutput` 为唯一数据来源；`RedirectStandardError=true` 仍保留作防御性捕获（若未来版本写 stderr），但不得依赖 stderr 判断错误 |

**与 asInvoker 硬约束的衔接（必须如实处理）**：实测输出中 ctl 自报 `SeDebugPrivilege not granted - run elevated if the target is elevated`，这是 **ctl 自身对目标已提权情形的提示文案**，`civlink_ctl.cpp` 的 `EnableDebugPrivilege`（行 52–78）也仅尝试调整令牌、无自提权。GUI 层**不执行**该文案暗示的提权动作（禁止 `psi.Verb = "runas"`，运行时全普通权限，硬约束）。GUI 的正确行为是：把 exit 2 + `OpenProcess failed` / `SeDebugPrivilege` 关键字映射为「目标进程无法打开：请确认《文明6》以普通权限启动、未被管理员权限运行后重试（本工具不申请管理员权限）」。「Steam Win64 正常启动的《文明6》是否始终普通权限、从而无需提权即可注入」为**待验证**的产品前提，需在 T2/T5 实机核验；若实机必须提权，则该矛盾应作为开放问题上报（§7.4），GUI 不得私自加提权按钮。

### 3.2 exit code 0–5 中文映射

依据 `civlink/ctl/civlink_ctl.cpp` 行 26–27 的注释语义：

| exit code | ctl 语义（源码） | GUI 中文提示（用户可见） |
|---|---|---|
| 0 | 成功 | 操作完成（机械动作已执行）。注入场景追加「这不代表联机验证通过」 |
| 1 | usage 或前置失败（含 `--iface` 非法、接口非本机 live IPv4、loopback 被拒、无自提权告警等） | 参数或前置条件不满足：请检查目标进程/接口选择；若提示权限不足，请以普通权限重试（安装期防火墙规则应由安装器完成） |
| 2 | 目标未找到或歧义（实测亦含「目标已提权致 OpenProcess 失败」，见 §3.1.1） | 无法打开目标进程：请确认《文明6》正在以普通权限运行并点「刷新」重选；若游戏以管理员身份运行，本工具不申请提权，请以普通权限重启游戏后重试 |
| 3 | 模块未加载（或 PE 身份校验不符） | 模块未加载或目标可执行文件与预期不符：已拒绝操作，未做任何注入 |
| 4 | 远程调用失败（含 counters magic 校验失败） | 远程状态不可信或调用失败：计数/状态数据已隐藏，请重试 |
| 5 | 状态超时 | 等待目标状态超时：目标可能正忙，请稍后重试 |

映射实现要求：集中在一个 `ExitCodeMapper.Map(int, Command)` 函数中，审计可逐条核对；未知 code 映射为「未预期结果（code=N），请导出诊断包反馈」而非静默成功。

### 3.3 AgentSupervisor：子进程启停与 stop-file 纪律

**启动**（参数全部来自 `civlink/agent/src/main.rs` Usage 行 1522–1527，禁止发明新参数）：

- 基础：`--listen-seconds <N 或 0> --out-dir <目录> [--quiet] --stop-file <文件>`；`--listen-seconds 0` 表示「直到 Ctrl+C」（行 1723），GUI 用 stop-file 而非 Ctrl+C 停止。
- 可选（仅模拟/自检场景，普通玩家默认不启用）：`--simulate <fixture>`、`--sim-lan-listen <IP>`、`--sim-room-name <NAME>`、`--sim-real-capture`、`--reserve-62900`、`--simulate-datapath --bind-ip <本机地址>`、`--loopback-selftest`。这些参数与 `README.md` 的 F1/F2/F5 自检口径一致，GUI 必须在启用时于界面显式标注「模拟/自检模式，非真实对局」。
- `--bind-ip` 校验（审计 N-2 修正，实读 `civlink/agent/src/main.rs` 行 891–892/2629–2631）：**agent 侧只做点分四段格式校验并拒 `0.0.0.0`/`255.255.255.255`，并不验证是否本机地址**；「本机性」由 GUI 侧下拉枚举本机 IPv4 保证，不能高估为 agent 的安全属性。GUI 下拉只列本机 IPv4 是这一约束的实际落点。

**端口占用检测**：启动前用 `Get-NetUDPEndpoint -LocalPort 34718` 的等价逻辑（.NET Framework 4.8 可用 `System.Net.NetworkInformation` 或 P/Invoke，具体实现待验证）检测回环端口是否被占用；占用则拒绝启动并提示「34718 已被其他 agent 占用（PID=...），请先停止」（脚本实证：`civlink/run-f1-selftest.ps1` 行 55–59、`civlink/run-f2-mechanical-selftest.ps1` 行 33–35）。GUI 绝不抢占端口。

**停止纪律**（严格按 `civlink/run-f2-mechanical-selftest.ps1` 行 56–59 实证顺序）：

1. 以 ASCII 写 stop 文件，内容 `stop`；
2. `WaitForExit(20000)` 等待 agent 自然退出并产出 `summary.txt`；
3. 超时才 `Kill()`，并提示「agent 未在 20s 内退出，已强制结束；summary 可能缺失」。

**agent 健康**：AgentSupervisor 持有子进程句柄，`Exited` 事件触发时托盘转红并提示「agent 异常退出（code=N）」；不自动重启（避免掩盖根因，也避免产生未脱敏日志）。

### 3.4 状态轮询策略

- 默认 3s 轮询 `status`，间隔可配置（§2.5，范围 1–30s）；仅当注入页已选定目标且窗口处于前台/可见时轮询，窗口最小化到托盘时暂停（省资源、减少无意义 ctl 进程创建）。
- 每次轮询是一次独立 ctl 短命进程；上一轮未结束不得叠加新一轮（用 `Interlocked`/锁保护，防止进程堆积）。
- 轮询结果只更新内存对象，不写盘；界面刷新用数据绑定（雏形用 `logBox.AppendText`，新 GUI 改为 BindingList/属性变更通知，WinForms 下用 `BindingSource`）。
- 轮询异常连续 3 次 → 托盘转红、停止自动轮询、提示手动重试；不记录异常详情到文件（零持久化日志）。

---

## 4. 企业级要素在 GUI 层的落地

### 4.1 脱敏规则（强制）

依据 `docs/survey-gui-quality-20261118.md` 行 74–76：日志脱敏「不记录机器名/用户名/路径」。GUI 层执行：

- 诊断包与界面展示中**不得**出现：机器名、用户名、用户目录完整路径（如 `C:\Users\<name>\...`）、`%LOCALAPPDATA%` 展开后的绝对路径。必须展示路径时用占位符（如 `%LOCALAPPDATA%\CivLink\...`）。
- agent summary 中的 `room` 字段：**不得信任 agent 已匿名化**（审计 N-1，2026-11-18 实读修正）。实读 `civlink/agent/src/main.rs` 行 2128–2130/2167：`summary.txt` 直接打印原始 `args.sim_room_name`，`anonymized at offset 24..46` 只是输出标签、`:348` 仅定长拷贝无遮蔽，LAN simulated host 段（`:2167`）连标签都没有。因此 `Redactor.Redact` 必须**无条件**对 summary 中所有 `room` 字段（含 LAN 段、含 `\nLAN simulated host` 段）做遮蔽/替换，不依赖任何「已匿名化」标签，也不从原始 fixture 读取真实房名。T4 验收增加「自定义房名后导出样本无原文」用例。
- `listen window 127.0.0.1:34718` 属回环地址，可保留；任何 LAN IP（如 `192.168.x.x`）在诊断包中按「主机地址已隐去」处理（因为可能关联用户网络拓扑）。
- 实现为集中式 `Redactor.Redact(string)`，所有导出内容必须经过它；审计抽查导出样本确认无 PII。

### 4.2 诊断包一键导出（零日志约束下的设计）

- **不写常驻日志**：GUI 运行期间零日志文件；诊断包只在用户点击时生成一次，内容在内存中组装 → 脱敏 → 写出到用户选择路径 → 清空缓冲区。
- **内容三件套**（用户任务要求）：
  1. `counters`：调 `civlink_ctl.exe counters` 的输出（若 exit 4 则写「不可信，已省略」）；
  2. `agent summary`：若本次 agent 运行产生 `summary.txt`（`civlink/agent/src/main.rs` 行 2032–2250），读取并按 §4.1 脱敏；
  3. 环境信息：OS 版本、`dotnet --list-runtimes` 等价探测得到的已安装 .NET 运行时版本、`csc`/ctl/agent 的文件版本与 SHA-256、构建哈希（来自 T1 构建脚本产物）。**环境信息里不得包含机器名/用户名/路径**。
- **固定声明头**：诊断包首行写「CivLink 诊断快照（一次性导出，项目 v1.0 零遥测/零持久化日志；机械证据不构成双人联机验证）」。
- **格式**：v1.0 用单个 UTF-8（无 BOM）纯文本文件，扩展名 `.txt`；是否打包为 `.zip` 待产品确认。

### 4.3 进程健康检测

- ctl 短命进程：每次调用捕获 ExitCode 与耗时；超时/Kill 计入内存计数器（仅当前会话），供诊断包「本次会话 ctl 调用摘要」使用，不落盘。
- agent 长命进程：`Exited` 事件 + 托盘三态（§2.1）；启动后立即检测是否秒退（脚本实证 `civlink/run-f1-selftest.ps1` 行 67–71 检查 `HasExited`），秒退则提示 code 并停止后续动作。
- GUI 主进程自身：不做崩溃转储/自动重启（属于 §4.5 的 P3 企业级项）。

### 4.4 防重复注入与错误码本地化

- 防重复注入：GUI 不自行判断，而是把 ctl 的 "already loaded / not injecting twice" 语义（`civlink_ctl.cpp` 行 458–466）显式映射为友好提示（§2.2）；注入按钮在 ctl 返回前禁用，防连点产生并发注入。
- 错误码本地化：§3.2 的映射表是唯一权威来源；所有命令共用，禁止各处硬编码数字。

### 4.5 明确属于 P3、不在 P1 范围的企业级项

`docs/M0D-OPENSOURCE-PLAN-20261118.md` §6（行 250–261）与 `docs/survey-gui-quality-20261118.md` 行 90–96 列出的企业级项中，以下 **P1 不做**（与零遥测/零日志及当前资源约束一致）：

| 企业级项 | 为何不在 P1 | 何时再做 |
|---|---|---|
| 结构化日志 + 崩溃转储 + 集中上报 | 与 d6 零持久化日志直接冲突 | 仅在用户撤销 d6 后，作为 P3 且默认关闭 |
| CI/CD 自动化测试流水线完整覆盖 | P1 用 T6 冒烟脚本 + 人工审计替代 | P3 引入 SDK 后建标准 CI（路径 C） |
| 代码签名 + 更新校验 + 自动更新 | 需证书与私钥管理（密钥管理项），且引入供应链 | P3 |
| 安装器写防火墙规则 | 属安装器阶段，非 GUI P1；但 GUI 需在安装说明中告知用户 | 安装器任务（独立） |
| 供应链门禁（依赖 SBOM/签名校验） | P1 只有 csc + 系统 DLL，暴露面小 | P3 随 SDK/nuget 引入时同步建设 |
| IPC 硬化（命名管道 + DACL） | v1.0 数据绑定直接用进程调用（`docs/M0D-OPENSOURCE-PLAN-20261118.md` §5）；agent 仅回环 UDP | 规划在 P3 评估 agent 直连时（§7.2） |
| 密钥管理 | P1 无任何密钥/凭据 | P3 代码签名时 |

---

## 5. 分阶段实现任务分解（T1–T6）

每阶段都给出「验收标准」与「可独立审计的产物」。审计子代理应能仅凭产物复核，不依赖口头说明。

### T1 — 构建底座验证

- 工作：固定 csc 路径与 4 个 `/r` 引用；原样编译现有 `civlink/ctl/civlink_ctl_gui.cs`；写可复现构建脚本；生成构建产物 SHA-256。
- 验收：零错误产出 exe；脚本在新 shell 中重复执行结果一致（同一输入→同一哈希，允许 PE 时间戳差异时记录为「待验证」）；exe 双击能显示空窗口。
- 可独立审计产物：`build-gui.ps1`（或 `.cmd`）、`build-manifest.txt`（csc 版本、参数、引用路径、输出哈希）、exe 文件。
- 前置条件：见 §1.2「T1 前置条件」四条；任一步失败即停。

### T2 — 注入向导页

- 工作：白名单发现（枚举官方进程名，PID 只读）、A/B 角色切换、`--iface` 枚举 + ALL、`--reserve-62900` 开关、命令拼装、CtlRunner 接入、exit code 映射、重复注入检测提示、边界语。
- 验收：在未启动游戏时提示「未发现《文明6》进程」；用假 ctl（审计桩）验证拼出的参数串与 §2.2 完全一致；exit 0–5 六条映射逐条可见；无任何「注入任意 PID」输入控件。
- 可独立审计产物：`InjectWizardForm` 源码、命令拼装单元测试或桩测试记录、控件清单截图（脱敏后）。

### T3 — 状态页 / 计数页

- 工作：`status` 轮询（§3.4）、托盘三态接入、验证状态固定话术；`counters` 解析为表格、exit 4 隐藏数据、常驻「本机计数≠对端到达」说明。
- 验收：连续轮询不叠加 ctl 进程（进程列表检查）；模拟 exit 1/3/4/5 各状态呈现正确；状态页与计数页全文检索无「联机已验证」字样。
- 可独立审计产物：`StatusForm`/`CountersForm` 源码、轮询并发保护说明、页面全文导出（用于关键词检索）。

### T4 — 设置页 / 诊断页

- 工作：设置页控件（不得有遥测/日志开关、不持久化）；诊断页三件套导出、Redactor、固定声明头、agent summary 分段解析。
- 验收：导出样本经审计确认无机器名/用户名/用户目录绝对路径；agent 未运行时导出内容标注「无 summary」；设置页全文无遥测/日志字样。
- 可独立审计产物：一份真实导出的诊断包样本（脱敏后）、`Redactor` 源码与测试用例、设置页控件清单。

### T5 — 托盘与 agent 子进程

- 工作：NotifyIcon 托盘、三态、右键菜单；AgentSupervisor 启动/停止（真实 CLI 参数）、端口占用检测、stop-file 纪律、健康检测、GUI 退出时停 agent。
- 验收：启动参数与 `civlink/agent/src/main.rs` Usage（行 1522–1527）逐项一致，无发明参数；占用 34718 时拒绝启动；stop-file 后 20s 内自然退出并产出 summary；模拟/自检模式界面有显著标注。
- 可独立审计产物：托盘与 supervisor 源码、agent 参数对照表、stop-file 时序测试记录。

### T6 — GUI 自动化冒烟

- 工作：用脚本（WinForms 可用 SendKeys/UIAutomation，或审计桩驱动 CtlRunner）跑端到端冒烟：打开→刷新白名单→选角色→注入（桩）→状态→计数→导出诊断包→停止 agent→退出。
- 验收：全流程无崩溃；零遥测（网络抓包无外连）、零持久化日志（运行前后用户目录无新增日志文件）；产物哈希与构建清单一致。
- 可独立审计产物：冒烟脚本、抓包摘要、`run-smoke.log`（注意：这是**测试脚本自身**的临时输出，不属于 GUI 运行时日志；如审计要求绝对零日志，可改为仅控制台输出）。

---

## 6. 审计清单（子代理逐条核验）

审计子代理应对照下表逐条打勾，任何一条不通过即判该阶段失败：

1. **构建可复现**：T1 脚本在本机零错误编译；csc 路径、4 个 `/r` 引用路径与 `build-manifest.txt` 一致；未假设 SDK 存在。**验收三准则（审计 N-3 修正）**：`source_sha256` 稳定 + `output_bytes=9216` 稳定 + exit=0；`output_sha256` 即便加 `/deterministic+` 也会因本机缺官方 ref assemblies 致 MVID/TimeDateStamp 差 22 字节而每次不同，**不得将输出哈希变化判为篡改或 T1 失败**（详见 `civlink/gui/build-manifest.txt` 的 note 行）。
2. **ctl 参数与源码一致**：注入页拼出的每个子命令与参数（`inject`/`inject-client`/`status`/`counters`/`shutdown`，`-x`/`-m`/`--iface`，`-d` 仅兼容）逐项对照 `civlink/ctl/civlink_ctl.cpp` 行 12–18/337–344/363–364/206–246；不得发明参数。
3. **agent 参数与源码一致**：AgentSupervisor 拼出的参数逐项对照 `civlink/agent/src/main.rs` 行 1522–1527；`--reserve-62900` 只与 `--sim-lan-listen` 同用（行 1547–1548）；`--bind-ip` 为主机本地地址（行 895–898）。
4. **exit code 映射**：0–5 六条与 `civlink_ctl.cpp` 行 26–27 语义逐条对应；未知 code 有兜底提示；集中在一个 Map 函数。
5. **白名单**：注入目标只来自官方进程名枚举；源码全文检索无「任意 PID 输入」控件；PID 只读展示。
6. **零遥测、零持久化日志**：GUI 源码无 HTTP 上报/Sentry/匿名 ID；运行前后用户目录无新增日志文件；诊断包仅用户点击时生成。
7. **边界语**：状态页/计数页/诊断包全文无「联机已验证/已双人对局」；机械证据出现处均附「不构成双人验证」说明（对照 `README.md` 行 4/1477–1480 与 `docs/M0D-OPENSOURCE-PLAN-20261118.md` §8.1 行 299–304）。
8. **asInvoker**：manifest 为 asInvoker；源码无 `runas`/自提权；安装期防火墙规则不在 GUI 运行时。
9. **脱敏**：导出样本无机器名/用户名/用户目录绝对路径；房名使用 agent 已匿名化的值。
10. **stop-file 纪律**：停止 agent 先写 ASCII `stop`，再 `WaitForExit(20000)`，超时才 Kill（对照 `run-f2-mechanical-selftest.ps1` 行 56–59）。
11. **端口纪律**：启动前检测 34718 占用，占用则拒绝（对照 `run-f1-selftest.ps1` 行 55–59）。
12. **哈希链**：GUI 不改动任何受哈希保护的 C++/agent 代码；构建清单含所有产物 SHA-256；诊断包中的环境哈希与之一致。

---

## 7. 风险与开放问题

### 7.1 SDK 缺失与路径 A 的隐藏风险

- 本机无 SDK、无 ref pack，路径 A 依赖 Windows 自带的 .NET Framework 4.8 程序集作编译引用。这些是「运行时实现 DLL」而非官方 ref assemblies，微软不保证长期作为编译目标；但在本机已实测存在且雏形历史编译成功，P1 接受此权衡。**风险缓解**：T1 必须实测并固定参数，构建清单记录文件版本（4.8.9256.0 等）；若 Windows Update 改动这些 DLL，需重跑 T1。
- 8,704B 的 gui exe 是用户口述历史事实，当前磁盘不存在；审计以实际编译产物为准，不引用该数字作为验收值。

### 7.2 WPF vs WinForms 迁移路径

- 产品调研主选 WPF（`docs/survey-gui-quality-20261118.md` 行 24–64），但当前构建现实只允许 WinForms。迁移触发条件：用户确认可联网下载 SDK，或项目进入 P3。
- 迁移策略：保持 CtlRunner / AgentSupervisor / Redactor / ExitCodeMapper 为框架无关的 POCO 类，仅替换 UI 层（WinForms Form → WPF Window）。五页签结构、话术、命令拼装不变。这样路径 A 的实现不会成为 P3 迁移的沉没成本。
- 路径 B（纯 C# WPF + csc）**编译与运行链已由父代理实测打通**（csc `/nostdlib+` 编译 + 手写 runtimeconfig.json + `dotnet.exe` 启动 + `WPF_TYPE_OK=System.Windows.Window` 类型加载），不再是技术未知；但因其需手写 runtimeconfig、纯代码 UI（无 XAML 设计器）、目标机预装 .NET Desktop Runtime 8.0.3，P1 不采用，保留为 P3 升级的可行备选（见 §1.2）。

### 7.3 未来多人/跨网扩展对 GUI 的影响

- v1.0 锁定 Steam Win64 双人、不内嵌组网、用户自建 relay（`docs/M0D-OPENSOURCE-PLAN-20261118.md` §9.1，行 344–358）。若未来支持多人：注入向导的 A/B 角色需扩展为「房主/多个客户端」，`--iface` 语义可能需要多接口选择，状态页话术需随 Gate 状态更新——但这些都属于 v1.0 之后的决策，当前 GUI 不得预留会破坏 v1.0 纪律的入口（如通用 PID 注入、强制组网配置）。
- 跨网/relay 场景若引入凭据，会与「零遥测/密钥管理 P3」耦合，需重新评估 §4.5 的范围。

### 7.4 其他开放问题（均待验证/待产品确认）

- 官方可注入进程名清单（DX12 / DX11 / 无后缀等）需产品最终确认。
- 普通玩家 A 侧流程已在 §2.6 按 N-5 裁定：**默认只注入不启 agent**，模拟能力收进高级页；该裁定**仍待项目负责人最终确认**，T2 按此默认实现，若另行裁定再调整（不再作为开放问题反复讨论）。
- 诊断包格式（单 `.txt` 还是 `.zip`）、是否记忆 ctl/agent 路径（与零持久化日志的边界）、状态轮询 3s 默认值是否合适——均为待确认的实现细节。
- `status`/`counters` 未显式 `-m` 时的自动探测（`civlink_ctl.cpp` 行 415–423）与 GUI 显式传 `-m` 的优先级，需实测确认输出一致性（待验证）。
- Windows 下等价 `Get-NetUDPEndpoint` 的 .NET Framework 4.8 实现方式（`System.Net.NetworkInformation` 或 P/Invoke）待 T5 实测。

---

## 附：关键证据索引

- `docs/M0D-OPENSOURCE-PLAN-20261118.md`：§5 行 218–243（GUI/托盘/数据绑定）、§6 行 250–261（企业级清单）、§8.1 行 299–304（表述纪律）、§9.1 行 344–358（决策记录）、附录 A 行 362–368（端口/协议基线）。
- `docs/survey-gui-quality-20261118.md`：行 24–64（框架）、行 74–76（脱敏）、行 90–96（企业级 Top5）、行 100–113（托盘 vs 服务）、行 115–125（asInvoker）、行 128–141（注入安全）。
- `civlink/ctl/civlink_ctl_gui.cs`：行 3–4（编译/权限注释）、:18（pidBox，实读修正 N-6）/行 107–124（ProbeProcess）、行 57–64（TargetArgs）、行 66–69（Quote）、行 71–105（RunCtl/ProcessStartInfo；其中 UseShellExecute/Redirect/CreateNoWindow 实为 :87–90、ReadToEnd/WaitForExit 实为 :93–95、`[exit code:N]` 实为 :98）。
- `civlink/ctl/civlink_ctl.cpp`：行 12–18/337–344（Usage）、行 26–27（exit code）、行 52–78（EnableDebugPrivilege）、行 166–180（PE 身份）、行 206–246（ResolveIface）、行 262–293（iface 配置路径）、行 363–403（inject-client/校验顺序）、行 415–423（模块自动探测）、行 445–466（位数/重复注入）、行 576–598（status/shutdown）、行 600–673（counters）。
- `civlink/agent/src/main.rs`：行 895–898/2625（bind-ip fail-closed）、行 1434–1518/1522–1527（CLI/Usage）、行 1547–1548（reserve 条件）、行 1723（listen-seconds 0）、行 2032–2250（summary 字段）、行 2889–2908（reserve 单测）。
- `civlink/run-f1-selftest.ps1` 行 55–59/63–71、`civlink/run-f2-mechanical-selftest.ps1` 行 33–59：端口检测与 stop-file 纪律实证。
- 父代理 ctl 子进程实测（2026-11-18，见 §3.1.1）：`civlink_ctl.exe` 188,416 B / SHA-256 前缀 6FCE456E…；无参数 exit 1 + 533B stdout Usage；`status -x __no_such_game__.exe` exit 2 含 `target process not found (or ambiguous)`；`status -x <name> -p 999999` exit 2 含 `OpenProcess failed err=87` / `SeDebugPrivilege not granted`；全部输出走 stdout、stderr=0B。
- `README.md`：行 4（v1.34 状态行）、行 1471–1480（v1.33/v1.34 修订口径与边界）。

---

**本设计已审计**：`docs/M0D-GUI-DESIGN-REVIEW-20261118.md` 裁定有条件通过、阻断 0、允许进 T1；N-1..N-7 已逐条关闭（见文首修订记录）。T2–T6 各阶段实现后仍需分别派子代理审计，不得跳过。
