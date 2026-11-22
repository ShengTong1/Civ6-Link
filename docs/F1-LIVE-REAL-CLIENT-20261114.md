# F1-live：真实文明6 客户端的发现发送被 Hook 捕获并逐帧到达 Agent

- 日期：2026-11-14
- 阶段：REV-016 §3 **F1（DLL + Agent 发现链路）**
- 证据目录：`M0A\captures\F1-live-20261114-092257`
- 状态（2026-11-14 复核后）：**有限通过** —— 仅「真实客户端 Hook→Agent 观测」子项通过；
  **F1 集成链路尚未通过**（模拟房主尚未接入 DLL/Agent 链路，客户端未显示模拟房间）

---

## 0. 一句话结论

在**单台真实 Civilization VI (DX12) 客户端**上注入 `civlink_hook.dll` 并运行 `civlink-agent.exe`，操作者点击局域网**刷新**后：

> **Hook 捕获到 1400 次发现发送（14 组 × 100 包），Agent 收到 1400 个 CVLH2 帧，
> 两侧计数完全闭合（1400 == 1400），无失败、无超限、无序号缺口、无重复、无乱序，
> 目标端口覆盖 62900–62999 全部 100 个，游戏进程保持响应且行为无变化。**

这证明：**真实客户端走的正是我们已挂的 `sendto` 路径**，且 Hook→Agent 的本机通道不存在"发送了但没到、且无人记录"的缺口。

> **复核边界（2026-11-14 codex 复核后补充）**：以上结论只覆盖
> 「真实客户端 Hook→Agent 观测」子项。按 REV-016 定义，F1 还要求把模拟房主接入
> DLL/Agent 链路并由真实客户端显示模拟房间——本轮 Agent **只观测不转发**、无模拟房主参与，
> 因此 **F1 整体未通过**，后续文档一律记作「观测子项通过」。

---

## 1. 执行环境

| 项 | 值 |
|---|---|
| 游戏进程 | `CivilizationVI_DX12.exe`，pid **46368**，启动 2026-11-14 09:16:02 |
| 安装路径 | `E:\SteamLibrary\steamapps\common\Sid Meier's Civilization VI\Base\Binaries\Win64Steam\CivilizationVI_DX12.exe`（注册表 `D:\steam` 已过期） |
| 状态 | 多人游戏 → 局域网 列表界面 |
| 游戏 UDP 端点 | 31 个，`0.0.0.0:58063–58094`（客户端形态，**不 bind 62900**） |
| Agent 监听 | `127.0.0.1:34718`，185.9 s |
| 控制器/Agent 运行位置 | 中立目录 `C:\Users\dd\Desktop\civlink-f1\`（见 §3） |
| 操作者动作 | 在局域网界面反复点击**刷新** |

---

## 2. 交付物身份（本轮构建，x64 / MT 静态 CRT）

**运行本轮 F1-live 时实际使用的二进制**（证据目录内计数即由这三件产生）：

| 文件 | 字节 | SHA256 |
|---|---|---|
| `civlink_hook.dll` | 118 272 | `71C240377449CF0AB14BE64C4BCD0E4D8CCAC024B629B285CCED47585CFED41D` |
| `civlink_ctl.exe` | 172 032 | `64C39027A14590FE6CBEBCCE026B1D5FB121C81181462639F22E1DF9E2499CBA` |
| `civlink-agent.exe` | 296 960 | `0EA74B4D3A7DB52E9B7A46F1A70DAD86B352A3D392C9ACF5584634EE5B4C0A9E` |

> **注**：`civlink_ctl.exe` 在本轮之后又改过两次（见 §7 第 1、5 条：`session=` 与
> `hook state` 的显示修复），当前树内哈希为
> `DD9FB2BE55D1D6476B98EFD85584545F841B0B35967E2C776FCBA870E7F80C05`；
> `hook_selftest.exe` 现为
> `0767D23E966D6F8096CB52CB9AF9315D07279D33410047499AAB17BC11355FFE`。
> 这两次改动**只涉及控制器的打印**，不触碰 Hook 与 Agent 的数据路径，
> 因此上面的 1400 帧证据仍然有效；`run-f1-selftest.ps1` 在改后复跑
> `F1-SELFTEST: PASS`（证据 `M0A\captures\F1-selftest-20261114-093344`）。

证据文件：

| 文件 | 字节 | SHA256 |
|---|---|---|
| `frame-log.txt` | 201 069 | `B3E3D72906820DF0CE14A3422020F8804461ADC04441111C0A59A5A7A6CDD18D` |
| `summary.txt` | 1 350 | `F94535EA782C991A65DA56CE7E403129478D7EFAD659D471C4301E38AA5349BA` |
| `counters-after.txt` | 1 336 | `1CD4336FD9CF356443F20B327EED9D7F2B7BC077C5201CB722B97FD3A5BE2567` |
| `shutdown-evidence-20261114-100926.txt` | 1 872 | `5106B6DD08A577F3F06DA89021F9D1584C2319859F823DD4B1F8C4594C62DC34`（复核后补录，见 §4.4） |
| `hook-events.txt` | 2 331 | `71269EFCEA44157C27CDEF2C084A601F367BCEBE6A4C14C5A95E326342EF5D1F` |
| `agent-console.txt` | 0 | `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`（`--quiet` 正常为空） |

---

## 3. 过程：两次窗口，第一次为 0 的原因

1. **09:17 首次尝试**（从项目目录 `CivLink-M0A-audit\civlink\` 启动）：Agent 起来了，但
   `civlink_ctl.exe inject` 报 `SeDebugPrivilege not granted` + `OpenProcess failed err=5`（exit 2）。
2. **根因不是游戏提权**：`GetTokenInformation(TokenElevation)` 实测游戏 `TokenElevation=0`；
   从本 shell（Medium IL）直接 `OpenProcess` 各掩码全部成功。
   真正原因与 PHASE0 同一类——**`C:\Users\dd\Desktop\injciv6-v0.3.3` 带
   `Mandatory Label\Low Mandatory Level:(OI)(CI)(NW)`，继承给 `civlink_ctl.exe`，
   使它自己跑在 Low IL，打不开 Medium IL 的游戏进程。**
3. **UAC 弯路（已放弃）**：写了自提权 `run-f1-live-elevated.cmd`，UAC 弹出的是
   "Open File - Security Warning"（pid 47232）而不是同意框，卡住不前进，已 `Stop-Process` 取消。
   **教训：不要用 UAC 绕过 Low IL，直接换中立目录。**
4. **突破**：把四件二进制与脚本复制到 `C:\Users\dd\Desktop\civlink-f1\`（无 Low 标签）→
   `civlink_ctl.exe status` 报 `hook state : 1 (running)`，`init error : 0`，注入成功。
5. **窗口 A（`F1-live-20261114-091950`，153 s）收到 0 个数据报** —— 原因是该窗口在
   **01:22:24 UTC（09:22:24 CST）** 就结束了，而操作者是收到我 09:24:33 的提示后才开始点刷新。
   **属窗口与操作时序错配，不是 Hook 失效。**
6. **窗口 B（`F1-live-20261114-092257`，185.9 s）**：操作者点刷新期间，计数开始滚动
   （`sent=100 → 200 → … → 1400`），停在 1400 后不再增长。

> Agent 的时间戳是 **UTC**（`01:23:19` = 北京时间 `09:23:19`）。

---

## 4. 核心结果

### 4.1 Hook 侧计数（`counters-after.txt`）

```
version        : 1
session id     : 0xb557b20a47f6
running        : 1
shutdown       : 0 (in-flight at shutdown: 0)
init error     : 0
sent           : 1400
send fail      : 0
reject oversize: 0
sent notify    : 0
ignored        : 0
scatter/gather : 0
sock overflow  : 0
src unknown    : 14
state queries  : 4
accounted      : 1400 (sent+sendFail+rejectOversize)
```

### 4.2 Agent 侧对账（`summary.txt`）

```
listen window   : 127.0.0.1:34718 for 185.9 s
datagrams       : 1400
bytes           : 64400
received frames : 1400 (processed 1400, rejected 0)
reconciliation  : processed + rejected = 1400 == received = 1400
sessions        : 1
  session 0xb557b20a47f6
    frames=1400 first_seq=Some(1) last_seq=Some(1400)
    seq gaps=0 missing_frames=0 duplicates=0 out_of_order=0
    payload bytes=5600 discovery_magic=1400 other_payload=0
    via_wsasendto=0 limited_bcast=1400 discovery_flag=1400 no_payload=0 rejected_oversize=0
    logical sockets=14
    dst ports=100 (min 62900, max 62999, in 62900..62999: 100)
```

**三方计数一致**：`hook.sent 1400 == agent.processed 1400 == agent.datagrams 1400`；
`hook.sendFail 0`、`hook.rejectOversize 0`、`agent.rejected 0`。

### 4.3 逐 socket 明细（`frame-log.txt` 1400 行，全部 `len=4 flags=0x06`）

| socket | 帧数 | 不同目标端口 | 端口范围 | 源端口 | 跨度 |
|---|---|---|---|---|---|
| 1 | 100 | 100 | 62900–62999 | 59473 | 01:23:19.127 → .129 |
| 2 | 100 | 100 | 62900–62999 | 62485 | 01:23:27.600 → .601 |
| 3 | 100 | 100 | 62900–62999 | 63167 | 01:23:37.483 → .484 |
| 4 | 100 | 100 | 62900–62999 | 57943 | 01:23:43.545 → .547 |
| 5 | 100 | 100 | 62900–62999 | 52705 | 01:23:52.066 → .067 |
| 6 | 100 | 100 | 62900–62999 | 63479 | 01:23:57.806 → .807 |
| 7 | 100 | 100 | 62900–62999 | 60611 | 01:24:02.684 → .685 |
| 8 | 100 | 100 | 62900–62999 | 56453 | 01:24:08.495 → .497 |
| 9 | 100 | 100 | 62900–62999 | 56614 | 01:24:14.511 → .512 |
| 10 | 100 | 100 | 62900–62999 | 63493 | 01:24:20.446 → .448 |
| 11 | 100 | 100 | 62900–62999 | 56409 | 01:24:26.934 → .936 |
| 12 | 100 | 100 | 62900–62999 | 57575 | 01:24:32.850 → .851 |
| 13 | 100 | 100 | 62900–62999 | 54711 | 01:24:39.427 → .429 |
| 14 | 100 | 100 | 62900–62999 | 54712 | 01:24:48.247 → .248 |

- 每组 100 包在 **1–3 ms** 内发完。
- 全部载荷 `4 字节`、`flags=0x06`（`LIMITED_BCAST | DISCOVERY`）、`head=8DE8FC70`。
- **突发间隔**（13 个）：8.473 / 9.883 / 6.062 / 8.521 / 5.740 / 4.878 / 5.811 / 6.016 / 5.935 / 6.488 / 5.916 / 6.577 / 8.820 s。

### 4.4 游戏健康与收尾（含复核后补录的 shutdown 证据）

采集期间 `Get-Process 46368` → `Responding = True`，工作集 1 426 MB，游戏行为无变化。

**收尾时序（2026-11-14 codex 复核后核对，修正此前"收尾即 shutdown"的表述）**：

1. **采集结束瞬间**（Agent 因 `STOP` 文件退出时）抓的 `counters-after.txt` 显示
   `running : 1 / shutdown : 0` —— 那一刻 Hook **仍在运行**（B2 审计运行模式，Agent 退出不自动卸钩）。
2. **shutdown 是之后单独执行**的（`civlink_ctl.exe shutdown`，当时返回 0 = 干净排空，0 在途）。
3. **复核后补录**（证据目录新增 `shutdown-evidence-20261114-100926.txt`，44 行，
   sha256 `5106B6DD08A577F3F06DA89021F9D1584C2319859F823DD4B1F8C4594C62DC34`）：
   - `civlink_ctl.exe shutdown`（复跑）→ `CivLinkShutdown returned 1 (already shut down)`，RC=0；
   - 事后 `status` → `hook state : -1 (shut down)`；
   - 事后 `counters` → `running : 0 / shutdown : 1 (in-flight at shutdown: 0)`、
     `sent : 1400` 保持不变、`state queries : 9`（含本次复核的查询）；
   - 游戏进程仍 `Responding=True`，DLL 按 B2 审计运行模式**保持映射直至进程退出**；
   - Agent 已退出、34718 已释放、无残留进程。

> 即：**shutdown 确实执行过且排空干净**（事后 `in-flight: 0`、`sent` 停在 1400 不再增长），
> 证据链为「采集结束时的 `counters-after.txt`（running:1）→ 单独 shutdown → 复核后补录的
> shutdown-evidence（running:0 / shutdown:1）」。1400 帧捕获与对账结论不受此项影响。

---

## 5. 本轮确立的四个新事实

1. **真实客户端走 `sendto`，不是 `WSASend`。**
   1400 帧全部 `via_wsasendto=0` + `limited_bcast=1400`，`ignored=0`（说明没有"调用了但不像发现包"的发送）。
   此前 96 s 零流量是**窗口内没人点刷新**造成的，不是 API 未覆盖——这一点在窗口 A/B 的对照中已排除。

2. **每次刷新都用一个全新 socket。**
   14 次刷新 → **14 个不同 logical_socket_id、14 个不同临时源端口**（59473、62485…54712）。
   即客户端不是复用长连 socket 反复广播，而是**一次性 socket：发 100 包 → 关掉**。
   这对 F2/F3 的会话表设计是硬约束：`socket_generation` 会快速单调增长，**不能假设 socket 长期存活**；
   Agent 侧按 socket 聚合时必须以"刷新"为单位而不是"连接"为单位。

3. **每个 socket 的首帧 `src=0.0.0.0:0` 属预期，且只出现 1 次/socket。**
   `src unknown = 14` 恰好等于 socket 数：UDP socket 在首次 `sendto` 前尚未绑定，`getsockname` 返回 `0.0.0.0:0`；
   Hook 按 v0.1.1 修复"未绑定不算已知"，下一帧重试即取得真实端口（第 2–100 帧全部有真实源端口）。
   **这是已记录的行为，不是缺陷。**

4. **本轮未观察到 F0 里那种 ~2.5 s 自动重发。**
   13 个间隔全部 ≥ 4.878 s。F0 曾观察到 6 组间隔 2.40–2.89 s 的补发。
   **两种可能无法区分**：操作者这次点得慢 / 自动重发只在特定条件下发生。
   **不得据本轮否定 F0 的自动重发观察**，也不得据 F0 断言本轮"每次刷新只有一组"。

---

## 6. 边界（强制）

**允许的表述**

- "在单台真实 Civilization VI (DX12) 客户端上，Hook 捕获到发现广播发送 1400 次，逐帧到达本机 Agent，两侧计数闭合。"
- "真实客户端一次刷新产生 100 个四字节发现包，覆盖 62900–62999，且每次刷新使用新的临时源端口。"
- "注入与观测期间游戏进程保持响应，行为未见变化。"

**不允许的表述**

- 不得写成"发现已被接管 / 已实现转发 / 已能联机 / M0-B 可行 / Gate A 通过"。
- 本阶段 **Agent 只观测不转发**，未向任何远端发送一个字节。
- 本轮**不涉及**第二台机器、不涉及 62056 数据面、不涉及 Fake-IP、不涉及 Relay。
- 不能据此勾掉 E2-A / E2-B / E3，不能移动任何 Gate。
- "游戏行为无变化"仅指本轮窗口内进程响应与界面可操作，**不是**完整回归结论。

---

## 7. 本轮发现并修掉的问题

1. **`civlink_ctl inject` 把模块基址当 session id 打印**
   （`ctl\civlink_ctl.cpp` 原 `printf("[+] hooks active … session=0x%llx", after.base)`）。
   这是**证据字段污染**：Agent 的 `session=` 是真实会话 id（`0xb557b20a47f6`），ctl 打印的却是 DLL 基址（`0x7ff9a3150000`）。
   已改为分别打印 `dll base` 与指向 `counters` 的提示，不再冒充 session id。

2. **DLL 被映射时无法重新 link（`LNK1104: 无法打开文件"civlink_hook.dll"`）**
   ——这是 B2 审计运行模式的必然后果（shutdown 不卸载模块）。
   `build-msvc.cmd` 增加 `CIVLINK_SKIP_DLL=1`：只改控制器/自检时复用在用 DLL，不尝试覆盖。

3. **UAC 自提权不可用**（安全警告框而非同意框）——已放弃该路径，改用中立目录；
   该实验性的 `run-f1-live-elevated.cmd` 已于本轮回退删除（SHA256 `D44792CE…` 仅留档于此）。

4. **Low IL 继承**是项目目录树的既有属性，不是本轮引入；凡需打开 Medium IL 进程的工具都必须从中立目录启动。

5. **`civlink_ctl status` 把 `-1` 打成 `4294967295`**
   （`CivLinkHookState` 返回 `int`，但 `RemoteCallInt` 取的是线程退出码 `DWORD`）。
   已加 `const int state = (int)st;` 后再比较，现输出 `hook state : -1 (shut down)`。
   同一类"类型宽度偷换"问题的第二次出现（第一次是把基址当 session id），
   **凡跨模块取返回值都要先确认签名宽度与符号性**。

6. **中性目录运行时证据目录落到 `C:\Users\dd\<用户>\M0A\captures`**
   （`run-f1-selftest.ps1` 用 `Split-Path -Parent` 上跳两级推算 repo 根，在中立目录下算错）。
   已加 `-OutRoot` 参数并让默认值先检测 `<repo>\M0A` 是否存在，否则退回脚本同级 `captures`；
   误建的 `C:\Users\dd\M0A\` 已清理。

---

## 8. 下一步（2026-11-14 复核后更新）

- **F1 状态**：仅「真实客户端 Hook→Agent 观测」子项通过（有限通过）；
  **F1 集成链路未通过**——补全方式：把模拟房主接入 DLL/Agent 链路（Agent 具备转发/注入能力后），
  由真实 Civ6 客户端显示模拟房间；本轮 Agent 只观测不转发，故该项仍待做。
- 进入 **F2（Fake-IP 游戏数据面，62056）** 的设计输入已确认（吸收本轮四个新事实 +
  codex 复核四条约束：会话以刷新为单位、首帧 `0.0.0.0:0` 不得用于 Peer/Fake-IP 映射、
  `sendto` 结论限本窗口不可外推、Hook 同步观测对游戏时序的影响须在队列满/Agent 未运行/高负载下验证）。
- 真实双机、E2-B、E3、Gate A 状态**未变**。
