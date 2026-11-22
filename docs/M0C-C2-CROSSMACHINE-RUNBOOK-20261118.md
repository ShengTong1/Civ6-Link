# M0-C C2 跨机实测操作单：验证 IP_UNICAST_IF 是否真的改变了广播出口网卡

- 文档日期：2026-11-18
- 前置文档：[M0C-C2-DESIGN-20261118.md](./M0C-C2-DESIGN-20261118.md)（§3.3 判定方法、§7.2 主判据）
- 前置状态：单机自检 `C2-BOOKKEEPING-SELFTEST: PASS (45/45)` 已通过（证据 `M0A\captures\C2-iface-selftest-20261118-0928`），但**记账层自检对"广播是否真的从选定网卡发出"零判别力**
- 状态：**待执行**（PC-B 于 2026-11-18 09:15 实测离线）

---

## §0 为什么当前证据不够

单机自检只能证明：计数器语义自洽、发送未被吞、fail-open/fail-closed 路径可达、槽表溢出被计数。它**不能**证明 `setsockopt(IPPROTO_IP, IP_UNICAST_IF)` 对 **limited broadcast（255.255.255.255）** 真的生效。原因有三：

1. Windows 本机把 `255.255.255.255` 广播发出后**不回环**到本机绑 `0.0.0.0` 的 socket（2026-11-18 实测：agent 绑 `0.0.0.0` 观测本机广播 `seen=0`，单播对照 `seen=100`），所以本机无法观测出站广播落在哪个接口；
2. `Get-Counter "\Network Interface(*)\Packets Sent/sec"` 对 Radmin / ZeroTier 等虚拟接口不可靠（设计 §3.3 已记录）；
3. `pktmon` 需要管理员，且当前会话非提权。

`setsockopt` 返回 0 只代表"参数被接受"，不代表"选项对广播路径生效"——这正是本操作单要判定的事。

---

## §1 判据设计：用「接收端看到的源 IP」代替计数器

这是本操作单的核心。**不依赖任何计数器或抓包工具**，只看对端日志里的源地址：

- 两台机各有两个可用接口：WLAN（192.168.31.0/24 段）与 Radmin VPN（26.x.x.x 段）；
- 台机 B 的默认广播出口由 InterfaceMetric 决定（当前 metric：B Radmin=200、WLAN=40 → **默认走 WLAN**）；
- 因此把 B 的发现广播**钉到 Radmin**（非默认、metric 更大的接口）后：
  - 若 `IP_UNICAST_IF` **生效** → A 侧收到的发现包源地址 = `26.187.101.177`（B 的 Radmin IP）；
  - 若 `IP_UNICAST_IF` **不生效** → A 侧收到的包源地址 = `192.168.31.214`（B 的 WLAN IP）。

源地址是**二值可判的硬证据**，不需要容忍抖动、不需要管理员、不需要抓包。

> 注意方向：本测试是 B → A 的**发现广播**，走 UDP `255.255.255.255:62900-62999`。A 侧只需要用 agent 的 LAN 模拟监听（`--sim-lan-listen`）把收到的 magic 包连同源地址记进 summary，即可读出判据。

---

## §2 前置检查（两台机都要）

| 检查项 | 命令 | 期望 |
|---|---|---|
| 两台机都在线且同 WLAN | A 上 `Test-Connection 192.168.31.214 -Count 2` | True |
| A 的接口与 metric | `Get-NetIPInterface -AddressFamily IPv4 \| Where-Object {$_.InterfaceAlias -in 'WLAN','Radmin VPN'} \| Select InterfaceAlias,InterfaceMetric` | WLAN=45、Radmin=200 |
| B 的接口与 metric | 同上（B 上执行） | WLAN=40、Radmin=200 |
| A 防火墙允许 agent 入站 | agent 路径下的 Allow 规则覆盖 Private 与 Public | 见 M0B 操作单 §前置 |
| A 的 62900-62999 空闲 | 无游戏运行时 `Get-NetUDPEndpoint -LocalPort 62900` 应为空 | 空 |

metric 若与上表不同，**不要**去改它——先记录实际值，判据里的"默认走哪个接口"按实际值重新推断即可。

---

## §3 A 机步骤（接收端 + 观测）

```powershell
cd C:\Users\dd\Desktop\civlink-f1
.\civlink-agent.exe --sim-lan-listen 0.0.0.0 --simulate .\fixture-reply-set `
  --listen-seconds 600 --out-dir .\c2-cross-a-<时间戳> --stop-file .\c2-cross-a-<时间戳>\STOP
```

要点：
- `--sim-lan-listen 0.0.0.0` 绑全部 100 个发现端口，**同时监听所有接口**（WLAN + Radmin），所以无论 B 从哪个接口发来都能收到；
- **不要**加 `--reserve-62900`——本测试不需要游戏参与，且需要 62900 也能收包；
- agent 的 summary 与 `discovery-*.log` 会记录每个收到的 magic 包及其**源地址与源端口**，这就是判据来源。

启动后在 A 上记录开始时刻，然后等待 B 发包。

---

## §4 B 机步骤（三个对照轮，顺序不可换）

B 机上准备 `civlink_client.dll` 与 `civlink_ctl.exe`。**每轮之间必须重启游戏进程**（配置只在 DLL 初始化时读一次）。

### 轮 1：基准轮 `--iface ALL`（不干预）

```powershell
cd <B 上 civlink 目录>
.\civlink_ctl.exe inject-client -x CivilizationVI_DX12.exe --iface ALL
```

- 期望：`[+] interface selected: ALL (no pinning, let the routing table decide)`
- 进入游戏 → 局域网界面 → 点"刷新"
- **期望结果**：A 侧收到 magic 包，源地址 = `192.168.31.214`（WLAN，metric 更小者）

这一轮验证"不干预时确实走默认接口"，同时建立判据基线。

### 轮 2：定向轮 `--iface <B 的 Radmin IP>`（pin 到非默认接口）

```powershell
.\civlink_ctl.exe inject-client -x CivilizationVI_DX12.exe --iface 26.187.101.177
```

- 期望：`[+] interface selected: Radmin VPN (IfIndex=.. IfType=.. metric=200)`
- 判定：`[+] client iface config written: 26.187.101.177 -> ...`
- 重启游戏 → 局域网界面 → 刷新
- **关键判据**：
  - **生效** → A 收到的是源地址 `26.187.101.177` 的包（且 A 侧 RADMIN 接口收到）
  - **不生效** → A 收到的是源地址 `192.168.31.214`（与轮 1 相同）

### 轮 3：反向对照 `--iface <B 的 WLAN IP>`（pin 到默认接口，应无变化）

```powershell
.\civlink_ctl.exe inject-client -x CivilizationVI_DX12.exe --iface 192.168.31.214
```

- 期望：源地址仍是 `192.168.31.214`；`sendFail` 应为 0
- 作用：证明"设成默认值时不引入副作用"

**三轮对比的判读表**：

| 轮 1（ALL） | 轮 2（pin Radmin） | 结论 |
|---|---|---|
| 源 192.168.31.214 | 源 **26.187.101.177** | **IP_UNICAST_IF 对广播生效** → C2 方案 B 成立，不需要方案 C |
| 源 192.168.31.214 | 源 192.168.31.214 | **不生效** → 必须启用方案 C（广播复制转发兜底） |
| 收不到包 | 收到 26.187.101.177 | 说明不干预时默认接口出口本身被阻断，需先排查基础连通性 |

---

## §5 证据采集与归档

每轮结束后：

1. **A 侧**：读取 agent summary 与发现日志，提取「源 IP : 源端口 → magic」行；
2. **B 侧**：`civlink_ctl.exe counters -x CivilizationVI_DX12.exe` 记录 `sent` / `sendFail` / `ignoredNonDiscovery`（用于交叉核对"B 认为发了多少"）；
3. **B 侧**：保存 `%LOCALAPPDATA%\CivLink\client-iface.txt` 的内容副本；
4. 归档到 `M0A\captures\C2-crossmachine-<时间戳>\`，每轮一个子目录（`round1-all/`、`round2-pin-radmin/`、`round3-pin-wlan/`），附 `README.txt` 写清每轮的 `--iface` 实参与 `counters` 读数。

**证据纪律**：即使三轮全部符合期望，也只证明"发现广播的出接口被改变"——**不证明**双人可加入对局、不证明 62056 数据面可达、不勾 E2-A/E2-B/E3、不移动 Gate A/B。

---

## §6 若判定"不生效"（方案 C 触发条件）

若轮 2 的源地址与轮 1 相同，按设计 §3.4 启用方案 C：对发现目标**复制**一份原广播并从定向网卡再发一次（不篡改原包、不吞原发送）。实施前需重新审计，因为它突破了"只读纪律"（新增一次发送），必须明确：

- 复制仅限**发现目标**（dst 端口 62900-62999 或 255.255.255.255），绝不复用 62056；
- 原发送的返回值与 last error 必须原样返回给游戏；
- 新增计数器区分"原始发送"与"复制发送"，便于对账。

---

## §7 本轮待办的边界说明

- PC-B 于 2026-11-18 09:15 实测离线（`Test-Connection 192.168.31.214` 返回 False），本操作单**尚未执行**；
- 真实《文明6》进程内的 `civlink_client.dll` 注入路径**至今一次都没成功执行过**（ctl 的三个用例都止于"目标进程不存在"或 `OpenProcess failed err=5` 分支），因此连"能不能注入进游戏"都还未验证；
- 在这两项完成之前，C2 **不得**表述为"已验证"，也不得据此关闭 E2-A/E2-B/E3。
