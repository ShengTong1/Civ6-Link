# F2 数据面原型 S1–S5 完成提交（2026-11-14）

> 状态：**裁定完成**。本文档汇总 F2 设计 v0.2（`F2-DATAPATH-SIMULATED-PEER-20261114.md`）规定的 S1–S5 全部完成证据与限定结论。裁定审计（子代理 a6a23515）结果：**①F2 数据面原型（非发布）验收——通过；②F3 设计输入采纳——通过；③F3 授权——有条件批准**（限定范围见 `F3-DIRECT-RELAY-DESIGN-20261114.md` v0.3 §6/D/E）。

## 1. 执行依据（codex 复核约束原文要点）

- D2 有条件批准 S1–S4：Agent 不得 bind `:62056`、不得设 SO_REUSEADDR、不得推断 H2/R1；`WSARecvFrom` 返回 WSA_IO_PENDING 时不得读 WSABUF/来源/完成字节数；分层计数只对明确相同报文集合对账。
- D3 有条件批准一次 S5（点击加入观察）：S1–S4 机械自检通过、游戏退出后重链、Agent 不 bind 62056、无远端目标；异常即停保留证据。
- D4：每次运行**最多 1 个 20B 固定响应**，仅源 IP 确认本机且源端口非零时发；0.0.0.0:0/非本机只记录不回。
- D5：`127.0.127.1..100` 仅纯内存测试，不配置网卡、不真实 bind、不发送。

## 2. 步骤与证据（全部机械自检/真机观察，非网络实验）

| 步骤 | 内容 | 证据目录 | 结果 |
|---|---|---|---|
| S1 | Agent `--simulate-datapath`（0.3.0，--bind-ip fail-closed + D4 一次性 20B 探测） | `M0A\captures\F2-datapath-selftest-20261114-115013` | PASS（reply sent 1 / bytes 20，仅回环） |
| S2 | Hook DLL 扩展（bind/recvfrom/WSARecvFrom 纯观测 + OBSERVED 帧 + 14 项分层计数） | `M0A\captures\F1-selftest-20261114-121044` | PASS（29 条断言 + 终行 PASS（共 30 行）+ `HOOK-SELFTEST: PASS (0 failure(s))` + agent reconciliation 5==5） |
| S3 | civlink-fakeip crate（双向映射，键含 session/generation，127.0.127.1..100 内存池） | `M0A\captures\F2-fakeip-selftest-20261114-123500` | PASS（17 单测 + 7 变异全捕获，restore 17/17） |
| S4 | 机械自检（含构造 WSA_IO_PENDING 路径、D4 正向/负向） | `M0A\captures\F2-mechanical-selftest-20261114-124842` | PASS（50 条断言 + 终行 PASS（共 51 行）+ `HOOK-SELFTEST: PASS (0 failure(s))` + agent reconciliation 7==7 + D4 reply sent 1） |
| S5 | 真机点击加入观察（游戏 pid 44828，模拟房主 agent pid 41128） | `M0A\captures\F2-S5-join-20261114` | 完成（见 §3） |

## 3. S5 实测发现（本机模拟条件）

- 点击加入后游戏 **bind 0.0.0.0:62056 通配**（F6 规范假设获真实证据支持；counters `bind 62056 : 1`）。
- 数据面出向走 **WSASendTo**（frame-log flags=0x21 = OBSERVED|VIA_WSASENDTO；counters `raw wsasendto : 10`、`scatter/gather : 10`）。
- 出向载荷 **8B**：前 6 字节 `17 32 00 00 FF FF` 固定、后 2 字节逐次变化（4FAC→35BA，含回绕）；目标 `房主IP:62056`。
- **无响应时指数退避重试**：seq 101→110 间隔 +0.5/1.0/2.0/4.0/8.0/16.0/32.0/64.0/128.0 s（10 帧，最后一次仍在重试）。
- 等待期间游戏对 62056 socket **忙轮询 `WSARecvFrom` ~1.6M 次/秒**（70s 内 110,496,364 次；`WSAEWOULDBLOCK` 非 `WSA_IO_PENDING`，非重叠调用）。
- 模拟房主按 D4 不回应（Hook 对 bind 0.0.0.0 socket 报 `src=0.0.0.0:62056` → Agent `not_local=10` 拒绝）→ 游戏停留在"正在检索创建人信息"页，持续重试。
- **D4 语义正确执行**：本机 loopback 模拟下源 IP=0.0.0.0 无法确认本机 → 不回应。真实双机时房主 Agent 看到对端真实源 IP，**不适用此限定路径**（此边界如实记录，不作推断）。

## 4. 限定结论（诚实边界）

- 证明：本机 Civ6 客户端在"模拟房主 → 真实客户端"条件下，加入流程发出 62056 数据面出向（WSASendTo、8B、指数退避重试、62056 通配绑定、忙轮询收包）——**均为本机构建 + 本机模拟条件下的观察**。
- **不证明**（显式对齐 D1 清单六项）：两台真实 Civ6 双机发现/加入/对局（E2-A/E2-B/E3）、62056 归属（E3）、**H1（198.18.0.0/15 过滤）、H2（通配与特定 bind 共存投递）、H8（62056 socket 选项矩阵）、R1（Design I 绑定共存阻断项）、Design I/II/III 投递机制选择**、Relay RTT、跨网长稳；不移动 Gate A/B；正式 M0-B/Gate B 仍冻结。

## 5. 文件身份表（SHA-256）

| 文件 | 哈希 | 字节 |
|---|---|---|
| README.md（v1.17，1140 行） | `2B8F87DCFF709DFB8EB54D9BC19077CE335D003F6504F757D81D2494D07AC0CC` | 93,397 |
| docs/CODEX-HANDOVER-M0A.md（129 行，第13项已扩展） | `D225290E5386F69A5BCEC28D1179FA6F55C16C0358210EAACAEE145A51AF0F87` | 28,173 |
| docs/F2-S5-JOIN-REAL-CLIENT-20261114.md（74 行，审计修正后） | `DD95445E65938D833E85434FF7FECA997F8396FE00D295B8FEE801BB93CF873C` | 5,856 |
| docs/F2-DATAPATH-SIMULATED-PEER-20261114.md（v0.2，审计后修订） | `AAEE4AF313911894B79AD437AC367C56B4474E8C26551D16E9165DD2922B1E6C` | 15,067 |
| docs/F2-DATAPATH-REVIEW-20261114.md（裁定） | `4EBBC452213DAAC4E3DDE01B6A264462AC6267E7F3DD52166DEDE526E8D10D17` | — |
| civlink/fakeip/src/lib.rs | `89C7041BEC3BAE38F640AB8ED54CC09F74FBDBE8BAF9ED5847E7A7879A4DCACE` | 27,455 |
| civlink_hook.dll（S4 终版） | `9424FC25FB45841FC6A31A0C9CD747067005D3FA32A06A18CD150B0C9CEBC10F` | 119,808 |
| civlink_ctl.exe（S4 终版） | `23923DFBAAB310F2BDAA1E1117110B92A74290E2C87396E5CB65EE0E4FEFEA30` | 173,056 |
| hook_selftest.exe（S4 终版） | `FE88D38E9D25293E0C2567907FE66E471CB8E0B5E924236608158D5630C2F477` | 148,992 |
| S5 summary.txt | `5B513D41AA2173FFF26D0881FF52A86B18FEE6E30CCE39622AFF3B0D88DB76EC` | 2,427 |
| S5 frame-log.txt（112 行） | `E45F4DE9FA830A6462C975D7F963E84746BB9A0F9FBCBE0B17E510F7D21DC21F` | 15,770 |
| S5 datapath-log.txt | `21285944CB0787538ABE758BF0350E3F4630CA99834610E758447FD2339FCE5B` | 1,073 |
| S5 sim-fixture-manifest.txt | `E1B4206C849521128442D59E51D7BBE26E7BCFD0BF3166DA8A4027EDDB6886AB` | 259 |
| S5 counters-post-run-20261114-1345.txt（审计补录） | `E74B104ADE506FFBCFB83C670B34B209923F901C3FD2C2B9D0BCDBBAA8B4C7C1` | 1,489 |

## 6. 裁定结果（子代理 a6a23515，2026-11-14）

1. **F2 数据面原型（非发布）验收：通过**——S1–S5 按 D2/D3/D4/D5 限定完成，证据链完整（S5 目录 6 文件哈希与 §5 身份表逐项一致），无未决阻断；子代理审计 9 项修正已全部落地（§7）。
2. **F3 设计输入采纳：通过**——8B 小载荷 + 指数退避（0.5→128s）+ 62056 忙轮询均有 frame-log/counters 直接支撑；0.5s 首窗为**响应时延预算（非协议承诺；S5 单次观察值）**。
3. **F3 授权：有条件批准**——限定范围（纯转发原型、测试 socket 注入、本机回环拓扑）内可开展 Relay/直连原型；前置条件与修正项（C1-C5、E1-E7）已全部落实于 `F3-DIRECT-RELAY-DESIGN-20261114.md` v0.3 定稿。

## 7. 审计修正记录（子代理 6b1dd7b0 复核后）

- ①lib.rs 已去 UTF-8 BOM，恢复无 BOM 哈希 `89C7041B…`（设计 §7 无 BOM/LF 要求）；②SIMULATED-PEER §8 自引用哈希改为"审计时点快照 + 权威值以本文件 §5 实测为准"；③S5 证据目录补录 `counters-post-run-20261114-1345.txt`（POST-RUN 快照，S5 时刻值见 S5 报告 §3）；④提交件 §2 S2/S4 行改为证据可核对表述（29 断言+终行 PASS=30 行 / 50 断言+终行 PASS=51 行 + reconciliation 5==5/7==7）；⑤S5 报告 §3.2 采集点措辞更正（seq 109 早于采集点 1s、seq 110 晚于采集点）。
- ⑥**S1 原始输出说明**：S1 轮 `agent-console.txt` 为 0 字节——agent 以 `--quiet` 运行（stdout 静默），命令/退出码未单独留存；summary/datapath-log/frame-log 完整，不影响结论。
- ⑦**S4 夹具说明**：S4 中 `hook_selftest.exe` 夹具进程内 bind `127.0.0.1:62056` 仅为验证 `bind62056Count` 计数，**该夹具非 Agent**——无游戏运行、未投递、未推断 H2，字面与精神均合规。
- ⑧**证据目录命名**：S2 证据目录沿用 F1 前缀 `F1-selftest-20261114-121044`（内容为 F2 S2 Hook 扩展后的机械自检），命名未随阶段更新，谨此澄清。
- ⑨提交件 §4 已显式补列 D1 六项不证明清单。

## 8. 状态

Gate A 未批准；正式 M0-B/Gate B 仍冻结；metric apply/restore 未授权；PC-B 原件回传已被负责人跳过（m10741）。
