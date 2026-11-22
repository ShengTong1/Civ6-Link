# REV-009 执行前置核查：条件 5 未通过（未执行 apply）

- 日期：2026-11-12
- 对象：`set-broadcast-path.ps1` v3.3（`206808649AC0F29AC50523E2B7A358B5CD2F0051B091CE8ACBEDAD8FDAC64CCA`）、新增 `rev009-roundtrip.ps1`（`B402DB3C7BF6E593149E3450910AFD02C2D5BE2A5EDC659559445B737EFC2055`）
- 结论：**条件 1/4 已满足，条件 5 未通过 → 不执行 apply**。真实往返仍为未执行状态。

## 1. 条件 1（修正过时文本）已完成

| 位置 | 修正前 | 修正后 |
|---|---|---|
| restore 成功摘要 | `AutomaticMetric == orig` | `AutomaticMetric in {orig,Disabled}` |
| 运行 banner | `(v3)` | `(v3.3)` + `Script SHA : <实际哈希>` |
| DryRun 计划 | 无 `raise` 行（回归缺陷） | `raise N interface(s) to metric M` + 逐行 `if= / old -> new` |
| restore 摘要 keep 行 | `if=`（空，作用域外引用 `$kIdx`） | `if=10`（改取 `$bak.keep.ifIndex`） |

`raise` 行缺失是此前为把 R-4 守卫前移而整段替换代码时误删的。条件 5 要求"计划恰为…"，依赖该输出，属必须修复项而非文本美化。

脚本身份：53 017 B / `206808649AC0F29AC50523E2B7A358B5CD2F0051B091CE8ACBEDAD8FDAC64CCA` / AST 0 错误 / 纯 LF / 单 BOM。

## 2. 条件 5 未通过：`26.187.101.177` 在 PC-A 上不解析到 Radmin

实测 DryRun（`-Action apply -PeerIp 26.187.101.177 -DryRun`）：

```
--- path to peer 26.187.101.177 ---
    if=10  WLAN   srcIp=192.168.31.59
[plan]
    keep   if=10 (WLAN) metric=45 auto=Disabled
    no competing interface has a metric <= the keep interface
    -> NOTHING TO DO. No backup will be written
```

计划并非"keep=if18 + raise if10/if15→2045"，而是 no-op。按条件 5「若 route/接口/任一数值不符，停止」。

### 2.1 排查：不是路由表问题

| 检查 | 结果 |
|---|---|
| `Get-NetRoute -PolicyStore All` 匹配 `26.187*` | 无 |
| `PersistentStore` 路由 | 只有 `0.0.0.0/0 → if18 26.0.0.1` |
| `route print -4` 含 `26.187` | 无 |
| 注册表任意值含该地址 | 无（递归三层扫描 HKLM Services / HKCU Software） |
| `Get-NetCompartment` | 只有默认 compartment |
| neighbor 项 | `if18  Incomplete  00-00-00-00-00-00` |
| 删除该 neighbor 后复测 | 仍判 if10（无关） |
| 静态路由表本身 | `26.0.0.0/8 → if18 on-link`，正确 |

### 2.2 定位：Windows IPv4 目标缓存（destination cache）被污染

```
netsh interface ipv4 show destinationcache

Interface 10: WLAN
1500 26.187.101.177   192.168.31.1      <-- 陈旧条目，下一跳是 WLAN 网关
1500 26.187.101.178   26.187.101.178    <-- 相邻地址条目正确（on-link）
```

`GetBestInterface`（iphlpapi）佐证：`26.187.101.177 → if10`，而 `26.187.101.170/176/178/200`、`26.1.2.3`、`26.186.1.1`、`26.255.255.254` **全部 → if18**。即只有这一个地址被钉到 WLAN。

`netsh interface ipv4 delete destinationcache` 返回 `rc=1`「需要提升权限」，**未执行**。

这是缓存层污染，不是配置错误；重启或清缓存应可消除，但两者都需要管理员操作，且清缓存本身即刻改变系统状态，超出"只读前置核查"的范围。

## 3. 唯一满足夹具的 peer 是 `26.74.126.98`

```
[plan]
    keep   if=18 (Radmin VPN) metric=1045 auto=Disabled
    skip   1 interface(s) that carry no broadcast (loopback) - never touched: if=1
    raise  2 interface(s) to metric 2045:
             if=10  WLAN      45    -> 2045
             if=15  ZeroTier  1045  -> 2045
```

与条件 5 逐项一致。但它是 **PC-A 自己的 Radmin 地址**：脚本匹配到它，是因为该地址的 `/32` 本地路由比 `/8` 更具体，语义上不构成"到对端的路径"。是否满足授权应由审批方判断，执行端不自行认定。

## 4. 已交付的执行编排器（用于条件 2/3/6/7 机械化）

`CivLink-M0A-audit\scripts\rev009-roundtrip.ps1`（18 696 B，AST 0 错误）+ GBK 启动器 `RUN-REV009-roundtrip.cmd`（1 243 B，纯 ASCII 正文，需输入 `YES` 确认才提权）。

它把七条前置条件做成硬闸门，默认 dry：

| 阶段 | 检查 | 不符时 |
|---|---|---|
| 身份 | 打印 helper SHA、自身 SHA、时间、主机 | — |
| 条件 2 | 无 `CivilizationVI*` 进程；无 `PktMon/dumpcap/tshark` | exit 3 |
| 条件 3 | 独立 BackupDir + 归档 `Get-NetIPInterface`/路由/`route print`/helper `snapshot` | — |
| 夹具 | 六个接口 metric/Auto 逐项等于 REV-009 表 | exit 3（可 `-AllowStateDrift` 覆盖，仅记录） |
| 条件 4/5 | DryRun 必须含 `keep if=18`、`raise … to metric 2045`、raise 数=2、含 if10 与 if15，且**不得**是 `NOTHING TO DO` | exit 3 |
| 条件 6 | apply 前复查状态未漂移、BackupDir 无未还原备份；apply 后查 exit/schema=4/sidecar 哈希/逐接口 readback | exit 4 或 6 |
| 条件 6b | restore 走**明确备份路径**；readback 必须逐接口等于 baseline；`.restored.json` 必须存在 | exit 5 或 6 |
| 条件 7 | 任一失败立即停止，不做第二次 apply | exit 3/4/5/6 |

dry 实测（`-PeerIp 26.74.126.98`，未执行 apply）：

```
--- precondition 2: the window is clean ---
  [OK]   no Civilization VI process
  [OK]   no capture tool active
--- precondition 3: archive the pre-apply baseline ---
  [OK]   baseline archived; helper snapshot exit=0
  [OK]   live state matches the REV-009 fixture exactly
--- precondition 4/5: read-only DryRun must match the fixture plan ---
  [OK]   plan matches: keep if=18, raise if=10/15 -> 2045
```

反向用例（证明闸门真的会挡）：

- `-PeerIp 26.187.101.177` → `exit 3`，报 4 条不符（keep 不是 if18 / 未 raise 到 2045 / 缺 if15 / 是 NOTHING TO DO），未创建任何备份。
- `-PeerIp 26.74.126.98 -Execute`（无提权）→ `exit 1`，`real changes need an elevated PowerShell`。

## 5. 归档

- `M0A\captures\REV-009-roundtrip-20261112-210904\`：`baseline-interfaces.csv`(481 B)、`baseline-GetNetIPInterface.txt`(1 265 B)、`baseline-GetNetRoute.txt`(2 973 B)、`baseline-route-print.txt`(3 783 B)、`baseline-snapshot.txt`(1 397 B)、`stage1-dryrun.txt`(1 892 B)、`stage2-NOT-EXECUTED.txt`(70 B)
- `M0A\captures\REV-009-textfix-20261112\raw-regression.txt`（14 138 B / `304ED03EDB6B30811D1FFBFE2C65E7D72B85EF3A7BAADEA4E9333DF5311DD310`）8 组用例

## 6. 待决断

1. **peer 选择**：
   - (a) 授权使用 `26.74.126.98`（本机 Radmin 地址，夹具完全匹配，可立即执行真实往返）
   - (b) 先以管理员清 `destinationcache`（或重启）后复测 `26.187.101.177`，若通过再用它
2. 若选 (a)，确认测试窗口；执行端将运行 `rev009-roundtrip.ps1 -PeerIp 26.74.126.98 -Execute` 并归档全部原始输出。

## 7. 门禁

Gate A 未批准；M0-B 冻结；E4/H7/H11 缺第三台真实机器；E5 缺 Win64EOS 构建。真实 apply→restore 未执行。v3.3 未同步 PC-B。
