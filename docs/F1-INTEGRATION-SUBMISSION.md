# F1 集成链路复核提交件（模拟房主 → 真实 Civ6 客户端显示）

- 提交日期：2026-11-14
- 提交方：执行端（DSH）
- 状态：**请求复核**。F1 两个子项（观测、集成）均已有机器证据 + 操作者口述；本件只申报证据与结论边界，不主张任何 Gate 状态变化。
- 关联文书：REV-016（`REV-016-SIMULATED-PEER-FAST-TRACK.md`，sha256 `D69D4DD2…`）§3 F1；codex 复核 `F1-LIVE-REAL-CLIENT-20261114.md`（m14211：「观测子项通过 · 集成链路未通过」）；`PROJECT-SCOPE-WIN-STEAM-2P.md` §3/§4。
- **Gate A 未批准、M0-B 冻结不变；本文不请求任何 Gate 变化。**
- 结论表述（限定，照抄使用）：
  > **本构建下，模拟房主（房间名 `CivLink-Test-Room-2222`）的 22 页公告经 DLL→Agent 本机链路
  > （CVLH2 over 127.0.0.1:34718）被单台真实 Civ6 客户端收到并显示在房间列表；
  > 第一轮 3/3 回复（66 页）、第四轮 7/7 回复（154 页），两轮机器断言 9/9 PASS，
  > 操作者两轮口述均确认房间可见。**

---

## 0. 本次请求复核的内容

按 REV-016 §3 F1 的定义，F1 = **DLL + Agent 发现链路**，其中"集成链路"要求：
**模拟房主接入 DLL/Agent 链路，由真实 Civ6 客户端显示模拟房间**（此前 m14211 复核判为
"未通过"的唯一原因）。

本件申报：该集成链路子项已执行并有两轮 PASS 证据 + 操作者口述。请复核：
1. 证据链是否闭合（Hook 计数 == Agent 计数 == 页数对账）；
2. 结论边界是否被遵守（不得写成联机/E2-B/Gate A）；
3. void 轮次归因是否成立（操作者时序，非产品故障）；
4. F1 是否可记"两个子项均通过"（由复核方裁决，执行端不自行宣布）。

## 1. 执行环境

| 项 | 值 |
|---|---|
| 游戏 | `CivilizationVI_DX12.exe`，pid 44832（2026-11-14 10:37:34 启动，重启后的新进程，无旧 hook）|
| 游戏路径 | `E:\SteamLibrary\steamapps\common\Sid Meier's Civilization VI\Base\Binaries\Win64Steam\CivilizationVI_DX12.exe` |
| Hook | `civlink_hook.dll`（dll base `0x7ff9a3510000`，第一轮注入后四轮复用同一映射）|
| Agent | `civlink-agent.exe` 0.2.0，`--simulate`（模拟房主模式）|
| 模拟房主 | 房间名 `CivLink-Test-Room-2222`（fixture 页 offset 24..46 匿名化替换），回复源 `26.74.126.98:62900`（自动探测的出口接口 IP）|
| fixture | `M0A\captures\E2A-H4-reply-20261113\reply-set`（reply-01..22.bin，22 页 × 1104 B）|
| 驱动 | `run-f1-integration.ps1`（见 §6 文件身份）|
| 运行位置 | 中立目录 `C:\Users\dd\Desktop\civlink-f1\`（项目树 Low IL 陷阱，README §3B.5）|
| 注入方式 | `civlink_ctl inject -x CivilizationVI_DX12.exe`（LoadLibraryW 远程线程）；hook 保持映射至进程退出（B2 审计运行模式）|

## 2. 第一轮：PASS 9/9 —— `M0A\captures\F1-integration-20261114-104235`

- 窗口 150 s；操作者点击 **3 次刷新**（hook `sent` 在 t=72/76/80 s 处 0→100→200→300）。
- **Hook 侧（counters）**：`sent=300`、`fail=0`、`oversize=0`、`ignored=0` 全程。
- **Agent 侧（0.2.0，listen 153.3 s）**：
  - `datagrams=300`，`received frames : 300 (processed 300, rejected 0)`，`reconciliation ==`，`large 0`、`notify 0`；
  - 会话 1 个：`frames=300`、`first_seq=1`、`last_seq=300`、`seq gaps=0`、`duplicates=0`、`out_of_order=0`、
    `discovery_magic=300`、`via_wsasendto=0`、`limited_bcast=300`、`discovery_flag=300`；
  - `logical sockets=3`（每次刷新一个 socket：`0.0.0.0:50433×99`、`0.0.0.0:63852×99`、`0.0.0.0:65485×99`，
    外加每 socket 首帧 `0.0.0.0:0×3`）；`dst ports=100`（62900–62999 全覆盖）。
- **模拟房主侧（sim）**：`requests seen=300`、`replied sockets=3`、`pages sent=66（==3×22）`、
  `send fail=0`、`no endpoint=3`（每 socket 首帧未绑定）、`max reached=0`、`bind fail=0`；
  回复源 `26.74.126.98:62900`。
- **机器断言 9/9 PASS**：`sentDelta 300 == processed 300`、`rejected 0`、`seen 300`、`replied 3`、
  `pages 66`、`sendFail 0`、`bindFail 0`、`max 0`。
- 操作者口述（m14428）：「我已经点击了三次，可以看到房间」。

## 3. 第二轮 / 第三轮：void（0 点击）—— 如实记录

| 轮次 | 证据目录 | 窗口 | 原因 | sent 全程 |
|---|---|---|---|---|
| 2 | `F1-integration-20261114-104534` | 90 s（10:45:36→10:47:06）| 点击指令 10:47:09 发出，晚于窗口 | 300（无增量）|
| 3 | `F1-integration-20261114-104723` | 150 s（10:47:23→10:49:53）| 点击指令 10:49:59 发出，晚于窗口 | 300（无增量）|

两轮 Agent 均 `datagrams=0`（无任何帧到达）；驱动对 3 项计数断言报 FAIL
（`delta=0`/`seen=0`/`replied=0`，其余 6 项因零计数恒真）。

**归因 = 操作者时序（指令送达晚于监听窗口），非产品故障**：
- Hook 计数全程保持基线 300，无任何新 `sendto` 发生 → 操作者确实未在窗口内点击（不是"点了但没捕获"）；
- 第二轮 90 s 窗口对本场景太短；第三轮 150 s 仍被中间轮次占用了送达时间；
- 第四轮改用 300 s 窗口即成功 → 与"窗口覆盖度"因果一致。

**教训（已写入 README §3B.3b）**：驱动窗口必须覆盖"指令发出 + 操作者响应"的完整延迟；
90 s/150 s 对人工操作太短，300 s 才稳定成功。

## 4. 第四轮：PASS 9/9 —— `M0A\captures\F1-integration-20261114-105026`

- 窗口 300 s；操作者实际点击 **7 次刷新**（hook `sent` 300→400→500→600→700→800→900→1000，
  每次 +100；t=174/182/186/190/192/194/216 s）。
- **Hook 侧**：`sent` 终值 1000（增量 700）、`fail=0`、`oversize=0`、`ignored=0` 全程。
- **Agent 侧（0.2.0，listen 305.1 s）**：
  - `datagrams=700`，`received frames : 700 (processed 700, rejected 0)`，`reconciliation ==`，`large 0`、`notify 0`；
  - 会话 1 个：`frames=700`、`first_seq=301`、`last_seq=1000`（承接第一轮会话计数，同进程内 seq 连续）、
    `seq gaps=0`、`duplicates=0`、`out_of_order=0`、`discovery_magic=700`、`via_wsasendto=0`、
    `limited_bcast=700`、`discovery_flag=700`；
  - `logical sockets=7`（如 `0.0.0.0:53588×99`、`0.0.0.0:54699×99`、`0.0.0.0:54700×99`、
    `0.0.0.0:54701×99` 等，每 socket 99 条 + 首帧无端点 7 条）；`dst ports=100` 全覆盖。
- **模拟房主侧**：`requests seen=700`、`replied sockets=7`、`pages sent=154（==7×22）`、
  `send fail=0`、`no endpoint=7`、`max reached=0`、`bind fail=0`。
- **机器断言 9/9 PASS**。
- 操作者口述（m14466）：「第一轮和第四轮，我实际操作的时候都显示」。

## 5. 对账汇总

| 项 | 第一轮 | 第四轮 |
|---|---|---|
| 刷新次数（操作者） | 3 | 7 |
| hook 捕获 sendto 增量 | 300 | 700 |
| agent 收到帧（processed） | 300 | 700 |
| 对账 | 300 == 300 | 700 == 700 |
| rejected / gaps / dup / reorder | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| 逻辑 socket（=刷新次数） | 3 | 7 |
| sim 回复 socket | 3 | 7 |
| 发送页数（=回复×22） | 66 | 154 |
| send fail / bind fail / max reached | 0 / 0 / 0 | 0 / 0 / 0 |
| 目标端口覆盖 | 100/100 | 100/100 |
| 操作者口述房间可见 | ✅ | ✅ |
| 驱动结论 | PASS（9/9）| PASS（9/9）|

## 6. 文件身份

### 6.1 代码与脚本

| 文件 | sha256 | 说明 |
|---|---|---|
| `civlink\agent\src\main.rs` | `7E3C62D7167782DE415748A6A31FE76F0F7DB2303F86F3A24A600B93CCF59553` | Agent 0.2.0 源码（含 --simulate）|
| `civlink-agent.exe` | `3F02E66602582D247CF618ADCF023D4F9F6769A1375113C59F5D08174CD4F27B` | 331,264 B，--simulate 版 |
| `civlink_hook.dll` | `71C240377449CF0AB14BE64C4BCD0E4D8CCAC024B629B285CCED47585CFED41D` | 118,272 B（第一轮注入）|
| `civlink_ctl.exe` | `64C39027A14590FE6CBEBCCE026B1D5FB121C81181462639F22E1DF9E2499CBA` | 172,032 B |
| `run-f1-integration.ps1` | `BA6A216FA42EFDBBFCC69C7EC092B3AD405DF1DDABE657B1B5A16D3657E047A2` | 集成驱动 |
| `run-f1-sim-selftest.ps1` | `31D9A9D0A74E48F1EC0B1B1FA0B75AE6FB4FCCCF953FC9DF1D8BC129E4FF3947` | sim 模式机械自检 |

### 6.2 证据目录（四轮，全部保留）

- **第一轮 PASS** `F1-integration-20261114-104235`：`summary.txt`=`AB312FD13434452E5CE14843BA71FD1AF453C1CF89A8F10FC105E9ED3893E3BA`（1,855 B）、
  `frame-log.txt`=`E4AFB693D2A2CEEE9923473D1F2F351A6B065CA466BB7C0BB7E51F8A190C2F1B`（42,912 B）、
  `counters-before.txt`=`8A8C7233BD8730212512471DC1592AD10810A58E1285CBEC20C208B6B99CCBDC`、
  `counters-after.txt`=`85F8A05E1760F8DE526AB43D131FC8FCE7B4EFD1FEE93AFD288C7569DF6A3D3B`、
  `verify-report.txt`=`E4E8E11A8BE41A15C42BDA39913F632882618ABA0FCD1C6D0401B4B7CAFFA296`。
- **第四轮 PASS** `F1-integration-20261114-105026`：`summary.txt`=`6D2DC8A6FE92D638E0BC95B45242FEF54B1D0480B3941377DA4AE22F231308EB`（1,864 B）、
  `frame-log.txt`=`622DF958BFF4F93B1FBC9214865D296F85DD4C197C54C84405718D285FCC3D54`（100,305 B）、
  `counters-before.txt`=`A837FBE78FF07F5B69EDF1FFA101E954EA1ED0C5CCEC5B35A17EEAC812D148F3`、
  `counters-after.txt`=`F4E690EE61B90E8CA087996D89549ECDAAA42FCAE7C54669CD197AF76CD5E583`、
  `verify-report.txt`=`D40BCCDEEF32224EDF81E93EA47BFA9A78863C2F724271899B3CEEFB088F9C51`。
- **第二轮 void** `F1-integration-20261114-104534`：`summary.txt`=`657E6A501E04BAE8154DC128979434A3D42AA00FAB0ED8E46AF79EE164468888`、
  `frame-log.txt`=`A5FB4B0B223A698A11B006F85EEBD880D759C3AA3D183472DEC9D16146D68E8A`（132 B，仅头注释行）。
- **第三轮 void** `F1-integration-20261114-104723`：`summary.txt`=`C468EE54589A81159D93A9F376CBC1BDB4A5939BDE6966D5982C05B600EB6A25`、
  `frame-log.txt`=`A5FB4B0B223A698A11B006F85EEBD880D759C3AA3D183472DEC9D16146D68E8A`（132 B，仅头注释行）；
  `counters-before == counters-after`（`58399A514FBEF350F39B85D3C7BA53ACB867E62CC149EF47AC5F011F027AFE91`）——无任何变化，佐证"无点击"。
- 四轮 `sim-page-01..22.bin` 与 `sim-fixture-manifest.txt`（`E1B4206C849521128442D59E51D7BBE26E7BCFD0BF3166DA8A4027EDDB6886AB`）逐字节一致
  （22 页 × 1104 B，fixture 匿名化重放，与 `reply-set` 原页一致仅房间名替换）。

### 6.3 相关报告

| 文件 | sha256 |
|---|---|
| `docs\F1-INTEGRATION-REAL-CLIENT-20261114.md` | `0F645DE02DE5DC49E58CE6F59634CD136469E73C4CF509AB607E811A1D728D00` |
| `docs\F1-LIVE-REAL-CLIENT-20261114.md` | `94C716BA02A6E7E094F4020F658BA8718AAB756ADBE332BD63BE99C5BB917FD4` |
| `README.md`（v1.15）| `99E2AFF5FA6AF853964AD505C9673FF044B123CF84B50C033656F9BB61850119` |
| `docs\CODEX-HANDOVER-M0A.md` | `2555063B6ABEB5D9A91C34A7163C3B4DB067C3D03A8FFC785834E1856E506B33` |

## 7. 请求复核的裁定项（供复核方裁决，执行端不自行宣布）

1. **F1 集成链路子项是否记为通过**（按 REV-016 §3 F1 的定义：模拟房主接入 DLL/Agent 链路并由真实客户端显示模拟房间）。
2. 证据表述是否满足边界（照抄 §0 限定结论；不得升级为联机/E2-B/Gate A）。
3. void 轮次归因（操作者时序）是否采信。
4. F1 整体状态是否可记为"两个子项均通过"，以及下一步 F2（Fake-IP + 62056 数据面）是否可以开始
   （F2 设计输入已确认：会话以刷新为单位、首帧 `0.0.0.0:0` 不得建映射、`sendto` 结论限本窗口、
   队列满/Agent 未运行/高负载时序影响须验证）。
