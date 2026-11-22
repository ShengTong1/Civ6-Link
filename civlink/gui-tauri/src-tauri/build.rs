fn main() {
    // Front-end assets are compiled into the binary by tauri-build, but nothing tells cargo to
    // rebuild when they change (the default watch list is tauri.conf.json + capabilities only).
    // Without these lines an edit to index.html/main.js/style.css silently ships the OLD UI.
    for f in ["../src/index.html", "../src/main.js", "../src/style.css"] {
        println!("cargo:rerun-if-changed={f}");
    }
    // Embed a manifest that requests administrator elevation on launch.
    // Rationale: the WebView2 data directory (dataDirectory=userdata next to the exe)
    // and the injected game both behave consistently under one privilege level; the
    // historical failure mode was mixed admin/non-admin instances fighting over locks.
    let manifest = std::path::Path::new("windows-app/civlink-gui.exe.manifest")
        .canonicalize()
        .expect("manifest file missing");
    let attrs = tauri_build::Attributes::new()
        .windows_attributes(
            tauri_build::WindowsAttributes::new().app_manifest(
                std::fs::read_to_string(manifest).expect("manifest unreadable"),
            ),
        );
    tauri_build::try_build(attrs).expect("failed to run tauri-build");
}
