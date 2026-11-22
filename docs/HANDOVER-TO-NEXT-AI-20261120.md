# CivLink 交接文档（给接手的 AI）

> 生成时间：2026-11-20 23:20（Asia/Shanghai）
> 生成者：上一任执行 AI（DSH/DeepSeek Harness 会话）
> 交接对象：下一个接手继续完成的 AI
> 项目负责人：用户（下称「负责人」）

**读这份文档的顺序**：§1 目标与现状 → §2 立刻要做的事 → §3 关键路径与产物 → §4 构建/部署规程 → §5 双机与 VM 环境 → §6 硬约束（不可破） → §7 已知缺陷 → §8 踩过的坑（必读，能省几小时） → §9 登记与审计规则 → §10 验证方法与判伪 → §11 交接验收清单。

---

## 1. 目标与现状

### 1.1 项目是什么

CivLink：给《文明 6》（Steam / Win64）做的**联机助手**。它不改游戏逻辑，解决的是「同一局域网内两台机器用 Civilization VI 的『局域网』模式互相找不到房间 / 不稳」的实际问题。

核心机制（已实测确认，不要重新发明）：

- 文明 6 房主建房时 `bind 0.0.0.0:62900`，并向 `255.255.255.255:62900..62999`（100 个端口）各发 1 个 4 字节 magic（`8D E8 FC 70`）广播。
- 客户端点「刷新」时**同样广播 100 包**（每端口 1 包），但**只监听自己的固定源端口**。
- 房主收到 magic 后，把 22 页 × 1104 字节的广告页**单播**回请求者的「源 IP:源端口」。
- 因此有效命中率原本是 1/100，且 UDP 广播丢包 6%–34%（E2-B 三轮实测），这就是「搜不到房间」的物理根因。
- CivLink 的做法：hook（注入 A 机游戏进程）捕获发现包 → 本地 agent 补齐/应答；M0-E 阶段进一步让 agent 绑 `62901..62999`（99 个端口）+ 游戏自己占 `62900` = **100 端口全覆盖**，任何端口收到请求都回**真实房间**的广告页。

### 1.2 已经完成并验收的里程碑

| 里程碑 | 内容 | 状态 |
|---|---|---|
| F0–F4 | 发现链路、数据面、Relay、退避、故障注入、发布候选 | 全部完成 + 审计闭环 |
| F5 | LAN 模拟房主 `--sim-lan-listen`，跨机发现链路 PASS（真机双机） | 完成 + 审计闭环 |
| B1 | 真实广告页捕获（不伪造房名） | 完成 + 审计闭环 |
| M0-B | 双机发现链路真机验证（B 见到真实房名） | 有条件通过（加入/数据面 M-1 未验证） |
| M0-C | C1 `--reserve-62900`（根治「agent 抢 62900 导致建房卡住」）+ C2 `civlink_client.dll --iface`（B 端定向网卡） | 完成 |
| M0-E | `--discovery-completion`：agent 绑 62901–62999 + 回真实广告页；B-1 钉源（IP_PKTINFO）+ B-2 去重（冷却 750ms） | 完成，VM 级跨机 PASS |
| M0-G | 助手互发现 `--peer-discover`：全网卡广播 + 多路径 RTT/抖动/丢包评分 + 推荐 | 完成，真机双机双向 PASS |
| GUI | Tauri 2 重写（六页：注入/节点发现/状态/计数/设置/诊断），提权 manifest，单实例 | 持续迭代中 |

### 1.3 **还没验证的唯一硬缺口**

- **M-1：加入 + 数据面 62056 真机验证**。即 B 从局域网列表点「加入」后能否进入大厅、开局后能否进地图。这是**整个项目唯一的未验证环节**，也是结项的唯一硬指标（内部代号 **T1**）。
- 之前所有「发现链路 PASS」都**不能**替代它。README/HANDOVER 里严禁把工具级/模拟级证据写成「双人联机已验证」。

---

## 2. 立刻要做的事（按优先级，负责人已下过指令）

### 2.1 P0-A：修 VM 测试暴露的「探针 sent=0 / recv=0」缺陷（**这是当前最紧的**）

负责人在 VM 上跑节点发现，页面显示：

```
对端设备 82206a3a
探测端口 63011
26.197.96.55:63233 192.168.31.176:63231
0s 前
路径                          收发   p50  p95  抖动  丢包 / 评分
WLAN (192.168.31.60) → 26.197.96.55:63011    0/0   0ms  0ms  0ms  0% / 0
WLAN (192.168.31.60) → 192.168.31.176:63011  0/0   0ms  0ms  0ms  0% / 0
无可用路径（未通过硬门槛：丢包>3% 或 p95>150ms 或样本<80）
```

**读数含义（已确认的语义）**：

- 对端被发现、双地址正确、`0s 前` → **助手互发现链路（门 1）本身在 VM 上是通的**，这部分没问题。
- `sent=0` → `probe_paths()` 里 `for seq in 0..100` 一次都没执行到 `st.sent += 1`。`recv=0`、`p50/p95/抖动=0`、`loss=0%`、`score=0` 都是「零样本」的连锁结果，**不是「测得 0ms 延迟」**。
- 页面那句「无可用路径」是 `pdRenderRec()` 的兜底文案，样本 0 必然落到它，属于表象。

**候选根因（按可能性排序，需要在真实 run 目录里判定，不要凭猜改代码）**：

1. **探针循环被 `abort` 立即打断**：`probe_paths` 的第 4 参实际接收的是 `abort`（`main.rs` 里 `run_peer_discover(..., stop.as_ref(), abort.as_ref())` 传下去，调用处是 `probe_paths(&ifaces, &peers, PROBES_PER_PATH, abort, Some(&probe_sock), start, &mut stats)`）。只要 `agent-out\stop.now` 存在，`abort=true`，每个 path 的第一轮判断 `if stop.load(...) || Instant::now() >= phase_deadline { break; }` 立刻 break → `sent=0`。GUI 的 `stop_agent` 会写这个文件；**一次「先点停止再重开」的时序就可能命中**。
2. **`send_to` 全部失败被 `continue` 吞掉**：`if udp.send_to(&pkt, dst).is_err() { continue; }` 只计数不报错，`st.sent` 不增加。跨接口发送（socket 绑在 `192.168.31.60`，目标 `26.197.96.55` 走 Radmin）在 Windows 上可能返回 `WSAENETUNREACH / WSAEINVAL`。
3. **`phase_deadline` 已过**：`PROBE_PHASE_BUDGET_MS = 45_000` 从 `probe_paths` 进入时起算，正常不会立刻过；但如果前一个 path 把 45s 耗尽，后续 path 会 0 发送——本轮只有 2 条 path，可能性低。

**判定方法（下一步 AI 必须照做）**：让负责人重跑一次，然后读那次 run 目录（`C:\Users\dd\Desktop\civlink-gui\agent-out\peer-<epoch>\`）里的：

- `summary.txt` 的 `probe sent` / `probes reflected` / `paths` 行；
- `err.txt`（`send failed` / `probe socket` 之类）；
- `peers-live.json` 的 `phase` 与 `elapsed_s`；
- 是否残留 `agent-out\stop.now`。

**建议的代码修法（判定后再动手）**：

- 让 `probe_paths` 给每条 `PathResult` 带上「为什么是 0 样本」的原因枚举（`Sent=0/Aborted/Deadline/SendError`），写进 `peers-live.json` 与 `summary.txt`，页面直接显示「探针未发出（已停止）」而不是「无可用路径」。这既是修复也是可观测性。
- 若确认是 `send_to` 失败：探针 socket 目前**故意不钉源**（单播不需要钉源，见源码注释），跨接口发送失败时应**回退到默认路由 socket 重试一次**，而不是静默 `continue`。
- 若确认是 `abort` 所致：GUI 侧在 `start_agent` 时已 `remove_file(stop.now)`，需检查 `stop_agent` → 立刻重启的竞态。

### 2.2 P0-B：GUI 节点发现页文案与状态改造（负责人 m35885 明确要求）

| 要求（逐字要点） | 实现要点 |
|---|---|
| 「开始发现」改为「开始广播」 | `index.html` L74 `<button id="pd-start" class="primary">开始发现</button>` |
| 广播中显示「正在广播」 | `#pd-phase` 现有 `PD_PHASE_LABEL.listening = "监听中"` → 改「正在广播」 |
| 按钮变虚 | 广播期间 `#pd-start` 加 `disabled`，`style.css` 补 `button:disabled{opacity:.45;cursor:not-allowed}` |
| 同时显示倒计时 | 需要把「剩余秒数」暴露给前端：当前 `peers-live.json` 只有 `elapsed_s`（已过秒数）。**要加 `remain_s`（或让 GUI 用 `--listen-seconds` 自己算 `start 时刻 + 60 - now`）**；推荐 agent 在 `write_live` 里直接写 `remain_s`，避免前后端两套时钟 |
| 「发现网卡」改为「网卡选择」 | `index.html` L64 `<span class="rowlabel">发现网卡</span>` |
| 删除「自动刷新（5s）」 | 删 `index.html` L65 的 `#pd-autorefresh` label 与 `main.js` 的 `startPdAuto/stopPdAuto` 绑定，**默认恒开自动刷新**（保留 5s 定时器，仅删开关 UI） |

**注意**：`PD_WARNINGS` 两条安全警告（①无鉴权仅限信任网络 ②VPN 即同一广播域）**不得从 GUI 彻底删除**——它是审计验收项 M5。当前做法是「点开始广播时逐行写进日志」，改文案时**必须保留这个动作**。

### 2.3 P0-C：服务端「监听网卡」改为固定 0.0.0.0（设计已定，代码未改）

负责人的疑问（m35863）与结论：

> 「为什么服务端也有『监听网卡』这项，服务端默认的不是监听所有网卡的那 99 个端口吗？」

**结论：服务端这一项不该让用户选，只能 `0.0.0.0`。** 实测证据（本机四组对照，同端口、`ReuseAddress`、发→收）：

```
bind 0.0.0.0       <- 255.255.255.255   : RECV 5      ← 通
bind 192.168.31.60 <- 255.255.255.255   : no          ← 收不到
bind 0.0.0.0       <- 192.168.31.255    : RECV 5
bind 192.168.31.60 <- 192.168.31.255    : RECV 5
```

文明 6 客户端刷新发的是**受限广播 `255.255.255.255`**，所以**绑具体单播 IP 的 socket 收不到，发现补全会静默失效**（没有报错，只表现为「B 又看不到房间」）。这就是一个「只能选对一次、选错就静默坏掉」的开关，必须去掉。

**改法**：

- `index.html` L38-40 的 `<div id="hostonly" class="row"><span class="rowlabel">监听网卡</span><select id="lanip"></select></div>` → 换成只读一行：
  `监听网卡：全部网卡（0.0.0.0，绑定 62901–62999，62900 留给游戏建房）`
- `main.js` 的 `agentstart` 处理里把 `const lanip = document.getElementById("lanip").value;` 改为固定 `"0.0.0.0"`，删掉 `if(lanip === "(不启用)")` 分支；
- `refreshIfaces()` 里 `["iface","lanip"]` 循环简化为只处理 `iface`；
- **B 端的「节点发现」页网卡多选（`--ifaces`）与注入页的 `--iface` 保持不变**——那两个是真有用的（一个控制从哪张卡发广播，一个用 `IP_UNICAST_IF` 控制游戏发包走哪张卡）。

### 2.4 P0-D：仓库整理 + 日志保存规范（负责人 m35885）

**现状**（必须处理）：仓库根散落 15 个构建/调试日志：`bd.log bd2.log bd3.log bd4.log bd5.log bfinal.log bfinal2.log bg.log bg2.log bg3.log gb.log gbuild.log gbuild2.log gbuild3.log pdsel.log`；`civlink\` 下还有 `build-hook*-out.txt`、`guibuild.log`、`clean.log`、`mut.log`、`restore.log`、`*.obj`、`*.lib`、`*.exp`、`*.bak-*`、`deploy-b\`、9 个 `pd-*` 运行目录、`_tmp\`。

**必须遵守的整理规则**（避免删掉证据导致文档哈希对不上）：

1. **先 grep 再动**：任何文件在删除/移动前，必须在 `README.md`、`docs\*.md`、`M0A\captures\**` 里搜文件名；被引用的一律**保留**，或只移动到 `_attic\` 并在原文档登记新位置。
2. **`M0A\captures\` 是审计证据区，只增不改**（68 个子目录，对应 F0–M0-G 各轮）。不得清理。
3. **`dist\` 下的历史发布包保留**（`civlink-beta-20261114` / `civlink-20261119-nightly` / `civlink-20261119-ready` 及 zip），它们对应历史证据轮次。
4. 产物类的 `.obj/.lib/.exp/.idb/.pdb` 与 `target\`、`obj\` 属于中间产物，可清理。
5. 新建 `.gitignore`（当前**没有**），至少覆盖：`target/`、`obj/`、`*.obj`、`*.lib`、`*.exp`、`*.pdb`、`*.idb`、`*.log`、`agent-out/`、`userdata/`、`deploy-b/`、`civlink/pd-*/`、`civlink/*-selftest-out/`、`dist/*.zip`（如需入库再例外）。

**日志保存规范（建议直接落地成 `docs\LOGGING-CONVENTION.md`）**：

| 类别 | 位置 | 命名 |
|---|---|---|
| 构建日志 | `artifacts\build\`（新建，gitignore） | `YYYYMMDD-HHmmss-<target>.log`（如 `20261120-231500-gui.log`） |
| 自检运行输出 | `civlink\<script-name>-out\` 或 `%TEMP%\pd-selftest-<HHmmss>` | 沿用现有脚本约定，别改 |
| 里程碑证据 | `M0A\captures\<milestone>-<YYYYMMDD>[-<HHmmss>]\` | 只增不改，附 `README.md` 记录本目录的判定与哈希 |
| agent/GUI 运行结果 | `C:\Users\dd\Desktop\civlink-gui\agent-out\peer-<epoch>\` | 用户可见，勿手工清空 |
| **禁止** | 仓库根目录 | 不许再出现 `*.log` |

### 2.5 P0-E：登记（**代码改完、用户目视确认之后**再落盘）

- `docs\M0G-GUI-PEERS-TAB-20261120.md` 追加「布局契约根因 + 本轮 UI 改造」；
- `README.md` 追加 **v1.45** 修订块 + 改 L3 版本行；
- `docs\CODEX-HANDOVER-M0A.md` 追加**第 32 项**。

**顺序铁律**：先改代码 → 构建 → 部署 → 用户目视确认 → 再登记。否则会把作废哈希写进文档（本项目已经因此返工多次）。

### 2.6 P1：T1 结项验证（等负责人安排两台真机 + 两台都能开文明 6）

**T1 双机真实对局闭环（结项唯一硬指标）**：

1. A 机（房主）：GUI「注入」页 → 角色=服务端 → 注入 `civlink_hook.dll` → **然后**在游戏里建「局域网」房 → 再在「设置」页点「启动发现补全」（顺序**不可反**，反了 agent 会占 62900 导致建房卡住）；
2. B 机（客户端）：游戏里点「局域网-刷新」→ 应看到 **A 的真实房名**（不是 `CivLink-Test-Room-2222`，那个是 fixture 匿名名，出现它说明回的是假数据 = 缺陷）→ 点「加入」→ 进大厅 → 开局进地图见到对方单位；
3. 同轮顺手取 A 侧 agent `summary.txt`（`requests seen ≈ 100×N`、`replays sent ≈ N`、`pages forwarded ≈ 22×N`、`duplicate magic ≈ 99×N`），这样 M0-E 就从「VM 级」升级到「真机级」（内部代号 **T2**）；
4. 可选 T3：B 侧注入 `civlink_client.dll --iface <WLAN IP>` 验证定向网卡。

**已知会挡路的坑**：防火墙必须按**程序绝对路径 + Profile** 双向覆盖。历史事故：A 机 WLAN = Private，但规则只建了 Public → agent 一个包都收不到（`requests seen=0`）。

---

## 3. 关键路径与产物

### 3.1 路径

```
项目根        C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit\
源 码         civlink\
  agent\src\main.rs                （约 4,230 行，CLI 与各模式主循环）
  agent\src\peer_discover_net.rs   （990 行，M0-G 网络层：enumerate/probe_paths/write_live/write_outputs）
  agent\src\peer_discover_core.rs  （368 行，纯逻辑 + 自检，零依赖，ALWAYS 编译）
  hook\hook.cpp                    （610 行，6 个 detour，全部透传）
  client\civlink_client.cpp        （IP_UNICAST_IF 定向网卡）
  ctl\civlink_ctl.cpp              （inject / inject-client / status / counters / shutdown）
  gui-tauri\src\{index.html,style.css,main.js}   （前端，无打包器，window.__TAURI__）
  gui-tauri\src-tauri\src\lib.rs   （264 行左右，Tauri 命令）
  gui-tauri\src-tauri\build.rs     （前端资源 rerun-if-changed 在这里）
  build-msvc.cmd                   （hook/ctl 构建，需 MSVC + MinHook v1.3.4）
证 据         M0A\captures\<milestone>-<date>\
文 档         docs\  （134 个文件）
桌面部署      C:\Users\dd\Desktop\civlink-gui\
```

### 3.2 当前产物身份（2026-11-20 23:20 实测，**作废值会害你，请以磁盘为准重算**）

| 产物 | 大小 | SHA-256 |
|---|---|---|
| `civlink-gui.exe`（部署） | 11,408,896 B | `4D02AA3C8030DF82A49D451CEA440C0CB0240B2B2207062D442D8F69AB39914B` |
| `civlink-agent.exe`（部署，feature peer-discover） | 614,912 B | `C51C4FA3EA201B2A5A811B584A03A148C613B9506FC76EB968B622A0AA43FE62` |
| `civlink_hook.dll` | 119,808 B | 以磁盘为准 |
| `civlink_client.dll` | 149,504 B | 以磁盘为准 |
| `civlink_ctl.exe` | 188,416 B | 以磁盘为准 |

文档侧：`README.md` **v1.44 / 163,002 B / `FB12843453BD042225A4C65CC2AB4109828DB21EB35583694448BF6357F9EE4E`**；`docs\CODEX-HANDOVER-M0A.md` **71,527 B / `A08C0674A102A01AFFF4F8971FCDD172555E27E1BF8C5DAB9D0B36AEBE373481`**（到第 31 项）；`docs\M0G-GUI-PEERS-TAB-20261120.md` **10,661 B / `968406B4…`**。

> ⚠️ 三份文档里 `civlink-gui.exe` 记的是 `907CF752…`，而实际部署已是 `4D02AA3C…`（仅资产嵌入时间差）。这一处口径待统一。

---

## 4. 构建与部署规程

### 4.1 agent（必须 `+1.75.0` + `--offline`）

```powershell
$env:PATH="D:\cargo\bin;$env:PATH"
cd C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit\civlink\agent
cargo +1.75.0 build --release --offline --features peer-discover
```

- `Cargo.toml` 默认**零依赖**，只有 `peer-discover` feature 才拉 `if-addrs` / `socket2`。
- `Cargo.lock` 必须是 **version 3**（用 `cargo +1.75.0 generate-lockfile --offline` 生成）；**stable 会写成 v4，1.75 直接报错**。
- `cargo` 把 stderr 转成 NativeCommandError 时 `exit code` 可能显示 1，**判定成败看 exe 是否落盘 + mtime 变化**。

### 4.2 GUI（必须 **stable**，不能用 +1.75.0）

```powershell
cd C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit\civlink\gui-tauri\src-tauri
cargo build --release
```

- 用 `+1.75.0` 会报 `lock file version 4 was found, but this version of Cargo does not understand this lock file`。
- 必须 `cd` 到 `src-tauri`（父目录没有 `Cargo.toml`）。
- **前端改动不触发重编**已由 `build.rs` 的三条 `println!("cargo:rerun-if-changed=../src/...")` 根治；若发现「改了没生效」，先查这三行还在不在。
- 提权 manifest 在 `src-tauri\windows-app\civlink-gui.exe.manifest`（`requireAdministrator`），**必须带 Common-Controls v6 依赖**，否则报「无法找到入口」。

### 4.3 hook / ctl（C++）

```powershell
cd ...\CivLink-M0A-audit\civlink
.\build-msvc.cmd     # 内部调用 D:\MSVC\BuildTools 的 vcvars64
```

- 硬约束：**/MT 静态 CRT**；MinHook 必须 pin `v1.3.4`（`deps\MinHook`，HEAD `8af6b4ac…`）。

### 4.4 部署（GUI 运行中 exe 被锁）

```powershell
$dst = 'C:\Users\dd\Desktop\civlink-gui'
Move-Item "$dst\civlink-gui.exe" "$dst\civlink-gui.exe.old" -Force
Copy-Item .\target\release\civlink-gui.exe $dst -Force
```

部署后**必须让负责人重开窗口**才生效。

### 4.5 投送到 PC-B（每次都要用，配方已验证）

```powershell
# 1) 新二进制放进隧道源目录（隧道固定指向它，忘了同步就会拉到旧哈希——踩过两次）
Copy-Item .\civlink-agent.exe '...\civlink\deploy-b\civlink-agent.exe' -Force
# 2) 起本地 HTTP
Start-Process python -ArgumentList '-m','http.server','8088','--bind','127.0.0.1' -WorkingDirectory '...\civlink\deploy-b'
# 3) 反向隧道（后台 job）
ssh -i C:\Users\dd\.ssh\id_ed25519_civlink -N -R 8089:127.0.0.1:8088 JIANGREN@192.168.31.214
# 4) B 侧拉取（用 -EncodedCommand 传 PowerShell）
#    Invoke-WebRequest http://127.0.0.1:8089/civlink-agent.exe -UseBasicParsing -OutFile D:\Desktop\civlink-agent.exe
```

**硬教训**：大二进制**不能**走 `ssh` 命令行 base64（`The filename or extension is too long`，807,596 字符直接失败）。

### 4.6 在 PC-B 上跑命令（远程）

- 一行 PowerShell 就用 `-EncodedCommand`：本地 `[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))`。
- **SSH 会话结束会杀掉子进程**：要长跑必须分离启动
  `Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='cmd.exe /c ""D:\Desktop\civlink-agent.exe" <args> > "D:\Desktop\out.txt" 2> "D:\Desktop\err.txt""'}`。
- 读回文件：`base64(UTF8)` 打印，前缀用 `|` 分隔（**别用冒号**，会被 PowerShell/ssh 层吃掉，得到零输出）。

---

## 5. 环境（双机 / VM）

| 角色 | 地址 | 备注 |
|---|---|---|
| A 机（本机，房主） | WLAN `192.168.31.60`，Radmin `26.74.126.98` | 用户日常机器；`InterfaceMetric`：Radmin=1、WLAN=45、ZeroTier=1045、vEthernet=5000 |
| PC-B（客户端） | WLAN `192.168.31.214`，SSH `JIANGREN@192.168.31.214:22`，key `C:\Users\dd\.ssh\id_ed25519_civlink` | **桌面是 `D:\Desktop`**（不是 `C:\Users\...\Desktop`）；Radmin `26.187.101.177` |
| VM（测试用） | `192.168.31.176`，Radmin `26.197.96.55`，SSH `dd@192.168.31.176` | 可跑 agent，**装不了文明 6**；VM 与 A 走 Radmin 二层同一房间时广播可达 |

- **PC-B 会离线**，离线时不要尝试任何远程操作（负责人明确说过「不在线就不要用」）。
- 测试时**不要干扰桌面环境、不要影响游戏对局**（负责人原话）。
- A 机 `$env:TEMP` 下写 `peers.jsonl` 会报 `拒绝访问 (os error 5)`——那是**沙箱**限制，不是产品缺陷；换到仓库树内或桌面目录即正常。

---

## 6. 硬约束（破一条就要返工）

1. **`/MT` 静态 CRT**；MinHook pin `v1.3.4`。
2. **agent 永不 `bind 0.0.0.0:62056`**（那是游戏数据面）。
3. **永不 `SO_REUSEADDR` 到已被占用的端口**（会劫持游戏的 62900 单播）。
4. **不伪造协议应答内容**（fail-closed）：广告页要么来自真实游戏，要么显式 fixture 且房名匿名化。
5. **机械/模拟证据 ≠ 双人联机验证**。文档措辞必须分级（D 级口述 / 机械计数 / 真机双人）。
6. agent `Cargo.toml` **默认零依赖**；`peer-discover` feature 才拉库。
7. `Cargo.lock` 必须 **v3**，禁 stable 重生成。
8. **中文源文件补丁必须 `[IO.File]::ReadAllLines` / `WriteAllLines`**：`Get-Content` 在 PS 5.1 按 GBK 读会把 UTF-8 中文打碎。
9. `rustc 1.75` **没有** `UdpSocket::try_recv_from`（要用 `try_clone()+set_nonblocking(true)+recv_from`）。
10. **变异测试前必须核对 exe mtime ≥ src mtime**，陈旧 exe 会伪造 baseline 失败。
11. **送审对象冻结**：文档送审后不得改字节；纯 ASCII 化必须在送审前完成。
12. **UI 双警告（无鉴权 / VPN 即广播域）不得从 GUI 彻底删除**（审计验收项 M5）。
13. **登记链单向引用**：README / HANDOVER 可以引用子文档哈希；**子文档不得反向嵌 README/HANDOVER 哈希**（否则循环重算，本项目已返工多次）。
14. GUI manifest 必须 `requireAdministrator` + Common-Controls v6。

---

## 7. 已知缺陷与遗留项（截至交接）

| 编号 | 内容 | 状态 |
|---|---|---|
| **D-1** | VM 上探针 `sent=0/recv=0`（§2.1） | **未定位，当前最紧** |
| **D-2** | 服务端「监听网卡」可选具体 IP，选错静默失效（§2.3） | 设计已定，**代码未改** |
| **D-3** | 「开始广播」状态/倒计时/禁用态未做（§2.2） | **未改** |
| **D-4** | 仓库根 15 个散落日志、`civlink\` 中间产物、无 `.gitignore`（§2.4） | **未整理** |
| **D-5** | 文档 GUI 哈希口径不一致（`907CF752…` vs 实际 `4D02AA3C…`） | 待统一 |
| **D-6** | `docs\M0G-GUI-PEERS-TAB-20261120.md` 未含「布局契约根因」（`.pd-result` 被 flex 裁掉）与最新 UI 轮 | 待补 |
| **D-7** | 设备行只显示 uuid 前 8 hex，**没有机器名/角色**（discovery 包 24B 无名称字段） | 需协议扩展，已登记为后续项 |
| **D-8** | `SECURITY.md` 联系渠道留空 | **发布阻断项** |
| **M-1** | 加入 + 62056 数据面真机验证 | **未验证（结项硬指标）** |
| **C4** | E2-A / E2-B / E3 结案 + Gate A 复核 | 未结案；Gate A 未批准 |

---

## 8. 踩过的坑（读这一节能省几小时）

### 8.1 进程/构建

- **`cargo` 假成功**：`Finished` + exit 0 但产物哈希没变 → tauri-build 没监听前端资源。已由 `build.rs` 修；agent 侧则要检查 mtime。
- **`+1.75.0` 不能编 GUI**（lock v4）；**stable 不能编 agent**（v3 lock 与 1.75 工具链）。两条链路工具链是分开的。
- **PS 5.1 三连坑**：①`[uint32]0xffffffff` 转不了，用 `[uint32]::MaxValue`；②残留 `civlink-agent` 进程占着 62900s 导致新实例静默失败，脚本开头先清进程；③`BeginOutputReadLine` 在 PS 5.1 后台线程会崩（进程级 exit 2、顶层 catch 抓不到）→ 改 `ReadToEndAsync()` + `WaitForExit()`。
- **PowerShell 写含 `<` / `"` 的多行代码必须用 `@'…'@` here-string**，否则 `<` 被当重定向运算符。
- **函数级代码改动必须整段替换**，逐行 `Insert/Delete` 曾吃掉 `fn` 头或末尾 `}`（`error: this file contains an unclosed delimiter`）。

### 8.2 网络（这些是真机制，不是玄学）

- **绑单播 IP 的 socket 收不到 `255.255.255.255`**（§2.3 实测表）。所以收包必须 `0.0.0.0` 通配 + `IP_PKTINFO` 取真实目的地址。
- **`255.255.255.255` 的出口由 `InterfaceMetric` 最小的网卡决定**，不是每张卡都发一份。Radmin（metric=1）会把广播吞掉 → 这就是「B 搜不到 A」的历史根因之一。
- **绑源 IP + 钉出口后，受限广播根本出不了机器**（`send_to` 还返回 Ok）→ 必须双 socket：pinned 的只发定向广播，默认路由的 socket 发受限广播。
- **探针反射必须持续到对端也测完**：两侧几乎同时进探针阶段，主循环里的反射器已停 → 各自测到静默对端 → 100% 丢包。修法是 `reflect_pending()`（探针期继续应答）+ `grace_answer()`（测完后再应答 `PEER_GRACE_MS=30s`）。
- **`IP_UNICAST_IF` 对 limited broadcast 确实生效**（四接口实测），但对非法 ifIndex 会**静默退回默认出口**，不报错。
- 回包过滤要按 `from.port() != dst.port()` 判，不能按整地址比（对端可能从另一张卡回）。

### 8.3 文档/审计

- **不要为了「好看」改已送审文档的字节**（哪怕只是注释/ASCII），哈希一漂就要重启审计。
- **登记链不能互引哈希**（README ↔ 子文档 ↔ HANDOVER 互嵌 = 循环重算）。
- 子代理审计容易「返回空产物」：给审计子代理下任务时**要求逐条落盘**（先写骨架文件，再增量填），并在会话里核验文件是否真的存在。
- **Beiling：`Get-Content` 显示乱码不代表文件坏了**，要用 `[IO.File]::ReadAllBytes` + `[Text.Encoding]::UTF8.GetString` 复核 BOM / CRLF / U+FFFD。

---

## 9. 验证方法（怎么知道自己没骗自己）

| 层次 | 方法 | 能证明什么 |
|---|---|---|
| 单元/纯逻辑 | `civlink\run-peer-discover-selftest.ps1` → 期望 `PD-SELFTEST: 6 checks, 0 failed` + `PASS - all mutations caught` | 评分/编码逻辑正确 + 变异可捕获 |
| 自检（其它） | `run-c1-reserve-selftest.ps1`（12/12）、`run-c1-combo-selftest.ps1`（14/14）、`run-m0e-completion-selftest.ps1`、`hook_selftest.exe`（52 条，**须先关文明 6**，否则 62056 被占） | 组件行为 |
| 单机冒烟 | agent `--peer-discover --listen-seconds 8` → 看 `peers-live.json` 是否 phase 流转、summary 是否落盘 | 数据源可用 |
| 跨机（VM 可） | A 起 agent，VM 起 agent，看双向 `peers` 与 path 行 | 发现 + 探针链路 |
| 跨机（真机） | A 建房 + 发现补全，B 刷新见**真实房名** → 加入 → 开局 | **唯一能证明「能用」的层次** |

**判伪三条**：

1. 任何「PASS」都要能在磁盘上找到对应的 `summary.txt` / `peers.jsonl` / `peers-live.json`；
2. 文档里的哈希必须能 `Get-FileHash` 复现，且 mtime 与记录一致；
3. `captured=0` 时**不能**声称「真实房间可见性」是 CivLink 的功劳（那可能是游戏自己应答的）。

---

## 10. 与负责人协作的方式（已验证有效）

- 负责人**要求每完成一步立即派子代理审计，并行下一步**。
- 负责人**不喜欢**：模糊措辞、把模拟证据说成联机验证、反复返工同一处、把窗口/按钮改得更乱。
- 负责人**明确要求过**：界面要专业、简洁、大字、浅色；警告不要用大块黄色底（改为点按钮时写日志）；日志要能滚但不能撑破页面。
- 每次改完 GUI **必须重新构建 + 部署 + 让负责人重开窗口**，否则他会看到旧界面并问「为什么没变」。
- 汇报时给**可验证的数字**（字节数 + sha256 前 8 位 + 关键计数），不要只说「已修复」。

---

## 11. 交接验收清单（接手后先跑这 6 条）

1. `Get-FileHash` 核对 §3.2 的 `civlink-gui.exe` / `civlink-agent.exe`，与本文一致 → 说明你拿到的是同一个状态。
2. `cd civlink\agent; cargo +1.75.0 build --release --offline --features peer-discover` 能过。
3. `cd civlink\gui-tauri\src-tauri; cargo build --release` 能过。
4. `powershell -File civlink\run-peer-discover-selftest.ps1` → `PD-SELFTEST: PASS`。
5. 读 `docs\CODEX-HANDOVER-M0A.md` 第 28–31 项（M0-G / GUI 三轮），确认你理解了「不得宣称已联机」的口径。
6. 打开 `C:\Users\dd\Desktop\civlink-gui\civlink-gui.exe`（需 UAC），点「节点发现」→「开始发现」，确认设备面板能渲染（无对端时显示空态文案）。

---

## 附：一句话总结当前状态

**发现链路已经打通并被真机双向验证过（M0-G）、真实房间应答也已在 VM 上跨机验证（M0-E）；现在卡在两件事：一是 VM 上探针 `sent=0` 这个新缺陷（D-1），二是「加入 + 62056 数据面」的真机验证（M-1）——后者是结项的唯一硬指标。**
