# M0-B 准备材料：DLL 注入稳定性观察（2026-11-15）

> **性质声明（必读）**：本文档是 **M0-B 的准备材料（tool-level evidence）**，不是 M0-B 验收，
> 不勾除 Gate A/B，不代表"双人真实联机已验证"。正式 M0-B 仍冻结；Gate A 未批准。
> 结论边界：单次会话、单进程、约 5 分钟窗口的稳定性观察。

## 1 目的

在真实 Civ6（DX12）进程中运行 civlink_hook.dll（F1 Hook 链路，3 detour），
观察计数单调性、失败计数、进程内存与整体稳定性，作为正式 M0-B 前的工具级准备材料。

## 2 环境

- 进程：CivilizationVI_DX12.exe pid=12420（DX12，12:25:51 启动）
- 注入工具：`civlink_ctl.exe v0.2.0-f2`（inject/status/counters）
- 注入 DLL：`civlink_hook.dll` 119,808B sha256=9424FC25FB45841FC6A31A0C9CD747067005D3FA32A06A18CD150B0C9CEBC10F
  （civlink\ 与 dist\civlink-beta-20261114\ 两处一致）
- 注入方式：管理员（SeDebugPrivilege）LoadLibraryW 注入
- 采样：60s 节拍 × 5 个采样点（12:50:09–12:54:09），elevated PowerShell 调用
  `civlink_ctl counters -x CivilizationVI_DX12.exe -p 12420` + 进程内存

## 3 证据

- 注入日志：`M0A\captures\M0B-prep-stability-20261115\inject-hook.txt`
  （`[+] hooks active (CivLinkHookState=1)`、LoadLibraryW 返回 0xeac60000、exit 0）
- 采样序列：`M0A\captures\M0B-prep-stability-20261115\samples.csv`（表头+5 行）

## 4 采样数据

| 时间 | sent | send fail | reject oversize | ignored | raw sendto | raw bind | raw recvfrom | recv on 62056 | bind 62056 | cvlh2 try | cvlh2 ok | state queries | 内存 (WS, MB) |
|------|------|-----------|-----------------|---------|------------|----------|--------------|---------------|------------|-----------|----------|---------------|---------------|
| 12:50:09 | 100 | 0 | 0 | 0 | 100 | 0 | 0 | 0 | 0 | 100 | 100 | 3 | 1659.8 |
| 12:51:09 | 100 | 0 | 0 | 0 | 100 | 0 | 0 | 0 | 0 | 100 | 100 | 3 | 4270.8 |
| 12:52:09 | 500 | 0 | 0 | 0 | 500 | 4 | 3,884,931 | 3,884,931 | 2 | 500 | 500 | 3 | 3708.2 |
| 12:53:09 | 500 | 0 | 0 | 0 | 500 | 5 | 3,884,931 | 3,884,931 | 2 | 500 | 500 | 3 | 3707.9 |
| 12:54:09 | 500 | 0 | 0 | 0 | 500 | 5 | 3,884,931 | 3,884,931 | 2 | 500 | 500 | 3 | 3707.5 |

## 5 观察结论

1. **转发链路正确**：sent==raw sendto==cvlh2 try==cvlh2 ok（100→500），全部发现包被 Hook
   截获并 100% 封装转发（cvlh2 ok == cvlh2 try），无发送失败。
2. **零失败计数**：采样期间 send fail / reject oversize / sent notify / ignored
   全程为 0（samples.csv 已采样列）；sock overflow / cvlh2 fail / cvlh2 errno /
   channel down 未纳入采样列，注入时点快照为 0（见 inject-hook.txt counters 段）。
3. **真实流量覆盖**：窗口内用户多次刷新大厅（发现广播 100 包/次，累计 500），并触发
   "加入"流程——raw recvfrom 达 388 万次且全部落在 62056（bind 62056=2）——
   60s 采样粒度支撑平均 ≥64,749 次/s（3,884,931/60），与 F2 S5 观察
   （客户端忙轮询 WSARecvFrom ≈1.6M/s）为量级一致的推断（峰值未复测）；
   Hook 在该忙轮询压力下稳定。
4. **内存平稳**：12:52 后连续 3 个采样点 3.70–3.71GB 稳定，无单调增长/泄漏迹象
   （12:50→12:51 的增长为游戏加载地图，非 DLL 所致）。
5. **state queries 恒定 3**：无状态机异常。

## 6 边界与不证明

- 不证明：双人真实联机、E2-A/E2-B/E3、对局稳定性、长时间（小时级）运行、多会话、
  跨进程、62056 数据面转发正确性（只观察了忙轮询收包，未观察转发）、Relay RTT、
  Fake-IP、Noise、跨网。
- 单次会话 5 分钟窗口，样本量小；正式 M0-B 验收仍需按 README v1.21 §4/§5 执行
  E2-A/E2-B/E3 双机流程（PC-B 在线）。
- 注入进程为 Civ6 DX12 本机运行；Hook DLL 与 agent 的完整端到端（agent 运行态）未在此
  窗口内验证（本次 agent 未运行，Hook 计数反映的是截获+封装成功，不涉及转发投递）。

## 7 文件身份

| 文件 | 字节 | SHA-256 |
|------|------|---------|
| civlink_hook.dll | 119,808 | 9424FC25FB45841FC6A31A0C9CD747067005D3FA32A06A18CD150B0C9CEBC10F |
| civlink_ctl.exe | 173,056 | 23923DFBAAB310F2BDAA1E1117110B92A74290E2C87396E5CB65EE0E4FEFEA30 |
| inject-hook.txt | 证据目录内 | 见证据目录 |
| samples.csv | 证据目录内 | 见证据目录 |
