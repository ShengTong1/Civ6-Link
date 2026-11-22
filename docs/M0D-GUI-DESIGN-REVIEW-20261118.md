# M0D GUI 设计文档独立审计裁定报告（2026-11-18）

> 审计对象：`docs/M0D-GUI-DESIGN-20261118.md`
> 审计角色：独立审计员（CivLink P1 / WPF-GUI 启动前设计审计）
> 裁定日期：2026-11-18
> 审计方式：全文实读 + 逐条 `read`/`grep` 实读被引用源码与文档核对（未仅凭文档自述）

---

## 0. 裁定（Verdict）

# 裁定：有条件通过（CONDITIONAL PASS）

**是否允许进入 T1 实现阶段：允许（YES）。**

- 七条硬约束**全部遵守，无阻断项**；未发现把机械/模拟证据写成双人真实验证的表述；文档末尾第 437 行显式标注「本设计未经审计，实现后需派子代理审计。」，无自指判词断言。
- 放行条件（不阻断 T1，但须在对应阶段前关闭）：
  1. **N-1（高）** 必须在 **T4 诊断页实现前**关闭：§4.1 第 294 行「agent 已对房名匿名化、GUI 可直接展示」的断言与源码不符，诊断包存在 PII 泄露风险。
  2. **N-3（中）** 必须在 **T1 产物独立审计前**同步修订：§6 审计清单第 1 条仍要求输出 SHA-256 稳定，与父代理实测及 build-manifest.txt 现行准则冲突，会导致误判 T1 失败。
  3. N-2/N-4/N-5（中）须在 T3/T5 实现前给出修订或产品裁定。

---

## 0.1 审计基线（实测元数据，非文档自述）

| 项 | 任务书声明 | 实测值 | 结论 |
|---|---|---|---|
| 文件大小 | 48,999 B | **52,207 B** | 不一致（文档已被设计子代理更新，新增 §3.1.1） |
| 行数 | 425 行 | **437 内容行 / LF=438 / CRLF=0** | 不一致（含末尾空行计 438 LF） |
| 编码 | UTF-8 无 BOM | **UTF-8 无 BOM（BOM=False）** | 一致 |
| SHA-256 | — | **`d9dcc5e282515a47a8a4deecd5cca7cca70d4202cc0b52a7bf5af38e456155a0`** | 审计固定基线 |
| 尾部声明 | — | 第 437 行「本设计未经审计，实现后需派子代理审计。」 | 已确认 |

父代理在审计期间两次来函确认：文档已更新至含 §3.1.1 的最新版，本报告以实测 52,207 B 版本为准。

被核对文件实测大小：`civlink/ctl/civlink_ctl_gui.cs` = 6,450 B（143 行，与任务书一致）；`civlink/ctl/civlink_ctl.cpp` = 30,658 B（674 行，任务书「499+ 行」成立）；`civlink/civlink_hook.dll` = 119,808 B；`civlink/civlink_client.dll` = 149,504 B；`civlink/civlink_ctl.exe` = 188,416 B / SHA-256 `6FCE456E4156873F093732253E0381872F0CDEAAFFF61655D9460ABB73634D26`（与文档第 234 行 `6FCE456E…` 前缀一致）。

---

## 1–9 逐条关闭表

| # | 审计要点 | 结论 | 依据（路径:行号） |
|---|---|---|---|
| 1 | 构建路径推荐（WinForms vs 已验证 WPF） | **需修正** | 文档第 58–62 行明确写明放弃 WPF「不是因为技术不可行，而是因为分发成本与收益不匹配」，并在第 49/55/408 行如实记录 WPF 全链路已实测打通（`WPF_TYPE_OK=System.Windows.Window`）。**诚实性合格，未混淆「技术不可行」与「分发成本」**。但「企业级 GUI」论证不足：第 44–46/401 行承认 WinForms 路径依赖 Windows 自带 .NET Framework 4.8 **运行时实现 DLL**（非官方 ref assemblies）作编译引用，属稳定性/兼容性权衡；第 62 行把 WPF 定性为「产品目标而非当前构建现实」，却未论证 WinForms 如何满足用户「企业级 GUI」预期，也未取得用户对框架降级的明确签核。建议补一段「WinForms 满足企业级稳定/兼容/安全的逐条映射 + 用户确认」，并保留 §7.2 的 POCO 迁移策略。 |
| 2 | 技术断言可核验性（≥10 条抽查） | **需修正** | 共核对 30+ 条，**核心 ctl/agent 契约断言全部属实**（见 §2 核对表）；但发现 **4 类 gui.cs 行号系统性偏差**（N-6）与 **2 处安全属性过度声明**（N-1/N-2）。第 5 行「本机环境结论均来自本次实际执行…不是臆测」对实测结论成立，但行号引用需校正。 |
| 3 | T1–T6 阶段可执行/可复现/可审计 | **需修正** | T1 前置条件（第 64–69 行：固定 csc 绝对路径、固定参数顺序、9,216 B 校验值、可复现脚本 + SHA-256 + build-manifest.txt）**充分**；父代理已实测执行（build-gui.ps1 / build-manifest.txt / exe 9,216 B，source_sha256 稳定）。T2–T6 每阶段均有工作/验收/独立产物。**唯一缺陷**：第 382 行 §6 清单第 1 条要求「输出 SHA-256 与清单一致」，与第 67 行「允许 PE 时间戳差异」及父代理实测 output_sha256 每次不同冲突（N-3）。 |
| 4 | 五页签规格完整性 / ctl CLI 一致性 | **通过（含 1 项待产品裁定）** | 控件/命令绑定/数据流/错误处理/边界语齐备。A 房主 `inject -x … -m civlink_hook.dll` + agent 侧 `--reserve-62900`（第 114 行，正确区分 ctl 与 agent 参数）；B 客户端 `inject-client -x … -m civlink_client.dll --iface <IP\|ALL>`（第 115 行）；重复注入检测（第 126 行 → civlink_ctl.cpp:458–466）；白名单探测（第 104/386 行）。命令与 Usage（civlink_ctl.cpp:337–344）一致。**保留项**：A 侧 `--sim-lan-listen` 模拟参数与「普通玩家三步即用」定位的脱节（N-5，文档已自行标注「待产品确认」）。 |
| 5 | 进程/IPC 模型 | **需修正** | UseShellExecute=false + 双重定向（第 220–223 行 → 雏形 gui.cs:87–90）✓；exit 0–5 中文映射（第 249–258 行 → civlink_ctl.cpp:26–27）✓，且第 240 行正确覆盖 exit 2 的 OpenProcess 失败情形；stop-file 纪律（第 270–275 行 → run-f2-mechanical-selftest.ps1:56–59）✓；34718 占用检测（第 268 行 → run-f1-selftest.ps1:55–59）✓；轮询防叠加（第 281 行 Interlocked）✓。**缺陷**：GUI 超时（第 229 行 status/counters 5s）短于 ctl 内部固定等待（civlink_ctl.cpp:301 15s / :501 15s / :620 10s），强杀 ctl 可能遗留游戏进程内远程线程（N-4）。 |
| 6 | 企业级落地 / 零日志冲突 | **需修正** | §4.1 脱敏、§4.2 一次性诊断包（第 300–306 行）、§4.5 P3 范围（第 319–332 行）可落地；诊断包为用户显式触发的一次性导出，不构成「常驻日志」，与 d6 不冲突；§4.5 明确把结构化日志/崩溃转储/集中上报列为 P3 且须用户撤销 d6 后（第 325 行）。**缺陷**：N-1 房名脱敏断言不成立，Redactor 不能依赖 agent 标签。 |
| 7 | 硬约束遵守 | **PASS** | 逐条见 §3：零遥测零日志、不内嵌组网、仅 Steam Win64、个人免费引导、v1.0 双人闭环、机械≠双人、UseShellExecute=false+重定向、不改产品 DLL、不干扰真实对局——九项全部未违反。 |
| 8 | 过度承诺检查 | **PASS** | 第 34/142/149/191/251/305/388 行反复强制「机械证据≠双人验证」话术；第 437 行显式「未经审计」；未发现自指判词（判词分母自指等）断言。第 149 行对 replySrc 间接证据的限定与 README.md:1480 一致。 |
| 9 | 新发现 N-1..N-7 | — | 见 §4：高 1 / 中 4 / 低 2，无阻断。 |

---

## 2. 技术断言实读核对表（抽查 20 条，全部实读源码/文档）

| 文档行 | 断言摘要 | 实读结论 | 依据 |
|---|---|---|---|
| 32 | EnableDebugPrivilege 仅调整令牌、无自提权 | ✅ 属实 | civlink_ctl.cpp:52–78；gui.cs:4 |
| 35 | pidBox 位于「行 55–56、107–124」 | ⚠️ 部分 | gui.cs:18 声明 / :107–124 ProbeProcess 属实；:55–56 非 pidBox（N-6） |
| 46 | .NET Framework 4.8 运行时 DLL 作编译引用 | ✅ 属实 | 父代理实测；第 401 行自述 |
| 47/67 | 雏形重编 9,216 B | ✅ 属实 | 父代理实测；build-manifest.txt |
| 50 | ctl_gui.cs 6,450 B，无预编译 exe | ✅ 属实 | 实测 6,450 B |
| 97–98 | README v1.34 修订 1477–1480，双角色 | ✅ 属实 | README.md:1477–1480 |
| 104 | 白名单探测 = ProbeProcess | ✅ 属实 | gui.cs:107–124 |
| 106 | inject-client 默认模块 civlink_client.dll | ✅ 属实 | civlink_ctl.cpp:363–364 |
| 107 | ResolveIface fail-closed exit 1 / 拒 loopback | ✅ 属实 | civlink_ctl.cpp:206–246 / :380–385 |
| 108 | --reserve-62900 属 agent 侧、C1 修复 | ✅ 属实 | README.md:1472；main.rs:1547–1548 |
| 110 | shutdown 不 FreeLibrary | ✅ 属实 | civlink_ctl.cpp:590–598（:595 明示 LEFT MAPPED） |
| 114/337 | Usage 行 337–344；-m 合法 | ✅ 属实 | civlink_ctl.cpp:337–344 |
| 126 | 重复注入 "already loaded…not injecting twice" / q<0 | ✅ 属实 | civlink_ctl.cpp:458–466 |
| 127 | IsWow64Process 行数 445–456 | ✅ 属实 | civlink_ctl.cpp:445–456 |
| 128/166 | RemotePeIdentity → exit 3 | ✅ 属实 | civlink_ctl.cpp:166–180 / :529–532 / :570–573 |
| 130 | client-iface.txt 路径 / N-2 遗留 | ✅ 属实 | civlink_ctl.cpp:262–293；README.md:1475 |
| 140 | CivLinkHookState 1=running/0=init/-1=shutdown | ✅ 属实 | civlink_ctl.cpp:576–588 |
| 145 | status 无 -m 时自动探测模块 | ✅ 属实 | civlink_ctl.cpp:415–423 |
| 157–164 | counters 字段 + magic 校验 exit 4 | ✅ 属实 | civlink_ctl.cpp:600–673（:638–641 "do not trust these numbers"） |
| 172/214 | RunCtl 行 71–105 | ✅ 属实 | gui.cs:71–105 |
| 193 | summary 四段标签 | ✅ 属实 | main.rs:2126/2158/2191/2223 |
| 201/262 | agent Usage 1522–1527；reserve 条件 1547–1548 | ✅ 属实 | main.rs:1522–1527 / :1547–1548 |
| 205 | 配置写入顺序修复 398–403 | ✅ 属实 | civlink_ctl.cpp:398–403（在 ResolveTarget 之后；N-2 仍存，见 :402 早于 :407 OpenProcess） |
| 229 | ctl -w 参数 Usage 12–18 | ✅ 属实 | civlink_ctl.cpp:12–18 |
| 243/385 | exit code 0–5 语义行 26–27 | ✅ 属实 | civlink_ctl.cpp:26–27 |
| 268 | 34718 占用检测脚本实证 | ✅ 属实 | run-f1-selftest.ps1:55–59；run-f2-mechanical-selftest.ps1:33–35 |
| 270 | stop-file 顺序实证 | ✅ 属实 | run-f2-mechanical-selftest.ps1:56–59 |
| 294 | agent 对房名做匿名化，GUI 可直接展示 | ❌ **不成立** | main.rs:2129/2167 直接打印 args.sim_room_name；:348 仅定长拷贝，无遮蔽（N-1） |
| 266 | --bind-ip 仅接受当前主机本地地址 | ❌ **过度声明** | main.rs:891–892/2629–2631 明示 agent 只做格式校验（N-2） |
| 311 | agent 秒退检测 f1 §67–71 | ✅ 属实 | run-f1-selftest.ps1:67–71 |
| 431 | bind-ip fail-closed 895–898/2625 | ⚠️ 部分 | 拒 0.0.0.0/广播属实；「仅本机地址」过度声明（N-2） |

---

## 3. 硬约束逐条核查表

| 硬约束 | 结论 | 文档依据 |
|---|---|---|
| 零遥测零日志（d5/d6） | ✅ 遵守 | 第 31/177/178/300/325 行；设置页无遥测/日志开关、无持久化；诊断包仅用户点击一次性导出 |
| 不内嵌第三方组网（d1） | ✅ 遵守 | 第 412 行「不内嵌组网…不得预留会破坏 v1.0 纪律的入口」 |
| 仅 Steam Win64（d3） | ✅ 遵守 | 第 105/412 行「请先以 Steam Win64 启动游戏」「v1.0 锁定 Steam Win64 双人」 |
| 个人免费引导（d7） | ✅ 遵守 | 第 412 行用户自建 relay 兜底；无商业化入口 |
| v1.0 双人可验证闭环方案 A（d4） | ✅ 遵守 | 第 412 行；README.md:1476 |
| 机械/模拟证据不得宣传为双人真实联机 | ✅ 遵守 | 第 34/142/149/191/305/388 行强制话术；第 437 行「未经审计」 |
| UseShellExecute=false + 重定向 stdout/stderr | ✅ 遵守 | 第 220–223 行；与 gui.cs:87–90 一致 |
| 不改产品 DLL，仅调现成 ctl CLI | ✅ 遵守 | 第 33/393/412 行；「1:1 复用 ctl，不重写 IPC」；GUI 无注入逻辑实现 |
| 不干扰真实游戏对局（m28510） | ✅ 原则遵守，⚠️ 实现风险 | 第 412 行；但 N-4 超时策略可能在异常路径遗留远程线程，须修 |

---

## 4. 新发现表

| 编号 | 严重度 | 描述 | 建议 |
|---|---|---|---|
| **N-1** | **高** | §4.1 第 294 行断言「agent 自身在 SIM_NAME_OFFSET..+SIM_NAME_LEN 对房名做了匿名化，GUI 直接展示脱敏后的值即可，不得从原始 fixture 重新读取真实房名」。实读 `civlink/agent/src/main.rs:2128–2130`/`:2167`：`summary.txt` 直接打印原始 `args.sim_room_name`，「anonymized at offset 24..46」只是输出标签；`:348` 仅把名字拷入定长字段，无哈希/遮蔽；LAN simulated host 段（`:2167`）连标签都没有。诊断包若信任该断言将原样导出用户自定义房名（可能含 PII），违反 §4.1 脱敏强制要求。 | `Redactor.Redact` 必须无条件处理 summary 中所有 `room` 字段（含 LAN 段），不得依赖 agent 的「已匿名化」标签；T4 验收增加「自定义房名后导出样本无原文」用例。 |
| **N-2** | 中 | §3.3 第 266 行与附录第 431 行称 `--bind-ip`「fail-closed，仅接受当前主机本地地址，拒 0.0.0.0/广播」。实读 `civlink/agent/src/main.rs:891–892`/`:2629–2631`：agent 只做点分四段格式校验并拒 `0.0.0.0`/`255.255.255.255`，**并不验证是否本机地址**（由调用方 Get-NetIPConfiguration 保证）。设计高估了 agent 侧安全属性。 | 改写为「agent 仅拒 0.0.0.0/广播，本机性由 GUI 下拉枚举本机 IPv4 保证」；审计判词同步下调。 |
| **N-3** | 中 | §6 清单第 1 条（第 382 行）要求「输出 SHA-256 与 build-manifest.txt 一致」，与第 67 行「允许 PE 时间戳差异记待验证」及父代理实测（即便 `/deterministic+`，output_sha256 每次不同，MVID/TimeDateStamp 差 22 字节）冲突。build-manifest.txt 已改用 source_sha256+output_bytes=9216+exit=0 三准则。照原文审计会误判 T1 失败。 | 将 §6 第 1 条验收口径同步为「源哈希稳定 + 输出字节 9,216 稳定 + exit 0」，明确 output_sha256 变化不视为篡改。 |
| **N-4** | 中 | §3.1 第 229 行建议 status/counters 超时 5s、inject 15s，但 `civlink_ctl.cpp:301` RemoteCallInt 等 15s、`:501` LoadLibrary 等 15s、`:620` counters 等 10s。GUI 提前 Kill ctl 不会终止其已在游戏进程内 CreateRemoteThread 的远程线程，异常路径可能遗留半注入状态，触及「不干扰真实对局」硬约束。 | GUI 超时设为 ≥ ctl 内部最大等待 + 余量（建议 inject/status 20s、counters 15s、shutdown 15s），或超时后先查询远程模块状态再决定是否清理，并在诊断包记录。 |
| **N-5** | 中 | §2.7 第 201–202 行把 A 房主核心流程建立在 `--sim-lan-listen <LAN IP> --reserve-62900` 模拟/自检参数上，但 §2.2 控件清单未给 A 角色提供 LAN IP 选择控件，且 §7.4 第 418 行声明「GUI 默认不启用模拟模式」。普通 Steam 玩家真实房主由游戏本体建房，并不需要 agent 模拟主机；`--reserve-62900` 仅在模拟场景有意义。A 角色向导与「普通玩家三步即用」定位脱节。 | 明确普通 A 房主默认流程（大概率完全不启动 agent/模拟），把模拟能力收进「高级/自检」入口；作为产品决策点请负责人拍板后再定 T2 控件。 |
| **N-6** | 低 | `civlink_ctl_gui.cs` 行号引用系统性偏差（实读）：第 220–223 行「雏形行 74/75/76/77」对应 UseShellExecute/RedirectStdout/RedirectStderr/CreateNoWindow，实际在 `civlink_ctl_gui.cs:87/88/89/90`；第 228 行「行 79–82 同步 ReadToEnd+WaitForExit」实际在 `:93–95`；第 230 行「[exit code:N]（行 83–84）」实际在 `:98`；第 35 行 pidBox「行 55–56」实际声明在 `:18`。疑为针对旧版雏形撰写。 | 全文重核 gui.cs 行号；第 5 行「不是臆测」的范围收敛为「实测结论属实，行号引用待校正」。 |
| **N-7** | 低 | 文档元数据与任务书声明不一致：任务书称 48,999 B / 425 行，实测 52,207 B / 437 内容行（因新增 §3.1.1）。父代理已确认更新。非设计缺陷，但影响审计基线固定。 | 以本报告实测 SHA-256 `d9dcc5e2…` 为唯一基线，后续任何修订须重算并登记。 |

---

## 5. T1 前置条件核验（依父代理实测，不作 T1 产物审计）

- 固定 csc 绝对路径 `D:\MSVC\BuildTools\MSBuild\Current\Bin\Roslyn\csc.exe`：✅ 满足。
- 固定参数顺序 + 裸 DLL 名引用：✅ 满足（父代理实测裸名可解析）。
- 原样编译 9,216 B 校验值：✅ 满足（source_sha256 `59309076…` 稳定，output_bytes 恒 9,216，exit 恒 0）。
- 可复现脚本 + 构建清单：`civlink/gui/build-gui.ps1` + `civlink/gui/build-manifest.txt` 已存在，✅ 满足。
- **注意**：output_sha256 不稳定属环境固有（缺官方 ref assemblies 致 MVID 不可字节复现），设计第 67 行已允许；唯一需修的是 N-3（§6 清单第 1 条口径），修完后 T1 审计不应因哈希变化判失败。

---

## 6. 放行条件汇总

| 条件 | 关闭时点 | 阻断 T1？ |
|---|---|---|
| N-3 修订 §6 清单第 1 条哈希口径 | T1 产物审计前 | 否 |
| N-1 Redactor 无条件处理 room 字段 | T4 实现前 | 否 |
| N-2 改写 bind-ip 安全声明 | T5 实现前 | 否 |
| N-4 调整 ctl 调用超时 ≥ 内部等待 | T3/T5 实现前 | 否 |
| N-5 产品裁定普通 A 房主默认流程 | T2 实现前 | 否 |
| N-6/N-7 校正行号与固定审计基线 | 随下一版文档 | 否 |

**最终裁定：有条件通过；允许进入 T1；无阻断项。**

---

*本报告所有行号均来自对 `CivLink-M0A-audit` 工作区文件的实读；未以文档自述替代源码核对。*
