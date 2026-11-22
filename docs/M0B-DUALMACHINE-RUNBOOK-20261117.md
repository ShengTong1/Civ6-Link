# M0B 双机真实联机操作单（Discovery Adapter 双路应答 + 数据面直连）

> 版本 1.0（2026-11-17）· 关联：`docs/M0B-FINAL-PROGRAM-PLAN-20261117.md` v1.1、README v1.29（授权登记）

## 1 目的

A（房主）/B（加入者）两台真实机器在同一 WLAN 下，通过 civlink 助手让 B 稳定看到并加入 A 的 Civ6 局域网房间，
消除原生发现 1/100 窗口与广播丢包问题（E2-B 首轮失败根因）。

## 2 机制（已实测确认）

- A 机 Civ6 房主：bind 0.0.0.0:62900，建房瞬间广播 2 轮 100 包 magic，发现 socket ~70s 生命周期。
- B 机 Civ6 客户端：局域网刷新 = 广播 100 包 magic（255.255.255.255:62900..62999 各 1 包，同一源端口）。
- A 机 agent（M0-B Discovery Adapter）：`--sim-lan-listen 0.0.0.0` 绑 62900..62999；因游戏占 62900 → bind fail=1 跳过 →
  实际绑 **62901..62999（99 端口）**（LanSimState::new 已处理，main.rs:541-560，机械证据 10/10 PASS
  `M0A\captures\M0B-adapter-selftest-20261117-131441`）。
- **双路应答**：B 的 100 包里目标 62900 那包 → 游戏 socket 收 → 游戏自身单播应答真实广告页（run-095336 形态）；
  其余 99 包 → agent 收 → agent 应答（--sim-real-capture 捕获的真实页优先，否则 fixture 兜底，房名 CivLink-Test-Room-2222）。
  任意一路成功 B 即看到房间 → 命中率从 1/100 提升到 ~99/100。
- **数据面直连**：广告页无 IP/端口字段（real-page-01.bin 实测），B 点加入后向「应答源 IP:62056」发 join（S5 观测端口固定 62056）。
  真实双机应答源 = agent 绑定的 A 机 WLAN IP → B 向 A 机 WLAN IP:62056 直连 → 落到 A 机 Civ6 62056 socket。
  agent 转发（Game Data Adapter）为备选，先测直连。

## 3 A 机步骤（房主）

1. 前置：civlink-b1 目录完整（civlink-agent.exe 033D7741…、civlink_ctl.exe、civlink_hook.dll 39D6735D…、fixture-reply-set/、start-m0b-adapter-a.ps1）。**防火墙前置检查**：civlink-b1\civlink-agent.exe 有入站 Block 规则（早期实验遗留的 Query User 规则）→ 有两条绕过路径：**推荐路径 B（零 UAC）**=用 civlink-f1\civlink-agent.exe（033D7741 同版，该路径已有 ALLOW 入站规则）+ civlink-f1\start-m0b-adapter-a-f1.ps1（已准备，同参数封装）；**路径 A（需 UAC）**=运行桌面 civlink-firewall-fix.cmd（右键管理员）删 Block+加 Allow 后用 civlink-b1。两条路径任选，否则 B→A 广播被拦截、双机验证必然 FAIL。
2. **先注入 hook，再建房，最后启动 agent**（★关键顺序：agent 会绑定全部 100 个发现端口；游戏建房时也要绑定 0.0.0.0:62900——两个 socket 不能同时绑同一端口。若 agent 先启动，它会抢走 62900，游戏建房绑定失败。正确顺序：注入 → 建房（游戏占 62900）→ 启动 agent（自动跳过 62900，回退绑定 62901-62999，见自检 bind fail=1））：
   a. 注入（身份判定需要 SlotBoundPort 在 bind 前就位）：`civlink_ctl.exe inject -x CivilizationVI_DX12.exe -d civlink_hook.dll`
      （若 Civ6 未运行则先通过带 CIVTRACE_TAG 的 Steam 启动游戏；注入后 `civlink_ctl.exe status -x CivilizationVI_DX12.exe` 确认 hooks active）
   b. Civ6 内创建局域网房间（多人游戏 → 局域网 → 创建房间）。建房瞬间广播 2 轮 magic（走 metric 最小网卡，不影响 B→A 请求与 A→B 应答）。
   c. **确认房间已创建后**再启动 agent（推荐路径 B）：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\dd\Desktop\civlink-f1\start-m0b-adapter-a-f1.ps1`（f1 目录，零 UAC；若选路径 A 用 civlink-b1\start-m0b-adapter-a.ps1）。封装 `--listen-seconds 1800 --sim-lan-listen 0.0.0.0 --simulate fixture-reply-set --sim-real-capture --sim-room-name CivLink-Test-Room-2222`；启动后检查 out 目录 stderr 有 `cannot bind 0.0.0.0:62900` 属预期（游戏已占）。
3. 等 B 刷新验证。

## 4 B 机步骤（加入者）

1. Civ6 → 局域网大厅 → 刷新（多次，间隔几秒）。
2. PASS 判定：大厅列表出现房间（真实房名 dingzihan2022 或 fixture 房名 CivLink-Test-Room-2222，可能同时两条=游戏应答+agent 应答）。
3. 任选其一加入 → 观察能否进入房间等待状态（数据面直连 A 机 62056）。
4. （可选）抓包/日志回传：B 侧 pcapng 或 civtrace（tag=client）日志。

## 5 判定与故障排查

- 判定：B 见真实房名（A 侧 agent summary captured>=1/active=yes 或 B 口述）+ B 成功加入 = M0B 双机验证 PASS。
- B 看不到房间 → 先查 A 侧 agent 存活（pid/out-dir console、stderr `cannot bind 0.0.0.0:62900` 属预期）+ hook 注入状态
  → 再查 **A 机 Civ6.exe（游戏进程）UDP 入站规则**（B→A magic 靠游戏 socket，非 agent.exe）。
- 加入后无响应 → 数据面直连失败 → 启用 Game Data Adapter（agent 转发 62056）备选方案（计划 §7 v1.1）。

## 6 边界（登记）

- 双路应答时 B 可能看到两条房间记录（游戏应答 62900 源 + agent 应答 62901-62999 源），同一房名，任选加入，数据面均直连 A 机 62056。
- 本操作单验证的是「真实双机发现+加入链路」（E2-B 结案目标），**对局完整性/长稳/跨网/加密不在本轮**（计划 §7 v1.1 边界）。
- 机械证据（10/10 PASS）不得宣传为双人真实联机验证；双人结论以本操作单执行结果为准。
- Agent 永不 bind 0.0.0.0:62056、永不 SO_REUSEADDR、每帧单次不重传不篡改。

## §5.5 证据采集（E2-B 结案登记用）

双机验证完成后请采集以下证据（A 机）：

1. **agent 运行目录**（start-m0b-adapter-a.ps1 输出的时间戳目录，内含 summary.txt / agent-console.txt / agent-stderr.txt）——核对 
requests seen（=B 到达的 magic 数，应接近 100 的倍数）、
replied sockets（≥1）、ind fail（=1，62900 被游戏占）。
2. **B 机口述/截图**：大厅列表可见房间（真实房名 dingzihan2022的游戏 或 fixture CivLink-Test-Room-2222）+ 成功加入后停留在房主房间等待界面。
3. **注入确认**：civlink_ctl status 输出（hooks active）。
4. （可选）B 机 civtrace 注入日志（tag=client）记录 join 数据面发包到 A 机 WLAN IP:62056——数据面直连证据。
   辅助脚本：pcb-kit\run-b-civtrace-client.ps1（1,652B/BACA66B7…，需游戏从带 CIVTRACE_TAG=client 的 Steam 会话启动）。
