# CIVINJECT 版本统一修正 — 独立审计报告

- **审计时间**：2026-11-15 11:16（Asia/Shanghai）
- **审计角色**：civlink 项目独立审计官（子代理，只读审计；除本报告外未修改任何文件）
- **审计对象**：`civinject.exe` 版本统一修正（三处二进制统一为源码树 54627EAB，旧版备份 .bak-4DCC9557，文档哈希同步）
- **工作目录**：`C:\Users\dd\Desktop\injciv6-v0.3.3`
- **方法**：对全部二进制独立重算 SHA256（Get-FileHash）与字节数，独立核对文档内容（Select-String），并追加 PE 头与字节级差分核验

---

## 一、逐项审计结果

### 1. civinject.exe 三处一致性 — **PASS**

期望值：171,520 字节，SHA256 `54627EABB15E203DE6112C8908B74E0714F0B8FA04567E2298B395534A700DF6`

| 位置 | 字节数 | SHA256 | mtime |
|---|---|---|---|
| `CivLink-M0A-audit\civtrace\civinject.exe` | 171,520 | 54627EAB…A700DF6 ✓ | 2026-11-13 14:27:04 |
| `C:\Users\dd\Desktop\civlink-run\civinject.exe` | 171,520 | 54627EAB…A700DF6 ✓ | 2026-11-13 14:27:04 |
| `M0A\pcb-kit\civinject.exe` | 171,520 | 54627EAB…A700DF6 ✓ | 2026-11-13 14:27:04 |

三处字节数与 SHA256 完全一致，且与源码树重建版逐字节相同；三处 mtime 均保留源码树构建时间 2026-11-13 14:27:04（拷贝未破坏时间戳）。

### 2. 旧版备份存在性 — **PASS**

期望：两处 `.bak-4DCC9557` 存在，哈希前缀 8 位 `4DCC9557`

| 备份文件 | 字节数 | SHA256（全值，前缀核对） | mtime |
|---|---|---|---|
| `C:\Users\dd\Desktop\civlink-run\civinject.exe.bak-4DCC9557` | 171,520 | `4DCC9557`8A5E0D85F0F6D4BA3C5EBED24CA0EE34D5EBF50A80F70C7FAA99EC72 ✓ | 2026-11-11 11:44:58 |
| `M0A\pcb-kit\civinject.exe.bak-4DCC9557` | 171,520 | `4DCC9557`8A5E0D85F0F6D4BA3C5EBED24CA0EE34D5EBF50A80F70C7FAA99EC72 ✓ | 2026-11-11 11:44:58 |

两处备份均存在，全哈希一致（相互也相同），前缀 8 位均为 `4DCC9557`；mtime 保留旧版构建时间 2026-11-11 11:44:58。

### 3. civtrace.dll 三处一致性（确认未被破坏） — **PASS**

期望值：246,272 字节，SHA256 `19196FF7A6CE36AD49C00AF7FCA74EFDE868F87A6BFB49BAB342F4CADF4BFEDE`

| 位置 | 字节数 | SHA256 |
|---|---|---|
| `CivLink-M0A-audit\civtrace\civtrace.dll` | 246,272 | 19196FF7…F4BFEDE ✓ |
| `C:\Users\dd\Desktop\civlink-run\civtrace.dll` | 246,272 | 19196FF7…F4BFEDE ✓ |
| `M0A\pcb-kit\civtrace.dll` | 246,272 | 19196FF7…F4BFEDE ✓ |

该件本次未动，三处仍一致，未被版本统一操作破坏。

### 4. MANIFEST-sha256.txt — **PASS**

- 文件：`M0A\pcb-kit\MANIFEST-sha256.txt`，实际 2,198 字节 = 期望 2,198B ✓
- `civinject.exe` 行：`54627EABB15E203DE6112C8908B74E0714F0B8FA04567E2298B395534A700DF6  civinject.exe` ✓
- `civtrace.dll` 行：`19196FF7A6CE36AD49C00AF7FCA74EFDE868F87A6BFB49BAB342F4CADF4BFEDE  civtrace.dll` ✓
- 旧值残留：`4DCC9557` 命中 0 次 ✓
- 备份文件行：清单中**无任何 .bak 条目**（既无旧值、也未登记备份文件）。按审计口径，备份条目"如有注明 .bak 亦可接受"——此处是**无备份条目**，属允许情形，如实说明：清单未对备份文件作登记，不影响一致性。

### 5. E2B-EXECUTION-PACK.md §1 — **PASS**

- 文件：`CivLink-M0A-audit\docs\E2B-EXECUTION-PACK.md`，实际 12,315 字节 = 期望约 12,315B ✓
- §1 表（第 28–29 行）：
  - 第 28 行 `civtrace.dll`（v0.4.4）：`19196FF7…F4BFEDE` / 246272 ✓
  - 第 29 行 `civinject.exe`（v0.4.4，2026-11-13 重建）：`54627EAB…A700DF6` / 171520 ✓（非 4DCC9557）
- 旧值残留：全文 `4DCC9557` 命中 0 次 ✓
- 附：文档第 33 行声明"两端都必须用上表同哈希…哈希不一致 = 本轮作废"，与修正目标一致；第 54–59 行同步脚本以源码树 `civtrace` 为唯一来源，与"以源码树为准"的授权口径一致。

### 6. 代码一致性说明（mtime 核验） — **PASS**（含 1 条信息级说明）

期望：`trace_dll.cpp` 75,055B、`injector.cpp` 25,303B，mtime 均为 2026-11-11

| 文件 | 字节数 | mtime |
|---|---|---|
| `CivLink-M0A-audit\civtrace\trace_dll.cpp` | 75,055 ✓ | 2026-11-11 11:44:33 ✓ |
| `CivLink-M0A-audit\civtrace\injector.cpp` | 25,303 ✓ | 2026-11-11 11:42:07 ✓ |

两个源文件 mtime 均早于重建版构建时间 2026-11-13 14:27:04，即 11-13 重建未改动源码，与"两版仅构建时间戳不同"的说法一致。

---

## 二、追加核验（超出清单，加强结论）

- **PE COFF 时间戳**：新版 `0x6AF6ADB8`（= 2026-11-13 14:27:04，与 mtime 逐秒吻合），旧版 `0x6AF3E4BA`（= 2026-11-11 11:44:58，与 mtime 逐秒吻合）。
- **字节级差分**（新 54627EAB vs 旧 4DCC9557，各 171,520B）：全文件仅 **6 字节**不同，即同一 4 字节时间戳值在 PE 头偏移 0xF8 与文件偏移 0x24194 两处各出现一次、低 3 字节不同（高字节 0x6A 相同故未计入差异）。其余字节逐位全同。
- **结论**：字节级证明两版二进制**除构建时间戳外完全一致**，"功能等价仅构建时间戳不同"的说法成立（严格功能等价由字节一致性+同源构建支撑，PE 层面无其他差异）。

---

## 三、缺陷分级清单

| 级别 | 编号 | 说明 |
|---|---|---|
| 阻断 | — | 无 |
| 高 | — | 无 |
| 中 | — | 无 |
| 低 | — | 无 |
| 信息 | I-1 | 审计任务书中第 6 项写"civtrace\src 下"，但源文件实际位于 `civtrace\` 根目录（无 src 子目录）。系审计描述偏差，非修正工作缺陷。 |
| 信息 | I-2 | MANIFEST 未登记 `.bak-4DCC9557` 备份文件条目（无旧值残留、无备份行）。允许情形，建议后续可在 MANIFEST 补充备份条目以便追踪。 |

---

## 四、必改项清单

**无**（0 项）。修正工作全部落实到位，无需任何返工。

---

## 五、最终裁定

# ✅ 通过（PASS）

- 6/6 审计项 PASS；无阻断/高/中/低缺陷；必改项为空。
- 三处 civinject.exe 已统一为源码树重建版 54627EAB（171,520B，2026-11-13 14:27:04），旧版 4DCC9557 备份双处齐全且哈希前缀核对无误。
- civtrace.dll 三处保持 19196FF7 一致，未被破坏。
- MANIFEST-sha256.txt（2,198B）与 E2B-EXECUTION-PACK.md（12,315B）哈希行均已同步为新值，全文无 4DCC9557 残留。
- E2 双机验证可直接使用当前三处二进制，无需再做任何版本修正动作。

（审计官注：以上全部结论由本次会话独立重算得出；审计过程只读，除本报告外未改动任何文件。）
