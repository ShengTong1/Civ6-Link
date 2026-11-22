use serde::Serialize;
use std::path::PathBuf;
use std::process::Command;
use std::time::Duration;
use tauri::Emitter;
use std::io::Read;
use std::sync::Mutex;

#[derive(Serialize, Clone)]
pub struct CtlResult {
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
    pub timed_out: bool,
}

fn exe_dir() -> PathBuf {
    std::env::current_exe().map(|p| p.parent().map(|d| d.to_path_buf()).unwrap_or_default()).unwrap_or_default()
}

fn ctl_path() -> PathBuf { exe_dir().join("civlink_ctl.exe") }
fn agent_path() -> PathBuf { exe_dir().join("civlink-agent.exe") }

fn wait_with_timeout(child: &mut std::process::Child, ms: u64) -> std::io::Result<Option<i32>> {
    // poll-based wait (std has no timeout wait); 50ms granularity
    let deadline = std::time::Instant::now() + Duration::from_millis(ms);
    loop {
        match child.try_wait()? {
            Some(st) => return Ok(Some(st.code().unwrap_or(-1))),
            None => {
                if std::time::Instant::now() > deadline { return Ok(None); }
                std::thread::sleep(Duration::from_millis(50));
            }
        }
    }
}

#[tauri::command]
fn run_ctl(cmd: String, args: Vec<String>, timeout_ms: Option<u64>) -> Result<CtlResult, String> {
    let path = ctl_path();
    if !path.exists() { return Err(format!("civlink_ctl.exe not found at {}", path.display())); }
    let mut c = {
        use std::os::windows::process::CommandExt;
        Command::new(&path)
            .arg(&cmd)
            .args(&args)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .creation_flags(0x08000000) // CREATE_NO_WINDOW: ctl is a console exe
            .spawn()
            .map_err(|e| e.to_string())?
    };
    // outputs are read after wait (ctl output is small); pipes stay open so no
    // deadlock risk at these sizes, but we cap by reading to string post-exit.
    let code = match wait_with_timeout(&mut c, timeout_ms.unwrap_or(20000)).map_err(|e| e.to_string())? {
        Some(code) => code,
        None => { let _ = c.kill(); return Ok(CtlResult { exit_code: -1, stdout: String::new(), stderr: String::new(), timed_out: true }); }
    };
    let mut stdout = String::new();
    let mut stderr = String::new();
    if let Some(mut so) = c.stdout.take() { let _ = so.read_to_string(&mut stdout); }
    if let Some(mut se) = c.stderr.take() { let _ = se.read_to_string(&mut stderr); }
    Ok(CtlResult { exit_code: code, stdout, stderr, timed_out: false })
}

#[tauri::command]
fn list_processes() -> Result<Vec<String>, String> {
    // whitelist: CivilizationVI_DX12 / CivilizationVI / CivilizationVI_DX11
    // output "name#pid" strings
    let mut result = Vec::new();
    let names = ["CivilizationVI_DX12", "CivilizationVI", "CivilizationVI_DX11"];
    let output = {
        use std::os::windows::process::CommandExt;
        Command::new("tasklist").args(["/FO", "CSV", "/NH"])
            .creation_flags(0x08000000) // CREATE_NO_WINDOW: no console flash
            .output().map_err(|e| e.to_string())?
    };
    let text = String::from_utf8_lossy(&output.stdout);
    for line in text.lines() {
        let parts: Vec<&str> = line.split("\",\"").collect();
        if parts.len() >= 2 {
            let exe = parts[0].trim_start_matches('"');
            let base = exe.trim_end_matches(".exe");
            for n in names.iter() {
                if base.eq_ignore_ascii_case(n) {
                    result.push(format!("{}#{}", base, parts[1].trim_end_matches('"')));
                }
            }
        }
    }
    Ok(result)
}

#[derive(serde::Serialize)]
struct IfaceNamed { ip: String, name: String, metric: u32 }

/// Live interface inventory: IPv4 address + adapter friendly name + InterfaceMetric.
/// Metric is what Windows ranks egress interfaces by (smaller = higher priority), so the
/// list is returned already sorted high-priority-first and the UI shows the raw number.
#[tauri::command]
fn list_ifaces_named() -> Result<Vec<IfaceNamed>, String> {
    let output = {
        use std::os::windows::process::CommandExt;
        Command::new("powershell.exe")
            .args(["-NoProfile", "-Command",
              "[Console]::OutputEncoding=[Text.Encoding]::UTF8; $m=@{}; Get-NetIPInterface -AddressFamily IPv4 | ForEach-Object { $m[$_.InterfaceIndex]=$_.InterfaceMetric }; Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1'} | ForEach-Object { $n=(Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue).Name; $mm=$m[$_.InterfaceIndex]; if($null -eq $mm){$mm=9999}; '' + $_.IPAddress + '|' + $n + '|' + $mm }"])
            .creation_flags(0x08000000)
            .output().map_err(|e| e.to_string())?
    };
    let text = String::from_utf8_lossy(&output.stdout);
    let mut out = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() { continue; }
        let mut parts = line.splitn(3, '|');
        let ip = parts.next().unwrap_or("").to_string();
        let name = parts.next().unwrap_or("").to_string();
        let metric = parts.next().and_then(|s| s.trim().parse::<u32>().ok()).unwrap_or(9999);
        if ip.is_empty() { continue; }
        out.push(IfaceNamed { ip, name, metric });
    }
    out.sort_by_key(|i| i.metric);   // smaller metric = higher priority = first
    Ok(out)
}

static AGENT_PID: Mutex<Option<u32>> = Mutex::new(None);

/// Where the agent writes its run directories (summary.txt / peers.jsonl).
/// The GUI shows this so the operator can actually open the results.
#[tauri::command]
fn agent_out_dir() -> String {
    exe_dir().join("agent-out").to_string_lossy().to_string()
}

static LAST_PEER_OUT: Mutex<Option<String>> = Mutex::new(None);

/// Run directory of the most recent peer-discovery start, so the UI can print the exact path
/// instead of a literal "<timestamp>" placeholder.
#[tauri::command]
fn last_peer_out() -> Option<String> {
    LAST_PEER_OUT.lock().unwrap().clone()
}

/// Live peer table published by the running agent (`peers-live.json` in the current run dir).
/// Returns the raw JSON object, or "" when the agent has not written it yet / no run is active.
///
/// Fallback: when this GUI process did not spawn the current run (restart, second window,
/// agent started from a script), scan `agent-out` for the newest `peer-*` directory that holds
/// a `peers-live.json`. Without this the device panel is empty after every GUI restart even
/// though the result files are right there on disk.
fn newest_peer_live(out_dir: &std::path::Path) -> Option<(String, String)> {
    let rd = std::fs::read_dir(out_dir).ok()?;
    let mut best: Option<(std::time::SystemTime, String, String)> = None;
    for e in rd.flatten() {
        let p = e.path();
        if !p.is_dir() { continue; }
        let name = e.file_name().to_string_lossy().to_string();
        if !name.starts_with("peer-") { continue; }
        let f = p.join("peers-live.json");
        let md = match std::fs::metadata(&f) { Ok(m) => m, Err(_) => continue };
        let mt = md.modified().unwrap_or(std::time::UNIX_EPOCH);
        let body = match std::fs::read_to_string(&f) { Ok(b) => b, Err(_) => continue };
        if body.trim().is_empty() { continue; }
        let dir = p.to_string_lossy().to_string();
        match &best {
            Some((t, _, _)) if *t >= mt => {}
            _ => best = Some((mt, dir, body)),
        }
    }
    best.map(|(_, d, b)| (d, b))
}

#[tauri::command]
fn peer_live() -> String {
    if let Some(d) = LAST_PEER_OUT.lock().unwrap().clone() {
        let f = std::path::Path::new(&d).join("peers-live.json");
        if let Ok(s) = std::fs::read_to_string(&f) {
            if !s.trim().is_empty() { return s; }
        }
    }
    let out_dir = exe_dir().join("agent-out");
    match newest_peer_live(&out_dir) {
        Some((d, body)) => {
            let mut g = LAST_PEER_OUT.lock().unwrap();
            if g.is_none() { *g = Some(d); }
            body
        }
        None => String::new(),
    }
}

#[tauri::command]
fn start_agent(args: Vec<String>, app: tauri::AppHandle) -> Result<u32, String> {
    let path = agent_path();
    if !path.exists() { return Err(format!("civlink-agent.exe not found at {}", path.display())); }
    let mut already = AGENT_PID.lock().unwrap();
    if let Some(pid) = *already {
        return Err(format!("agent already running (pid {})", pid));
    }
    let out_dir = exe_dir().join("agent-out");
    let _ = std::fs::create_dir_all(&out_dir);
    let stop_file = out_dir.join("stop.now");
    let _ = std::fs::remove_file(&stop_file);
    // Peer-discovery runs write summary.txt / peers.jsonl into a run directory.
    // The agent would otherwise default to "peers" relative to whatever cwd the
    // GUI inherited, which the operator can never find - pin it under agent-out.
    let mut args = args;
    if args.iter().any(|a| a == "--peer-discover") && !args.iter().any(|a| a == "--peers-dir") {
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
        args.push("--peers-dir".to_string());
        args.push(out_dir.join(format!("peer-{stamp}")).to_string_lossy().to_string());
        *LAST_PEER_OUT.lock().unwrap() = Some(out_dir.join(format!("peer-{stamp}")).to_string_lossy().to_string());
    }
    let mut c = {
        use std::os::windows::process::CommandExt;
        Command::new(&path).args(&args).arg("--stop-file").arg(&stop_file)
            .creation_flags(0x08000000) // CREATE_NO_WINDOW (agent writes logs to files)
            .spawn().map_err(|e| e.to_string())?
    };
    let pid = c.id();
    *already = Some(pid);
    // spawn watcher thread to emit agent-exited event
    std::thread::spawn(move || {
        let _ = c.wait();
        // Bugfix 2026-11-22 (audit round 2): stop_agent() takes AGENT_PID *before* the
        // process actually exits, so a new agent may already own the slot when this old
        // watcher wakes. Compare-and-clear: only clear if the slot still names OUR pid,
        // never wipe a newer run's registration.
        {
            let mut guard = AGENT_PID.lock().unwrap();
            if *guard == Some(pid) { *guard = None; }
        }
        let _ = app.emit("agent-exited", pid);
    });
    Ok(pid)
}

#[tauri::command]
fn stop_agent() -> Result<bool, String> {
    let pid = AGENT_PID.lock().unwrap().take();
    match pid {
        Some(_p) => {
            let out_dir = exe_dir().join("agent-out");
            let stop_file = out_dir.join("stop.now");
            std::fs::write(&stop_file, "stop").map_err(|e| e.to_string())?;
            Ok(true)
        }
        None => Ok(false)
    }
}

#[tauri::command]
fn udp_port_in_use(port: u16) -> bool {
    // A Civ6 host room binds UDP 62900. netstat needs no admin and parses in ~100 ms;
    // the smart-completion poller calls this every 2 s. We match the local-address
    // token ("0.0.0.0:62900" / "[::]:62900") so ":62900" never collides with e.g. ":162900".
    if let Ok(out) = std::process::Command::new("netstat").args(["-ano", "-p", "UDP"]).output() {
        let needle = format!(":{port}");
        let text = String::from_utf8_lossy(&out.stdout);
        for line in text.lines() {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2
                && parts[0].eq_ignore_ascii_case("UDP")
                && parts[1].ends_with(&needle)
            {
                return true;
            }
        }
    }
    false
}

#[tauri::command]
fn save_diag(path: String, text: String) -> Result<(), String> {
    // UTF-8 without BOM (parity with WinForms diag export)
    use std::io::Write;
    let mut f = std::fs::File::create(&path).map_err(|e| e.to_string())?;
    f.write_all(text.as_bytes()).map_err(|e| e.to_string())
}
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            // second launch: focus the existing window instead of dying on a WebView2 user-data lock conflict (0x800700AA)
            use tauri::Manager;
            if let Some(w) = app.get_webview_window("main") { let _ = w.set_focus(); }
        }))
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![run_ctl, list_processes, list_ifaces_named, last_peer_out, peer_live, agent_out_dir, start_agent, stop_agent, save_diag, udp_port_in_use])
        .setup(|app| {
            // Explicit per-install user-data folder next to the exe.
            // Why: the default %LOCALAPPDATA%\io.github.shengtong.civlink\EBWebView can be
            // poisoned by an admin-privilege run (non-admin relaunches then fail with
            // 0x800700AA "resource in use"). A UDD beside the exe keeps every privilege
            // level isolated and travels with the app (portable).
            use tauri::Manager;
            let udd = std::env::current_exe()
                .ok()
                .and_then(|p| p.parent().map(|d| d.to_path_buf()))
                .map(|d| d.join("userdata"))
                .unwrap_or_else(|| std::env::temp_dir().join("civlink-gui-userdata"));
            let _ = std::fs::create_dir_all(&udd);
            if let Some(w) = app.get_webview_window("main") {
                let _ = w.set_focus();
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
