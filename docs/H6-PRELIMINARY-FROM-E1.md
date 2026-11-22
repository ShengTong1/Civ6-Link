# H6 预备数据：来自 E1 真实日志的窗口测量（非 E2-B）

> 状态：**预备数据（preliminary）**，不能作为 E2-B 结论，也不能作为 Gate A 依据
> 生成时间：2026-11-13 13:22
> 工具：`CivLink-M0A-audit\scripts\analyze-h6-window.ps1`
> SHA256 `1606BD039CA353554BAAEC0F2EBD559BAD6BAF836CEF678BB53273211C8D3F9D` / 12,355 B

---

## 1. 为什么要先测这一组

H6 是"发现 socket 从首包广播到 `closesocket` 活多久"。它决定 CivLink 能不能用
**中继发现请求**这种最省事的架构。E2-B 的正式测量要等 PC-B 在线，
但在那之前，E1 已经留下了一份**真实的、未被分析过的** civtrace 日志，可以先验工具、
顺带拿到一个量级参考。

**这份数据只回答"工具算得对不对、量级大概多少"，不回答"H6 成立"。**

## 2. 数据来源

| 项 | 值 |
|---|---|
| 日志 | `C:\Users\dd\AppData\Local\CivLink\M0A\logs\civtrace_20261111_151008_pid42256.log` |
| 大小 | 65,986,528 B（460,403 行） |
| 采集场景 | E1 单机发现（本机既无为房主、无对端响应） |
| 注入工具 | civtrace v0.4.4（31/31 hooks） |

## 3. 逐轮结果

| 轮次 | socket | sendto | 端口数 | 突发跨度 | **窗口（首包→关闭）** | 响应 | 响应→关闭 |
|---|---|---|---|---|---|---|---|
| 1 | `0x868` | 100 | 100 | 1.004 ms | **2021.252 ms** | 0 | n/a |
| 2 | `0x15c8` | 100 | 100 | 3.824 ms | **2018.945 ms** | 0 | n/a |
| 3 | `0x1718` | 100 | 100 | 4.133 ms | **2013.841 ms** | 0 | n/a |

分布：`n=3  min=2013.841  p50=2018.945  p90=2018.945  max=2021.252` ms。

## 4. 与 `+20~50 ms` 中继目标的对照

```
relay target 50 ms : 3/3 closed rounds have window >= target
```

3 轮窗口都是 ~2.0 s，比 50 ms 的中继目标宽约 **40 倍**。
仅就"窗口是否容纳中继 RTT"这一条而言，**E1 数据没有显示出风险**。

## 5. 必须同时记住的限定

1. **这是单机、无房主响应的轮次。** `recvfrom` 全部为 0，所以这 2 s 是
   **纯 select 轮询窗口**（日志里对应 `select rfd=n=1[0x868] timeout=set` 连续 134 次）。
   一旦真有房主响应，游戏是否会更早关 socket，**本轮无法回答**。
2. **不是 E2-B。** E2-B 要求双端注入、双端 v0.4.4、全新进程、角色/PID/tag、
   10 次刷新取分布、Wireshark 交叉验证——这些一项都没做。
3. **不能推"中继可行"。** H6 只是可行性的**必要输入之一**，不是充分条件；
   端口随机、响应源端口语义、分页重组等仍需各自裁决。
4. **不能用于 Gate A。** Gate A 未批准、M0-B 冻结的状态不因本文件改变。

## 6. 这组数据真正证明的事

- 工具能在 66 MB / 46 万行日志上正确切分轮次（3 轮 × 100 包，无漏无并）
- `sendto` 突发跨度 1.0–4.1 ms，与 E1 早期人工结论一致，交叉验证通过
- 窗口数从"人工读日志估计"变成"一条命令可复现的数字"，E2-B 时可直接套用

## 7. 复现命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit\scripts\analyze-h6-window.ps1 `
  -Log "$env:LOCALAPPDATA\CivLink\M0A\logs\civtrace_20261111_151008_pid42256.log" `
  -RelayRttMs 50
```

工具自身回归：20/20 通过（`scripts\test-analyze-h6.ps1`），
证据目录 `M0A\captures\h6-selftest-20261113-132232\`。

## 8. E2-B 时要补的

- 有房主响应时的窗口（本轮全是 0 响应）
- 10 次刷新的分布（本轮只有 3 轮，且来自 E1 的既有日志）
- 双端日志的时间戳交叉验证
- `resp2close`（末响应→关闭）的排空余量
