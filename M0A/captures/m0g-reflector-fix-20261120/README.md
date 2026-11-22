# M0-G 探针阶段反射缺陷修复 —— 双机验证证据

日期：2026-11-20
二进制：civlink-agent.exe 601,600 B
sha256：279FC4B177ED30B3DCE13D02EBAC8A2DF9F579DA08C5157F4998BC73F05224D4
（A 机 C:\Users\dd\Desktop\civlink-gui\ 与 B 机 D:\Desktop\ 同哈希）

## 缺陷

旧版只在主循环里反射对端探针；探针阶段结束时主循环已退出，而两台机器的
监听窗长度相同 → 两边几乎同时进入探针阶段 → 双方的反射器都已停止
→ 各自探测一个不会应答的对端 → 所有路径 100% 丢包，永远 RECOMMENDED: none。

实测（修复前，pd-v3 / pd-v4 两轮）：A 侧 recv=0 loss=100%、B 侧 recv=0 loss=100%。

## 修复

peer_discover_net.rs：
1. probe_paths 增加 reflector 参数（Some(&probe_sock)）；
2. 探针等待循环内调用新函数 reflect_pending(reflector, &mut rbuf_refl, start)，
   在等待自己那条应答的同时继续为对端反射；
3. reflect_pending 复用 encode_probe(seq, true, t1, t2, t2)。

## 修复后双机结果（同时启动，listen-seconds 45）

A 侧 summary.txt（864 B）：
  discovery sent/recv : 45/84
  peers discovered    : 1
  probes reflected    : 2
  path WLAN(192.168.31.60) -> 192.168.31.214:63011 : sent=100 recv=98
       p50=16.5ms p95=40.1ms J=5.43ms loss=2.00% score=0.4366 recommendable=true
  RECOMMENDED: WLAN(192.168.31.60) -> 192.168.31.214:63011

B 侧 summary.txt（1,008 B）：
  discovery sent/recv : 45/88
  peers discovered    : 1
  probes reflected    : 0
  path WLAN(192.168.31.214) -> 192.168.31.60:63011 : sent=100 recv=100
       p50=16.4ms p95=28.0ms J=4.03ms loss=0.00% score=0.1918 recommendable=true
  path WLAN(192.168.31.214) -> 26.74.126.98:63011 : sent=100 recv=0 loss=100%（预期：
       Radmin 侧未开同房间，A 的 Radmin 地址不可达）
  RECOMMENDED: WLAN(192.168.31.214) -> 192.168.31.60:63011

双向互见成立（peers.jsonl 双方各学到 1 个 peer，含双地址）。

## 边界

- 这是助手之间的发现与链路质量测量，不是文明6 双人对局验证；
  不勾 E2-A/E2-B/E3，不移动 Gate A。
- 仍保留：无鉴权（同广播域任何人可发现/伪造）、VPN 即二层广播域。
- 探测期需落在对端监听窗内：两端应大致同时启动，否则晚启动一侧
  的探针无人反射（此为设计语义，非缺陷）。