# 文明6局域网联机助手开源化 — GUI 与质量要素技术调研报告

- 调研日期：2026-11-18
- 调研人：技术调研员（subagent）
- 项目背景：CivLink（文明6局域网联机助手）开源化，C++/Rust 混合（`civlink_ctl.exe` C++ 控制器、`civlink-agent.exe` Rust agent、`civlink_hook.dll` C++ MinHook 注入 DLL），已有 `civlink_ctl_gui.cs`（C# WinForms 雏形，约 6,450 行）。目标平台：Windows（游戏为 Windows 版）。要求：GUI 界面 + 企业级稳定性/兼容性/安全性，开源给游戏爱好者。
- 说明：本报告基于公开检索与工作区已有资料（`deps/MinHook/LICENSE.txt` 已直接核实）。第三方信息以来源链接为准。

---

## 0. 结论速览（TL;DR）

| 决策项 | 建议 |
|---|---|
| GUI 框架（主选） | **WPF（C#）** — 仅 Windows 目标 + 20 年成熟生态 + 与现有 C# 雏形衔接 + 企业级配套最齐；备选 Avalonia / WinUI 3 / Tauri |
| 主代码 License | **MIT**（或 Apache-2.0）；文档 CC-BY-4.0；第三方依赖保留各自许可并出具 THIRD-PARTY 清单 |
| 企业级要素 Top 5 | ① CI（构建+测试+静态分析）② 结构化日志+崩溃转储 ③ 代码签名+更新签名校验 ④ 安装器+自动更新 ⑤ 依赖/供应链门禁 |
| 后台进程模式 | **托盘程序**（非 Windows 服务）；防火墙规则在安装器阶段一次性提权写入，运行时保持 asInvoker |
| 注入安全 | 白名单进程 + 签名校验 + 回环 IPC + DACL 仅当前用户 |

---

## 1. Windows GUI 框架选型对比

### 1.1 总对比表

| 框架 | 语言 | License | 成熟度 | 部署体积 | 与 C++/Rust 混合便利性 |
|---|---|---|---|---|---|
| **WPF** | C#（.NET） | MIT（.NET 开源） | 极高（2006 至今，生态最大） | 框架依赖需 .NET Desktop Runtime（下载 ~60–80MB）；自包含发布 ~100–150MB | 好：C# P/Invoke 直接调 `civlink_ctl.exe`/agent 接口 |
| **WinUI 3**（Windows App SDK） | C# 或 C++/WinRT | MIT（`microsoft-ui-xaml` 开源） | 中高（微软官方推荐的新框架；1.x 仍在演进） | MSIX 打包，或未打包需 WindowsAppRuntime（几十 MB），或自包含（增 ~30–50MB） | 好：同 WPF，P/Invoke 无障碍 |
| **Avalonia** | C#（.NET） | MIT | 高（v11；Autodesk、JetBrains、Devolutions 生产在用） | 需 .NET 运行时；自包含 ~60–90MB | 好：同 WPF，P/Invoke 无障碍；跨平台 |
| **Qt（Qt 6）** | C++（亦可 QML） | 商业 或 LGPLv3/GPLv3（双轨） | 极高 | 动态链接 Qt DLL ~30–50MB；静态链接有合规要求 | 中：C++ 与 hook 同栈，但与 Rust agent 需额外 FFI/进程桥 |
| **Dear ImGui** | C++ | MIT | 中（工具类成熟，非应用框架） | 极小（单 exe + 渲染后端） | 好：与 MinHook 同栈；但非完整应用框架 |
| **Tauri 2** | Rust + Web 前端 | MIT/Apache-2.0 双许可 | 中高（2.0 已稳定） | 极小（~5–15MB）；依赖 WebView2（Win11/新 Win10 预装，老系统需 Evergreen 引导 ~1.5MB） | 好：后端 Rust 与 agent 同语言最顺；前端 Web 技术栈 |
| **egui / eframe** | Rust | MIT/Apache-2.0 双许可 | 中（0.3x 活跃演进，API 有变动） | 极小（单 exe ~5–10MB） | 好：与 agent 同栈；即时模式 |
| **Slint** | Rust/C++/JS | **GPLv3 或商业付费**（Royalty-Free/Startup/Enterprise） | 中（较新，SixtyFPS 维护） | 小 | 好：Rust 一等支持；但开源仅限 GPLv3 |
| **原生 Win32** | C/C++ | 无第三方许可问题 | 极高（Windows 本身） | 最小（静态 CRT 单 exe，与现有 `/MT` 风格一致） | 好：纯 C/C++；但开发效率低 |

### 1.2 逐项要点

- **WPF**：仅限 Windows，20 年稳定，工具链/第三方库最全（MVVM、DataGrid、主题、本地化、UI 自动化、Serilog/Velopack/Sentry 均一等支持）。对「目标平台已确定仅 Windows」的项目是最低风险选择。参考：[WPF 概述 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/desktop/wpf/overview/)。
- **WinUI 3**：微软官方当前推荐的 Windows 原生新框架（Fluent 设计、C#/C++ 双语言、Windows 10 1809+；PowerToys 等开源项目在用），但部署（Windows App SDK 运行时 / 自包含）与 1.x 演进期的 API 变动带来额外成本。参考：[WinUI 3 - Microsoft Learn](https://learn.microsoft.com/zh-cn/windows/apps/winui/winui3/)、[microsoft/microsoft-ui-xaml - GitHub](https://github.com/microsoft/microsoft-ui-xaml)。
- **Avalonia**：MIT + 跨平台 + 与 WPF 相近的 XAML 心智模型，生产验证充分；若未来想把「联机助手」跑在 macOS/Linux 主机端，这是唯一同时满足「C# 复用 + MIT + 跨平台」的选项。参考：[avaloniaui.net](https://avaloniaui.net/)。
- **Qt**：C++ 老牌巨头，但双轨许可（商业 vs 社区 GPL/LGPL，且官方明确「不可混用、不可随意切换」）增加合规成本；对纯 Windows 小工具而言其跨平台优势用不上，且与 Rust agent 多一层 FFI。若坚持使用：LGPLv3 **动态链接** + 主代码 MIT 合规可行；**静态链接**闭源必须买商业许可。参考：[Qt Licensing Overview](https://www.qt.io/development/qt-framework/qt-licensing)。
- **Dear ImGui**：适合诊断/调试面板，不适合做主 GUI——无内建复杂控件、可访问性、本地化，中文 IME 输入体验弱。
- **Tauri 2**：Rust 单栈 + 最小体积 + 明确安全模型（CSP、命令白名单），是「agent 用 Rust 写」的项目最优雅的纯 Rust 路线；代价是引入 WebView2 运行时依赖与 Web 前端 npm 供应链，安全配置（CSP/权限）是额外责任面。参考：[Tauri 2.0](https://v2.tauri.app/)。
- **egui**：纯 Rust 即时模式，单 exe 极小，适合工具类小界面；复杂表单与中文输入仍是短板，API 版本演进较快。参考：[egui](https://www.egui.rs/)。
- **Slint**：声明式、Rust 友好，但**开源只能用 GPLv3**（或付费商业许可）——与「项目以 MIT 开源」的诉求直接冲突，除非接受整个 GUI 组件 GPL 化。参考：[Slint Pricing](https://slint.dev/pricing)。
- **原生 Win32**：适合托盘图标、单窗口小工具；做完整 GUI（列表、表单、多窗口、主题、高 DPI、无障碍）开发量过大。

### 1.3 推荐结论（GUI 框架）

**主选：WPF（C#）**，理由：

1. **目标平台已确认仅 Windows**（hook/agent 必须跑在游戏机上）→ 不需要跨平台，WPF 的 20 年成熟度与微软全工具链是「企业级稳定性」的最低风险路径。
2. **衔接现有资产**：已有 C# WinForms 雏形（`civlink_ctl_gui.cs`）→ 同语言，控制器调用逻辑（调 `civlink_ctl.exe`、解析 agent 输出、状态机）可 1:1 复用；XAML 化成本集中在界面层，逻辑层基本无损迁移。
3. **企业级配套最齐**：Serilog（结构化日志）、Velopack（更新/安装）、MSIX/WiX、Sentry .NET SDK、UI 自动化测试、GitHub Actions .NET 模板均为一等支持。
4. **License 干净**：.NET/WPF 为 MIT，与项目选 MIT 完全兼容，无传染性。

**备选（按适用场景）**：
- **Avalonia**：若未来需要 macOS/Linux 主机端（MIT + 跨平台 + C# 复用）。
- **WinUI 3**：若想跟随微软官方新方向、要现代 Fluent UI，接受 WindowsAppSDK 部署复杂度。
- **Tauri**：若希望 Rust 单语言栈 + 最小体积，接受 WebView2 与 Web 前端供应链。

**排除**：Qt（许可双轨合规成本 + Rust 集成多一层 FFI）、Slint（开源仅限 GPLv3）、Dear ImGui/egui（即时模式不适合作为主 GUI，可留作内部诊断面板）。

---

## 2. 企业级软件质量要素清单

### 2.1 完整清单

| 类别 | 具体要素 | 落地建议（本项目） |
|---|---|---|
| **日志** | 结构化日志 | C# GUI 用 Serilog（JSON 结构化、按天/大小轮转、多 sink）；Rust agent 用 `tracing` crate（`tracing-subscriber` + rolling file）。参考：[Serilog](https://serilog.net/) |
| | 崩溃转储 | ① WER LocalDumps 注册表（`HKCU\Software\Microsoft\Windows\Windows Error Reporting\LocalDumps`，`DumpFolder` / `DumpCount` / `DumpType=2`）自动收集 GUI/agent 崩溃 minidump；② agent/hook 内用 `MiniDumpWriteDump`（或 C++ 侧 `SetUnhandledExceptionFilter`）自捕。参考：[Collecting User-Mode Dumps - Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/wer/collecting-user-mode-dumps) |
| | 日志脱敏 | 不上报机器名/用户名/路径，可配置 `--log-dir` |
| **更新机制** | 自动更新 | **Velopack**：安装器 + 后台更新 + delta 差分包 + 自更新便携版，支持 .NET/C++/Rust/Tauri，核心开源；发布物放 GitHub Releases 静态托管。参考：[velopack.io](https://velopack.io/)、[github.com/velopack/velopack](https://github.com/velopack/velopack) |
| | 签名校验 | 更新包 Authenticode 校验（`WinVerifyTrust`），HTTPS 下载；拒绝无签名/签名失败更新 |
| | 版本策略 | 语义化版本；`--check-update` 手动触发 + 启动时后台静默检查 |
| **安装包** | 安装器选型 | 短期：**Inno Setup**（免费、简单、32/64 位支持，参考 [Inno Setup](https://jrsoftware.org/isinfo.php)）或 Velopack 自带 `vpk` 生成安装器；企业化：**WiX v4/v5（MSI）**（组策略/静默部署友好）；后期可上 MSIX（微软商店分发，签名要求更严） |
| | 安装行为 | 安装器 UAC 提权一次：写防火墙规则、装 .NET 运行时前置（如有）、注册 HKCU Run 自启项 |
| **错误上报** | 可选、开源友好 | **Sentry**（开源可自托管，或 SaaS 免费档）：明示 opt-in、匿名 ID、脱敏后上报；不开遥测也能收 minidump 文件。参考：[Sentry](https://sentry.io/) |
| **代码签名** | 证书类型 | **Azure Trusted Signing**（2024 年推出的微软云签名，无需 EV 硬件令牌、可 CI 自动签名、开源项目有免费额度）> OV 证书（~100–200 美元/年）> EV 证书（最高信任，需硬件令牌，~200–400 美元/年，防 SmartScreen 效果最好）。具体价格以官方为准 |
| | 签名范围 | 所有发布二进制：GUI exe、`civlink_ctl.exe`、`civlink_hook.dll`、安装器/更新包——否则 SmartScreen 警告劝退非技术玩家 |
| **静态分析** | C++ 侧 | cppcheck + clang-tidy + MSVC `/W4` `/analyze`（hook.cpp、ctl）。参考：[Cppcheck](https://cppcheck.sourceforge.io/) |
| | Rust 侧 | `cargo fmt` + `clippy -D warnings` + `cargo-deny`（banned/advisories/license）+ `cargo audit`（RustSec 公告库） |
| **测试与 CI** | 单元/集成 | C++：GoogleTest（hook.cpp 纯逻辑部分可测）+ CTest；Rust：`cargo test`（agent 协议解析已有 fixture，`CivLink-M0A-audit/civlink/fixture-reply-set` 可直接复用） |
| | CI | GitHub Actions `windows-latest`（内置 VS2022 MSVC + rustup）：构建 → 测试 → 静态分析门禁 → 打包 → 签名（密钥走 secrets）→ 发布 Release + SBOM |

### 2.2 企业级要素优先级 Top 5（建议落地顺序）

1. **自动化 CI：构建 + 测试 + 静态分析门禁（GitHub Actions）** —— 开源项目的第一印象与质量底线：`cargo test` + GoogleTest + clippy/cppcheck 全绿才发版。
2. **结构化日志 + 崩溃转储（WER LocalDumps + 自捕 minidump）** —— 无 GUI 现场时唯一可诊断的数据来源，用户报障才能定位。
3. **代码签名（Azure Trusted Signing 或 OV/EV）+ 更新签名校验（WinVerifyTrust）** —— 防 SmartScreen、防篡改；注入器与 hook DLL 必须签。
4. **安装器 + 自动更新（Velopack / Inno Setup，或 WiX MSI）** —— 非技术玩家的一键安装与静默升级体验。
5. **依赖与供应链门禁（Cargo.lock 提交 + cargo-deny/cargo-audit + SBOM + 第三方 License 清单）** —— 开源合规与 CVE 防护，发布物附带 NOTICE。

---

## 3. Windows 服务 / 后台进程模式

### 3.1 托盘程序 vs Windows 服务

| 维度 | 托盘程序（推荐） | Windows 服务 |
|---|---|---|
| 运行身份 | 当前用户会话 | SYSTEM / 专用账号 |
| 桌面交互 | 直接有 GUI、托盘图标 | 无桌面交互，需双进程 IPC 才能弹 UI |
| 提权需求 | asInvoker 普通权限即可 | 安装时写 SCM，权限面大 |
| 生命周期 | GUI 启停 agent 子进程（`civlink-agent.exe`） | 开机即起、无人登录也跑（本场景不需要） |
| 防火墙/卸载 | 简单 | 规则与清理更复杂 |
| 适用性 | ✅ 局域网联机助手（需要用户交互、状态展示） | ❌ 除非「无用户登录也要提供服务」，本场景不需要 |

**结论：agent 作为 GUI 托盘子进程 + 托盘图标**（状态：房间/在线人数/agent 健康）。开机自启用 HKCU Run 注册表项即可，不需要服务。

### 3.2 提权最小化（UAC）

- 所有可执行文件 manifest 设为 `requestedExecutionLevel=asInvoker`（普通权限）。
- 唯一需要管理员的操作：**防火墙规则写入**。推荐在**安装器阶段**（安装器自身 UAC 提权一次）完成，运行时保持普通权限。
- 规则：升级现有 `netsh advfirewall` 用法（netsh 已用过）→ 安装器内一次性执行 `netsh advfirewall firewall add rule ...`，只开**入站**、按固定/可配 UDP(TCP) 端口或程序路径，出站一般不写。

### 3.3 防火墙管理要点

- 入站规则按「游戏对等通信端口」开放；端口建议固定或可配置，避免每次改端口都要提权。
- 规则命名带产品前缀（便于卸载清理）；安装器卸载时删除规则。

---

## 4. 安全性

### 4.1 DLL 注入的安全边界（注入器防滥用）

- **白名单进程**：注入器仅允许注入明确白名单（进程名 + 全路径匹配，默认仅 Civilization VI 相关进程）；**绝不提供「注入任意 PID」的通用接口**——开源后防止被恶意 fork 成通用注入器。
- **目标签名校验（可选开关）**：`WinVerifyTrust` 校验目标进程镜像的 Authenticode 签名/发布者后再注入。
- **hook DLL 功能克制**：只做白名单函数的内存 patch / 协议转发；不实现键盘钩子、截图、敏感文件读写等「危险」能力；patch 前校验原字节模式（防游戏版本不符导致崩溃）。
- **IPC 硬化**：agent 与 GUI 的命名管道/共享内存/事件设置 DACL **仅限当前用户**（默认 SecurityDescriptor 即创建者），防低权限进程冒充或干扰；agent 本地监听绑定 `127.0.0.1`，跨机通信走游戏自身协议或受控端口。
- **输入校验**：所有来自网络/游戏的输入按不可信处理（长度、边界、类型检查）。

### 4.2 密钥 / 证书管理

- 签名私钥永不进仓库与 CI 明文 → GitHub Actions secrets + **Azure Trusted Signing**（云签名，私钥不出 Azure，最适合开源项目）。
- 本地敏感配置用 **DPAPI**（`CryptProtectData`）加密存储；无硬编码密钥。

### 4.3 供应链安全

- 提交 **Cargo.lock**（可复现构建）；依赖 pin：MinHook 已 pin v1.3.4 ✓（工作区 `deps/MinHook` 为完整源码，建议以 submodule 或 vendor 形式随仓库发布并记录版本）。
- `cargo-deny`（banned + advisories + license 三合一）+ `cargo audit`（RustSec Advisory DB）入 CI 门禁。
- C++ 侧避免新增第三方依赖，或全部 vendor + 记录版本。
- 发布物附 **SBOM**（syft 生成）+ 校验和（如 `sha256sums` 文件）。

---

## 5. 开源合规

### 5.1 License 选择建议（MIT / Apache-2.0 / GPL-3.0）

| License | 特点 | 适合场景 | 对本项目评价 |
|---|---|---|---|
| **MIT** | 最宽松：任何人可任意使用、修改、闭源再分发；最短文本 | 工具类、游戏爱好者社区、希望「人人能用」 | ✅ **推荐**：最易懂、最友好；工具类无专利风险 |
| **Apache-2.0** | MIT + 明确专利授权 + 贡献条款 | 希望被企业采用、想明确专利边界 | ✅ 次选（同样合适，条款略长） |
| **GPL-3.0** | 强 copyleft：分发衍生品必须开源（含反 TiVoization） | 想强制「改我代码必须开源」 | ⚠ 会劝退部分贡献者与公司用户；且与部分依赖（如 Slint 的 GPLv3）叠加复杂 |

**建议：主代码 MIT（或 Apache-2.0）；文档 CC-BY-4.0。** 注意与依赖许可的兼容：MIT 主代码 + LGPL 动态链接（Qt 场景）合规；但选 GPL 系依赖（如 Slint）会传染整个项目。

### 5.2 第三方依赖 License 合规清单

随开源发布必须附 `THIRD-PARTY-NOTICES` / `NOTICE`，逐项保留版权声明：

| 依赖 | License | 核实来源 |
|---|---|---|
| **MinHook v1.3.4**（含 HDE32/HDE64） | **BSD 2-Clause**（Copyright (C) 2009-2017 Tsuda Kageyu；HDE 部分 Copyright (c) 2008-2009 Vyacheslav Patkov） | 已直接核实工作区 `CivLink-M0A-audit/deps/MinHook/LICENSE.txt`；另见 [TsudaKageyu/minhook - GitHub](https://github.com/TsudaKageyu/minhook) |
| Rust std / 工具链 | MIT OR Apache-2.0 | — |
| cargo 依赖（serde/clap/tokio 等） | 逐项审计（多为 MIT/Apache/BSD） | 用 `cargo-deny` + `cargo about` / `cargo license` 自动生成清单 |
| .NET / WPF 运行时 | MIT（.NET Foundation） | — |
| Serilog | Apache-2.0 | [serilog.net](https://serilog.net/) |
| Velopack | 核心开源（MIT） | [velopack.io](https://velopack.io/) |
| Inno Setup | 免费但**非 OSI 开源**的专有许可（免费使用） | [Inno Setup](https://jrsoftware.org/isinfo.php) — 需列入 NOTICE |
| WiX（若用） | MS-RL（宽松） | — |
| GoogleTest（若用） | BSD-3-Clause | — |
| Sentry SDK（若用） | MIT | [sentry.io](https://sentry.io/) |

**合规流程**：仓库根放 `LICENSE`（MIT）+ `THIRD-PARTY-NOTICES`；CI 用 cargo-deny 卡不兼容许可；Release 附 SBOM 与校验和。

---

## 6. 汇总建议

1. **GUI 框架**：主选 **WPF（C#）**（仅 Windows 目标 + 生态成熟 + 复用现有 C# 雏形 + 企业级配套齐全，MIT 兼容）；备选 Avalonia（跨平台）、WinUI 3（官方新方向）、Tauri（Rust 单栈）。
2. **主代码 License**：**MIT**（或 Apache-2.0）；第三方依赖保留各自许可并出具 THIRD-PARTY 清单；MinHook（BSD-2-Clause）合规已核实。
3. **企业级要素 Top 5**：① CI 构建+测试+静态分析门禁 ② 结构化日志 + WER LocalDumps/自捕 minidump ③ 代码签名（Azure Trusted Signing / OV/EV）+ 更新签名校验（WinVerifyTrust）④ 安装器 + 自动更新（Velopack / Inno Setup）⑤ 依赖/供应链门禁（Cargo.lock + cargo-deny/audit + SBOM）。
4. **进程模式**：托盘程序（agent 为 GUI 子进程），asInvoker；防火墙规则在安装器阶段一次性提权写入。
5. **安全性**：注入白名单 + 目标签名校验 + 回环 IPC + DACL 仅当前用户 + 输入校验；私钥走云签名/secrets，本地配置 DPAPI。

---

## 参考链接

- [WinUI 3 - Microsoft Learn](https://learn.microsoft.com/zh-cn/windows/apps/winui/winui3/)
- [WPF 概述 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/desktop/wpf/overview/)
- [Avalonia UI 官网](https://avaloniaui.net/)
- [Qt Licensing Overview - qt.io](https://www.qt.io/development/qt-framework/qt-licensing)
- [Slint Pricing - slint.dev](https://slint.dev/pricing)
- [Tauri 2.0 官网](https://v2.tauri.app/)
- [egui 官网](https://www.egui.rs/)
- [Velopack（安装器+自动更新）](https://velopack.io/) / [github.com/velopack/velopack](https://github.com/velopack/velopack)
- [TsudaKageyu/minhook - GitHub](https://github.com/TsudaKageyu/minhook)（License 以工作区 `deps/MinHook/LICENSE.txt` 核实为准）
- [Collecting User-Mode Dumps（WER LocalDumps）- Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/wer/collecting-user-mode-dumps)
- [Serilog（结构化日志）](https://serilog.net/)
- [Cppcheck（C/C++ 静态分析）](https://cppcheck.sourceforge.io/)
- [Inno Setup 官网](https://jrsoftware.org/isinfo.php)
- [Sentry（错误上报，开源可自托管）](https://sentry.io/)
