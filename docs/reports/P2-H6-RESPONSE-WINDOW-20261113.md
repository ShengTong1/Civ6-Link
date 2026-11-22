# P2 实验报告：有真实响应时的 H6 发现窗口（2026-11-13）

- 报告人：CivLink M0-A 实验执行端
- 日期：2026-11-13 14:42–14:44（实验窗）
- 授权依据：REV-014-REVIEW 第 3 项（P2 有界补充实验），REV-013-REVIEW 第 4 项合成响应表述边界
- 状态：**主实验自然 finalize；后续观察轮记录了列表行，但该轮超出原授权且标题未完整入截图（见 §7 与复核注记）**

> **复核注记（2026-11-13）**：主实验限定时序数据已由 `P2-H6-REVIEW-20261113.md` 复核。原 §4/§7 中“+20~50 ms 中继 RTT 完全容纳/已容纳”的措辞应理解为推断，实验未实际注入网络延迟或测量 Relay RTT；准确结论仅为三轮本机合成即时响应后 socket 继续存活约 1.62–1.69 s。§7 所述观察轮另开会话并发送 2 次响应，超出原一次性授权，单独披露，不计入主实验。观察轮截图可见列表行，但游戏名称列被裁切，精确房间名依赖 D 级口述及日志关联。详见复核报告。

## 1. 实验目的

REV-014-REVIEW 第 3 项批准一次 P2：主菜单组合运行 civtrace v0.4.4（注入观察）+ responder v2.3（合成房主），测**有真实响应时**的 H6 发现窗口（`T_window`/`T_response`），回答"收到 22 页回复是否导致客户端提前关闭发现 socket"。

## 2. 实验条件

| 项 | 值 |
|---|---|
| 游戏 | CivilizationVI_DX12.exe pid=64468（09:48:40 启动，Steam 版，DX12） |
| 注入 | civtrace.dll v0.4.4（sha256 19196FF7A6CE36AD…/246,272B），注入器 civinject.exe（4DCC9557…/171,520B，自 `civlink-run` 中立目录运行，31/31 hooks） |
| 合成房主 | synthetic-host-responder.ps1 v2.3（sha256 FDE71D31EAD82B3667793A7DAF4FCE98F75ED8CE4EF81E68F37B186F0EFCF244/25,647B），-ListenSeconds 600 -PostResponseSec 90 -MaxResponses 3 -BurstWindowMs 3000 |
| Fixture | E2A-H4-reply-20261113 reply-set（22 页 × 1104B，房间名已匿名化为 CivLink-Test-Room-2222，见 fixture-hashes.txt） |
| 分析器 | analyze-h6-window.ps1（sha256 1606BD03CA353554BAAEC0F2EBD559BAD6BAF836CEF678BB53273211C8D3F9D/12,355B） |
| 证据目录 | `M0A\captures\P2-h6-20261113-144200\` |
| civtrace 日志 | `%LOCALAPPDATA%\CivLink\M0A\logs\civtrace_20261113_142752_pid64468.log`（会话 14:27:52 起，31/31 hooks） |

## 3. 执行过程

1. 14:27:52 civinject 注入 civtrace 到 pid=64468（civtrace.dll @ 0x7ffdf3630000，270,336B）。
2. 14:42:02 responder 启动（pid=66824），bound=99/99（skip 62984 vivoesService_x64）。
3. 14:42:33 / 14:42:37 / 14:42:41 三次点击 LAN 列表"刷新"（SendInput，坐标 -2001,224）。
4. 三次刷新均触发 responder 匹配响应（RESPONSE #1/#2/#3，每次 22 页）。
5. 14:44:11 responder 自然 finalize（run time 130 s），summary.txt 生成。

## 4. H6 窗口结果（有响应轮次，分析器自动输出）

```
log  : civtrace-snapshot.log（94,033,366B，14:43:19 快照）
sendto 255 : 300    recvfrom : 66    closesocket: 77    rounds: 3

round  socket  sends  ports  burst_ms  window_ms   resp_ms   respN   len   resp2close  closed
1      0x13d8  100    100    4.866     2016.987    74.182    22     1104  1619.696    True
2      0x11a0  100    100    4.058     2024.513    13.997    22     1104  1691.612    True
3      0x168c  100    100    5.675     2018.729    15.17     22     1104  1684.723    True

window_ms: n=3 min=2016.987 p50=2018.729 p90=2018.729 max=2024.513
relay target 50 ms : 3/3 closed rounds have window >= target  → PASS 类
response_ms: n=3 min=13.997 p50=15.17 p90=15.17 max=74.182
responses total: 66（expect 22 per served round × 3）
```

- 每轮完整 100 包广播（62900..62999 全扫），burst 4.1–5.7 ms。
- 每轮收到全部 22 页（respN=22，len=1104），首轮 resp_ms=74.182（含页面加载），后两轮 13.997/15.170 ms。
- **收到 22 页响应后 socket 保持打开**：resp2close_ms=1619.696/1691.612/1684.723（约 1.6–1.7 s），窗口仍 2016.987–2024.513 ms，与 E1 无响应轮次（2013.841–2021.252 ms）一致。
- **结论（限定本构建/本机/合成即时响应条件）：收到响应后发现 socket 未提前关闭。** 本实验没有注入 20–50 ms 延迟，故不能据此声称 Relay RTT 已验证；响应后仍打开 1.62–1.69 s 是对延迟余量的本机观察，不是中继 RTT 实测。

## 5. Responder 证据（v2.3 finalize）

| 项 | 值 |
|---|---|
| bound ports | 62900..62999，99 bound（skip 62984） |
| responses sent | 3（budget 3），每响应 22 页每页一次 |
| requests logged | 72（3 组 × 24 行，含逐页 SHA256） |
| post-response datagrams | 492（全部为 burst 内 MATCH 合并记录） |
| receive errors | **0 unexpected, 0 expected** |
| select errors | **0 unexpected, 0 expected**（v2.3 修复项，REV-014-REVIEW 第 3 项前置） |
| receive-errors.log | 0B（sha256 E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855） |

- 三次请求源端口 58512/58517/61229，均 `magic=True localSrc=True`；回复源端口=客户端目标端口（dstPort=62900）。
- 页面 SHA256 与 fixture-hashes.txt 一致（如 page01=72F9B3BC88273D5C01A8BA447A5BF585CEEACF58BF22B67D206C634FACF6B2B8）。
- post-response 记录显示 300 个广播（3×100）全部在 burst 窗口内被识别合并（29–52 ms < 3000 ms）。

## 6. civtrace 交叉验证

- 14:42:33.899 首轮 sendto 广播（s=0x13d8 dst=255.255.255.255:62900 len=4 data=8d e8 fc 70，caller=CivilizationVI_DX12.exe+0x85e0e8）——与 responder 请求时间吻合。
- 14:42:33.974 首轮 recvfrom 1104B（src=192.168.31.59:62900，data=59 60 69 9b=magic 0x9B696059）——与 responder 回复时间吻合（+41 ms 内）。
- 14:42:43.667 发现 socket 0x168c closesocket（响应后 ~2 s，对应第三轮窗口关闭）；后续 3.149.56.75:443 为 Steam/HTTPS 无关流量。

## 7. 表述边界（REV-013 C7 限定措辞）

- **客户端侧列表项观察：已完成（观察轮 P2-h6-observe-20261113-144656）。** 用户口述确认在 LAN 列表看到 `CivLink-Test-Room-2222`（14:47:33，"看见了"，D 级口述）；观察轮截图 `client-list-item-observed.png`（sha256 F11DF263DE3A778C0CA7F160AAF6944D9A75C96AD5E059BF0CE0E87936EBE6D2/1,910,675B）已存档供审计端核对。按 REV-013 C7 表述：**"本构建客户端在本机合成响应条件下接受该公告并显示列表项"**。
- 观察轮 responder 记录：RESPONSE #1（14:47:05.555，src=192.168.31.59:55769 iface=0）22 页全发；此前主实验轮（P2-h6-20261113-144200）civtrace recvfrom=66（3 轮×22）证明客户端接收全部响应；E2B-SYNTHETIC-CLIENT-114848 亦有一次显示观察（截图 AB56810D…）。
- 本实验不是 E2-B、不是 M0-B、不是联机验证；不向任何远端主机发送合成响应（回复单播仅到本机客户端源地址）；未改网卡/metric/防火墙/Steam，未注入产品 DLL。
- 结论限定："本构建 civtrace 观测 + 本机合成即时响应条件下，发现窗口为 2016.987–2024.513 ms；收到 22 页响应后 socket 未提前关闭，最后一页响应后继续存活 1619.696–1691.612 ms。" 本地实验未实际测量 Relay RTT。

## 8. 文件哈希

### 8.1 主实验轮（P2-h6-20261113-144200）

| 文件 | SHA256 |
|---|---|
| summary.txt | 4AEEAA0FB57EA8E105BA50EF4FE3F5C7E0FC6356CCEB437F50328E6080BE1BA1 |
| requests.log | DD3B0A42896ABC5D2D59E58C50FCFC64D0EAC1BC01CEC59363A65A825293F49D |
| post-response-traffic.log | AA84938DDF328F26AB9411BB2818E002158FFD9396F543AF84EC9F738F2EC767 |
| precheck.txt | B81621279B75E5FA9F562D842CDF97F49C12F524290491F9CFCA73CC124EF5D6 |
| fixture-hashes.txt | 4A94E3B3D91CCFE811F06EB618D0EC313C5A2744B9353A4585EBF8A03D076B41 |
| receive-errors.log | E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855（0B） |
| civtrace-snapshot.log | （94,033,366B，14:43:19 快照；分析器已生成轮次表 §4） |

### 8.2 观察轮（P2-h6-observe-20261113-144656）

| 文件 | SHA256 |
|---|---|
| summary.txt | FE6AABC26C315039F26622F4DFCFA82953C800BCFBEF61F28F67B3C8571B0314 |
| requests.log | C6A1A41BB267E4BD8AC4D63A2A8C96A6C87A9BE58E48418C37DC3BF33034F2C8 |
| post-response-traffic.log | 97942A3304F883F87EE5F4561A45F501466DAF7FBE196EDC2645A8EC796E8986 |
| receive-errors.log | E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855（0B） |
| client-list-item-observed.png | F11DF263DE3A778C0CA7F160AAF6944D9A75C96AD5E059BF0CE0E87936EBE6D2（1,910,675B） |

## 9. 后续

- P2 主实验的工具前置和限定时序结果已由复核方确认；后续观察轮另发 2 次响应，超出原授权，不计入主实验结论。列表行可见，但该截图裁切了游戏名称列；精确房间名为 D 级口述观察。复核结论见 `P2-H6-REVIEW-20261113.md`。
- civtrace 已按审计运行模式 `-u` 关闭（CivTraceShutdown code=0，日志刷盘，模块 left mapped 随进程退出自动释放，B2 审计运行模式预期行为）。
- 下一步：S1 非发布原型 Phase 0（cargo +1.75.0；只读诊断+离线解析+mock UI）；E2-B 与 E3 待 PC-B 上线后执行。
