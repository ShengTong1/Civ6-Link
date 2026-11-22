# M0-E 双机验证操作单（发现补全器 · 跨机）

版本：v1.2（2026-11-19，在 v1.1 审计修订基础上并入预检 v3 定版；v1.1 审计报告 sha256=190DEF2C40051B8F5655ACE8361732CCD5818A1B9534CF2821C83DA25B2BDFAE）
预检脚本：`civlink\run-m0e-preflight.v3.ps1`（24,386 B / `0224B231…`，自查主导定版）；设计与证据见 `docs\M0E-PREFLIGHT-20261119.md` v2.0
前置文档：`M0E-DISCOVERY-COMPLETION-20261118.md`（设计 v2.1，7AF86CB4…）、`M0B-DUALMACHINE-RUNBOOK-20261117.md`（M0-B 旧流程，本文取代其 A 侧 agent 部分）、`NIGHTLY-PACKAGE-20261119.md`

## 1. 目的

用两台真实机器验证 M0-E 发现补全器（`--discovery-completion`）的跨机行为：
1. B 机（客户端）刷新时能**通过 agent 补全链路**看到 A 机真实房间（真实房名，非 fixture）。
2. B 机加入房间后数据面（62056）**直连**能否建立对局（M-1 的核心未验证项）。

边界：本操作单不证明 Fake-IP/Noise/Relay/跨网；证据只到「发现链路跨机 + 加入行为」，不做长跑。

## 2. 前置条件（两侧）

| 项 | A 机（房主） | B 机（客户端） |
|---|---|---|
| 硬件/系统 | Windows + Civ6 Steam Win64 | 同左 |
| 网络 | 同 WLAN（或同广播域）；Radmin/ZeroTier 若开着须注意广播出口——**当前 Radmin metric=1 压过 WLAN=45**，HOST 角色可容忍、CLIENT 角色致命，见预检 C7.2 | 同左 |
| 防火墙 | civlink-agent Allow（Private+Public 双 profile）；Civ6 Allow 同 | Civ6 Allow |
| 产物 | `dist\civlink-20261119-nightly\`（agent 15321D49…、tray F49CE006…、MANIFEST 36/36） | 同左（拷贝整个 nightly 目录；**拷完按 MANIFEST.txt 抽验 agent/tray 两项 sha256 一致**，N-5） |
| Civ6 版本 | 相同 | 相同 |

**启动顺序（关键，m25442 教训）**：①先启动 Civ6 → ②建房（游戏占 62900+62056）→ ③再启动 agent（`--reserve-62900` 跳过 62900，只绑 62901–62999）。顺序颠倒会导致游戏 bind 62900 失败、建房卡住。

## 3. A 机步骤（房主）

```powershell
# 0) 预检（必须，完整 READY 才能继续）：
#    把 run-m0e-preflight.v3.ps1 拷到 nightly 目录（包布局，可同时验完整性），然后：
#    powershell -NoProfile -ExecutionPolicy Bypass -File .\run-m0e-preflight.v3.ps1
#    退出码 0=PREFLIGHT: READY / READY WITH CAVEATS；2=ACTION NEEDED（按提示修完再跑）；3=FATAL。
#    它覆盖：agent 入站 Allow 是否精确匹配"你要运行的 exe 路径"、是否覆盖本机在用的全部
#    Profile、游戏是否已持 62900/62056、有无残留 agent、广播出口是否被虚拟网卡抢走。
#    历史两轮真机失败全在这几项上，不再靠现场试错发现。
#    注意：建房前跑通常是 READY WITH CAVEATS（game premise 未验）——建房后必须重跑到完整 READY。
# 1) 启动 Civ6（正常启动，进入局域网建房）
# 2) 建房成功后确认端口占用：
Get-NetUDPEndpoint -OwningProcess (Get-Process CivilizationVI_DX12 -ErrorAction Stop).Id |
  Where-Object { $_.LocalPort -in 62900,62056 }   # 期望两行 0.0.0.0:62900 / 0.0.0.0:62056
#    （DX11 版进程名是 CivilizationVI，把 CivilizationVI_DX12 换成 CivilizationVI 即可）
# 3) 启动 agent（GUI 推荐：勾选「回真实房间（M0-E）」；或 CLI）：
cd <nightly 目录>
.\civlink-agent.exe --listen-seconds 1800 --sim-lan-listen 0.0.0.0 `
  --discovery-completion --reserve-62900 `
  --out-dir <证据目录>\a-agent
```
参数约束（设计 §5.1）：`--discovery-completion` 必须配 `--sim-lan-listen`；不得带 `--simulate`；不得带 `--sim-real-capture`；必须显式给 `--reserve-62900`；`--game-discovery-addr` 默认 `127.0.0.1:62900` 不改。

## 4. B 机步骤（客户端）

1. 启动 Civ6 → 主菜单 → 局域网 → **刷新**（一次即可；刷新按钮每按一次发 100 magic）。
2. 观察：应看到 **A 机真实房名**（不是 CivLink-Test-Room-2222 fixture 名）。记录截图或口述。
3. **加入房间**（M-1 核心步骤）：点击房间 → 加入。若卡在「检索创建人信息」，按 §6 排查。

> 预检口径（v3）：A 机建房后若预检仍显示 `READY WITH CAVEATS` 且 caveat 点名 game 62900/62056，说明端口前提没验到，先别让 B 刷新——确认游戏处于建房状态、重跑到完整 `PREFLIGHT: READY` 再继续。`CAVEAT` 不是 PASS。

## 5. 证据采集（A 机 agent 侧）

agent 退出方式（N-1 修订，关键）：**CLI Ctrl+C 无信号处理，强杀进程不会写 summary.txt**。让 agent 自然超时（1800 s）退出，或提前结束用 GUI tray 的停止按钮（写 stop 文件优雅退出，约 20 s），或给 CLI 加 `--stop-file <路径>` 后创建该文件。退出后读 `<证据目录>\a-agent\summary.txt`，关键行：

| 行 | PASS 期望 | 含义 |
|---|---|---|
| `requests seen` | ≈99×刷新次数（100 magic 中 99 落 agent 的 62901–62999，1 落游戏 62900） | agent 收到 B 的 magic |
| `port 62900` | `reserved, not bound` | 未劫持游戏端口 |
| `replays sent` | == 去重后的刷新次数 N | B-2 修复生效（不应出现 99/2178） |
| `duplicate magic` | ≈98×N（每轮 99 拦截 −1 轮；设计 §4.7 实测 99/1/98） | 一次刷新只重放一次 |
| `pages collected/forwarded` | == 22×N | 游戏真实广告完整转发 |
| `egress pinned` | == pages forwarded（B-1） | 回包源 IP=被探测地址 |
| `timeouts` / `short replies` | 0 | fail-closed 未触发 |
| `bind fail` | 1（62900 被游戏持有时）或 0 | 有残留占用会 >1，见 §6 |

另采集：B 机截图/口述（房名可见性）、加入是否成功、能否进入对局、对局 5 分钟稳定性。证据目录归档 `M0A\captures\M0E-crossmachine-<时间戳>\`（项目根或审计仓库内均可，登记时按设计 §10 v2.1 口径注明）。

## 6. 故障排查

| 症状 | 可能原因 | 处置 |
|---|---|---|
| 预检 C4.1 FAIL 但不想提权 | 防火墙按路径匹配，nightly 新目录无规则 | 按预检打印的 `ZERO-UAC REMEDY`，改从已有 Allow 规则的路径运行**同一哈希**的 agent（零提权、零配置改动） |
| B 看不到任何房间 | 防火墙拦 agent/Civ6（Profile 不匹配） | `netsh advfirewall firewall show rule name=all` 查两条 Block；补 Private 规则 |
| B 只看到虚拟房名（CivLink-Test-Room-2222） | agent 还在跑旧版（`--simulate`）或 fixture 目录残留 | 确认命令行无 `--simulate`；agent 0.4.6+ |
| B 见房名但加入卡住「检索创建人信息」 | 62056 直连失败（NAT/防火墙/多归属） | 这是 M-1 的已知未验证项；采集 A/B 两侧 `netstat -ano | findstr 62056`；不要反复重试（每轮都发 100 magic） |
| agent summary `timeouts > 0` | 游戏未建房或已退出建房状态 | 确认 62900 被游戏持有后再启 agent |
| `egress unpinned > 0` | 探测来自非 IPv4/loopback 或 IP_PKTINFO 失败 | 记录 `probed address` 行并归档；不影响 fail-closed 正确性，但说明钉源未生效 |
| B 刷新但 agent 无反应/summary `duplicate magic` 不增 | B 在 750 ms 冷却窗内连点刷新被静默去重 | 冷却窗内重复请求不重放（客户端表现为"这次没搜到"）；等 >750 ms 再刷；不要设 `--completion-cooldown-ms 0`（等效禁用去重，会放大成 99 次重放/2.41 MB，设计 §5.1 N-6） |
| summary `bind fail > 1` | 62901–62999 有残留 agent 占用 | §3 步骤 0 预检；杀掉残留 civlink-agent 进程后重启 |

## 7. 判定与边界

- **发现链路 PASS**：B 见真实房名 + agent summary 满足 §5 期望行。
- **M-1 PASS**：B 加入成功且能进入对局 ≥5 分钟（62056 直连成立）。
- **边界**：即使双 PASS 也不得宣称 E2-A/E2-B/E3 全结案——E2 结案需按其原始定义复核（Gate A 复核流程）；本操作单不覆盖 62056 数据面故障注入（F3-E 已覆盖单机侧）、长跑、多客户端并发（设计 §8）。
