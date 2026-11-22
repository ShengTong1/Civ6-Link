// CivLink GUI frontend glue (vanilla JS + window.__TAURI__ global).
const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const BOUNDARY_STATE = "双人验证未完成（Gate A 未批准）";
const BOUNDARY_MECH  = "机械动作完成 ≠ 双人真实联机";

// ---------- Redactor (parity with WinForms Redactor rules) ----------
function redact(input){
  if(!input) return input || "";
  let s = input;
  s = s.replace(/^(.*\b(room|room[_ ]?name|sim_room_name)\b.*[:=]\s*).+$/gim, "$1<redacted>");
  s = s.replace(/^.*simulated host.*$/gim, "<redacted simulated-host line>");
  s = s.replace(/\b(room(?:[_ ]?name)?|sim_room_name)\b[^\r\n]{0,80}/gi, "$1=<redacted>");
  s = s.replace(/([A-Z]:\\Users\\)[^\\\r\n]+/gi, "$1<user>");
  s = s.replace(/(CIVTRACE_TAG\s*=\s*)[^\r\n]+/gi, "$1<redacted>");
  return s;
}

// ---------- role-driven UI (A host / B client) ----------
function applyRole(){
  const isHost = document.getElementById("role").selectedIndex === 0;
  document.getElementById("clientonly").classList.toggle("hidden", isHost);
  document.getElementById("hostonly").classList.toggle("hidden", !isHost);
  // Discovery completion only makes sense on the host (the machine with the room).
  // On the client there is no local game room to replay into, so hide the whole row.
  document.getElementById("hostcompletion").classList.toggle("hidden", !isHost);
  updateAgentCtl();
}
function updateAgentCtl(){
  const isHost = document.getElementById("role").selectedIndex === 0;
  const on = isHost && document.getElementById("agentenable").checked;
  document.getElementById("agentctl").classList.toggle("hidden", !on);
}
document.getElementById("role").addEventListener("change", applyRole);
document.getElementById("agentenable").addEventListener("change", () => {
  updateAgentCtl();
  // Unchecking also cancels the room watch and stops a running completion agent,
  // so reverting needs no extra step.
  if (!document.getElementById("agentenable").checked){
    stopRoomWatch();
    if (agentRunning){
      invoke("stop_agent").then(ok => {
        if (ok){ agentRunning = false; log("injectlog", "发现补全已随勾选取消而停止。"); }
      }).catch(() => {});
    }
  } else {
    // Checking (even after inject already completed) arms the room watch, so the
    // checkbox alone is a complete enable switch - no re-inject and no manual button.
    startRoomWatch();
  }
});

// ---------- tabs ----------
document.querySelectorAll("nav#tabs button").forEach(btn => {
  btn.addEventListener("click", () => {
    document.querySelectorAll("nav#tabs button").forEach(b => b.classList.remove("active"));
    document.querySelectorAll(".tab").forEach(t => t.classList.remove("active"));
    btn.classList.add("active");
    document.getElementById("tab-" + btn.dataset.tab).classList.add("active");
    if (btn.dataset.tab === "peers") {
      // NIC pills are built once (on load / manual refresh); toggling them never
      // spawns powershell.exe. The result panel only refreshes for runs started
      // in THIS window session (newest_peer_live fallback is intentionally skipped).
      if (pdSessionStarted) refreshPdLive();
    }
  });
});

function log(id, text){ const p=document.getElementById(id); if(!p) return; p.textContent += text + "\n"; p.scrollTop = p.scrollHeight; }

// ---------- inject page ----------
async function refreshProcesses(){
  try {
    const list = await invoke("list_processes");
    const sel = document.getElementById("proc");
    sel.innerHTML = "";
    if(list.length === 0){
      const o = document.createElement("option");
      o.textContent = "(未发现白名单进程，请先启动《文明6》Steam Win64)";
      sel.appendChild(o);
    } else {
      list.forEach(p => { const o=document.createElement("option"); o.textContent=p; sel.appendChild(o); });
    }
    log("injectlog", "[refresh] " + (list.length ? list.join(", ") : "no whitelisted process"));
  } catch(e){ log("injectlog", "[refresh ERROR] " + e); }
}
document.getElementById("refresh").addEventListener("click", refreshProcesses);

async function refreshIfaces(){
  try {
    // Same inventory as the discovery NIC picker: IP + friendly name, sorted by
    // InterfaceMetric (high priority first). Keep option.value as the pure IP so
    // inject-client still passes a clean --iface; only the visible label gets the name.
    const list = await invoke("list_ifaces_named");
    const sel = document.getElementById("iface");
    sel.innerHTML = "";
    const all = document.createElement("option"); all.value="ALL"; all.textContent="ALL（全部网卡）"; sel.appendChild(all);
    list.forEach(n => {
      const o = document.createElement("option");
      o.value = n.ip;
      o.textContent = n.name ? `${n.ip}（${n.name}）` : n.ip;
      sel.appendChild(o);
    });
    sel.selectedIndex = 0;
  } catch(e){ log("injectlog", "[ifaces ERROR] " + e); }
}

document.getElementById("injectlog-clear").addEventListener("click", () => {
  const p = document.getElementById("injectlog");
  if (p) p.textContent = "";
});

document.getElementById("inject").addEventListener("click", async () => {
  const role = document.getElementById("role").selectedIndex; // 0=A,1=B
  const proc = document.getElementById("proc").value;
  const dll = (role === 0) ? "civlink_hook.dll" : "civlink_client.dll"; // role decides module (A host=hook, B client=NIC-pin)
  const iface = document.getElementById("iface").value;
  if(!proc || !proc.includes("#")){ log("injectlog","[!] 请先刷新并选择目标进程"); return; }
  const pid = proc.split("#")[1];
  const cmdName = (role === 1) ? "inject-client" : "inject";
  const args = ["-p", pid, "-d", dll, "-w", "20"];
  if(role === 1){
    args.push("--iface", iface);
  }
  log("injectlog", `[运行] civlink_ctl ${cmdName} ${args.join(" ")}`);
  try {
    const r = await invoke("run_ctl", { cmd: cmdName, args: args, timeoutMs: 25000 });
    const ok = (r.exit_code === 0);
    log("injectlog", `[退出码 ${r.exit_code}] ` + (r.stdout || "") + (r.stderr ? " [stderr] " + r.stderr : ""));
    if(r.timed_out) log("injectlog", "[!] 操作超时");
    // Chinese verdict line always present (success or failure)
    if(ok){
      if (role === 0) {
        log("injectlog", "【注入成功】钩子已激活（civlink_hook.dll），现在可以回到游戏建房。");
        if (document.getElementById("agentenable").checked){
          log("injectlog", "发现补全已勾选：已开启智能补全，检测到游戏房间（UDP 62900）后会自动启动，无需再点按钮。");
          startRoomWatch();
        }
      } else {
        log("injectlog", "【注入成功】客户端网卡定向已生效（civlink_client.dll）。");
      }
    } else {
      const reason = (r.stderr || r.stdout || "").includes("not found") ? "目标进程里没有找到模块（可能还没注入过，或路径不对）"
                   : (r.exit_code === 2) ? "没有找到目标进程（请先刷新进程列表）"
                   : (r.exit_code === 3) ? "模块未加载成功"
                   : (r.exit_code === 4) ? "远程调用失败"
                   : (r.exit_code === 5) ? "状态未到达（钩子初始化未完成）"
                   : "未知错误（详情见上方日志）";
      log("injectlog", `【注入失败】${reason}`);
    }
  } catch(e){ log("injectlog", `【注入失败】${e}`); }
});

// ---------- uninject (shutdown) ----------
document.getElementById("uninject").addEventListener("click", async () => {
  const proc = document.getElementById("proc").value;
  if(!proc || !proc.includes("#")){ log("injectlog","[!] 请先刷新并选择目标进程"); return; }
  const pid = proc.split("#")[1];
  log("injectlog", `[运行] civlink_ctl shutdown -p ${pid}`);
  try {
    const r = await invoke("run_ctl", { cmd: "shutdown", args: ["-p", pid], timeoutMs: 20000 });
    log("injectlog", `[退出码 ${r.exit_code}] ` + (r.stdout || ""));
    if(r.exit_code === 0){
      stopRoomWatch();
      if (agentRunning){
        try { await invoke("stop_agent"); log("injectlog", "发现补全已一并停止。"); }
        catch(e){ log("injectlog", "[agent stop ERROR] " + e); }
        agentRunning = false;
      }
      log("injectlog", "【卸载成功】钩子已安全关闭，日志已刷盘（模块按审计运行模式保留在进程中，不影响游戏）。");
    }
    else if(r.exit_code === 1) log("injectlog", "【卸载跳过】钩子本来就没有运行。");
    else log("injectlog", "【卸载失败】请查看上方日志。");
  } catch(e){ log("injectlog", `【卸载失败】${e}`); }
});

// ---------- status / counters (now embedded in diagnostics export) ----------
// The standalone status/counters tab was merged into the "关于" page's diagnostic
// export, which runs `civlink_ctl status` and `civlink_ctl counters` on demand.

// ---------- agent start/stop (发现补全, optional on host) ----------
// Smart completion (方案A): once host injection succeeds with the checkbox on, the GUI
// watches for the game room (UDP 62900) and auto-starts the agent - no manual start
// click needed. Uninject (or unchecking) stops the watch and the agent, so the whole
// flow collapses to: 注入 -> 建房 -> 玩 -> 卸载注入.
function logBoth(text){ log("injectlog", text); }
let agentRunning = false;    // discovery-completion agent started by THIS window
let roomWatchTimer = null;
const GAME_HOST_PORT = 62900;
const ROOM_WATCH_MS = 2000;
const ROOM_WATCH_TRIES = 60; // 120 s window to detect the room

function stopRoomWatch(){
  if (roomWatchTimer){ clearInterval(roomWatchTimer); roomWatchTimer = null; }
}

async function startAgentCore(){
  // Server side always listens on the wildcard: binding a specific IP does NOT receive
  // limited broadcast 255.255.255.255 (measured 2026-11-20), so a selectable NIC is a
  // silent-failure trap. 62900 stays reserved for the game host.
  const args = ["--sim-lan-listen", "0.0.0.0", "--discovery-completion", "--reserve-62900", "--listen-seconds", "1800"];
  // Single agent slot: node discovery owns it while running, so refuse clearly instead
  // of letting start_agent fail with a bare "agent already running" (bugfix 2026-11-22).
  if (pdSessionStarted){
    logBoth("【提示】节点发现正在运行（单 Agent 槽）。请先到「节点发现」页停止广播，再启动发现补全。");
    return null;
  }
  try {
    const pid = await invoke("start_agent", { args: args });
    agentRunning = true;
    stopRoomWatch();
    logBoth(`【发现补全已启动】pid=${pid}（绑定 62901-62999，62900 留给游戏）`);
    return pid;
  } catch(e){ logBoth("[agent ERROR] " + e); return null; }
}

async function startRoomWatch(){
  stopRoomWatch();
  let tries = 0;
  roomWatchTimer = setInterval(async () => {
    tries++;
    let found = false;
    try { found = await invoke("udp_port_in_use", { port: GAME_HOST_PORT }); } catch (e) { /* keep polling */ }
    if (found && !agentRunning && !pdSessionStarted){
      stopRoomWatch();
      log("injectlog", "检测到游戏房间（UDP 62900）→ 自动启动发现补全…");
      await startAgentCore();
    } else if (tries >= ROOM_WATCH_TRIES){
      stopRoomWatch();
      log("injectlog", "120 秒内未检测到游戏房间（UDP 62900）：请先在游戏里建房，再重新勾选「启用」重试。");
    }
  }, ROOM_WATCH_MS);
}

// 2026-11-23: manual start/stop buttons removed by user request - completion is now
// fully automatic (checkbox = enable switch). No GUI entry to the agent slot here;
// re-toggling the checkbox re-arms the room watch. agentRunning is still cleared by
// the agent-exited event so state stays correct.
listen("agent-exited", (ev) => { agentRunning = false; logBoth(`【Agent 已退出】pid=${ev.payload}`); });

// ---------- 节点发现（peer discovery + path quality） ----------
// 2026-11-22: the two M5 warnings were removed by explicit project-lead instruction
// (m02344: "我以项目负责人的身份明确告诉你，去掉两条警告") - recorded as an authorized
// M5 change for the registration chain; they are no longer rendered in the GUI.
let pdChecked = new Set();       // survives refreshes
let pdSessionStarted = false;    // result panel only shows runs started in THIS window session
let pdAgentPid = null;           // pid of the node-discovery agent we started (to filter agent-exited)

// Result-panel errors surface in the phase badge (red).
function pdErr(text){
  const el = document.getElementById("pd-phase");
  if (!el) return;
  el.textContent = text;
  el.className = "phase err";
}
// Strip bracket/paren suffixes from Windows adapter names (e.g. "vEthernet (Default Switch)",
// "ZeroTier One [zt-abc]"); the row shows the clean name and the IP separately.
function pdCleanName(n){
  const s = String(n || "").replace(/\[[^\]]*\]|\([^)]*\)|（[^）]*）|【[^】]*】/g, "").replace(/\s+/g, " ").trim();
  return s || "(未命名网卡)";
}

let pdAllIps = [];   // current adapter list (drives the select-all / clear-all toggle)
function updateSelectAllBtn(){
  const btn = document.getElementById("pd-select-all");
  if (!btn) return;
  const allOn = pdAllIps.length > 0 && pdChecked.size === pdAllIps.length;
  btn.textContent = allOn ? "取消全选" : "全选";
}

async function refreshPdIfaces(verbose) {
  const box = document.getElementById("pd-ifaces");
  try {
    const list = await invoke("list_ifaces_named");   // [{ip,name,metric}] already sorted by metric asc
    pdAllIps = list.map(i => i.ip);
    // keep user's ticks, drop entries that disappeared
    const present = new Set(pdAllIps);
    pdChecked = new Set([...pdChecked].filter(ip => present.has(ip)));
    box.innerHTML = "";
    for (const it of list) {
      const on = pdChecked.has(it.ip);
      const nmTxt = pdCleanName(it.name);
      const row = document.createElement("button");
      row.type = "button";
      row.className = "iface-row" + (on ? " sel" : "");
      row.setAttribute("aria-pressed", on ? "true" : "false");
      row.dataset.ip = it.ip;
      row.title = nmTxt + " · " + it.ip;
      const nm = document.createElement("span"); nm.className = "nm"; nm.textContent = nmTxt;
      const ip = document.createElement("span"); ip.className = "ip"; ip.textContent = it.ip;
      const mt = document.createElement("span"); mt.className = "mt"; mt.textContent = "优先级 " + it.metric;
      row.appendChild(nm); row.appendChild(ip); row.appendChild(mt);
      // Toggle restyles only this row (no DOM rebuild, no powershell.exe spawn)
      // -> the first-tick hitch and the collapse hitch both disappear.
      row.addEventListener("click", () => {
        const now = !pdChecked.has(it.ip);
        if (now) pdChecked.add(it.ip); else pdChecked.delete(it.ip);
        row.classList.toggle("sel", now);
        row.setAttribute("aria-pressed", now ? "true" : "false");
        updateSelectAllBtn();
      });
      box.appendChild(row);
    }
    if (!list.length) box.innerHTML = "<div class='muted'>未发现可用网卡</div>";
    updateSelectAllBtn();
  } catch (e) {
    box.innerHTML = "<div class='muted'>网卡枚举失败：" + e + "</div>";
  }
}

// One shared toggle: 全选 <-> 取消全选 (flips every row's selected state).
document.getElementById("pd-select-all").addEventListener("click", () => {
  const allOn = pdAllIps.length > 0 && pdChecked.size === pdAllIps.length;
  pdChecked = allOn ? new Set() : new Set(pdAllIps);
  document.querySelectorAll("#pd-ifaces .iface-row").forEach(row => {
    const on = pdChecked.has(row.dataset.ip || "");
    row.classList.toggle("sel", on);
    row.setAttribute("aria-pressed", on ? "true" : "false");
  });
  updateSelectAllBtn();
});

document.getElementById("pd-refresh").addEventListener("click", () => refreshPdIfaces(true));

// Broadcast state: the Start button turns into "正在广播" (disabled) while the agent runs.
function setPdBroadcastUi(broadcasting){
  const start = document.getElementById("pd-start");
  const stop  = document.getElementById("pd-stop");
  if (start){ start.disabled = broadcasting; start.textContent = broadcasting ? "正在广播" : "开始广播"; }
  if (stop) stop.disabled = !broadcasting;
}

document.getElementById("pd-start").addEventListener("click", async () => {
  const ips = [...pdChecked];
  if (!ips.length) { pdErr("请先勾选一块网卡"); return; }
  try {
    // the agent enumerates NICs itself; --include-vpn decides whether VPN adapters take part
    const all = await invoke("list_ifaces_named");
    const vpnSelected = ips.some(ip => {
      const it = all.find(x => x.ip === ip);
      return it && /radmin|zerotier|tailscale|wireguard|vpn|tap|vEthernet|ngrok/i.test(it.name || "");
    });
    // Pass the ticked NICs through: the agent only broadcasts on these addresses. Without
    // --ifaces it would enumerate every eligible adapter and ignore the checkboxes.
    const args = ["--peer-discover", "--listen-seconds", "60", "--discover-port", "63010", "--probe-port", "63011", "--ifaces", ips.join(",")];
    if (vpnSelected) args.push("--include-vpn");
    // Single agent slot (start_agent refuses a second instance): if the discovery-
    // completion agent is running, stop it first, otherwise this fails with
    // "agent already running (pid)" and the node-discovery run never starts.
    if (agentRunning){
      try { await invoke("stop_agent"); } catch (e) { /* ignore */ }
      agentRunning = false;
      stopRoomWatch();
      log("injectlog", "已停止发现补全（切换为节点发现）。");
    }
    const pid = await invoke("start_agent", { args });
    pdAgentPid = pid;
    pdSessionStarted = true;
    pdResetResult();               // clears phase, devices, paths, rec
    startPdLive();
    setPdBroadcastUi(true);
  } catch (e) { pdErr("启动失败：" + e); }
});
document.getElementById("pd-stop").addEventListener("click", async () => {
  try {
    const ok = await invoke("stop_agent");
    if (ok){
      // Keep the 700ms live poll running: the agent writes phase=done before exiting,
      // and agent-exited then stops the poll. (Previously the poll was killed here,
      // freezing the panel on the last "探测中 · 剩余 Ns" frame — time no longer ticking.)
    } else {
      stopPdLive();
      setPdBroadcastUi(false);
    }
  } catch (e) { pdErr("停止失败：" + e); }
});
listen("agent-exited", async (ev) => {
  // Only react when the exiting agent is OUR node-discovery agent. The discovery-completion
  // agent also emits agent-exited (its own listener above); without this pid filter, the
  // completion agent stopping would tear down the live panel and reset the buttons mid-run.
  // Strict guard: no pd pid => this is not our run, ignore entirely (bugfix 2026-11-22).
  if (pdAgentPid == null || ev.payload !== pdAgentPid) return;
  pdAgentPid = null;
  // Bugfix 2026-11-22 (audit round 2): pdSessionStarted was set true on start but never
  // reset. Once any discovery run finished, startAgentCore() refused forever ("节点发现
  // 正在运行") and the peers tab kept polling stale runs from disk. Reset it on real exit.
  pdSessionStarted = false;
  stopPdLive();
  setPdBroadcastUi(false);
  await refreshPdLive();
});
// ---------- live discovered-device panel ----------
const PD_PHASE_LABEL = { listening: "正在广播", probing: "探测中", answering: "应答中", done: "已完成" };
const PD_PHASE_CLASS = { listening: "on", probing: "on", answering: "on", done: "done" };
let pdLiveTimer = null;
let pdLastJson = "";

function escapeHtml(s){
  return String(s == null ? "" : s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function pdRenderPhase(phase, elapsed_s, remain_s){
  const el = document.getElementById("pd-phase");
  if (!el) return;
  let txt = PD_PHASE_LABEL[phase] || (phase ? phase : "未开始");
  if (phase && phase !== "done" && remain_s != null) txt += " · 剩余 " + remain_s + "s";
  else if (elapsed_s != null) txt += " · 已用 " + elapsed_s + "s";
  el.textContent = txt;
  el.className = "phase " + (PD_PHASE_CLASS[phase] || "");
}

function pdRenderDevices(peers){
  const box = document.getElementById("pd-devices");
  if (!box) return;
  if (!peers || !peers.length){
    box.innerHTML = '<div class="empty">尚未发现设备</div>';
    return;
  }
  box.innerHTML = peers.map(p => {
    // addrs are the peer's discovery SOURCE addresses: the ports are ephemeral and change
    // every run (noise), so the row shows bare IPs; the full ip:port list stays in the tooltip.
    const rawAddrs = (p.addrs || []).map(a => String(a));
    const addrs = rawAddrs.map(a => a.replace(/:\d+$/, ""));
    return '<div class="dev-item"><span class="dot"></span>'
      + '<span class="who">对端设备 ' + escapeHtml(p.short || "") + '</span>'
      + '<span class="ad" title="' + escapeHtml(rawAddrs.join("  ")) + '">' + escapeHtml(addrs.join("  ")) + '</span>'
      + '<span class="secs">' + (p.last_seen_s || 0) + 's 前</span></div>';
  }).join("");
}

const PD_ZERO_REASON = { stopped: "已停止", deadline: "时间不足", send_error: "发送失败" };

function pdRenderPaths(paths){
  const box = document.getElementById("pd-paths");
  if (!box) return;
  if (!paths || !paths.length){
    // Probing is still running (paths arrive only when the probe phase finishes): the
    // phase badge already says "探测中 · 剩余 Ns", so an empty table shows nothing.
    box.innerHTML = "";
    return;
  }
  const head = '<div class="path-row head"><span>路径</span><span>收发</span><span>p50</span>'
             + '<span>p95</span><span>抖动</span><span>丢包</span></div>';
  box.innerHTML = head + paths.map(p => {
    const cls = p.ok ? "ok" : "bad";
    const recvTxt = (p.sent === 0 && p.reason) ? (PD_ZERO_REASON[p.reason] || "未发出") : (p.sent + "/" + p.recv);
    // Zero samples: percentiles/jitter are 0 by construction, which would read as a perfect
    // link (0.00ms) on a channel that never answered. Dash them instead.
    const noSamples = !(p.recv > 0);
    // Zero-sent rows already carry a reason in 收发; a "0.00% / 0" score is meaningless there.
    const noProbe = p.sent === 0 && p.reason;
    return '<div class="path-row ' + cls + '">'
      + '<span>' + escapeHtml(pdCleanName(p.iface)) + ' (' + escapeHtml(p.local_ip) + ') → ' + escapeHtml(p.peer) + '</span>'
      + '<span>' + recvTxt + '</span>'
      + '<span>' + (noSamples ? "—" : p.p50_ms + "ms") + '</span>'
      + '<span>' + (noSamples ? "—" : p.p95_ms + "ms") + '</span>'
      + '<span>' + (noSamples ? "—" : p.jitter_ms + "ms") + '</span>'
      + '<span>' + (noProbe ? "—" : p.loss_pct + "%") + '</span></div>';
  }).join("");
}

function pdRenderRec(paths){
  const el = document.getElementById("pd-rec");
  if (!el) return;
  const good = (paths || []).filter(p => p.ok);
  if (!good.length){
    el.className = "rec none";
    const list = paths || [];
    const allZero = list.length > 0 && list.every(p => p.sent === 0 && p.reason);
    if (allZero){
      // Zero-sample probe: report WHY nothing was measured instead of implying a bad link.
      const r = list[0].reason;
      el.textContent = r === "stopped" ? "探针未发出（已停止）"
                     : r === "deadline" ? "探针未发出（时间不足）"
                     : r === "send_error" ? "探针未发出（发送失败）"
                     : "探针未发出";
    } else {
      el.textContent = list.length ? "无可用路径（未通过硬门槛：丢包>3% 或 p95>150ms 或样本<80）" : "";
    }
    return;
  }
  good.sort((a, b) => a.score - b.score);
  el.className = "rec";
  el.textContent = "推荐路径：" + pdCleanName(good[0].iface) + " → " + good[0].peer;
}

function pdResetResult(){
  pdLastJson = "";
  pdRenderPhase("");
  pdRenderDevices([]);
  pdRenderPaths([]);
  pdRenderRec([]);
  const selfEl = document.getElementById("pd-self");
  if (selfEl) selfEl.textContent = "本机 —";
  const cnt = document.getElementById("pd-count");
  if (cnt) cnt.textContent = "设备 0 · 路径 0";
}

async function refreshPdLive(){
  let raw = "";
  try { raw = await invoke("peer_live"); } catch (e) { return; }
  if (!raw){ pdRenderPhase(""); return; }
  if (raw === pdLastJson) return; // unchanged: leave the DOM alone
  pdLastJson = raw;
  let data;
  try { data = JSON.parse(raw); } catch (e) { return; }
  pdRenderPhase(data.phase || "", data.elapsed_s, data.remain_s);
  const selfEl = document.getElementById("pd-self");
  if (selfEl && data.self && data.self.short) selfEl.textContent = "本机 " + data.self.short;
  const peers = data.peers || [];
  const paths = data.paths || [];
  pdRenderDevices(peers);
  pdRenderPaths(paths);
  pdRenderRec(paths);
  const cnt = document.getElementById("pd-count");
  if (cnt) cnt.textContent = "设备 " + peers.length + " · 路径 " + paths.length;
}

function startPdLive(){
  stopPdLive();
  pdLiveTimer = setInterval(() => {
    if (document.getElementById("tab-peers").classList.contains("active")) refreshPdLive();
  }, 700);
}
function stopPdLive(){ if (pdLiveTimer) { clearInterval(pdLiveTimer); pdLiveTimer = null; } }

document.getElementById("pd-clear").addEventListener("click", () => pdResetResult());
// ---------- diagnostics (关于页：status + counters + redacted log) ----------
let diagText = "";
async function ctlText(cmd, timeoutMs){
  const proc = document.getElementById("proc").value;
  if(!proc || !proc.includes("#")) return "[!] 请先刷新并选择目标进程";
  const pid = proc.split("#")[1];
  try {
    const r = await invoke("run_ctl", { cmd, args: ["-p", pid], timeoutMs });
    return `[exit ${r.exit_code}] ` + (r.stdout || "") + (r.stderr ? " [stderr] " + r.stderr : "");
  } catch(e){ return "[ERROR] " + e; }
}
document.getElementById("btndiag").addEventListener("click", async () => {
  const proc = document.getElementById("proc").value;
  const pid = proc && proc.includes("#") ? proc.split("#")[1] : "(none)";
  const role = document.getElementById("role").selectedIndex === 0 ? "A host" : "B client";
  const logEl = document.getElementById("diaglog");
  logEl.textContent = "正在采集运行状态与错误计数…";
  const statusTxt = await ctlText("status", 22000);
  const countersTxt = await ctlText("counters", 18000);
  diagText = [
    "CivLink diagnostic (in-memory preview)",
    "time: " + new Date().toISOString(),
    "role: " + role,
    "target pid: " + pid,
    "boundary: " + BOUNDARY_STATE + " / " + BOUNDARY_MECH,
    "--- 运行状态 (civlink_ctl status) ---",
    statusTxt,
    "--- 错误计数 (civlink_ctl counters, 查 initError) ---",
    countersTxt,
    "--- redacted log tail ---",
    redact(document.getElementById("injectlog").textContent.split("\n").slice(-40).join("\n")),
  ].join("\n");
  logEl.textContent = diagText;
});
document.getElementById("diagexport").addEventListener("click", async () => {
  if(!diagText){ log("diaglog","[!] 请先生成诊断预览"); return; }
  try {
    const { save } = window.__TAURI__.dialog;
    const path = await save({ defaultPath: "civlink-diag.txt" });
    if(path){ await invoke("save_diag", { path: path, text: diagText }); log("diaglog", "[saved] " + path); }
  } catch(e){ log("diaglog", "[save ERROR] " + e); }
});

// ---------- init ----------
window.addEventListener("DOMContentLoaded", () => {
  applyRole();
  refreshProcesses();
  refreshIfaces();
  refreshPdIfaces();
  setPdBroadcastUi(false);
  // 2026-11-22: M5 warnings removed by explicit project-lead instruction (see the comment
  // at the top of the peer-discovery section); the #pd-warn footer no longer exists.
  const b = document.getElementById("about-boundary");
  if (b) b.textContent = BOUNDARY_STATE + " · " + BOUNDARY_MECH;
});
