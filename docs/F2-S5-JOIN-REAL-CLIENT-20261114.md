# F2 S5：真实客户端"加入"行为观察（模拟房主条件）

- **实验日期**：2026-11-14 12:57–13:05（北京时间）
- **授权依据**：codex F2 裁定（F2-DATAPATH-REVIEW-20261114.md）D3（有条件批准一次 S5 手动点击加入）+ D4（整个运行最多 1 个 20B 固定响应）
- **证据目录**：`M0A\captures\F2-S5-join-20261114\`

## 1. 前置条件（D3/D4 检查清单）

| 前置 | 状态 |
| --- | --- |
| S1-S4 机械自检通过 | ✅ F2-MECHANICAL-SELFTEST: PASS（证据 `F2-mechanical-selftest-20261114-124842`） |
| Civ6 已退出后重链 Hook | ✅ 游戏 PID 44828 为全新进程，注入成功 |
| Agent 不 bind :62056 | ✅ agent 只绑 127.0.0.1:62900 + 127.0.0.1:34718 |
| 无远端目标 | ✅ 模拟房主 = 本机 agent（sim-src-ip 127.0.0.1） |
| 只点击一次加入 | ✅ 用户 m15436 只点了一次 |

## 2. 运行配置

- 游戏：`CivilizationVI_DX12.exe`（PID 44828，E:\SteamLibrary\...\Win64Steam）
- Hook：`civlink_hook.dll` v0.2.0-f2（SHA256 见 §6），注入成功，`hook state : 1 (running)`，session 0xaf8a2794b6d7
- Agent：`civlink-agent.exe` 0.3.0（PID 41128），参数：`--listen-seconds 420 --simulate <fixture> --sim-max-replies 20 --sim-src-ip 127.0.0.1 --simulate-datapath --bind-ip 127.0.0.1 --quiet`
- 模拟房主：22 页公告（CivLink-Test-Room-2222），只回本机、只答发现请求

## 3. 观察结果

### 3.1 发现阶段（用户点刷新）
- 游戏发 100 包广播（255.255.255.255:62900-62999，每端口 1 个，payload=8DE8FC70，flags=0x06 LIMITED_BCAST|DISCOVERY）
- 模拟房主回 22 页公告，用户看到房间列表项（m15436 口述）
- counters：`sent: 100`、`raw sendto: 100`、`cvlh2 try/ok: 108`

### 3.2 加入阶段（用户点一次"加入"）
- **游戏 bind 62056**（`bind 62056: 1`）——客户端加入时确实在 62056 上监听（F6 通配绑定的本机观测支持）
- **游戏对 62056 socket 疯狂调用 WSARecvFrom**：点击加入后 ~70s 内 `recv on 62056` 达 **110,496,364 次**（≈1.6M 次/秒忙轮询）
- **`wsarecv pending: 0`**：这些调用返回的是 WSAEWOULDBLOCK 而非 WSA_IO_PENDING（非重叠调用）
- **★62056 出向帧（10 个，收尾后 frame-log 112 行证实）**：seq 101–110 全部为 `dst=127.0.0.1:62056 len=8 flags=0x21 src=0.0.0.0:62056 head=17320000FFFFXXXX`（0x21=OBSERVED(0x20)|VIA_WSASENDTO(0x01)，payload 8B：前 6 字节 `17 32 00 00 FF FF` 固定、后 2 字节逐次变化 4FAC/51A1/558A/5D5A/6CFA/8C3A/CABA/47BA/41BA/35BA）
- **★指数退避重试**：首帧 04:58:11.107（点加入后 ~2.3s），此后 +0.5s/+1.0s/+2.0s/+4.0s/+8.0s/+16.0s/+32.0s/+64.0s/+128.0s（0.5×2^n），第 10 帧在 128s 后仍在重试（05:02:26.609）
- counters（13:00:19 采集，此时 seq 1–108 已发）：`raw wsasendto: 8`、`observed frames: 8`、`scatter/gather: 8`；收尾后共 10 帧——**seq 109 于 13:00:18 发出（采集点前 1s，采集计数可能未含），seq 110 于 13:02:26 发出（晚于采集点）**；收尾后 frame-log 112 行（110 帧）为最终数据

### 3.3 用户观察
- 用户 m15436：「点击刷新之后看到了模拟房间，但点击加入后一直停在"正在检索创建人信息"这个页面」
- **判定**：模拟房主 Agent 按 D4 限定不回应（Hook EnsureLocalEndpoint 对 bind 0.0.0.0 的 socket 报 src=0.0.0.0:62056 → Agent `not_local=10` 拒绝，即使游戏确实发来 62056 请求）→ 游戏收不到创建人信息，按指数退避持续重试。**非崩溃/卡死**。

## 4. 结论（限定表述）

在本构建、本机、模拟房主条件下：

- 观察到 Civ6 客户端点击"加入"后 bind 0.0.0.0:62056（F6 通配绑定本机观测支持），**并通过 WSASendTo 向房主地址:62056 发出 8B 数据面出向帧**（payload 前 6 字节 `17 32 00 00 FF FF` 固定、后 2 字节变化）；
- 无响应时游戏以**指数退避重试**（0.5→128s，观测到 10 帧），期间对 62056 socket 以 ~1.6M 次/秒忙轮询 WSARecvFrom（WSAEWOULDBLOCK，非重叠）；
- 模拟房主不回应"创建人信息"握手（D4 限定 + not_local 拒绝），客户端停在"正在检索创建人信息"页；
- **本实验不证明**：双机发现/加入/对局、62056 数据面出向完整格式与握手语义、H2/R1 绑定投递、Relay RTT、真实房主协议兼容。

## 5. 诚实记录

- 本次只点击加入一次（D3 限制），未重试、未修改游戏、未修改网络配置；
- agent 于 12:57:32 启动、`-listen-seconds 420` 自然收尾（13:04:32 生成 summary.txt，run time 05:04:32.835）；
- `raw wsarecvfrom` 计数为 u64，数值 110,496,364 是 70 秒内忙轮询的真实计数；
- 早前"无 62056 出向帧"的初步判断（基于 agent 仍在跑时 66 行 frame-log，BufWriter 每 64 帧才 flush）已被收尾后 112 行版推翻——seq 101–110 在缓冲区中，须以收尾后数据为准。

## 6. 文件身份（收尾后）

| 文件 | SHA256 |
| --- | --- |
| summary.txt | 5B513D41AA2173FFF26D0881FF52A86B18FEE6E30CCE39622AFF3B0D88DB76EC（2427B） |
| frame-log.txt | E45F4DE9FA830A6462C975D7F963E84746BB9A0F9FBCBE0B17E510F7D21DC21F（15770B，112 行） |
| datapath-log.txt | 21285944CB0787538ABE758BF0350E3F4630CA99834610E758447FD2339FCE5B（1073B，含 10 帧 datapath 记录） |
| sim-fixture-manifest.txt | E1B4206C849521128442D59E51D7BBE26E7BCFD0BF3166DA8A4027EDDB6886AB（259B） |
| sim-page-01..22.bin | 22×1104B，哈希见证据目录（与 fixture 一致，匿名化房间名） |
| counters（本实验） | （见 §3 数值） |
| hook_selftest（S4） | FE88D38E… |

## 7. 状态

- **S5 完成（D3 限定）**：一次点击加入观察完成，无异常崩溃，结论为 D3 预期。
- **Gate A 未批准、正式 M0-B/Gate B 冻结**；本报告不构成联机验证。
