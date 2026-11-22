# REV-010 执行报告：定向删除 destination cache 的结果，及机制重新判定

- 日期：2026-11-12 21:35 (+08:00)
- 主机：DESKTOP-E9ERP1I（PC-A）
- 授权依据：REV-010 单项清理授权 + REV-011 §2（只批准单条 destination-cache 删除与只读复测）
- 结论：**清理已按授权执行并成功（rc=0），但 DryRun 仍未匹配夹具；且机制判定被推翻——这不是缓存污染，而是邻居不可达导致的 on-link 路由回退。条件 5 在字面形式下不可达，需审批方重新裁定。**

## 1. 已执行动作（严格限于授权范围）

| 项 | 内容 |
|---|---|
| 执行命令 | `netsh interface ipv4 delete destinationcache interface=10 address=26.187.101.177` |
| 执行方式 | 自提权（UAC 由本机用户点击确认），`scripts\rev010-apply.ps1` |
| 返回码 | `rc=0`，控制台输出「确定。」 |
| 范围 | 仅 if10、仅该单一目的地址；**未做全表清理** |
| 静态/持久路由 | 未修改 |
| `Set-NetIPInterface` | **全程未调用** |
| 网卡现值 | if10 `45 / Disabled`、if18 `1045 / Disabled`、if15 `1045 / Disabled`（与执行前一致） |
| 备份目录 | `C:\Users\dd\civlink-metric-backups-rev009` 仍为 0 文件 |

## 2. 清理后的只读复测（未匹配夹具）

```
Find-NetRoute 26.187.101.177
  IPAddress      : 192.168.31.59
  InterfaceIndex : 10
  InterfaceAlias : WLAN

helper -Action status  -PeerIp 26.187.101.177   -> exit 0
  [OK] predicted broadcast exit (if=10) EQUALS peer path (if=10)

helper -Action apply -PeerIp 26.187.101.177 -DryRun   -> exit 0
  [plan]
      keep   if=10 (WLAN) metric=45 auto=Disabled
      no competing interface has a metric <= the keep interface
      -> NOTHING TO DO. No backup will be written
```

`keep=if10`、空改动集，**不满足 REV-009 条件 5**。按条件 5「任一不符即停」，未调用 apply。

## 3. 机制判定被推翻（本次最重要的结论）

先前把 `26.187.101.177` 解析到 if10 归因为「Windows destination cache 污染」。清理成功后现象不变，说明该归因不成立。随后做了两组对照，机制已确定：

### 3.1 从未访问过的新地址同样会翻转

探针地址 `26.187.101.190`，此前无任何缓存条目（neighbor=`Unreachable`）：

| 时刻 | 路由判定 | 邻居状态 |
|---|---|---|
| initial | `if18 on-link nextHop=0.0.0.0` | Unreachable |
| ping #1 期间 | `if18 on-link` | Incomplete，100% loss |
| ping #1 后 0.7s | `if18 on-link` | Incomplete |
| ping #2 期间 | `if18 on-link` | Incomplete |
| **ping #2 后 0.7s** | **`if10 DEFAULT-GW nextHop=192.168.31.1`** | Incomplete |
| ping #3 | `if10 DEFAULT-GW`（保持） | Incomplete |

翻转发生在邻居解析**持续失败之后**，而非首次发包。

### 3.2 控制组不翻转

| 地址 | 条件 | 连 ping 4 次后 |
|---|---|---|
| `26.197.96.55` | VM，ARP=`Stale` 且有真实 MAC | `if18 on-link`（不翻转） |
| `26.187.101.179` | 无应答但从未被探测 | `if18 on-link`（不翻转） |

### 3.3 结论

当 on-link 邻居的 ARP 解析持续失败（`Incomplete`）时，Windows IPv4 放弃该 `/8` on-link 路由，回落到次优路由——if10 WLAN 的默认网关 `192.168.31.1`。

这是**「邻居不可达 → 路由回退」**，不是缓存污染。删缓存后系统重新推导，结果相同（§1、§2 已实证）。

先前误判的原因是缺少两项对照：①从未访问过的新地址是否也翻转；②ARP 有应答的地址是否不翻转。

## 4. 对 REV-009 条件 5 的直接影响

只要 PC-B `26.187.101.177` 不回应 Radmin 二层 ARP，该地址就**必然**回落到 if10。因此针对它的 DryRun 永远得到 `keep=if10` + `NOTHING TO DO`。

**条件 5 在其字面形式下不可达**，且不是 helper 或编排器的缺陷。这与 REV-005 已记录的「Radmin 房间内 ARP Incomplete、隧道不通」是同一事实的两个侧面。

由此推论：REV-009 条件 5 设想的「用真实 PC-B 的 Radmin 地址做夹具匹配、验证 keep=if18」这一路线，在 Radmin 二层当前不通的条件下无法实现。

## 5. 待审批决定

1. 条件 5 是否改为**接受已知回退行为**：即以 `keep=if10`、空改动集记录为「Radmin 通路不通时的预期结果」，并把一次性往返改用其它可 ARP 应答的 peer（例如 PC-B 的 WLAN 地址 `192.168.31.214`，但该地址当前也是 `NOTHING TO DO`，同样无法产生非空改动集）。
2. 或明确：v3.3 的真实 apply→restore 往返**暂时无法在现有网络条件下执行**，等 Radmin 通路恢复或改用第三台机器后再说。
3. 无论选哪条，执行端不会自行放宽条件 5，也不会用 `26.74.126.98` 顶替 peer（REV-011 §5 第 4 条）。

## 6. 顺带记录：编排器代码缺陷已知未修

REV-011 §3 的 P1-1..P1-4（CMD 默认 peer 为本机地址、raise 断言未绑定计划行、snapshot 失败不阻断、失败路径谎称「没有改动」）**尚未修复**。按 REV-011 §5 第 2 条，修复前 `RUN-REV009-roundtrip.cmd` 不得用于真实执行。本报告未改动该编排器。

## 7. 门禁

Gate A 未批准；M0-B 冻结；E4/H7/H11 缺第三台真实机器；E5 缺 Win64EOS 构建。v3.3 未同步 PC-B。真实 apply→restore 未执行。
## 8. 附：交付物与哈希

| 文件 | 大小 | SHA256 |
|---|---:|---|
| `scripts\REV-010-EXECUTION-REPORT.md` | 本文件 | 自引用哈希不入表，定稿值见交付说明 |
| `scripts\rev010-mechanism-evidence.txt` | 2 942 B | `17AE45D7E3D9B8DD03EB016CB9C5561E243C887B76A33F93F968F5565E6E0DD8` |
| `scripts\rev010-dryrun.txt` | 3 221 B | `92511D96CD8F75CBF95437659B3162FB858E6B63CC0872F46F5987A5073DFEC4` |
| `scripts\rev010-apply.ps1` | 2 730 B | `4C709CC93FECF38D34DD699C6DA6C012B6A87F426CC10A2C392DB329C56FFE9D` |
| `scripts\RUN-REV010-cache-cleanup.cmd` | 714 B | `7593005931CC98EE23074164D5C7A71C3B7A2F42E2E1D74CEB79BE0A349A1A01` |

作废与清理：交互版 `rev010-cache-cleanup.ps1`（含 `Read-Host`，曾导致首次提权尝试挂起）已删除；`rev010-result.txt`（netsh GBK 输出被按 UTF-8 解码产生乱码）已删除；CMD 已改为指向非交互的 `rev010-apply.ps1`，并在 `rev010-apply.ps1` 顶部设置 `[Console]::OutputEncoding = GBK(936)` 以避免同类乱码。

说明：本次清理已由本机用户在 UAC 提示上确认并成功执行（rc=0）。上方哈希为报告定稿时的值；若后续再改报告，需重算。