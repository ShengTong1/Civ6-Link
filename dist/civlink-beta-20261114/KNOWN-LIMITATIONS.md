# CivLink Beta 2026-11-14 — 已知限制（KNOWN LIMITATIONS）

> 发布标签：**模拟对端 / 发现助手测试版**。本包**不**构成"双人真实联机已通过"，
> 也不移动 Gate A/B。任何宣传必须使用本文件与 README v1.20 的限定措辞。

## 1. 本包能做什么（已验证，单机）

- 发现链路：真实 Civ6 客户端的 LAN 刷新请求经 civlink_hook.dll → 本机 Agent →
  模拟房主（fixture 22 页公告）→ 回注客户端，客户端 LAN 列表显示模拟房间
  （F1 集成证据：两轮 300/700 帧计数闭合；F0 基线 20/20 刷新）。
- 数据面观测：Agent `--simulate-datapath` 观察 62056 帧；整个运行至多回 1 个
  20 B 固定探针（D4）。游戏点"加入"后停在"正在检索创建人信息"是**预期行为**
  （模拟房主按 D4 不回应），不是卡死或缺陷。
- 分层计数对账：Hook 观测路径计数与 Agent 收包数在 F1/F3-A/F3-B/F3-C/F3-D/F3-E
  的合成实验中全部闭合（F3-D 压力：40,000 帧下 Agent 8,035 收、Relay 13,214 转，
  恒等式成立；丢包率是驱动属性，不代表产品表现）。
- 故障底线（F3-E 23/23）：对端退出、Relay 掉线、通道 down 时计数如实、该 fatal
  时真实退出码（exit 3）、不产生伪协议应答。

## 2. 已知限制（未验证 / 未实现）

| # | 限制 | 状态 |
|---|---|---|
| L1 | **F3-D 判据前半句未验证**：62056 忙轮询（~1.6 M recv/s）下 Hook detour 在真实游戏进程内不丢帧 | 归 M0-B 真机工作；不得因 F3-D 合成实验 PASS 视为已勾掉（README v1.18 Gate 登记） |
| L2 | 双人真实对局（两个真实 Civ6 进程加入并游玩） | 未验证（PC-B 离线）；E2-A/E2-B/E3 仍"待验证"，模拟测试不能勾掉 |
| L3 | DEGRADED/RECONNECTING 状态机、Relay 心跳（15 s）与"不踢人"语义 | 未实现（F3 原型无状态机，M0-B 目标） |
| L4 | Relay 跨真实网络（非回环）行为、NAT 穿透 | 未验证；F3-B/C/D/E 全在回环 |
| L5 | Noise 加密（L1 Agent↔Relay、L2 Agent↔Agent） | 未实现（F3 原型明文，规范 §4.1） |
| L6 | Fake-IP 数据面（127.0.127.x 映射）在真实游戏内生效 | 未验证（fakeip crate 17/17 单测仅纯内存逻辑） |
| L7 | DLL 对异步/重叠 I/O、事件、WSAPoll、IOCP 的语义覆盖 | 未验证（M0-B；F1/F2 仅覆盖 sendto/WSASendTo 发现路径与 62056 观测） |
| L8 | 不同 VPN 产品 / 跨 NAT 环境 | 未逐项验证，不宣称兼容 |
| L9 | DLL 卸载 | B2 审计运行模式：**模块保持映射直到目标进程退出**；注入器对活动进程不执行 FreeLibrary。干净停用=`civlink_ctl.exe shutdown -x CivilizationVI_DX12.exe`（禁钩+排空），然后退出游戏 |

## 3. 使用（单机验收流程）

1. 从**中立目录**（非项目树，如 `C:\Users\dd\Desktop\civlink-f4\`）运行本包
   ——项目树含 Low Mandatory Label，会导致 ctl 无法 OpenProcess。
2. 启动 Civ6 → 多人 → 局域网。
3. `powershell.exe -NoProfile -ExecutionPolicy Bypass -File run-f4-beta.ps1`
   （自动：版本检测 → agent 模拟房主 → relay → 注入 → 等待操作）。
4. 在游戏内点刷新 ≥3 次（应看到 `CivLink-Beta-Room-2222`）；可选点一次加入
   （预期停在检索页）。回脚本按回车结束。
5. 查看证据目录 `M0A\captures\F4-beta-<ts>\` 的 summary.txt / VERSIONS.txt /
   path-state-*.txt；`check-f4-package.ps1` 做包完整性自检（无需游戏）。
6. 收尾：hook 已 shutdown（模块保持映射），退出 Civ6 即完全卸载。

## 4. 文件身份（dist\civlink-beta-20261114）

| 文件 | 字节 | sha256 |
|---|---|---|
| `civlink-agent.exe` | 382,464 | `93F1751620C2B83D413AADACD9DA1EB167F4D6ECDCCFECA447AC0D7245E92132` |
| `civlink-relay.exe` | 262,144 | `9E323F818AF0DE7699F6C3DBA7D29FB786BBC27CDC2F2D5B908E935A7D60C98C` |
| `civlink_ctl.exe` | 173,056 | `23923DFBAAB310F2BDAA1E1117110B92A74290E2C87396E5CB65EE0E4FEFEA30` |
| `civlink_hook.dll` | 119,808 | `9424FC25FB45841FC6A31A0C9CD747067005D3FA32A06A18CD150B0C9CEBC10F` |
| `run-f4-beta.ps1` | — | 见 VERSIONS.txt / 打包时哈希 |
| `check-f4-package.ps1` | — | 见 VERSIONS.txt / 打包时哈希 |

## 5. 证据索引

- F1 集成：`M0A\captures\F1-integration-20261114-104235`、`-105026`（两轮 PASS 9/9）
- F0 基线：`M0A\captures\F0-run-20261114-000141`（20/20）
- F3-A/B/C/D/E：见对应 `docs\F3?-*.md` 的 §7 证据哈希表
- Gate 登记：`CivLink-M0A-audit\README.md` v1.18
