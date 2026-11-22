# 日志与产物保存规范（LOGGING CONVENTION）

> 建立：2026-11-20（P0-D 仓库整理轮）。依据：`HANDOVER-TO-NEXT-AI-20261120.md` §2.4。
> 适用：`CivLink-M0A-audit` 仓库内的一切构建、自检、运行、证据产物。

## 1. 分类与去向（铁律）

| 类别 | 去向 | 说明 |
| --- | --- | --- |
| 构建日志 | `artifacts\build\YYYYMMDD-HHmmss-<target>.log` | 每次真实构建的完整 stderr/stdout，含目标名与时间戳 |
| 自检输出 | `civlink\<script>-out\` 或 `%TEMP%\pd-selftest-<HHmmss>` | 自检脚本生成的证据目录，不落仓库根 |
| 里程碑证据 | `M0A\captures\<milestone>-<date>\` | **只增不改**，目录内 README 说明本次捕获 |
| agent / GUI 运行 | `C:\Users\dd\Desktop\civlink-gui\agent-out\peer-<epoch>\` | 运行产物目录，**勿手工清空**（登记链依赖其哈希复核） |
| 已引用旧日志 | `docs\archive\` 下按事件建子目录 | 文档已登记哈希的日志，清理时**先 grep 再动**，移动后在此登记 |

## 2. 禁止项

- **仓库根目录禁止任何 `*.log`**（本轮已清除 15 个散落日志，见 §4 登记）。
- `M0A\captures\` 一律只增不改，不得删除、移动或改写其中任何文件。
- `civlink\` 根的 `civlink_hook.dll` / `civlink_client.dll` / `civlink_ctl.exe` / `civlink_ctl_gui.exe` / `hook_selftest.exe` / `client_selftest.exe` / `civlink-agent.exe` / `relay-civlink-relay.exe` / `wsaprobe.exe` 是 `build-msvc.cmd` 的**产物出口**与历史脚本套件的**运行入口**（`run-f1/f2/f3/c1/m0e-completion/f5*.ps1` 均以 `Join-Path $here 'civlink-agent.exe'` 引用），**不得删除**；新构建流程的 agent 用 `agent\target\release\civlink-agent.exe`。
- `deploy-b\` 是 PC-B 隧道投送目录（`python http.server` 工作目录），保留空目录。
- `fix-m0e-preflight*.ps1` / `run-m0e-preflight*.ps1` 各版本与 `run-f3*.ps1.bak-*` 已被审计文档登记哈希（`M0E-PREFLIGHT-20261119.md`、`F3A/F3B-REVIEW-*.md`），属审计证据，**保留原址不动**。

## 3. 处置规则

1. 任何清理动作前，先对目标文件名在 `README.md`、`docs\`、`M0A\captures\**`、`civlink\*.ps1`、`civlink\*.cmd` 内 **grep**。
2. 有引用 → 保留原址，或移 `docs\archive\<事件>\` 并在此文档登记（哈希+新路径）。
3. 无引用且属构建/运行产物（`.obj` `.lib` `.exp` `.log`、`pd-*` 运行目录、`agent-out` 等）→ 可清除；`.gitignore` 已覆盖的产物可放心清。
4. 不确定 → 保留，不强行清理。

## 4. 2026-11-20 P0-D 清理登记

| 动作 | 对象 | 结果 |
| --- | --- | --- |
| 删除 | 仓库根 15 个散落日志：`bd.log bd2.log bd3.log bd4.log bd5.log bfinal.log bfinal2.log bg.log bg2.log bg3.log gb.log gbuild.log gbuild2.log gbuild3.log pdsel.log` | 已删（grep 全树无引用；新规范禁止根目录 `*.log`） |
| 删除 | `civlink\`：`clean.log guibuild.log mut.log restore.log fakeip-selftest-run.log` | 已删（无引用） |
| 删除 | `civlink\`：`buffer.obj hde32.obj hde64.obj hook.obj trampoline.obj civlink_ctl.obj wsaprobe.obj civlink_client.exp civlink_client.lib civlink_hook.exp civlink_hook.lib` | 已删（build-msvc 中间产物，gitignore 覆盖） |
| 删除 | `civlink\pd-*` 12 个运行目录（`pd-filter-192_168_31_60` `pd-filter-26_74_126_98` `pd-filter-ALL` `pd-filter-test` `pd-live-a` `pd-live-a2` `pd-live-smoke` `pd-live-smoke2` `pd-local-grace` `pd-local-smoke` `pd-panel-smoke` `pd-verify-live`） | 已删（运行 scratch，gitignore 覆盖 `civlink/pd-*/`） |
| 移动并登记 | `build-hook-out.txt build-hook2-out.txt build-hook3-out.txt build-hook4-out.txt build-hook5-rebuild-20261117-1051.txt` → `docs\archive\build-hook-20261117\` | 见下表哈希（`B1-RUNBOOK-V4-REVIEW.md` 登记过 `build-hook4-out.txt` 哈希，故移动而非删除） |
| 新建 | `.gitignore`（仓库根） | 覆盖 `target/ obj/ *.obj *.lib *.exp *.pdb *.idb *.log agent-out/ userdata/ deploy-b/ civlink/pd-*/ civlink/*-selftest-out/ dist/*.zip` |
| 保留 | `deploy-b\`、`civlink\` 根 dll/exe、`fix/run-m0e-preflight*.ps1`、`run-f3*.bak-*` | 理由见 §2 |

移动文件哈希（sha256 前 8 位 / 字节数）：

| 文件名 | 新路径 | sha256 前缀 | 字节 |
| --- | --- | --- | --- |
| build-hook-out.txt | `docs\archive\build-hook-20261117\` | `12B22ECC` | 850 |
| build-hook2-out.txt | `docs\archive\build-hook-20261117\` | `37E6325D` | 720 |
| build-hook3-out.txt | `docs\archive\build-hook-20261117\` | `885EEE55` | 850 |
| build-hook4-out.txt | `docs\archive\build-hook-20261117\` | `DC34B999` | 850 |
| build-hook5-rebuild-20261117-1051.txt | `docs\archive\build-hook-20261117\` | `827DBC60` | 463 |

> 注：`B1-RUNBOOK-V4-REVIEW.md` 内记录的 `build-hook4-out.txt` 哈希为 `0965154A…`，与本次移动时重算的 `DC34B999…` 不同——文档记录的是当时（11-17 10:18:16 之后）的该文件哈希；本登记以移动当日实算值为准，路径已更新，旧哈希口径差异属既有 D-5 类文档口径问题，留待 P0-E 统一。
