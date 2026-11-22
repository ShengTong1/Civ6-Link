# P0-A D-1 证据（2026-11-21 归档）

场景：新版 agent（628,736B/EE7309CF...，--features peer-discover）单实例，GUI 同参数
（--listen-seconds 60、--discover-port 63010、--probe-port 63011、--ifaces 192.168.31.60）。

- fake-*：向 127.0.0.1:63010 发 24B CLPR 发现报文（假 uuid + probe_port=63099）→ agent 记录对端；
  监听期（约第 8 秒）写 stop.now → agent exit 0。
  结果：peers-live.json paths[0]={sent:0,recv:0,...,ok:false,reason:"stopped"}，
  remain_s 自 53 递减；summary.txt 路径行 reason=stopped，
  RECOMMENDED: none (no probe was actually sent - stopped/deadline/send error; see per-path reason)。
- repl-*：无对端场景的 remain_s 倒计时验证（listening 第 8 秒 remain_s=53 → 停止后 done/remain_s=0）。

运行目录原件：C:\Users\dd\Desktop\civlink-gui\agent-out\（运行日志去向见 docs\LOGGING-CONVENTION.md）。

