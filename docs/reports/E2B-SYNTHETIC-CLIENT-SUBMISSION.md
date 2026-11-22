# E2-B-SYNTHETIC-CLIENT 提交：单机假房主有界合成响应实验

- **提交编号**：E2B-SYNTHETIC-CLIENT
- **提交日期**：2026-11-13
- **提交方**：执行端（PC-A）
- **上游依据**：`REV-013-REVIEW.md` §4（批准一次有界合成响应实验，含七条执行条件与受限表述要求）
- **本件性质**：**实验记录 + 裁定请求**。不是验收申请，不主张任何 Gate 条目通过。
- **门禁状态**：Gate A 未批准、M0-B 冻结。
- **表述边界（自我约束）**：本件不得被引用为 E2-B 完成、不得被引用为 M0-B 最小可行原型、不得被引用为文明6联机验证。

---

## §0 一句话摘要

按 REV-013-REVIEW §4 的七条条件，在本机用合成响应器应答本机 Civ6 客户端的一次局域网刷新，客户端**接受该公告并在列表显示匿名化房间项**（`CivLink-Test-Room-2222 | 资料片：风云变幻 | 盘古大陆 | 联机 | 1/6`）；过程中发现并修复了一个**接收端工具缺陷**（脚本级 `[ref]` 出参复用导致突发中第 2 个数据报起抛 `MethodInvocationException` 并被静默吞掉，表现为"100 包只收到 1 包"），该缺陷曾被误判为"客户端行为差异"。本件请求就三项事实与一项定性作出裁定。

---

## §1 授权条件逐条对照（REV-013-REVIEW §4）

| # | 条件（原文语义） | 本轮实际执行 | 证据 |
|---|---|---|---|
| 1 | 最多响应 3 次匹配本机请求 | `-MaxResponses 3`；实际 `responses sent: 1 (budget 3)` | `summary.txt` |
| 2 | 每次 22 页、每页一次 | 22 页，各 1104 B，各页 SHA256 互不相同；`pages per resp: 22 (each once)` | `requests.log` / `sent-reply-01..22.bin` |
| 3 | 只回本机源、不向远端发 | 只回应 `192.168.31.59:64387`（本机 WLAN）；**Responder 未向任何远端主机发送合成响应**。Civ6 客户端自身按正常发现流程发出的广播属于授权实验的一部分，可能到达 WLAN | `requests.log` / `post-response-traffic.log` |
| 4 | 不回应后续握手 | 预算耗尽后仅被动记录后续数据报，未再发送任何包 | `post-response-traffic.log`（98 行，全部 `coalesced, no extra reply`） |
| 5 | 不改网卡/防火墙/不注入产品 DLL | 全程无 `Set-NetIPInterface`、无防火墙变更、无 `civtrace`/`civinject` 调用；客户端为原生进程 | 本件 §2.3 |
| 6 | 匿名化房间名并记录 fixture 哈希与变更偏移 | 每页 offset 24..45 替换为 `CivLink-Test-Room-2222`（22 B ASCII）；记录 original/sent SHA256 与 `changedOffsets` | `fixture-hashes.txt` |
| 7 | 结果表述受限 | §5 使用限定措辞；`summary.txt` 内置 C7 restricted phrasing 提示 | `summary.txt` |

**结论**：七条条件均有对应落实与证据；无越界动作。

---

## §2 实验装置与文件身份

### §2.1 软件（源码 + SHA256，均在本机磁盘）

| 文件 | SHA256 | 字节 |
|---|---|---|
| `CivLink-M0A-audit\scripts\synthetic-host-responder.ps1` | `C4AD239708C94083664AD11B8E658A1B28C355FF0E39DDA1FFE71D9B558A3582` | 19,469 |
| `CivLink-M0A-audit\scripts\gui-sendinput.ps1` | `31AD0355BB7536B669B7CD5F2A78C9808C6D39FDDBB5F28BFA7DAAB807DD4906` | 4,007 |
| `CivLink-M0A-audit\scripts\analyze-room-advert.ps1`（解析器 v2） | `D94A79F7A0D109C50BB5A6792DE4B5271F6FE6B673D6340611EDB1D37E926DEE` | 9,590 |
| `CivLink-M0A-audit\scripts\probe-burst-count.ps1`（100/100 收包参照实现） | `90643CE46E7E7E9F96BEFF9E21A7B26D0522BD088A43403E61E9ED8FF5707B9D` | 5,019 |
| `CivLink-M0A-audit\scripts\RUN-synthetic-selftest.cmd` | `4DF5446B01DD3C111415FE3C040794A442656BEB96A989E5AE4626CB9C2BDFE6` | 3,071 |
| `CivLink-M0A-audit\scripts\RUN-synthetic-host.cmd` | `BD9AD8DF72016BF50921903BC169F043DE006FB55D1AA26D729167EB4CB59BA4` | 3,021 |

> `synthetic-host-responder.ps1` 的 SHA256 为**修复后**版本（见 §6）。修复前版本为 `4D1C5B6E71B0297211A6152C60D5704D93882F31F87626B58E7282A295EABB31`（18,475 B）。

### §2.2 fixture（原始公告来源）

- 来源：`M0A\captures\E2A-H4-reply-20261113\reply-set\reply-01.bin` … `reply-22.bin`，各 1,104 B，采集于 2026-11-13 单机自收（见 `E2A-H4-REPLY-EVIDENCE-20261113.md`）。
- 22 页 sha256 序列与原采样一致（首包 `DDC8CD34D85EB43B218F6A4DB8B6867ECFB9C703623B69C3AAF7A93D8D6D99E8`，末包 `6F98152D…`）。
- 解析结果（`analyze-room-advert.ps1` v2）：22 页 / `recordCnt=13` / `pageCount=22` / 内容区 938 B / framing exact / 尾部 646 B 全零 / JSON blobs valid=4 invalid=0。

### §2.3 客户端与被测环境

- 进程：`CivilizationVI_DX12`，PID 64468，启动 2026-11-13 09:48:40。
- 窗口：`hwnd=11012632`，`class=WinClass_FXS`；Run B 时 `GetWindowRect = (-1707,0)-(0,1067)`（未最大化，位于副屏 DISPLAY1 右半部）。
- 本机网络：WLAN `if10` = `192.168.31.59`；`255.255.255.255/32` 等价路由下当前最小 InterfaceMetric 为 WLAN（metric=45），因此广播实际从 WLAN 发出（metric 修复结果，见 REV-012 提交件）。
- 未注入任何 DLL、未挂钩、未改包：客户端全程为原生 Steam 构建（版本条显示 `1.0.12.72 (1327737)`）。

---

## §3 全部运行历史（含失败与误判，如实记录）

| 轮次 | 时间 | 装置 | 结果 | 性质 |
|---|---|---|---|---|
| R1（void） | 09:35:20–09:45:20 | responder 只绑 62900；窗口 600 s | `responses sent: 0`。客户端 09:48:40 才启动，**晚于监听窗口 3 分 20 秒** | **空跑**，条件未成立，不是"客户端拒绝公告" |
| R2 | 09:52:21–10:22:23 | responder 只绑 62900；窗口 1800 s | `requests.log` 与 `summary.txt` 均未生成（0 请求） | 装置缺陷：客户端把唯一命中包发到区间内非 62900 端口 |
| R3 | 10:49:52–11:14:53 | responder 全区间（99 bound）v2 | `responses sent: 1`、`requests logged: 24`、`request ports: 62900`（**只有 1 个**）、`post-response datagrams: 0`。客户端**已显示列表项** | 收包缺陷未定位时的运行：回复成功但请求捕获率 1/100 |
| — | 11:16–11:46 | 被动探针/最小复现器矩阵 | 广播 100 包实测（`probe-burst-count.ps1` 100/100）；`probe-select-limit.ps1` 稳定 1/100；根因定位（§6） | 缺陷取证 |
| **R4（本件主证据）** | 11:52:58–11:58:00 | responder 修复版全区间（99 bound，跳过 62984）；`-ListenSeconds 300 -PostResponseSec 60 -MaxResponses 3`；自然 finalize | `responses sent: 1 (budget 3)`、`requests logged: 24`、**`request ports:` 列全 99 个**、`post-response datagrams: 98`；客户端显示列表项 | **成功** |

> R3 还有一次同类成功运行（证据目录 `M0A\captures\E2B-synthetic-20261113-114848`），但该轮 responder 被手工 `Stop-Process` 提前终止，**未生成 `summary.txt` 与 `post-response-traffic.log`**。本件主证据因此采用 **R4**（自然 finalize、文件齐全）。R3 目录保留作为独立复现（客户端截图 sha256 见 §9）。

---

## §4 R4 详细时间线（毫秒级）

| 时刻 | 事件 | 证据文件 |
|---|---|---|
| 11:52:58 | responder 启动，PID 65984 | — |
| 11:53:00.040 | 预检：区间内 3 个端点 → `62970/62969 ::1 (pid 8340 svchost)`、`62984 0.0.0.0 (pid 6296 vivoesService_x64)`；**IPv4 需跳过：62984**；实际 bound = 99 | `precheck.txt` |
| 11:53:00–11:53:04 | 99 个 socket 依次 bind：`62900..62983, 62985..62999` | — |
| 11:53:04.44 | 点击 LAN 大厅"刷新"（SendInput，屏幕 `(-1997,212)`，`foreground=11012632 match=True`） | — |
| 11:53:04.440 | 收到首个匹配请求：`dstPort=62900 len=4 src=192.168.31.59:64387 iface=0 payload=8D-E8-FC-70 magic=True localSrc=True` → `RESPONSE #1 (from dstPort 62900)` | `requests.log` |
| 11:53:04.456–.494 | 22 页依次从 **62900** 单播回 `192.168.31.59:64387`，每页 1,104 B，逐页记录 SHA256 | `requests.log` / `sent-reply-*.bin` |
| 11:53:04.519–.674 | 其余 **98** 个匹配请求陆续到达（62901..62983、62985..62999），全部落在 3,000 ms 突发窗内 → `coalesced, no extra reply` | `post-response-traffic.log` |
| 11:53:04.5+ | 客户端列表出现匿名房间项 | `client-list-item-observed.png` |
| 11:58:00 | 窗口自然结束，finalize 写 `summary.txt` | `summary.txt` |

**R4 自身的突发跨度**：首个匹配请求 `11:53:04.440` → 末个匹配请求 `11:53:04.674`，即 **约 234 ms**（因 62984 被跳过，这是 99 个端口的到达跨度）。另有独立被动探针两轮完整 100/100 测量：`probe-burstcount-20261113-113234.log` 首末 `11:32:51.909`→`.997`（**约 88 ms**）、`probe-burstcount-20261113-113622.log` 首末 `11:36:24.756`→`.864`（**约 108 ms**）。三组数字量级一致，但**不是同一个测量**；正文中凡引用单一时长，均标明其来源轮次（见 §11 勘误 E-1）。

**请求口径**：一次刷新 = 向 `255.255.255.255` 的 `62900..62999` **每端口 1 包**，共 100 包（独立被动探针 `probe-burst-count.ps1` 在同条件下捕获 100/100、`per-source: 192.168.31.59:xxxxx:100`，WLAN `SentBroadcastPackets` 差值 = +100）。responder 因 62984 被其他进程占用只绑 99 端口，故最多可捕获 99 包；本轮实测 1（首包触发响应）+ 98（突发窗合并记录）= **99/99 捕获**。

---

## §5 客户端观测结果（受限表述）

**观察到的事实**：匿名化后的合成公告被本构建客户端接受，局域网列表出现一行：

```
CivLink-Test-Room-2222 | 资料片：风云变幻 | 盘古大陆 | 联机 | 1/6
```

表头为 `游戏名称 / 规则设定 / 地图类型 / 游戏速度 / [图标] / 玩家`；该行 `1/6` 与 fixture 中 `MapName=Pangaea.lua`、`RuleSet=RULESET_EXPANSION_2`、`GameSpeed` 等字段一致，说明客户端确实解析了合成载荷而非回显本地缓存。

**按 REV-013-REVIEW 措辞，本轮结论只能写作**：

> 本构建客户端在本机合成响应条件下接受该公告并显示列表项。

**不得据此推出的结论**（明确否认）：不表示 E2-B（双机）通过；不表示 M0-B 原型可行；不表示文明6联机可玩；不表示该公告格式是普遍协议事实（仍限于"当前构建、当前载荷"的样本性结论）。

**副观察（未裁决，如实记录）**：
1. 在 R3 中，同一 UI 会话内再点 2 次刷新未产生新请求（`requests` 仍为 1），且列表项随后消失。R4 未复测该现象。**"刷新后列表项消失"的原因未裁决**，不得写成"客户端拒绝"。
2. 一次刷新只发一轮 100 包；同一 UI 会话内重复刷新是否再次发送，R3 观察到"否"，R4 未做系统性重复测试 → **未裁决**。
3. `iface=0`：.NET `IPPacketInformation.Interface` 在本机自发自收场景返回 0，**不能当作物理网卡号**；本机归属由源地址 `192.168.31.59` 与 WLAN `SentBroadcastPackets` 差值共同支撑。

---

## §6 收包缺陷：根因、证据与修复（本件技术价值所在）

### §6.1 现象

R3 之前的所有轮次中，客户端一次刷新发 100 包，responder 只记录 1 个（且总是 `62900`）。最初被解释为"客户端每次进入大厅只发一轮=1 包"，**该解释错误**。

### §6.2 受控对照

| 变体 | 发送方式 | 结果 |
|---|---|---|
| `probe-variant.ps1`（循环内 `New-Object` 三个出参） | 广播 99 包 | **99/99** |
| `probe-B-hoist.ps1`（出参为脚本级变量，直接 `[ref]`） | 广播 99 包 | **1/99** |
| 同上 | 单播 99 包 | **99/99** |
| `probe-A-refs.ps1`（原脚本改造：循环内重建出参） | 广播 99 包 | **99/99** |
| `probe-burst-count.ps1`（非阻塞 + 内层排空 + 循环内重建） | 广播 100 包 | **100/100** |

发送端真实性用 WLAN `SentBroadcastPackets` 差值校验（每次均为 +99/+100），排除"发送端没发出去"。

### §6.3 决定性诊断（`probe-E-diag.ps1`）

逐次记录每次 `ReceiveMessageFrom` 调用结果后发现：hoist 版从**第 2 个数据报起**每次调用抛

```
MethodInvocationException: 使用"3"个参数调用"ReceiveMessageFrom"时发生异常:
"引用的对象类型不支持尝试的操作。"
```

而原脚本的 `catch { break }` **静默吞掉**该异常 → 每个 socket 只成功处理第一条，其余丢弃。单播场景每次调用命中一个 socket 的各 1 条，所以不触发第二个数据报 → 表现为"单播正常、广播异常"。

### §6.4 修复

`synthetic-host-responder.ps1` 改两处：

1. 删除脚本级 `$remoteEp/$flags/$pinfo`，改为在**每个 socket 的排空循环内**重新 `New-Object` 三个出参；
2. 监听改为 per-socket **排空循环**（`while($true)` + `ReceiveMessageFrom` + `if($entry.Sock.Available -le 0){break}`），而不是"每 socket 只读 1 次"。

修复后：合成突发测试 `request ports` 列全 99 个；R4 真实运行同样列全 99 个（§4）。

> **注（2026-11-13 复核后更正）**：本件初稿在此处写作"对 `SocketException` 与通用异常分别处理、不再静默吞"。**该表述超出当时源码现状**——v2 的通用异常分支仍是裸 `catch { break }`，`SocketException` 也被一概当作队列已空。此项已按 `E2B-SYNTHETIC-CLIENT-REVIEW.md` §3 作为残余缺陷单独整改为 v2.2，见 §11。

### §6.5 教训（对后续工具/助手的直接影响）

- 本次证明的主要故障是 **`[ref]` 输出对象跨调用复用** + **未记录异常**；不是"所有监听器都必须一次回调排空所有 socket"。每个 socket 在一次 readiness 回调内是否排空，取决于事件模型与队列语义——生产接收器要保证**每个数据报最终可被处理**，而不必强求单次回调清空。多端口同突发场景下，per-socket 读取后仍需依赖下一轮 readiness。
- PowerShell 中 `ReceiveMessageFrom` 的 `ref` 出参**不可跨调用复用脚本级变量**。
- 收包异常必须落盘并计数；`catch { break }` 会把"丢包"伪装成"没发包"。

---

## §7 边界与未完成项（明确列出）

1. 本轮**没有抓取 pcapng/pktmon 原始抓包**。包级记录由三部分组成：`requests.log`（1 请求 + 22 页回复，含逐页 SHA256）、`post-response-traffic.log`（98 条并发命中）、以及独立的 `probe-burst-count.ps1` 100/100 捕获日志（`M0A\captures\probe-burstcount-20261113-113622.log`）。若审计端要求 pcapng，需另做一轮（pktmon 需管理员权限与安全桌面 UAC）。
2. R3 与 R4 各有一次成功运行，但 R3 缺 `summary.txt`（被手工终止）。本件只用 R4 作主证据，R3 仅作独立复现。
3. 本实验**不是** E2-B；E2-B 仍需两台可运行 Civ6 的电脑、双端 v0.4.4 注入、角色/PID/tag 标记。
4. 本实验**不是** M0-B 最小可行原型，不构成 Gate A 的任何一条。
5. 客户端"刷新后列表项消失""同一会话重复刷新是否重发"两个观察未裁决。

---

## §8 请求裁定项

| # | 请求 | 说明 |
|---|---|---|
| 1 | 确认"本构建客户端在本机合成响应条件下接受该公告并显示列表项"可作为**限定结论**入档 | 措辞严格采用 REV-013-REVIEW §4 原文；不扩展为协议事实 |
| 2 | 确认 §6 的收包缺陷定位与修复可记为**工具缺陷（T-class）**，并确认此前的"一次刷新只发 1 包"结论**作废** | 该错误结论曾写入早期沟通；正确口径是"一次刷新发 100 包，接收端缺陷导致只看到 1 个" |
| 3 | 确认收到 99/99、回复 1/1、无越界动作，本实验在 REV-013-REVIEW §4 授权范围内**闭合** | 附 §1 对照表与 §9 文件身份表 |
| 4 | 是否要求补做 pcapng 原始抓包（§7-1） | 若要求，需另约一次带 UAC 授权的采集窗口 |

---

## §9 文件身份表

### §9.1 主证据目录 `M0A\captures\E2B-synthetic-20261113-115258\`

| 文件 | SHA256 | 字节 |
|---|---|---|
| `summary.txt` | `2B36F4D2AF095A174BECECAE6D1B5309FE5752D873A6B7399F7A72FE21A5DED6` | 2,019 |
| `requests.log` | `BAFEFC71597FF8A28FE330E1141A6C1E5643F2CEF5CD9E4EC6B818ABBCC122F7` | 3,953 |
| `post-response-traffic.log` | `6EE662D67098BD9B53E69E82CBB2171A1A90F4D7F1406FD03A331C1DC1C8362A` | 18,382 |
| `precheck.txt` | `091AD0B2664464BC57DC62D6AD3FA0B22523933300B410525E661CF064EC892E` | 263 |
| `fixture-hashes.txt` | `4A94E3B3D91CCFE811F06EB618D0EC313C5A2744B9353A4585EBF8A03D076B41` | 5,151 |
| `client-list-item-observed.png` | `EFD9BC49C9CD4D6BDCFEA0A092624C85B0B5312D61DB457D0825682165961CCF` | 4,658,073 |
| `sent-reply-01.bin` | `72F9B3BC88273D5C01A8BA447A5BF585CEEACF58BF22B67D206C634FACF6B2B8` | 1,104 |
| `sent-reply-02.bin` | `3F063EC8CCF7EDD6149E9FC2CD571E88CB43AC3FDD7DA607848F9BC658CEF546` | 1,104 |
| `sent-reply-22.bin` | `05FDECDA66784D9EA2F27C41310596E9EAFAD162CBABC1F1F5EE01E1E61D3B7A` | 1,104 |

（`sent-reply-03..21.bin` 各 1,104 B；逐页 SHA256 见 `requests.log` 与 `fixture-hashes.txt`，两处互相校验。）

### §9.2 独立复现目录 `M0A\captures\E2B-synthetic-20261113-114848\`

| 文件 | SHA256 | 字节 |
|---|---|---|
| `requests.log` | `DA91505FAD873BD49DA04F2CB8E1E7B9FDA7DD8238C89D61AD19E2D6601838C0` | 3,953 |
| `precheck.txt` | `A5D1DC800D6A37587EBB06A60ED985E11DDBA26D63AD74A7CB9CCD744D1A737B` | 263 |
| `client-list-item-observed.png` | `AB56810D7D345AB69BBCD17C85B474A6D1838AAE653BFA993431618DDCE2CE14` | 4,673,966 |

> 该目录**缺** `summary.txt` 与 `post-response-traffic.log`（被手工终止，见 §3 注）。

---

## §10 一句话给审计端

行为已经做出来并复现了两次：**本构建客户端接受本机合成公告并显示列表项**。真正需要审计端拍板的是三件小事——这句限定结论能不能入档、§6 那个"100 包只收到 1 包"的工具缺陷定性、以及要不要再花一轮补 pcapng。

---

## §11 复核后勘误与整改（2026-11-13，按 `E2B-SYNTHETIC-CLIENT-REVIEW.md`）

复核已对四项请求作出裁定（全部接受）。本节记录据此对本件与工具所做的更正与整改；**原始运行文件保持不改**，勘误只作用于本件正文与工具源码。

### §11.1 勘误 E-1：突发时长"约 86 ms"的归属

- 初稿 §4 曾写"100 包在约 86 ms 内完成"并置于 R4 时间线语境下。
- 复核 §1-4 指出该数字不能作为 R4 时长。核实结果：R4 自身首末匹配请求为 `11:53:04.440`→`.674`，跨度 **约 234 ms**；`86 ms` 一类数字来自**独立被动探针**（88 ms / 108 ms 两轮）。
- 更正：§4 已分列三组测量并标明来源轮次；不再把探针时长当作 R4 时长。

### §11.2 勘误 E-2：流量边界措辞

- 初稿 §1 条件 3 与 `summary.txt` 边界注曾写"no packet left this machine except unicast replies"。
- 复核 §1 指出按整机理解不准确：实验期间 **Civ6 客户端本身按其正常发现流程发出了广播**（这是授权实验的一部分，广播可能到达 WLAN）；应表述为 **"Responder 未向远端发送合成响应"**。
- 更正：`summary.txt` 模板已改为 "Responder did NOT send any synthetic response to a remote host. Civ6 itself emitted its normal discovery broadcasts during the experiment..."；本件 §1 条件 3 同步按此理解。原始运行目录中的 `summary.txt` 保持未改，本勘误即为说明。

### §11.3 整改 R-1：接收异常不再静默（脚本 v2.2）

复核 §3 指出 v2 的 `catch { break }` 仍会静默吞掉非预期接收错误，本件初稿"不再静默吞"的表述超出源码现状。已整改：

| 项 | v2（初稿时） | v2.2（整改后） |
|---|---|---|
| would-block / timed-out / connection-reset | 与其它异常一并 `break` | 记为 `expected`，计数 `recvErrorsExpected` |
| 其它 `SocketException` | 静默 `break` | 记为 `unexpected` + 写 `receive-errors.log`（含 code/msg/port/时间） |
| 通用异常 | 静默 `break` | 记为 `unexpected` + 写异常类型与消息 |
| 汇总 | 无 | `summary.txt` 新增 `receive errors : N unexpected, M expected(would-block) - see receive-errors.log` |
| 空错误列表 | 无文件 | 写 **0 字节** `receive-errors.log`（用无 BOM UTF-8），使"没有错误"可证伪而非仅未被观察 |

脚本新增 `-InjectReceiveFault N`（**仅测试用**，实验运行恒为 0）以便故障注入回归。

### §11.4 整改验证（回归测试）

新增 `CivLink-M0A-audit\scripts\test-responder-errorpath.ps1`，两条路径、共 9 项断言：

```
PASS  A.errors-file-exists      receive-errors.log present=True
PASS  A.errors-recorded-2       lines=2 (expected 2)
PASS  A.injected-recorded       receive errors  : 2 unexpected, 22 expected(would-block)
PASS  A.survived-to-finalize    script reached finalize (summary + logs written)
PASS  A.error-line-has-detail   [12:15:11.521] port=62950 kind=InvalidOperationException msg=INJECTED TEST FAULT on port 62950 (remaining 1)
PASS  B.errors-file-exists      receive-errors.log present=True
PASS  B.errors-file-empty       size=0 bytes (expected 0)
PASS  B.zero-unexpected         receive errors  : 0 unexpected, 22 expected(would-block)
PASS  B.receive-path-entered    matched request lines=1

RESULT: 0 failure(s)
```

功能回归（v2.2，合成 99 包广播）：`bound=99`、`request ports` 列全 99、`responses sent: 1`、22 页、`receive errors : 0 unexpected` → 接收路径未被整改破坏。

> 首次跑该测试时 `B.errors-file-empty` 失败（3 字节 BOM-only 文件），已改为无 BOM 写入后 9/9 通过。该失败与修正一并记录，避免"零字节"断言被 BOM 蒙混。

### §11.5 整改后脚本身份

| 文件 | SHA256 | 字节 |
|---|---|---|
| `synthetic-host-responder.ps1` v2.2 | `C74A9ED96A3C2C4E9145445363698950031111E5D181456D495CDA3EF9DC090C` | 22,744 |
| `test-responder-errorpath.ps1` | `56ED65C6630A89C90FBA7D126EDFBD3CC8D8B8E2F7DE58DC4C3EDAE970849B5C` | 6,633 |

两者均为 UTF-8 **BOM**（first3 = 239,187,191）。`synthetic-host-responder.ps1` v2.2 与本件 §4 主证据所用的 v2（`C4AD2397…`，19,469 B）**不是同一文件**：v2.2 增加了 `-InjectReceiveFault` 测试 seam、`receive-errors.log` 记录与 summary 的 `receive errors` 行，接收路径逻辑未变。

### §11.6 v2.2 真实客户端复跑（已执行，2026-11-13 12:25:48–12:32:49）

**执行方式**：与 R4 相同的真实路径，但**点击动作由人工完成**（桌面当时处于 Windows 锁屏、`SendInput` 不可用，故由用户在大厅内手动点"刷新"）；responder 侧全自动。

| 项 | 值 |
|---|---|
| 证据目录 | `M0A\captures\E2B-synthetic-v22-real-20261113-122548\` |
| responder | pid 67924，`-ListenSeconds 420 -PostResponseSec 90 -MaxResponses 3 -BurstWindowMs 3000` |
| 窗口 | 启动 12:25:48，**自然 finalize 12:32:49**（未被手工终止） |
| bind | `99 bound, skipped 62984`（vivoesService_x64 占用；62969/62970 为 svchost 的 IPv6-only，不跳过） |
| 客户端 | Civ6 `CivilizationVI_DX12` pid 64468，11-13 09:48:40 启动 |
| 人工点击 | 用户在 LAN 大厅点"刷新"一次（12:26:07 前后），随后再次刷新（12:26:54）以确认可重复 |

**结果**：

| 观测 | 值 | 证据 |
|---|---|---|
| `requests.log` 行数 | **48**（= 2 组 × 24 行：每组 1 条触发 + 22 条 page + 1 条 replies） | `requests.log` |
| 触发请求 | **2** 条：`12:26:07.915 dstPort=62900 iface=0`、`12:26:54.170 dstPort=62900 **iface=10**` | `requests.log` |
| `request ports` | 列全 **99** 个（62900..62999，跳过 62984） | `summary.txt` |
| 合成响应 | **2 次**（budget 3）：`RESPONSE #1` 12:26:07.981、`RESPONSE #2` 12:26:54.198 | `requests.log` |
| 每响应页数 | 22 页，各 1,104 B，逐页 SHA256 | `requests.log` |
| `post-response datagrams` | **295** | `summary.txt` / `post-response-traffic.log`（55,622 B，295 行） |
| **`receive errors`** | **`0 unexpected, 0 expected(would-block)`** | `summary.txt` |
| `receive-errors.log` | **0 字节**（`E3B0C442…B855`，空文件的 SHA256） | 目录内 |
| 客户端列表 | 用户在界面确认**出现列表项**（"有"）；本轮未能留存截图，原因见下 | — |

> `summary.txt` 中 "OUTCOME-PENDING: client list result must be observed…" 是脚本内固定写入的 C7 受限措辞模板（提示两种允许写法），**不是**本轮的判定结果；本轮判定为"显示列表项"，见 §11.6 正文与 R4 截图。
> 另注：本轮第 2 次触发请求的 `iface=10`（WLAN 接口号），而 R4 为 `iface=0`——该字段来自 .NET `IPPacketInformation`，在单机/回环路径上取值不稳定，**不能**当作网卡归属证据使用（真正的接口归属以 `Get-NetAdapterStatistics` 差量与源地址为准）。

**关于缺失的截图（如实记录）**：12:27:32 抓取的一帧全黑（18,971 B，`0CD7B6E5…`），诊断时前台窗口为 `hwnd=852502 title='Windows 默认锁屏界面'`（LogonUI 在运行），即桌面在抓图前已回到锁屏——该帧**不能**作为"客户端显示列表项"的证据，已从证据目录删除以免被误读。因此本轮的客户端侧证据为**用户界面口述确认（"有"）**，与 R4 的截图（§4、§9.1）互为补充：**R4 提供界面截图，本轮提供 `receive errors = 0 unexpected` 的干净运行**。

**本轮相对 R4 的新增价值**：
1. v2.2 在真实广播路径上 `unexpected = 0`、`receive-errors.log` 为空——证明 §11.3 的错误分流整改**未把真实异常误报为 would-block，也未漏记**；
2. 自然 finalize 产生了 `summary.txt`（R3 曾缺），且 `post-response datagrams: 295` 表明突发窗合并逻辑在多次刷新下仍按设计工作；
3. `-MaxResponses 3` 预算下只用了 2 次，第 3 次未触发——"两次刷新各触发一次响应"这一重复性观察首次被记录。

**仍成立的表述边界**：本轮结论仍只能写作"本构建客户端在本机合成响应条件下接受该公告并显示列表项"；不是 E2-B、不是 M0-B 原型、不是联机验证。

### §11.7 文件身份（本轮，§11.6）

| 文件 | SHA256 | 字节 |
|---|---|---|
| `summary.txt` | `E912AC7055005F71FA27F0D22D69A202684DFF88C7B36A0B4C06D6706562ABA4` | 2,204 |
| `requests.log` | `E93C5401D567EF4649DF07996CB0315D3DA336BA4269FB97200639F4767BEF71` | 7,905 |
| `post-response-traffic.log` | `6A50674A0C2CEC2B7814F9298F209A7291FA02F16C3012214EB867A10F3F9C27` | 55,622 |
| `precheck.txt` | `8D789632939BC45D594B34C93F1F984C67ECEC10771627E38EA51D1B8C57E2A3` | 263 |
| `fixture-hashes.txt` | `4A94E3B3D91CCFE811F06EB618D0EC313C5A2744B9353A4585EBF8A03D076B41` | 5,151 |
| `receive-errors.log` | `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855` | 0 |
| `sent-reply-01.bin` | `72F9B3BC88273D5C01A8BA447A5BF585CEEACF58BF22B67D206C634FACF6B2B8` | 1,104 |
| `sent-reply-22.bin` | `05FDECDA66784D9EA2F27C41310596E9EAFAD162CBABC1F1F5EE01E1E61D3B7A` | 1,104 |

`fixture-hashes.txt` 与 §9.1 / §9.2 完全一致（`4A94E3B3…`），说明三次运行用的是同一匿名 fixture；`sent-reply-01/22.bin` 亦与 R4 相同。"本件主证据仍为 §4 的 R4 运行"这一说明**依然成立**：R4 有界面截图，本轮有干净的错误计数与自然 finalize。
