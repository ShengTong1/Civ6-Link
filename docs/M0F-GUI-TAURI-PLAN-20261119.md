# M0F：GUI 迁移到 Tauri 2.x（2026-11-19）

## 1. 背景与动机
- 现有 WinForms GUI（civlink_tray.exe，C#）虽功能完备（5 标签页、40 条自检），但用户两轮反馈「太丑、字体看不清」。
- 用户选择 Tauri：Rust 内核 + Web 前端，界面现代、体积小（~10MB）、与 agent 同 Rust 生态、适合开源产品形态。
- 本迁移只重做 **前端壳**，联机引擎（agent/hook/ctl/relay）零改动。

## 2. 环境事实（2026-11-19 实测）
- rustc/cargo 1.99.1（x86_64-pc-windows-msvc）
- Node v24.21.0 + npm 11.19.0
- WebView2 运行时 157.0.4341.60 已装（Tauri Windows 必需）
- cargo-tauri CLI 未装 → `cargo install tauri-cli --locked`（需网络）
- crates.io / npmjs 可达（tauri 2.12.7 max stable）
- **网络纪律变更**：agent 本体仍保持 Cargo.toml 零依赖 + `--offline`；Tauri GUI crate 是独立项目，允许在线拉依赖（用户知情）

## 3. 架构设计
```
civlink/gui-tauri/
├── src/                    # Web 前端（vanilla TS，无重型框架）
│   ├── index.html
│   ├── main.ts
│   └── style.css           # 现代深色主题（沿用 v3 色板并升级）
├── src-tauri/
│   ├── Cargo.toml          # tauri 2.x + tauri-plugin-shell
│   ├── tauri.conf.json     # 窗口 820×600、productName civlink-gui
│   ├── capabilities/       # 权限：shell execute（白名单 ctl/agent）
│   └── src/
│       ├── main.rs
│       └── lib.rs          # invoke handlers
└── package.json            # @tauri-apps/cli
```

### 后端职责（Rust，src-tauri）
- `run_ctl(cmd, args)` → `Command::new(ctl_path).args(...)`，收集 exit code + stdout + stderr 返回给前端（与 CtlRunner 语义对齐）
- `start_agent(args)` / `stop_agent()` → agent 子进程管理（stop-file 纪律）
- `list_processes()` → 枚举白名单进程（与 WinForms Whitelist 一致）
- `list_ifaces()` → 本机 IPv4 列表
- `save_diag(text)` → 诊断导出（UTF-8 无 BOM，room 字段脱敏逻辑在前端 TS 复刻 Redactor 规则）
- **安全**：ctl/agent 路径解析为 exe 同目录（`AppDomain.BaseDirectory` 等价=tauri exe 同目录），白名单进程名校验在后端做，前端传参仅限枚举值

### 前端职责（vanilla TS，不用 React/Vue——零构建依赖膨胀）
- 5 个标签页：注入向导 / 状态 / 计数 / 设置 / 诊断（功能对齐 WinForms 版）
- 现代深色主题：CSS variables、卡片布局、圆角、无 3D 边框、等宽日志区
- 调用后端：`import { invoke } from '@tauri-apps/api/core'`

### 权限模型（Tauri 2 capability）
- `capabilities/default.json`：仅开放 `shell:allow-execute`（白名单两个 exe 名）、`core:event:default`
- 不开放 fs 写（除诊断导出用 dialog 插件）

## 4. 功能对齐清单（与 WinForms 版语义 1:1）
| WinForms 功能 | Tauri 对应 | 状态 |
|---|---|---|
| 注入向导（角色/进程/模块/iface/lanIp/realRoom） | 同 6 控件，角色默认 A | ☐ |
| 刷新进程（白名单 3 名） | list_processes | ☐ |
| 执行注入（ctl inject / inject-client） | run_ctl | ☐ |
| 查询状态（ctl status） | run_ctl | ☐ |
| 读取计数（ctl counters） | run_ctl | ☐ |
| 启动/停止 agent（stop-file 纪律） | start_agent/stop_agent | ☐ |
| 诊断导出（脱敏 + UTF-8 无 BOM） | save_diag（前端 Redactor 复刻） | ☐ |
| Boundary 文案（双人验证未完成/Gate A 未批准） | 常量注入前端 | ☐ |
| 零遥测/零日志/asInvoker | Tauri 默认无遥测；tauri.conf 不加任何 plugin | ☐ |

## 5. 验收标准
- `cargo tauri build` 产出单 exe + WebView2 依赖（系统已装）
- 前端 5 页可交互，全部 invoke 通路打通
- 诊断导出文件与 WinForms 版脱敏规则等价（用同一批自检样本比对）
- exe 体积 < 15MB
- 零网络行为（构建后运行时）

## 6. 边界
- 本迁移不改变联机引擎与既有验收结论；机械证据≠双人验证；不勾 E2/Gate A
- WinForms 版（v3）保留不删，作为 fallback 与历史证据

## 7. 执行记录
- （待填：cargo install tauri-cli 耗时、init 脚手架、构建时长、最终 exe 体积）
