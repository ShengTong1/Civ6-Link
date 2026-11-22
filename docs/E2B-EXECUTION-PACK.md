# E2-B 执行包（CivLink M0-A / 双机发现取证）

> 版本：v1.3（2026-11-16 23:35；按 civtrace v0.4.5 日志限流修复更新 §1 二进制身份：`civtrace.dll`=`60232D93…`/247,296 B、`civinject.exe`=`4C1E1D0D…`/171,520 B，v0.4.4 的 `19196FF7…`/`54627EAB…` 已作废；理由：v0.4.4 会把 62056 数据面忙轮询每条写盘，单轮可产生 15.4 GB 日志，详见 `docs\CIVTRACE-LOGBOUND-20261116.md`。v1.2 于 2026-11-16 21:53；v1.1 按 E2B-TAG-MECHANISM-REVIEW 审计修正：做法 B 用真实 exe 路径 + `Start-Process -WorkingDirectory`、补 DRM 未验证声明与 tag 字符集、§8 权威指针标注操作单/交接文档为历史记录；v1.0 的 `$env:` 设 tag 写法在 Steam 启动路径下不生效，已更正为 `setx`+重启 Steam 或直接起 exe，见 §3 步骤 2）
> 授权依据：REV-012-REVIEW（E2-B 批准，排在 E2-A/H4 之后）
> 适用条件：**两台机器同时在线、两端都能运行 Civ6、执行者能手动点 UAC**
> 前置状态：E2-A/H4 已结案（H4 限定样本）；合成实验 E2-B-SYNTHETIC-CLIENT 已闭合，**不替代本实验**

---

## 0. 这个包解决什么

E2-B 要回答的核心问题只有一个：

> **Civ6 的发现 socket 从第一包广播到 `closesocket` 之间活了多久？这个窗口装不装得下 +20~50 ms 的联机助手中继 RTT？**

这就是 H6。它决定 CivLink 能不能用"中继发现请求"这种最省事的架构——
如果窗口只有 30 ms 而后端要 50 ms，中继方案直接出局，必须改成"客户端侧伪造房主列表"。

配套工具 `analyze-h6-window.ps1` 已就绪并回归 20/20 通过，直接从 civtrace 日志算出这个数，
不需要人手工读 60 MB 日志。

---

## 1. 本包文件清单与身份

| 文件 | SHA256 | 字节 |
|---|---|---|
| `CivLink-M0A-audit\civtrace\civtrace.dll`（v0.4.5，日志限流版） | `60232D932B110D52C017CE8206A95C59A91AE948EE728ACBA172992553A53843` | 247296 |
| `CivLink-M0A-audit\civtrace\civinject.exe`（v0.4.5） | `4C1E1D0D43EA718618BE31C6DAB3E0C39478C03229B138444A515745F30AC93F` | 171520 |
| `CivLink-M0A-audit\scripts\analyze-h6-window.ps1` | `1606BD039CA353554BAAEC0F2EBD559BAD6BAF836CEF678BB53273211C8D3F9D` | 12355 |
| `CivLink-M0A-audit\scripts\test-analyze-h6.ps1` | `BBA8D3EFC6826DCA230916583EEE72B657EB9FDE6D35AF94418C703D380FA2D3` | 10114 |

两端都必须用**上表同哈希**的 `civtrace.dll` / `civinject.exe`。哈希不一致 = 本轮作废。

---

## 2. 阶段门禁（缺一条就不许开始）

- [ ] 两台机器都在同一广播域（`ping` 互通，`netpath.ps1` 的 `Find-NetRoute 255.255.255.255` 指向 WLAN）
- [ ] 两端都完全退出 Civ6（不是回主菜单，是**进程结束**）
- [ ] 两端 `CIVTRACE_TAG` 已分别设为 `host` / `client`，且该变量**已进入游戏进程自己的环境**（见 §3 步骤 2 的两种正确做法；仅在某个 PowerShell 窗口 `$env:` 里设不算），注入后日志文件名带 `_host` / `_client` 后缀可自证
- [ ] 执行目录用的是中立副本 `C:\Users\dd\Desktop\civlink-run\`（**不能**在项目目录里跑，见 §2.1）
- [ ] 两端都能点一次 UAC（pktmon 抓包需要）
- [ ] Gate A 仍未批准、M0-B 仍冻结 —— 本实验**只做被动观测，不改包、不改网卡、不动防火墙**

### 2.1 为什么必须用中立目录（踩过的坑）

在项目目录 `injciv6-v0.3.3\` 里注入时，`civinject.exe` 只看到 **29 个进程**；
同一份二进制放到 `C:\Users\dd\Desktop\civlink-run\` 就正常看到 **361–366 个进程**。
这是项目目录的进程可见性限制导致的注入器枚举不全，会让"没找到游戏"变成假故障。

准备指令（两端都做）：
```powershell
$src = 'C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit\civtrace'
$run = 'C:\Users\dd\Desktop\civlink-run'
New-Item -ItemType Directory -Force -Path $run | Out-Null
Copy-Item "$src\civtrace.dll" $run -Force
Copy-Item "$src\civinject.exe" $run -Force
Get-FileHash "$run\civtrace.dll","$run\civinject.exe" -Algorithm SHA256
```
最后一步的哈希必须与 §1 表一致。

---

## 3. 执行步骤（按序，每步有验证）

### 步骤 1 — 两端各跑一次基线（E0）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit\scripts\collect-baseline.ps1 `
  -GameDir "E:\SteamLibrary\steamapps\common\Sid Meier's Civilization VI" `
  -Tag E2-B -PeerIp <对端局域网IP>
```

**验证**：`lan-reachability.txt` 里 `Test-Connection` 对端全 0 丢包，`Find-NetRoute` 指向 WLAN 接口。
不满足 → 本轮无效，停下来查网络，不要继续。

### 步骤 2 — 两端设角色 tag 并启动游戏

> **关键机制（2026-11-16 更正，v1.1）**：`civtrace.dll` 是在**游戏进程内部**调用
> `GetEnvironmentVariableW("CIVTRACE_TAG")`（`trace_dll.cpp:287`）——它读到的是
> **游戏进程自己的环境**，注入器不做任何传递。而从 Steam 客户端启动的游戏继承的是
> **Steam 进程**的环境，不是你在另一个 PowerShell 窗口里 `$env:` 设的值。
> 历史证据：本机 86 份 civtrace 日志中带 `_host`/`_client` 后缀的为 **0** 份，
> 即 v1.0 的 `$env:` 写法在 Steam 启动路径下**从未生效**过。

**做法 A（推荐，两端都适用）** —— 持久化到用户环境后重启 Steam：

```powershell
# PC-A（房主）
setx CIVTRACE_TAG host
# PC-B（客户端）
setx CIVTRACE_TAG client
```

`setx` 写的是注册表用户环境，**对已经运行的进程无效**，所以必须：

1. 彻底退出 Steam（托盘右键退出，任务管理器确认 `steam.exe` 没了）；
2. 重新从开始菜单/桌面启动 Steam（新 Steam 会读到新值）；
3. 从 Steam 启动 Civ6 —— 游戏继承 Steam 的环境，tag 生效。

**做法 B（免重启 Steam，适合只想跑一次）** —— 直接从 PowerShell 启动游戏 exe：

```powershell
$env:CIVTRACE_TAG = 'host'   # PC-B 用 'client'
$exe = "E:\SteamLibrary\steamapps\common\Sid Meier's Civilization VI\Base\Binaries\Win64Steam\CivilizationVI_DX12.exe"
Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe)
```

游戏作为该窗口的子进程启动，**直接继承** `$env:` 值（本机实测继承语义成立）。
Steam 客户端保持后台运行作为 DRM 宿主；**该 DRM 行为未在本机验证**——若直接启动后
游戏秒退，请改用做法 A。`Win64Steam\` 目录下的 `CivilizationVI.exe`（DX11）与
`CivilizationVI_DX12.exe`（DX12）择一即可，但 `-x` 的进程名必须与之一致。
注意：这样启动的游戏若崩溃，启动它的窗口关掉游戏也会退出，属正常。

**自证（注入后立刻看）**：日志文件名必须是
`civtrace_<日期>_<时间>_pid<N>_host.log` / `..._client.log`。**没有后缀就是没生效**，
停下来按 A 或 B 重来，不要继续后面步骤。可直接粘贴：

```powershell
Get-ChildItem "$env:LOCALAPPDATA\CivLink\M0A\logs\*.log" |
  Where-Object Name -match '_(host|client)\.log$' |
  Sort-Object LastWriteTime | Select-Object -Last 1 Name,Length,LastWriteTime
```

> tag 只接受 `A-Z a-z 0-9 - _`，最多 24 字符；**非法字符会被静默丢弃**
> （`trace_dll.cpp:289-292`）——写中文 tag 会退化成无后缀，等于没设。

> 顺带：`$env:CIVTRACE_TAG='client'` 误打进 A 机窗口不会造成任何损害——它只影响
> "从那个窗口启动的进程"，关掉窗口即消失；但若用做法 B 且已经这样启动了游戏，
> 要完全退出游戏后重来（同一进程内不能重复启停追踪）。
>
> 收尾清理（若用过做法 A 的 `setx`）：实验结束后执行
> `setx CIVTRACE_TAG ""`（或 `reg delete HKCU\Environment /v CIVTRACE_TAG /f`），
> 避免后续单机实验带着错误 tag 污染日志名。

### 步骤 3 — 回主菜单后注入（两端）

> `-x` 后面的名字必须与**实际在跑的那个 exe** 一致。Steam 默认启动 DX12 版，进程名是
> `CivilizationVI_DX12.exe`；如果启动的是普通版则是 `CivilizationVI.exe`。
> 不确定就先跑一句确认：
> ```powershell
> Get-Process | Where-Object { $_.ProcessName -like 'CivilizationVI*' } | Select-Object Id, ProcessName, Path
> ```

```powershell
cd C:\Users\dd\Desktop\civlink-run
.\civinject.exe -x CivilizationVI_DX12.exe
```

**验证**：
- 输出含 `[*] matched N process(es)` 和完整镜像路径
- 输出 `[+] OK @ <模块基址>`
- 日志文件出现：`%LOCALAPPDATA%\CivLink\M0A\logs\civtrace_<日期>_<时间>_pid<N>_<tag>.log`
- 日志里有 `hooks installed ok=31 fail=0` ← **必须 31/31，缺一个都停**

只有主菜单能注入。**不要**在大厅或对局里注入。

### 步骤 4 — 两端同时开始抓包（需各点一次 UAC）

按 `README §1.4` 的方式启动 pcapng 抓包，**`--pkt-size 0`**（默认 128 会把 1146 B 帧截成 86 B 载荷，1104 B 的 JSON 就没了）。

两端都确认打印出「现在开始抓包」之后再进下一步。

### 步骤 5 — 房主建房

PC-A 进 多人游戏 → 局域网 → 创建游戏，建房并停在房间界面。

**记录**：PC-A 是否在此时 `bind ...:62900`。这一步是 E2-A 的复证，顺带做。

### 步骤 6 — ★客户端刷新 10 次（本轮核心数据）

PC-B 进 多人游戏 → 局域网，然后**点刷新 10 次，每次间隔 1–2 秒**。

每点一次，**记录这一轮有没有看到房间**（例如最后汇总成 `3/10`）。
这个计数本身就是 H4/发现可靠性的现场旁证，别漏。

### 步骤 7 — 进对局 2–3 分钟

两端都加入并进对局，正常玩 2–3 分钟。这段是 E3 的素材（62056 / H3 / H8 / H10），
本轮不分析，但**抓包别停**，一起收走。

### 步骤 8 — 回主菜单后停用（两端）

```powershell
cd C:\Users\dd\Desktop\civlink-run
.\civinject.exe -x CivilizationVI_DX12.exe -u
```

**验证**：
- 输出 `CivTraceShutdown confirmed`
- 输出 `[+] B2 audit-run mode: ... intentionally LEFT MAPPED until pid=N exits`
- 退出码 **0**

> **`-u` 返回 2 是正常的**：说明还有 hook 正在执行，5 秒排空超时。
> 回主菜单**静止 10 秒以上**再 `-u` 一次即可。**绝不要强杀进程**——v0.4.4 是审计运行模式，
> DLL 会保持映射到进程退出，强杀会丢日志尾巴。

再执行一次 `-u` 应该幂等返回 0；再注入应报 `already loaded`（证明 hook 未恢复）。
**同一进程内不能重复启停追踪**，要重跑必须完全退出游戏。

### 步骤 9 — 停抓包并回传

停 pktmon，取 pcapng。然后按 §4 清点。

---

## 4. 回传清单（缺项即视为本轮不完整）

### 4.1 两端日志
- `civtrace_*_pid<N>_host.log`（PC-A）
- `civtrace_*_pid<N>_client.log`（PC-B）
- 每个日志的 **完整路径 + 字节数 + SHA256**

### 4.2 两端抓包
- `*.pcapng` + SHA256（两端各一份）

### 4.3 现场记录（`report.txt`，手写即可，必须诚实）
1. 每端点刷新看到了几次房间？→ 如 `3/10`
2. 注入输出原文（两端的 `matched` / `OK @` 行）
3. `-u` 的退出码，以及是否出现过返回 2、重试几次才 0
4. 两端 PID（游戏进程）与注入时刻
5. 有没有任何一步没按规程做（如实写，比事后解释有用）

### 4.4 分析结果（回来跑，见 §5）

---

## 5. 数据分析（回到 PC-A 上跑）

### 5.1 先确认追踪没改变行为（E2-B 的前置判据）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit\scripts\analyze-trace.ps1 `
  -Log <client日志> -Discovery
```

看 `sendto 255.255.255.255` 条数：**一次刷新 = 100 条**（每端口一条）。
如果明显不是 100 的倍数，说明追踪改变了发现行为，本轮结论作废，先查原因。

### 5.2 主分析：H6 窗口分布

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit\scripts\analyze-h6-window.ps1 `
  -Log <client日志> -RelayRttMs 50 `
  -Csv C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\E2B-<日期>\h6.csv
```

输出会直接给：
- 每轮的 `sends / ports / burst_ms / window_ms / resp_ms / respN / resp2close / closed` 表
- `window_ms: n= min= p50= p90= max=`
- `relay target 50 ms : X/Y closed rounds have window >= target`
- 判定一句话（PASS / MIXED / NO closed round fits）

**退出码**：`0` = 找到轮次；`2` = 没有广播（日志角色或时机不对）；`3` = 文件不存在。

### 5.3 判据对照

| 指标 | 含义 | 期望 |
|---|---|---|
| `sends=100 ports=100` | 完整 62900..62999 扫描 | 每轮都应是 |
| `burst_ms` | 100 包撒完耗时 | 与 E1 的 1–4 ms 同量级 |
| `window_ms` | 首包→closesocket | **H6 核心数**，看 p50/p90 |
| `resp_ms` | 首包→首响应 | E2-A 实测约 10 ms |
| `respN` | 该轮收到几页 | 正常 22（房主分页） |
| `resp2close` | 末响应→关闭 | 剩余排空余量 |

### 5.4 交叉验证（Wireshark）

用 `analyze-discovery-handshake.ps1 -Pcap <pcapng>` 抽出 REQ/REP 的 tick 时间戳，
与日志的 `window_ms` / `resp_ms` 对比。两者量级一致才算交叉验证通过——
**日志是本机 QPC，抓包是网卡时间戳，两者不该差出一倍**。

---

## 6. 结论怎么写（表述边界，不可越界）

**可以写**：
- "在两端均为 v0.4.4、全新进程、双端注入条件下，发现 socket 存活窗口 n 轮 min/p50/p90/max = …"
- "该分布 [容纳 / 不总容纳 / 完全不容纳] +20~50 ms 中继 RTT"
- "E2-A 的 F2（1104 B × 22 页）在本轮复证成立/不成立"

**不可以写**：
- ❌ "E2-B 完成" → 若某项判据没拿到，就是没完成
- ❌ "中继方案可行" → H6 只是**必要输入之一**，不构成可行性结论
- ❌ "M0-B 最小可行原型已验证" → Gate A 都没批
- ❌ 把合成实验（E2-B-SYNTHETIC-CLIENT）的证据混进本轮
- ❌ 把单机/双机发现阶段的结论说成"联机对局已验证"

**E3 仍未完成**：62056 归属、H3 五分类、H8 socket 选项、H10 清理时序都要单独裁。
本轮抓包顺带收到的对局流量只是素材，不是结论。

---

## 7. 已知失败模式（照这份清单排，别重新发明）

| 症状 | 原因 | 处理 |
|---|---|---|
| 注入报 `matched 0 process(es)` | 在项目目录里跑，进程枚举不全 | 换 `civlink-run\` 中立目录 |
| 注入报 `already loaded` | 同进程已注入过 | 完全退出游戏重启；同一进程不能重复启停 |
| 日志没有 `_host` / `_client` 后缀 | tag 没进**游戏进程**的环境（Steam 启动继承 Steam 环境，另一窗口 `$env:` 无效） | 按 §3 步骤 2 做法 A（`setx` + 重启 Steam）或做法 B（从该窗口直接起 exe），退出游戏重来 |
| `-u` 返回 2 | 有 hook 在执行，5 s 排空超时 | 回主菜单静止 10 s 再 `-u`，别强杀 |
| `analyze-h6-window.ps1` 退出 2 | 日志里没有广播 | 拿错角色的日志（房主只有建房那一刻广播），或注入晚于发现阶段 |
| `window_ms` 显示 `n/a` | 日志没覆盖到 `closesocket` | 抓包/日志要覆盖到回主菜单之后 |
| pcapng 里载荷只有 86 B | `--pkt-size 128` 截断 | 必须 `--pkt-size 0` |
| 抓包为空 | 没点 UAC / 抓包起晚了 | 抓包必须在"点刷新之前"启动 |

---

## 8. 本包与其它文书的关系

| 文书 | 关系 |
|---|---|
| `REV-012-REVIEW.md` | E2-B 的授权来源与判据要求 |
| `README.md §4` | 原始步骤定义（本包是它的可执行化展开） |
| `M0A\pcb-kit\PC-B-操作单.md` | PC-B 侧的通俗版操作单（本包 §3 与之对应）。**该文件头部自述已过期（G2/Radmin 归因早于 2026-11-12 范围决议）——E2-B 只以本包 §3 为准** |
| `M0A\pcb-kit\PC-B-交接文档.md` | 历史记录，**不得据其执行**（其中 tag 设置等语句已被本包 v1.1 更正取代） |
| `E2B-SYNTHETIC-CLIENT-SUBMISSION.md` | 合成实验，**不替代**本实验 |
| `CivLink-技术设计规范-v2.1.md` | 架构与稳定性阈值，本包不改动任何阈值 |

---

## 9. 状态

- 本包状态：**就绪，等 PC-B 在线**
- 阻塞原因：2026-11-13 13:13 实测 `Test-Connection 192.168.31.214` = False，
  `Get-NetNeighbor` 里 `192.168.31.214` 为 `Unreachable`，PC-B 当前离线
- 一旦两端可同时起 Civ6，按 §3 顺序执行，约 30–40 分钟可完成数据采集
