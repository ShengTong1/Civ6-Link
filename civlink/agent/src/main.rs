// civlink-agent - CivLink F1 Agent (discovery observation side)
//
// Listens on 127.0.0.1:34718 for CVLH2 frames emitted by civlink_hook.dll and reconciles
// what the Hook says it sent against what actually arrived.
//
// SCOPE (REV-016 §3 F1):
//   * Receive and validate CVLH2 frames. Bad magic / unknown version / short frame /
//     oversize payload are REJECTED and counted - never silently ignored.
//   * Track sequence continuity per session so a dropped loopback datagram is visible as a
//     gap instead of vanishing (spec v2.1 §4.4: no silent loss).
//   * Count per discovery port, per logical socket, and per direction.
//   * Write a durable per-frame log and a summary whose numbers are the reconciliation
//     evidence: agent.received must equal hook.sent, and
//     agent.processed + agent.rejected == agent.received.
//
// With `--simulate <fixture-dir>` this agent ALSO acts as a local simulated host
// (F1 integration): every discovery request arriving via the Hook chain is answered with
// the 22-page advertisement fixture, injected back into the game's socket over loopback
// from <sim-src-ip>:62900. The simulated host is therefore reachable ONLY through the
// DLL->Agent chain - the same path a Relay would take in F3 - never through the network.
// Without --simulate this agent only observes; it never forwards to a peer and never
// modifies game traffic.
//
// With `--simulate-datapath` (F2, codex review F2-DATAPATH-REVIEW-20261114.md §2.1/§2.2/D4)
// this agent ALSO observes datapath (62056) outbound frames arriving via the Hook chain and
// MAY send at most ONE 20-byte fixed probe datagram per run, to a game source endpoint that
// is confirmed local and non-zero, from an ephemeral source port. It NEVER binds :62056,
// never sets SO_REUSEADDR, never claims a real peer port or protocol (D4 replacement).
// `--bind-ip` is mandatory with --simulate-datapath and is fail-closed: only a current
// host-local address is accepted; without it the datapath mode refuses to start.
//
// Zero dependencies: must build with `cargo +1.75.0 build --offline`.
use std::collections::BTreeMap;
use std::env;
use std::fs::{self, File};
use std::io::{self, BufWriter, Write};
use std::net::{IpAddr, SocketAddr, UdpSocket};
use std::path::Path;
use std::process::ExitCode;
use std::time::{Duration, Instant, SystemTime};

// M0-G Peer Discover: pure logic core is ALWAYS compiled (zero dependency), so the
// `--peer-discover-selftest` mode and `cargo test` work in the default build. Only the
// network I/O module needs the optional feature.
mod peer_discover_core;
#[cfg(feature = "peer-discover")]
mod peer_discover_net;
#[cfg(feature = "peer-discover")]
use std::sync::atomic::{AtomicBool, Ordering};

// ----------------------------------------------------------------- frame contract (cvlh2.h)
const FRAME_MAGIC: [u8; 4] = [b'C', b'V', b'L', b'H'];
const FRAME_VER: u8 = 2;
const FRAME_HDR: usize = 42;
const MAX_PAYLOAD: usize = 1280;

const DIR_HOOK_TO_AGENT: u8 = 0;

const FLAG_VIA_WSASENDTO: u8 = 0x01;
const FLAG_LIMITED_BCAST: u8 = 0x02;
const FLAG_DISCOVERY: u8 = 0x04;
const FLAG_REJECTED_OVERSIZE: u8 = 0x08;
const FLAG_NO_PAYLOAD: u8 = 0x10;

const DEFAULT_PORT: u16 = 34718;
const DISCOVERY_FIRST: u16 = 62900;
const DISCOVERY_LAST: u16 = 62999;

// F2 datapath: the in-game data plane port (spec v2.1 F3: UDP 62056).
const DATAPATH_PORT: u16 = 62056;
// D4 replacement reply: at most ONE 20-byte fixed datagram per run.
const DATAPATH_REPLY_LEN: usize = 20;
const DATAPATH_REPLY_PAYLOAD: [u8; DATAPATH_REPLY_LEN] = [
    0x43, 0x56, 0x4C, 0x44, // "CVLD" - civlink datapath probe marker
    0x01, 0x00, 0x00, 0x00, // probe version 1
    0x00, 0x00, 0x00, 0x00, // reserved (zero)
    0x00, 0x00, 0x00, 0x00, // reserved (zero)
    0x00, 0x00, 0x00, 0x00, // reserved (zero)
];

// The 4-byte discovery magic observed on the wire in E1/E2-A/F0 evidence.
const DISCOVERY_MAGIC: [u8; 4] = [0x8D, 0xE8, 0xFC, 0x70];

/// A discovery request, by the design's own definition (v0.3 §3.2 rule 3): the destination
/// port is in the discovery window AND the payload is exactly the 4-byte discovery magic.
///
/// This is deliberately an AND, matching `SimState::consider`. The first F3-A revision used
/// `flag != 0 || port in range`, which meant a genuine 62056 data-plane frame that happened to
/// carry FLAG_DISCOVERY was dropped by the forward path without landing in any counter
/// (F3-A audit round 2, finding M1).
fn is_discovery_request(frame: &Frame) -> bool {
    let dst_port = port_from_be16(frame.dst_port_be);
    frame.payload_len == DISCOVERY_MAGIC.len()
        && frame.payload.len() == DISCOVERY_MAGIC.len()
        && dst_port >= DISCOVERY_FIRST
        && dst_port <= DISCOVERY_LAST
        && frame.payload[..4] == DISCOVERY_MAGIC
}

// ----------------------------------------------------------------- payload digest (F3-A)
/// SHA-256 of a payload, lowercase hex. Used to prove byte-identical delivery in both
/// directions: the forwarder logs the digest it sent, the peer logs the digest it received,
/// and the driver compares them with the sender's own value. Implemented here rather than
/// pulled from a crate because the Agent must keep building with zero dependencies on the
/// pinned 1.75 toolchain (see the header note).
fn sha256_hex(data: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ];
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];
    let mut msg = data.to_vec();
    let bit_len = (data.len() as u64) * 8;
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bit_len.to_be_bytes());
    for chunk in msg.chunks(64) {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([
                chunk[i * 4],
                chunk[i * 4 + 1],
                chunk[i * 4 + 2],
                chunk[i * 4 + 3],
            ]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }
        let (mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh) =
            (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7]);
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let t1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let t2 = s0.wrapping_add(maj);
            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(t1);
            d = c;
            c = b;
            b = a;
            a = t1.wrapping_add(t2);
        }
        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }
    let mut out = String::with_capacity(64);
    for v in h.iter() {
        out.push_str(&format!("{v:08x}"));
    }
    out
}

#[derive(Debug)]
struct Frame {
    dir: u8,
    seq: u32,
    session_id: u64,
    logical_socket_id: u32,
    socket_generation: u32,
    af: u8,
    src_ip_be: u32,
    src_port_be: u16,
    dst_ip_be: u32,
    dst_port_be: u16,
    flags: u8,
    payload_len: usize,
    payload: Vec<u8>,
}

fn get_u16le(b: &[u8]) -> u16 {
    u16::from(b[0]) | (u16::from(b[1]) << 8)
}

fn get_u32le(b: &[u8]) -> u32 {
    u32::from(b[0]) | (u32::from(b[1]) << 8) | (u32::from(b[2]) << 16) | (u32::from(b[3]) << 24)
}

fn get_u64le(b: &[u8]) -> u64 {
    let mut v = 0u64;
    for i in (0..8).rev() {
        v = (v << 8) | u64::from(b[i]);
    }
    v
}

/// Ports are stored as the raw 16-bit value of `sin_port`, i.e. big-endian bytes on a
/// little-endian machine. Swapping recovers host order.
fn port_from_be16(be: u16) -> u16 {
    be.swap_bytes()
}

fn ipv4_from_be(be: u32) -> String {
    // The frame carries the four address octets in NETWORK order (the bytes as they sit in
    // `sin_addr`). `get_u32le` reads them little-endian, so the first octet lands in the low
    // byte and a.b.c.d is recovered low-to-high - not high-to-low.
    format!(
        "{}.{}.{}.{}",
        be & 0xFF,
        (be >> 8) & 0xFF,
        (be >> 16) & 0xFF,
        (be >> 24) & 0xFF
    )
}

#[derive(Debug)]
enum FrameError {
    TooShort(usize),
    BadMagic,
    BadVersion(u8),
    PayloadTooLarge(usize),
    Truncated { declared: usize, actual: usize },
    WrongDirection(u8),
    BadAddressFamily(u8),
}

impl FrameError {
    fn kind(&self) -> &'static str {
        match self {
            FrameError::TooShort(_) => "short-frame",
            FrameError::BadMagic => "bad-magic",
            FrameError::BadVersion(_) => "bad-version",
            FrameError::PayloadTooLarge(_) => "payload-too-large",
            FrameError::Truncated { .. } => "truncated",
            FrameError::WrongDirection(_) => "wrong-direction",
            FrameError::BadAddressFamily(_) => "bad-address-family",
        }
    }

    /// Human-readable specifics, kept separate from `kind()` so the counter keys stay
    /// stable (a metrics key that embeds frame sizes would explode the label space).
    fn detail(&self) -> String {
        match self {
            FrameError::TooShort(n) => format!("only {n} B, need {FRAME_HDR}"),
            FrameError::BadVersion(v) => format!("ver={v}, expected {FRAME_VER}"),
            FrameError::PayloadTooLarge(n) => format!("declared {n} B > {MAX_PAYLOAD}"),
            FrameError::Truncated { declared, actual } => {
                format!("declared {declared} B payload, got {actual} B")
            }
            FrameError::WrongDirection(d) => format!("dir={d}, expected {DIR_HOOK_TO_AGENT}"),
            FrameError::BadAddressFamily(af) => format!("af={af}, expected 2 (AF_INET)"),
            FrameError::BadMagic => "magic is not CVLH".to_string(),
        }
    }
}

// ----------------------------------------------------------------- simulated host (F1 integration)
// With --simulate <fixture-dir> the Agent loads the 22-page advertisement fixture captured
// in H4/E2-A (reply-01.bin .. reply-22.bin, 1104 B each), anonymizes the room-name field,
// and answers discovery requests that arrive VIA THE HOOK CHAIN. Replies are injected back
// into the game's socket over loopback from a socket bound to <sim-src-ip>:62900. Nothing
// else on the network can trigger a reply: the simulated host is reachable only through the
// DLL->Agent path (the shape the F3 Relay path will take).
const SIM_PAGE_SIZE: usize = 1104;
const SIM_PAGE_COUNT: usize = 22;
const SIM_NAME_OFFSET: usize = 24; // room-name field in the 164 B page header, 22 bytes
const SIM_NAME_LEN: usize = 22;
const SIM_REPLY_PORT: u16 = 62900;
// The H4-captured fixture pages carry the page magic on the wire as bytes 59 60 69 9B
// (numeric 0x9B696059 in little-endian disk order). Compare the raw bytes, not the number.
const SIM_MAGIC: [u8; 4] = [0x59, 0x60, 0x69, 0x9B];

fn parse_dotted_ip(s: &str) -> Result<[u8; 4], String> {
    let parts: Vec<&str> = s.split('.').collect();
    if parts.len() != 4 {
        return Err(format!("'{s}' is not an IPv4 address"));
    }
    let mut out = [0u8; 4];
    for (i, p) in parts.iter().enumerate() {
        let v: u16 = p.parse().map_err(|_| format!("bad octet '{p}'"))?;
        if v > 255 {
            return Err(format!("octet {v} > 255"));
        }
        out[i] = v as u8;
    }
    Ok(out)
}

/// Validate one fixture page: exact size, magic, declared page count and its own index.
fn validate_page(page: &[u8], expected_index: usize) -> Result<(), String> {
    if page.len() != SIM_PAGE_SIZE {
        return Err(format!(
            "page {}: {} B, expected {SIM_PAGE_SIZE}",
            expected_index + 1,
            page.len()
        ));
    }
    if page[0..4] != SIM_MAGIC {
        return Err(format!("page {}: bad magic", expected_index + 1));
    }
    let count = get_u32le(&page[156..160]);
    if count != SIM_PAGE_COUNT as u32 {
        return Err(format!(
            "page {}: header page count {count}, expected {SIM_PAGE_COUNT}",
            expected_index + 1
        ));
    }
    let idx = get_u32le(&page[160..164]);
    if idx != expected_index as u32 {
        return Err(format!(
            "page {}: header page index {idx}, expected {expected_index}",
            expected_index + 1
        ));
    }
    Ok(())
}

fn load_fixture_pages(dir: &str) -> Result<Vec<Vec<u8>>, String> {
    let mut pages = Vec::with_capacity(SIM_PAGE_COUNT);
    for i in 0..SIM_PAGE_COUNT {
        let path = format!("{dir}/reply-{:02}.bin", i + 1);
        let b = fs::read(&path).map_err(|e| format!("cannot read {path}: {e}"))?;
        validate_page(&b, i)?;
        pages.push(b);
    }
    Ok(pages)
}

/// Replace the room-name field ([24..46)) with a fixed ASCII name padded to 22 bytes.
fn anonymize_pages(pages: &mut [Vec<u8>], room: &str) {
    let mut name = room.as_bytes().to_vec();
    name.truncate(SIM_NAME_LEN);
    name.resize(SIM_NAME_LEN, b' ');
    for p in pages.iter_mut() {
        p[SIM_NAME_OFFSET..SIM_NAME_OFFSET + SIM_NAME_LEN].copy_from_slice(&name);
    }
}

/// Where a simulated reply goes: the peer endpoint recorded on the frame. An unresolved
/// source IP (0.0.0.0 - the game socket is unbound, only its ephemeral port matters) or a
/// loopback source means the game socket lives on this machine, so the configured fallback
/// address (default 127.0.0.1) is used as the destination.
fn resolve_destination(src_ip_be: u32, src_port_be: u16, fallback: [u8; 4]) -> SocketAddr {
    let port = port_from_be16(src_port_be);
    if src_ip_be == 0 || ipv4_from_be(src_ip_be) == "127.0.0.1" {
        SocketAddr::from((fallback, port))
    } else {
        SocketAddr::from((
            [
                (src_ip_be & 0xFF) as u8,
                ((src_ip_be >> 8) & 0xFF) as u8,
                ((src_ip_be >> 16) & 0xFF) as u8,
                ((src_ip_be >> 24) & 0xFF) as u8,
            ],
            port,
        ))
    }
}

#[derive(Default)]
struct SimStats {
    requests_seen: u64,
    replied_sockets: u64,
    pages_sent: u64,
    send_fail: u64,
    no_endpoint: u64,
    max_replies_reached: u64,
    bind_fail: u64,
    reply_addr: Option<SocketAddr>, // actual bound local addr of the reply socket (S-2: log real port, not config)
}

#[derive(Default)]
struct SocketSim {
    replied: bool,
    budget_denied: bool,
    known_ip_be: Option<u32>,
    known_port_be: Option<u16>,
}

struct SimState {
    pages: Vec<Vec<u8>>,
    reply_sock: Option<UdpSocket>,
    max_replies: u64,
    fallback_ip: [u8; 4],
    stats: SimStats,
    sockets: BTreeMap<u32, SocketSim>,
}

impl SimState {
    fn new(
        fixture_dir: &str,
        src_ip: &str,
        max_replies: u64,
        room: &str,
        out_dir: Option<&str>,
    ) -> Result<Self, String> {
        let mut pages = load_fixture_pages(fixture_dir)?;
        anonymize_pages(&mut pages, room);
        let fallback_ip = parse_dotted_ip(src_ip)?;
        let bind_addr = SocketAddr::from((fallback_ip, SIM_REPLY_PORT));
        let mut stats = SimStats::default();
        let reply_sock = match UdpSocket::bind(bind_addr) {
            Ok(s) => Some(s),
            Err(e) => {
                eprintln!(
                    "[!] simulated-host reply socket: cannot bind {bind_addr}: {e} (replies disabled)"
                );
                stats.bind_fail = 1;
                None
            }
        };
        if let Some(dir) = out_dir {
            fs::create_dir_all(dir).map_err(|e| format!("cannot create {dir}: {e}"))?;
            for (i, p) in pages.iter().enumerate() {
                let path = format!("{dir}/sim-page-{:02}.bin", i + 1);
                fs::write(&path, p).map_err(|e| format!("cannot write {path}: {e}"))?;
            }
            let manifest = format!(
                "# simulated-host fixture\n\
                 # fixture dir: {fixture_dir}\n\
                 # room name: {room} (anonymized at offset {SIM_NAME_OFFSET}..{})\n\
                 # sim-page-01.bin..sim-page-22.bin hold the exact bytes sent in replies.\n",
                SIM_NAME_OFFSET + SIM_NAME_LEN
            );
            let path = format!("{dir}/sim-fixture-manifest.txt");
            fs::write(&path, manifest).map_err(|e| format!("cannot write {path}: {e}"))?;
        }
        Ok(SimState {
            pages,
            reply_sock,
            max_replies,
            fallback_ip,
            stats,
            sockets: BTreeMap::new(),
        })
    }

    /// Called for every ACCEPTED (processed) frame. Answers discovery requests once per
    /// logical socket, at most `max_replies` sockets in total. The first frame of an
    /// unbound UDP socket carries 0.0.0.0:0; the reply is deferred until the next frame of
    /// that socket exposes the real ephemeral port.
    fn consider(&mut self, frame: &Frame) {
        let dst_port = port_from_be16(frame.dst_port_be);
        let is_req = frame.flags & FLAG_DISCOVERY != 0
            && dst_port >= DISCOVERY_FIRST
            && dst_port <= DISCOVERY_LAST
            && frame.payload_len == 4
            && frame.payload.len() == 4
            && frame.payload[..4] == DISCOVERY_MAGIC;
        if !is_req {
            return;
        }
        self.stats.requests_seen += 1;
        let slot = self.sockets.entry(frame.logical_socket_id).or_default();
        if frame.src_port_be != 0 {
            slot.known_ip_be = Some(frame.src_ip_be);
            slot.known_port_be = Some(frame.src_port_be);
        }
        if slot.replied {
            return;
        }
        if self.stats.replied_sockets >= self.max_replies {
            if !slot.budget_denied {
                slot.budget_denied = true;
                self.stats.max_replies_reached += 1;
            }
            return;
        }
        let reply_sock = match self.reply_sock.as_ref() {
            Some(s) => s,
            None => return,
        };
        match (slot.known_ip_be, slot.known_port_be) {
            (Some(ip), Some(port)) => {
                let dst = resolve_destination(ip, port, self.fallback_ip);
                let mut ok = true;
                for page in &self.pages {
                    match reply_sock.send_to(page, dst) {
                        Ok(n) if n == page.len() => self.stats.pages_sent += 1,
                        _ => {
                            self.stats.send_fail += 1;
                            ok = false;
                        }
                    }
                }
                if ok {
                    slot.replied = true;
                    self.stats.replied_sockets += 1;
                }
            }
            _ => {
                self.stats.no_endpoint += 1;
            }
        }
    }
}

// ----------------------------------------------------------------- F5 LAN simulated host
//
// REV-016 双机发现路径：不依赖原生广播选路、接口 metric 或游戏进程的防火墙放行——
// Agent 自己绑定全部 100 个发现端口（62900..62999）直接收 Civ6 客户端的发现广播
// （magic 8D-E8-FC-70），并从 <listen-ip>:62900 应答 22 页 fixture。同一客户端刷新
// 会向每个端口各发 1 个 magic（100 包），所以按 (src ip, src port) 键去重，每个
// 临时端口（一次刷新）只应答一次。0.0.0.0 = 绑定所有接口（F0 responder 同构）。
struct LanSimState {
    pages: Vec<Vec<u8>>,
    listeners: Vec<UdpSocket>, // one per successfully bound discovery port
    reply_sock: Option<UdpSocket>, // the 62900 listener doubles as the reply socket
    reply_addr: Option<SocketAddr>, // actual bound local addr of the reply socket (S-2: log real port, not config)
    max_replies: u64,
    stats: SimStats,
    answered: BTreeMap<(u32, u16), bool>, // (src_ip_be, src_port_be) -> replied once
    /// M0-E: when set, a magic datagram is answered with the LOCAL game's own reply instead
    /// of the fixture. This is the mode the owner actually wants (m29860): the client sees
    /// the real room, never a synthetic one. Requires the game to be hosting on 62900.
    completion: Option<CompletionState>,
}

fn is_discovery_magic(data: &[u8]) -> bool {
    data.len() == 4 && data == DISCOVERY_MAGIC
}

// ----------------------------------------------------------------- discovery completion (M0-E)
//
// Discovery completion (M0-E): the Agent owns 62901..62999 (62900 stays with
// the game), so it receives the client's magic on every one of the 99 ports instead of the
// single port Civ6 listens on. In completion mode it does NOT answer itself: it replays the
// magic to the LOCAL game over loopback and forwards the game's own reply back to the
// client. The advert is therefore always the real room, freshly generated by the game -
// nothing is cached, nothing is invented, and a rebuilt room is picked up immediately.
//
// Verified on a live hosted room (M0A\captures\C3-loopback-replay-20261118-2235,
// M0A\captures\C3-fullchain-20261118-2240): the game answers all 22 pages, the pages are
// byte-identical across different replay source ports, and they contain neither 127.0.0.1
// nor the host's LAN address - so replaying over loopback cannot leak a wrong address into
// the advert.

// ---------------------------------------------------------------------------
// M0-E audit B-1: egress address control.
//
// The Agent's discovery listeners are bound to the wildcard address (they must be: a socket
// bound to one concrete address does not receive the client's limited broadcast). A wildcard
// socket does NOT choose the source address of a reply - Windows does, at send time, from the
// route. On a host with WLAN + Radmin + ZeroTier that is not necessarily the address the
// request arrived on, and the Civ6 client lists rooms keyed by source address, so the wrong
// source address makes the completed room invisible - the very symptom this mode exists to
// remove.
//
// Two ways to fix it:
//   (a) put every listener on a concrete per-interface address - rejected: it breaks the
//       broadcast reception the whole feature depends on, and multiplies sockets by the
//       interface count;
//   (b) keep the wildcard listener for RECEIVING, learn the destination address from
//       WSARecvMsg + IP_PKTINFO, and pin that address with WSASendMsg + IP_PKTINFO when
//       replying.
//
// (b) is what this module implements. It costs a hand-written ws2_32 binding instead of a
// crate: `[dependencies]` in Cargo.toml is empty and the build must stay `--offline`, so
// pulling in a socket crate is not an option. When the query fails for any reason the code
// falls back to a plain `send_to` and the round is counted as `egress_unpinned` - degraded,
// visible in the summary, never silently assumed correct.
#[cfg(windows)]
pub(crate) mod egress {
    use std::io;
    use std::mem::{size_of, zeroed};
    use std::net::{SocketAddr, UdpSocket};
    use std::os::windows::io::AsRawSocket;

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct SockaddrIn {
        sin_family: u16,
        sin_port: u16,
        sin_addr: u32,
        sin_zero: [u8; 8],
    }

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct WsaBuf {
        len: u32,
        buf: *mut u8,
    }

    /// Mirrors WSAMSG exactly:
    ///   LPSOCKADDR name; INT namelen; LPWSABUF lpBuffers; ULONG dwBufferCount;
    ///   WSABUF Control; ULONG dwFlags;
    ///
    /// Control is a nested WSABUF (len + pointer), NOT a bare pointer plus a length: getting
    /// this wrong makes WSARecvMsg read the pointer as a length and fail with WSAEFAULT
    /// (10014) on every receive - measured on 2026-11-19, 146 errors in one run.
    #[repr(C)]
    #[derive(Clone, Copy)]
    struct WsaMsgHdr {
        name: *mut u8,
        namelen: i32,
        buf: *mut WsaBuf,
        buflen: u32,
        control: WsaBuf,
        flags: u32,
    }


    #[link(name = "ws2_32")]
    extern "system" {
        fn WSAIoctl(
            s: usize,
            code: u32,
            inbuf: *mut u8,
            inlen: u32,
            outbuf: *mut u8,
            outlen: u32,
            bytes: *mut u32,
            overlapped: *mut u8,
            completion: *mut u8,
        ) -> i32;
    }

    // WSAGetLastError lives in the same DLL but is declared separately for clarity.
    #[link(name = "ws2_32")]
    extern "system" {
        #[link_name = "WSAGetLastError"]
        fn wsagetlasterror() -> i32;
    }

    #[link(name = "ws2_32")]
    extern "system" {
        fn setsockopt(s: usize, level: i32, name: i32, val: *const u8, len: i32) -> i32;
    }

    /// Ask the socket to attach an IP_PKTINFO control message to every received datagram.
    ///
    /// Without this the control block in the WSARecvMsg result is empty and the Agent cannot
    /// learn which local address the client probed (audit B-1).
    pub fn enable_pktinfo(sock: &UdpSocket) -> bool {
        let on: i32 = 1;
        let rc = unsafe {
            setsockopt(
                sock.as_raw_socket() as usize,
                0,  // IPPROTO_IP
                19, // IP_PKTINFO
                &on as *const i32 as *const u8,
                size_of::<i32>() as i32,
            )
        };
        rc == 0
    }

    const SIO_GET_EXTENSION_FUNCTION_POINTER: u32 = 0xC800_0006;
    // WSAID_WSARECVMSG / WSAID_WSASENDMSG as they are laid out in memory: GUID Data1 is a
    // little-endian u32, Data2/Data3 little-endian u16, Data4 a plain byte array:
    //   {0xf689d7c8,0x6f1f,0x436b,{0x8a,0x53,0xe5,0x4f,0xe3,0x51,0xc3,0x22}}  (mswsock.h)
    //   {0xa441e712,0x754f,0x43ca,{0x84,0xa7,0x0d,0xee,0x44,0xcf,0x60,0x6d}}
    // Getting these bytes wrong makes WSAIoctl fail silently and every reply falls back to
    // the routing table, which is exactly the B-1 defect (measured: egress api MISSING).
    const WSAID_WSARECVMSG: [u8; 16] = [
        0xC8, 0xD7, 0x89, 0xF6, 0x1F, 0x6F, 0x6B, 0x43, 0x8A, 0x53, 0xE5, 0x4F, 0xE3, 0x51,
        0xC3, 0x22,
    ];
    const WSAID_WSASENDMSG: [u8; 16] = [
        0x12, 0xE7, 0x41, 0xA4, 0x4F, 0x75, 0xCA, 0x43, 0x84, 0xA7, 0x0D, 0xEE, 0x44, 0xCF,
        0x60, 0x6D,
    ];

    struct Functions {
        recv: Option<unsafe extern "system" fn(usize, *mut WsaMsgHdr, *mut u32, *mut u8, *mut u8) -> i32>,
        send: Option<unsafe extern "system" fn(usize, *const WsaMsgHdr, u32, *mut u32, *mut u8, *mut u8) -> i32>,
    }

    fn lookup<T: Copy>(sock: usize, guid: &[u8; 16]) -> Option<T> {
        if size_of::<T>() != size_of::<*mut u8>() {
            return None;
        }
        let mut ptr: *mut u8 = std::ptr::null_mut();
        let mut bytes: u32 = 0;
        let rc = unsafe {
            WSAIoctl(
                sock,
                SIO_GET_EXTENSION_FUNCTION_POINTER,
                guid.as_ptr() as *mut u8,
                16,
                &mut ptr as *mut *mut u8 as *mut u8,
                size_of::<*mut u8>() as u32,
                &mut bytes,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
            )
        };
        if rc != 0 || ptr.is_null() {
            return None;
        }
        // Transmute the pointer VALUE into the function-pointer type. `zeroed()` is not
        // allowed for fn pointers (it aborts at runtime with "attempted to zero-initialize
        // type ... which is invalid"), so the copy has to come from the pointer itself.
        Some(unsafe { std::mem::transmute_copy::<*mut u8, T>(&ptr) })
    }

    fn functions(sock: usize) -> Functions {
        Functions {
            recv: lookup::<unsafe extern "system" fn(usize, *mut WsaMsgHdr, *mut u32, *mut u8, *mut u8) -> i32>(sock, &WSAID_WSARECVMSG),
            send: lookup::<unsafe extern "system" fn(usize, *const WsaMsgHdr, u32, *mut u32, *mut u8, *mut u8) -> i32>(sock, &WSAID_WSASENDMSG),
        }
    }

    /// One parsed incoming datagram plus the local address it was delivered to.
    pub struct RecvInfo {
        pub len: usize,
        /// The sender (the client that probed a discovery port).
        pub from: SocketAddr,
        /// The address the client actually sent to (one of this host's interface addresses).
        pub local_addr: Option<SocketAddr>,
    }

    /// Receive one datagram and learn which local address it was addressed to (B-1).
    ///
    /// Returns `Ok(None)` when nothing is queued (a non-blocking socket), and an `Err` mirroring
    /// the underlying socket error otherwise, so the caller keeps its existing error handling.
    pub fn recv_with_dst(
        sock: &UdpSocket,
        buf: &mut [u8],
    ) -> io::Result<Option<RecvInfo>> {
        let sock_usize = sock.as_raw_socket() as usize;
        let fns = functions(sock_usize);
        let recv = match fns.recv {
            Some(f) => f,
            None => {
                // Extension missing: fall back to a plain receive, no destination address.
                return sock.recv_from(buf).map(|(len, from)| {
                    Some(RecvInfo {
                        len,
                        from,
                        local_addr: None,
                    })
                });
            }
        };

        let mut name: [u8; 16] = [0; 16];
        let mut control = [0u8; 128];
        let mut one = WsaBuf {
            len: buf.len() as u32,
            buf: buf.as_mut_ptr(),
        };
        let mut ctrl_buf = WsaBuf {
            len: control.len() as u32,
            buf: control.as_mut_ptr(),
        };
        let mut hdr = WsaMsgHdr {
            name: name.as_mut_ptr(),
            namelen: 16,
            buf: &mut one as *mut WsaBuf,
            buflen: 1,
            control: ctrl_buf,
            flags: 0,
        };
        let mut bytes: u32 = 0;
        let rc = unsafe {
            recv(
                sock_usize,
                &mut hdr as *mut WsaMsgHdr,
                &mut bytes,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
            )
        };
        if rc == 0 {
            // hdr.name now holds the sender; the destination address is in the control block.
            // hdr.control.len is what WSARecvMsg actually wrote; clamp defensively so a
            // bogus length can never index outside our own buffer.
            let clen = (hdr.control.len as usize).min(control.len());
            let local_addr = parse_pktinfo(&control[..clen]);
            let from = parse_sockaddr_in(&name);
            return Ok(Some(RecvInfo {
                len: bytes as usize,
                from,
                local_addr,
            }));
        }
        let err = unsafe { wsagetlasterror() } as i32;
        // 10035 WSAEWOULDBLOCK, 10060 WSAETIMEDOUT
        if err == 10035 {
            return Ok(None);
        }
        if err == 10060 {
            return Err(io::Error::new(io::ErrorKind::TimedOut, "recv timed out"));
        }
        Err(io::Error::from_raw_os_error(err))
    }

    /// Decode the SOCKADDR_IN that WSARecvMsg wrote into `name` (sender address + port).
    fn parse_sockaddr_in(name: &[u8; 16]) -> SocketAddr {
        let family = u16::from_ne_bytes([name[0], name[1]]);
        let port = u16::from_be_bytes([name[2], name[3]]);
        let ip = std::net::Ipv4Addr::new(name[4], name[5], name[6], name[7]);
        if family == 2 {
            SocketAddr::new(std::net::IpAddr::V4(ip), port)
        } else {
            // WSARecvMsg always reports IPv4 here because the listeners are AF_INET.
            SocketAddr::new(std::net::IpAddr::V4(std::net::Ipv4Addr::UNSPECIFIED), 0)
        }
    }

    /// Walk the control block for an IP_PKTINFO cmsg and return its destination address.
    fn parse_pktinfo(control: &[u8]) -> Option<SocketAddr> {
        // WSACMSGHDR: cmsg_len (SIZE_T, 8 on x64), cmsg_level (INT), cmsg_type (INT)
        const HDR: usize = 8 + 4 + 4;
        let mut off = 0usize;
        while off + HDR <= control.len() {
            let mut len_buf = [0u8; 8];
            len_buf.copy_from_slice(&control[off..off + 8]);
            let cmsg_len = usize::from_ne_bytes(len_buf);
            let level = i32::from_ne_bytes([
                control[off + 8],
                control[off + 9],
                control[off + 10],
                control[off + 11],
            ]);
            let ctype = i32::from_ne_bytes([
                control[off + 12],
                control[off + 13],
                control[off + 14],
                control[off + 15],
            ]);
            if cmsg_len < HDR || off + cmsg_len > control.len() {
                break;
            }
            // IPPROTO_IP == 0, IP_PKTINFO == 19
            if level == 0 && ctype == 19 {
                let data = &control[off + HDR..off + cmsg_len];
                if data.len() >= size_of::<InPktInfo>() {
                    let mut pi: InPktInfo = unsafe { zeroed() };
                    unsafe {
                        std::ptr::copy_nonoverlapping(
                            data.as_ptr(),
                            &mut pi as *mut InPktInfo as *mut u8,
                            size_of::<InPktInfo>(),
                        );
                    }
                    let ip = std::net::Ipv4Addr::from(u32::from_be(pi.addr));
                    return Some(SocketAddr::new(std::net::IpAddr::V4(ip), 0));
                }
            }
            // WSACMSGHDR lengths are 8-byte aligned on x64.
            let step = (cmsg_len + 7) & !7;
            if step == 0 {
                break;
            }
            off += step;
        }
        None
    }

    /// Mirrors IN_PKTINFO exactly: 8 bytes, the ADDRESS comes FIRST and the interface index
    /// second. Reading them in the other order yields 10.0.0.0-style garbage (measured: the
    /// control block carried c0 a8 1f 3c 0a 00 00 00 = 192.168.31.60 + ifindex 10).
    #[repr(C)]
    #[derive(Clone, Copy)]
    struct InPktInfo {
        addr: u32,
        if_index: u32,
    }

    /// Send one datagram to `to`, pinning `from` as the source address when possible.
    ///
    /// Returns the number of bytes written, matching `UdpSocket::send_to`. On any failure of
    /// the pinned path the caller should fall back and count it.
    pub fn send_from(
        sock: &UdpSocket,
        payload: &[u8],
        to: &SocketAddr,
        from: std::net::Ipv4Addr,
    ) -> io::Result<usize> {
        let sock_usize = sock.as_raw_socket() as usize;
        let fns = functions(sock_usize);
        let send = match fns.send {
            Some(f) => f,
            None => return sock.send_to(payload, to),
        };

        let v4 = match to {
            SocketAddr::V4(a) => a,
            SocketAddr::V6(_) => return sock.send_to(payload, to),
        };
        let mut to_raw = SockaddrIn {
            sin_family: 2, // AF_INET
            sin_port: v4.port().to_be(),
            sin_addr: u32::from_ne_bytes(v4.ip().octets()),
            sin_zero: [0; 8],
        };

        // Build IP_PKTINFO with only the source address set (if_index 0).
        let mut control = [0u8; 64];
        const HDR: usize = 8 + 4 + 4;
        let data_len = size_of::<InPktInfo>();
        let cmsg_len = HDR + data_len;
        let mut hdr_bytes = [0u8; 8];
        hdr_bytes.copy_from_slice(&(cmsg_len as u64).to_ne_bytes());
        control[0..8].copy_from_slice(&hdr_bytes);
        control[8..12].copy_from_slice(&0i32.to_ne_bytes()); // IPPROTO_IP
        control[12..16].copy_from_slice(&19i32.to_ne_bytes()); // IP_PKTINFO
        let pi = InPktInfo {
            addr: u32::from_ne_bytes(from.octets()),
            // if_index 0 = "pick the interface from the source address".
            if_index: 0,
        };
        unsafe {
            std::ptr::copy_nonoverlapping(
                &pi as *const InPktInfo as *const u8,
                control.as_mut_ptr().add(HDR),
                data_len,
            );
        }

        let mut buf = WsaBuf {
            len: payload.len() as u32,
            buf: payload.as_ptr() as *mut u8,
        };
        let ctrl_buf = WsaBuf {
            len: cmsg_len as u32,
            buf: control.as_mut_ptr(),
        };
        let msg = WsaMsgHdr {
            name: &mut to_raw as *mut SockaddrIn as *mut u8,
            namelen: size_of::<SockaddrIn>() as i32,
            buf: &mut buf as *mut WsaBuf,
            buflen: 1,
            control: ctrl_buf,
            flags: 0,
        };
        let mut bytes: u32 = 0;
        let rc = unsafe {
            send(
                sock_usize,
                &msg as *const WsaMsgHdr,
                0, // dwFlags
                &mut bytes,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
            )
        };
        if rc == 0 {
            Ok(bytes as usize)
        } else {
            Err(io::Error::from_raw_os_error(unsafe { wsagetlasterror() }))
        }
    }

    /// Whether the egress pinning path is usable at all on this socket (checked once, so the
    /// summary can state it instead of guessing).
    pub fn available(sock: &UdpSocket) -> bool {
        let sock_usize = sock.as_raw_socket() as usize;
        let fns = functions(sock_usize);
        fns.recv.is_some() && fns.send.is_some()
    }
}

#[cfg(not(windows))]
mod egress {
    use std::io;
    use std::net::{Ipv4Addr, SocketAddr, UdpSocket};

    pub struct RecvInfo {
        pub len: usize,
        pub from: SocketAddr,
        pub local_addr: Option<SocketAddr>,
    }

    pub fn recv_with_dst(sock: &UdpSocket, buf: &mut [u8]) -> io::Result<Option<RecvInfo>> {
        sock.recv_from(buf).map(|(len, from)| {
            Some(RecvInfo {
                len,
                from,
                local_addr: None,
            })
        })
    }

    pub fn send_from(
        sock: &UdpSocket,
        payload: &[u8],
        to: &SocketAddr,
        _from: Ipv4Addr,
    ) -> io::Result<usize> {
        sock.send_to(payload, to)
    }

    pub fn available(_sock: &UdpSocket) -> bool {
        false
    }

    pub fn enable_pktinfo(_sock: &UdpSocket) -> bool {
        false
    }
}

struct CompletionStats {
    requests_intercepted: u64,
    replays_sent: u64,
    replays_failed: u64,
    pages_collected: u64,
    pages_forwarded: u64,
    forwards_failed: u64,
    timeouts: u64,
    empty_replies: u64,
    /// Pages whose length differed from SIM_PAGE_SIZE (kept, not dropped: a future game
    /// build may change the page size, and a wrong guess here is worse than forwarding).
    odd_page_sizes: u64,
    /// M0-E audit B-2: magics suppressed because the same client already had a round inside
    /// the cooldown window. One client refresh is 100 magics on 100 ports; without this the
    /// game is asked for 99 adverts (~2.41 MB measured) for a single refresh.
    duplicate_magic: u64,
    /// Rounds refused because --completion-max-replies was exhausted.
    budget_exhausted: u64,
    /// Stale datagrams dropped from the forward socket before a round started (B-2): leftover
    /// pages from a previous round must never be mistaken for this round's advert.
    backlog_cleared: u64,
    /// B-1: replies whose source address was pinned to the address the client actually probed.
    egress_pinned: u64,
    /// B-1: replies where the destination address could not be learned, so the OS picked the
    /// source address (degraded: the client may key the room to a different address).
    egress_unpinned: u64,
    /// B-1 diagnostics: how many receives failed (a non-WouldBlock/non-timeout error on the
    /// completion path stops that port's drain silently, so the count and the last error must
    /// be visible in the summary instead of showing up as "requests seen 0").
    recv_errors: u64,
    last_recv_error: i32,
    /// B-1: whether IP_PKTINFO could be enabled, i.e. whether the probed address is knowable.
    pktinfo_enabled: bool,
    /// B-1: diagnostics - how many of the intercepted magics carried a usable probed address.
    probe_addr_seen: u64,
    probe_addr_missing: u64,
    /// B-1: the last probed address seen (string form, for the summary and for tests).
    last_probe_addr: String,
    /// B-1: whether the WSARecvMsg/WSASendMsg extensions were found on the forward socket.
    /// When false the Agent cannot learn the probed address at all and every reply is
    /// unpinned - the summary states this instead of leaving the operator to guess.
    egress_available: bool,
}

impl Default for CompletionStats {
    fn default() -> Self {
        CompletionStats {
            requests_intercepted: 0,
            replays_sent: 0,
            replays_failed: 0,
            pages_collected: 0,
            pages_forwarded: 0,
            forwards_failed: 0,
            timeouts: 0,
            empty_replies: 0,
            odd_page_sizes: 0,
            duplicate_magic: 0,
            budget_exhausted: 0,
            backlog_cleared: 0,
            egress_pinned: 0,
            egress_unpinned: 0,
            egress_available: false,
            recv_errors: 0,
            last_recv_error: 0,
            pktinfo_enabled: false,
            probe_addr_seen: 0,
            probe_addr_missing: 0,
            last_probe_addr: String::new(),
        }
    }
}

struct CompletionState {
    /// Talks to the local game. MUST stay bound to 0.0.0.0: a socket bound to a concrete
    /// LAN address cannot send to 127.0.0.1 (WinError 10049, measured in C3).
    forward: UdpSocket,
    game_addr: SocketAddr,
    max_pages: usize,
    /// M0-E audit B-2: hard cap on how many full rounds this Agent will run, so a hostile or
    /// glitching client cannot make the game generate adverts forever.
    max_replies: u64,
    replies: u64,
    /// M0-E audit B-2: one client refresh arrives as 100 magics on 100 different discovery
    /// ports but from ONE source endpoint. Keying on (client ip, client port) collapses the
    /// whole refresh into a single round; the cooldown keeps a client that hammers refresh
    /// from turning into a game-side load generator.
    answered: BTreeMap<(u32, u16), Instant>,
    cooldown: Duration,
    read_timeout: Duration,
    stats: CompletionStats,
}

impl CompletionState {
    fn new(
        game_addr: &str,
        timeout_ms: u64,
        max_pages: usize,
        max_replies: u64,
        cooldown_ms: u64,
    ) -> Result<Self, String> {
        let game_addr: SocketAddr = game_addr
            .parse()
            .map_err(|e| format!("bad --game-discovery-addr '{game_addr}': {e}"))?;
        if !game_addr.ip().is_loopback() {
            return Err(format!(
                "--game-discovery-addr must be a loopback address (got {game_addr}): the replay must reach the local game, not re-broadcast the client's magic onto the network"
            ));
        }
        let forward = UdpSocket::bind("0.0.0.0:0")
            .map_err(|e| format!("discovery completion: cannot bind forward socket: {e}"))?;
        let read_timeout = Duration::from_millis(timeout_ms);
        forward
            .set_read_timeout(Some(read_timeout))
            .map_err(|e| format!("discovery completion: cannot set read timeout: {e}"))?;
        let _ = forward.set_nonblocking(false);
        let egress_available = egress::available(&forward);
        let mut stats = CompletionStats::default();
        stats.egress_available = egress_available;
        Ok(CompletionState {
            forward,
            game_addr,
            max_pages,
            max_replies,
            replies: 0,
            answered: BTreeMap::new(),
            cooldown: Duration::from_millis(cooldown_ms),
            read_timeout,
            stats,
        })
    }

    /// Drop anything already queued on the forward socket (B-2): a previous round that ended
    /// on a short read can leave pages behind, and those pages belong to the OLD advert.
    /// Reading them as if they were this round's would forward a mixed advert.
    fn clear_backlog(&mut self, buf: &mut [u8]) {
        if self.forward.set_nonblocking(true).is_err() {
            return;
        }
        loop {
            match self.forward.recv_from(buf) {
                Ok((len, _)) if len > 0 => self.stats.backlog_cleared += 1,
                _ => break,
            }
        }
        let _ = self.forward.set_nonblocking(false);
    }

    /// One completion round: replay the client's magic into the local game and forward the
    /// game's own reply back to `client` from `listener` (so the client sees the answer
    /// coming from the very port it probed).
    ///
    /// Fail-closed: when the game does not answer (timeout / zero pages / send error) the
    /// client gets NOTHING. Returning an invented advert instead would show a room the host
    /// may not actually have - exactly the "virtual room" the owner rejected (m29860).
    /// Answer one discovery request with the local game's real advertisement.
    ///
    /// `probed_addr` is the local address the client actually sent its magic to (B-1). When
    /// it is known the reply is sent FROM that address, so the client keys the room to the
    /// address it used - not to whatever the route table would pick on a multi-homed host.
    fn handle(
        &mut self,
        listener: &UdpSocket,
        magic: &[u8],
        client: &SocketAddr,
        probed_addr: Option<SocketAddr>,
    ) -> CompletionOutcome {
        self.stats.requests_intercepted += 1;

        // B-2 budget: refuse before touching the game.
        if self.replies >= self.max_replies {
            self.stats.budget_exhausted += 1;
            return CompletionOutcome::BudgetExhausted;
        }

        // B-2 de-duplication: collapse the 100 magics of one refresh into one round.
        let key = match client.ip() {
            IpAddr::V4(v4) => (u32::from(v4), client.port()),
            IpAddr::V6(_) => {
                // The game is IPv4-only; an IPv6 source cannot be a Civ6 client.
                self.stats.duplicate_magic += 1;
                return CompletionOutcome::Duplicate;
            }
        };
        if let Some(last) = self.answered.get(&key) {
            if last.elapsed() < self.cooldown {
                self.stats.duplicate_magic += 1;
                return CompletionOutcome::Duplicate;
            }
        }

        let mut buf = vec![0u8; 4096];
        self.clear_backlog(&mut buf);

        match self.forward.send_to(magic, self.game_addr) {
            Ok(n) if n == magic.len() => self.stats.replays_sent += 1,
            Ok(_) => {
                self.stats.replays_failed += 1;
                return CompletionOutcome::ReplayFailed;
            }
            Err(_) => {
                self.stats.replays_failed += 1;
                return CompletionOutcome::ReplayFailed;
            }
        }
        // Record the attempt up front: a round that fails must still occupy the cooldown slot,
        // otherwise a client retrying faster than the game can answer would be let through
        // again and again (B-2 amplification).
        self.answered.insert(key, Instant::now());
        self.replies += 1;

        // Collect the game's pages. Only datagrams from the game's exact address AND port are
        // accepted (audit H-1): any process on this machine can send to the loopback forward
        // socket, and accepting those would let it choose the room name the client sees.
        // A wall-clock deadline is enforced independently of the "keep waiting" branches so
        // unrelated traffic cannot stretch a round indefinitely (audit H-1).
        let deadline = Instant::now() + self.read_timeout;
        let mut pages: Vec<Vec<u8>> = Vec::new();
        let mut odd = 0u64;
        while pages.len() < self.max_pages && Instant::now() < deadline {
            match self.forward.recv_from(&mut buf) {
                Ok((len, from)) => {
                    if from != self.game_addr {
                        continue; // not the game: ignore (the deadline still bounds the round)
                    }
                    if len == 0 {
                        continue;
                    }
                    if len != SIM_PAGE_SIZE {
                        odd += 1;
                    }
                    pages.push(buf[..len].to_vec());
                }
                Err(ref e)
                    if e.kind() == io::ErrorKind::WouldBlock
                        || e.kind() == io::ErrorKind::TimedOut =>
                {
                    break;
                }
                Err(_) => break,
            }
        }
        self.stats.odd_page_sizes += odd;
        self.stats.pages_collected += pages.len() as u64;

        if pages.is_empty() {
            // Distinguish "silence" from "answered with nothing": both mean the host has no
            // room to advertise right now (or the game is still loading one).
            if odd == 0 {
                self.stats.timeouts += 1;
            } else {
                self.stats.empty_replies += 1;
            }
            return CompletionOutcome::GameSilent;
        }
        if pages.len() < self.max_pages && pages.len() < SIM_PAGE_COUNT {
            // A partial set: the game stopped early. Forward it anyway (the client decides
            // whether it can parse a short advert) but count it so the summary shows it.
            self.stats.empty_replies += 1;
        }

        let mut ok = true;
        // B-1: pin the source address of every page to the address the client probed. A
        // fallback to send_to is kept (and counted) because the information can be missing
        // when the WSARecvMsg extension is unavailable.
        if let Some(pa) = probed_addr {
            self.stats.last_probe_addr = pa.to_string();
        }
        let pin = match probed_addr {
            Some(SocketAddr::V4(v4)) if !v4.ip().is_unspecified() && !v4.ip().is_loopback() => {
                self.stats.probe_addr_seen += 1;
                Some(*v4.ip())
            }
            _ => {
                // The IP_PKTINFO address was absent, unspecified, or loopback: loopback
                // traffic reports 127.0.0.1 and CANNOT be pinned (a packet whose source is
                // 127.0.0.1 cannot leave this host), so those replies legitimately fall back
                // to the routing table.
                self.stats.probe_addr_missing += 1;
                None
            }
        };
        for page in &pages {
            let sent = match pin {
                Some(ip) => match egress::send_from(listener, page, client, ip) {
                    Ok(n) if n == page.len() => {
                        self.stats.egress_pinned += 1;
                        true
                    }
                    Ok(_) => false,
                    Err(_) => match listener.send_to(page, client) {
                        Ok(n) if n == page.len() => {
                            self.stats.egress_unpinned += 1;
                            true
                        }
                        _ => false,
                    },
                },
                None => match listener.send_to(page, client) {
                    Ok(n) if n == page.len() => {
                        self.stats.egress_unpinned += 1;
                        true
                    }
                    _ => false,
                },
            };
            if sent {
                self.stats.pages_forwarded += 1;
            } else {
                self.stats.forwards_failed += 1;
                ok = false;
            }
        }
        if ok {
            CompletionOutcome::Forwarded
        } else {
            CompletionOutcome::ForwardFailed
        }
    }
}

#[derive(Debug, PartialEq, Eq)]
enum CompletionOutcome {
    Forwarded,
    ReplayFailed,
    GameSilent,
    ForwardFailed,
    /// B-2: the same client already had a round inside the cooldown window.
    Duplicate,
    /// B-2: --completion-max-replies exhausted.
    BudgetExhausted,
}


/// C1 (M0-C): decide which discovery ports the simulated LAN host binds.
///
/// Pure on purpose (no sockets, no I/O) so the `--reserve-62900` rule can be unit-tested
/// without occupying 100 real ports: with the flag set, the game's host port `62900` is
/// left out of the bind set, which is what guarantees that a room can always be (re-)created
/// even when the Agent started first (the m25442 symptom).
fn plan_discovery_ports(reserve_62900: bool) -> Vec<u16> {
    (DISCOVERY_FIRST..=DISCOVERY_LAST)
        .filter(|port| !(reserve_62900 && *port == SIM_REPLY_PORT))
        .collect()
}

impl LanSimState {
    fn new(
        fixture_dir: Option<&str>,
        listen_ip: &str,
        max_replies: u64,
        room: &str,
        out_dir: Option<&str>,
        reserve_62900: bool,
        completion: Option<CompletionState>,
    ) -> Result<Self, String> {
        // M0-E completion mode answers from the local game, so no fixture is needed at all;
        // in that case `pages` stays empty and is never consulted (poll short-circuits).
        let mut pages = match fixture_dir {
            Some(dir) => load_fixture_pages(dir)?,
            None => Vec::new(),
        };
        if fixture_dir.is_some() {
            anonymize_pages(&mut pages, room);
        }
        let ip = parse_dotted_ip(listen_ip)?;
        let mut stats = SimStats::default();
        let mut listeners = Vec::new();
        let mut reply_sock = None;
        let mut pktinfo_ok: u32 = 0;
        if reserve_62900 {
            // M0-C C1: leave 62900 to the game's LAN-host socket so the owner can always
            // (re-)create a room even when this Agent started first (m25442). The reply
            // source then falls back to the first bound port (62901..), logged as
            // `reply source` in the summary.
            eprintln!(
                "[!] LAN simulated host: {listen_ip}:{SIM_REPLY_PORT} reserved for the game host (--reserve-62900), not bound by the Agent"
            );
        }
        for port in plan_discovery_ports(reserve_62900) {
            let addr = SocketAddr::from((ip, port));
            match UdpSocket::bind(addr) {
                Ok(s) => {
                    let _ = s.set_nonblocking(true);
                    // M0-E audit B-1: completion mode needs IP_PKTINFO on every listener,
                    // otherwise the receive path cannot tell which local address the client
                    // probed and the reply's source address is left to the routing table.
                    if completion.is_some() {
                        if egress::enable_pktinfo(&s) {
                            pktinfo_ok += 1;
                        }
                    }
                    if port == SIM_REPLY_PORT {
                        reply_sock = Some(
                            s.try_clone()
                                .map_err(|e| format!("cannot clone reply socket {addr}: {e}"))?,
                        );
                    }
                    listeners.push(s);
                }
                Err(e) => {
                    stats.bind_fail += 1;
                    eprintln!(
                        "[!] LAN simulated host: cannot bind {addr}: {e} (port skipped; the game client sends one magic per port, so a skipped port only loses one of the 100 copies)"
                    );
                }
            }
        }
        if listeners.is_empty() {
            return Err(format!(
                "LAN simulated host: could not bind any discovery port on {listen_ip} (all 100 in use?)"
            ));
        }
        if reply_sock.is_none() {
            // 62900 itself failed (game already owns it) or was reserved (--reserve-62900):
            // pick the first bound socket as reply source (source port then differs from
            // SIM_REPLY_PORT; acceptable, and logged in the summary as `reply source`).
            reply_sock = Some(
                listeners[0]
                    .try_clone()
                    .map_err(|e| format!("cannot clone reply socket: {e}"))?,
            );
        }
        stats.reply_addr = reply_sock.as_ref().and_then(|s| s.local_addr().ok());
        let pktinfo_enabled = completion.is_some() && pktinfo_ok as usize == listeners.len();
        if let Some(dir) = out_dir {
            fs::create_dir_all(dir).map_err(|e| format!("cannot create {dir}: {e}"))?;
            for (i, p) in pages.iter().enumerate() {
                let path = format!("{dir}/lan-page-{:02}.bin", i + 1);
                fs::write(&path, p).map_err(|e| format!("cannot write {path}: {e}"))?;
            }
            let manifest = format!(
                "# LAN simulated host fixture\n\
                 # fixture dir: {}\n\
                 # room name: {room} (anonymized at offset {SIM_NAME_OFFSET}..{})\n\
                 # listen: {listen_ip} on {DISCOVERY_FIRST}..{DISCOVERY_LAST}; pages below are the exact reply bytes.\n\
                 # mode: {}\n",
                fixture_dir.unwrap_or("(none - M0-E completion mode answers from the local game)"),
                SIM_NAME_OFFSET + SIM_NAME_LEN,
                if completion.is_some() {
                    "discovery completion (loopback replay, real room from the local game)"
                } else {
                    "fixture / captured advertisement"
                }
            );
            let path = format!("{dir}/lan-fixture-manifest.txt");
            fs::write(&path, manifest).map_err(|e| format!("cannot write {path}: {e}"))?;
        }
        let reply_addr = reply_sock.as_ref().and_then(|s| s.local_addr().ok());
        // B-1: the completion state records whether the probed address is knowable at all.
        let completion = completion.map(|mut c| {
            c.stats.pktinfo_enabled = pktinfo_enabled;
            c
        });
        Ok(LanSimState {
            pages,
            listeners,
            reply_sock,
            reply_addr,
            max_replies,
            stats,
            answered: BTreeMap::new(),
            completion,
        })
    }

    /// Non-blocking drain of every bound discovery port. Returns the number of magic
    /// datagrams handled (for the caller's log accounting).
    ///
    /// B1 (--sim-real-capture): `cache` receives non-magic datagrams on the discovery ports
    /// (capture path P2 - A-machine Civ6 advertisement pages broadcast on the LAN, received
    /// via loopback on this machine). When the cache holds the full 22-page set, replies are
    /// served from the REAL pages instead of the fixture.
    fn poll(&mut self, buf: &mut [u8], mut cache: Option<&mut RealAdCache>) -> u64 {
        let mut handled = 0;
        let mut i = 0;
        while i < self.listeners.len() {
            loop {
                // M0-E audit B-1: learn the address the client actually probed, so the reply
                // can be sent FROM that address. A plain recv_from on a wildcard socket does
                // not expose it, and without it the OS picks the source address from the
                // route table - which on a multi-homed host is not necessarily the one the
                // client used to reach us.
                let received = if self.completion.is_some() {
                    match egress::recv_with_dst(&self.listeners[i], buf) {
                        Ok(Some(info)) => Some(info),
                        Ok(None) => break, // nothing queued (non-blocking socket)
                        Err(ref e)
                            if e.kind() == io::ErrorKind::WouldBlock
                                || e.kind() == io::ErrorKind::TimedOut =>
                        {
                            break
                        }
                        Err(e) => {
                            // B-1: surface the real errno instead of silently ending the
                            // drain - a wrong WSARecvMsg signature shows up as "requests
                            // seen 0" and nothing else.
                            if self.completion.is_some() {
                                if let Some(c) = self.completion.as_mut() {
                                    c.stats.recv_errors += 1;
                                    c.stats.last_recv_error = e.raw_os_error().unwrap_or(-1);
                                }
                            }
                            break
                        }
                    }
                } else {
                    match self.listeners[i].recv_from(buf) {
                        Ok((len, from)) => Some(egress::RecvInfo {
                            len,
                            from,
                            local_addr: None,
                        }),
                        Err(ref e)
                            if e.kind() == io::ErrorKind::WouldBlock
                                || e.kind() == io::ErrorKind::TimedOut =>
                        {
                            break
                        }
                        Err(_e) => break,
                    }
                };
                let info = match received {
                    Some(v) => v,
                    None => break,
                };
                let len = info.len;
                let from = info.from;
                if is_discovery_magic(&buf[..len]) {
                    // M0-E: in completion mode the answer comes from the LOCAL game itself,
                    // not from the fixture and not from the B1 capture cache. This branch
                    // takes precedence over both.
                    if self.completion.is_some() {
                        // Take the state out so `self.listeners[i]` can be borrowed while it
                        // is being used (handle blocks for at most one
                        // --completion-timeout-ms round).
                        let mut comp = match self.completion.take() {
                            Some(c) => c,
                            None => unreachable!(),
                        };
                        let outcome = comp.handle(
                            &self.listeners[i],
                            &buf[..len],
                            &from,
                            info.local_addr,
                        );
                        let game_addr = comp.game_addr;
                        self.completion = Some(comp);
                        if outcome == CompletionOutcome::ReplayFailed {
                            eprintln!("[!] discovery completion: replay to {game_addr} failed");
                        }
                        handled += 1;
                        continue;
                    }
                    let real_pages = cache
                        .as_ref()
                        .filter(|c| c.active)
                        .map(|c| c.pages.as_slice());
                    let outcome = self.consider(&from, real_pages);
                    if let Some(c) = cache.as_mut() {
                        match outcome {
                            ReplyOutcome::Real => c.stats.replies_used_real += 1,
                            ReplyOutcome::Fixture => c.stats.replies_used_fixture += 1,
                            ReplyOutcome::Skipped => c.stats.replies_skipped += 1,
                        }
                    }
                    handled += 1;
                } else if let Some(c) = cache.as_mut() {
                    // B1 path P2: a non-magic datagram on a discovery port may be a real
                    // advertisement page (A-machine Civ6 hosting + broadcast). Only NotAPage
                    // counts as noise (audit R-2); any valid page - stored, duplicate, or
                    // full-set-rejected - flips active when the full set is held.
                    match c.try_capture(&buf[..len], "P2-lan") {
                        CaptureOutcome::NotAPage => {
                            c.stats.noise_on_discovery_port += 1;
                        }
                        _ => {
                            if c.pages.len() == SIM_PAGE_COUNT {
                                c.active = true;
                            }
                        }
                    }
                }
                // Non-magic datagrams on discovery ports are ignored unless
                // --sim-real-capture is on (B1 path P2 handled above).
            }
            i += 1;
        }
        handled
    }

    /// Answer one discovery request (once per (src ip, src port) key). When `real_pages` is
    /// Some (the B1 capture holds the full set), the real pages are sent; otherwise the
    /// fixture pages. Returns the tri-state outcome (audit R-3): Real / Fixture when the
    /// reply was actually sent, Skipped when it was NOT answered for any reason (dedup
    /// skip, src port 0, max replies, no reply socket, or a send failure - a failed send
    /// is NOT a fixture reply).
    fn consider(&mut self, from: &SocketAddr, real_pages: Option<&[Vec<u8>]>) -> ReplyOutcome {
        let ip = match from.ip() {
            IpAddr::V4(v4) => u32::from(v4),
            IpAddr::V6(_) => return ReplyOutcome::Skipped, // the game is IPv4-only
        };
        let src_port = from.port();
        if src_port == 0 {
            self.stats.no_endpoint += 1;
            return ReplyOutcome::Skipped;
        }
        self.stats.requests_seen += 1;
        let key = (ip.to_be(), src_port.to_be());
        if self.answered.contains_key(&key) {
            return ReplyOutcome::Skipped;
        }
        if self.stats.replied_sockets >= self.max_replies {
            self.stats.max_replies_reached += 1;
            return ReplyOutcome::Skipped;
        }
        let reply_sock = match self.reply_sock.as_ref() {
            Some(s) => s,
            None => return ReplyOutcome::Skipped,
        };
        let pages: &[Vec<u8>] = match real_pages {
            Some(p) if !p.is_empty() => p,
            _ => &self.pages,
        };
        let mut ok = true;
        for page in pages {
            match reply_sock.send_to(page, from) {
                Ok(n) if n == page.len() => self.stats.pages_sent += 1,
                _ => {
                    self.stats.send_fail += 1;
                    ok = false;
                }
            }
        }
        if ok {
            self.answered.insert(key, true);
            self.stats.replied_sockets += 1;
            if real_pages.is_some() {
                ReplyOutcome::Real
            } else {
                ReplyOutcome::Fixture
            }
        } else {
            ReplyOutcome::Skipped
        }
    }
}

// ----------------------------------------------------------------- B1 real advertisement capture
//
// B1: capture the REAL advertisement pages
// that A-machine Civ6 sends when it hosts a game (via the Hook chain, path P1) or that it
// broadcasts on the LAN (via the discovery-port listeners, path P2), cache them, and answer
// discovery requests with the real pages instead of the anonymized fixture.
//
// Identification rule: a page is exactly SIM_PAGE_SIZE (1104) bytes and its first four bytes
// are SIM_MAGIC (59 60 69 9B) - the same header the fixture pages carry. This is mutually
// exclusive with the 4-byte discovery magic (8D E8 FC 70) by length alone.
#[derive(Default)]
struct RealAdStats {
    captured: u64,
    /// A NEW distinct page when the 22-page set is already full (the set is closed).
    rejected: u64,
    /// Byte-identical pages already held (same page arriving via P1 hook chain AND P2 LAN
    /// loopback counts once). Not a rejection - the page is valid, just already captured.
    duplicates: u64,
    /// P2 candidates seen on a discovery port that were not real pages (noise).
    noise_on_discovery_port: u64,
    /// Replies served from the real capture (>= SIM_PAGE_COUNT pages) vs the fixture.
    replies_used_real: u64,
    /// Replies served from the fixture pages (real capture not yet active).
    replies_used_fixture: u64,
    /// Discovery requests that were NOT answered (dedup skip, src port 0, max replies,
    /// missing reply socket, send failure). NOT a fixture reply.
    replies_skipped: u64,
}

/// B1 audit R-2: outcome of one capture attempt. A valid page - whether stored, a duplicate,
/// or rejected because the full set is closed - is NOT noise. Only NotAPage is noise.
enum CaptureOutcome {
    Captured,
    Duplicate,
    FullRejected,
    NotAPage,
}

/// B1 audit R-3: outcome of one discovery reply attempt. Skipped (dedup / no endpoint /
/// max replies / no socket / send failure) is NOT a fixture reply.
enum ReplyOutcome {
    Real,
    Fixture,
    Skipped,
}

/// B1 capture cache. Owned by run(); poll() and the frame loop hand it in as needed.
/// A capture only becomes the active reply set once it holds all SIM_PAGE_COUNT pages -
/// a partial capture is NOT used (avoid a half-real, half-anonymous reply set; the fixture
/// remains the fallback). `active` is flipped when the cache reaches the full set.
struct RealAdCache {
    pages: Vec<Vec<u8>>,
    stats: RealAdStats,
    active: bool,
}

impl RealAdCache {
    fn new() -> Self {
        RealAdCache {
            pages: Vec::with_capacity(SIM_PAGE_COUNT),
            stats: RealAdStats::default(),
            active: false,
        }
    }

    /// Validate one candidate and classify it (B1 audit R-2/S-4): a valid page - whether
    /// stored, a duplicate, or rejected because the full set is closed - is NEVER noise;
    /// only NotAPage is. The caller flips `active` when the cache holds the full set.
    ///
    /// Deduplication (B1 audit round): the same page can arrive twice - via the hook chain
    /// (P1, the A-machine game's own broadcast being forwarded) and via the LAN loopback
    /// (P2, the agent's own discovery-port listener receiving that same broadcast). A
    /// byte-identical page already in the set must not inflate `captured` nor the file set;
    /// it is counted once in `duplicates`.
    fn try_capture(&mut self, data: &[u8], source: &str) -> CaptureOutcome {
        if data.len() == SIM_PAGE_SIZE && data[..4] == SIM_MAGIC {
            if self.pages.iter().any(|p| p.as_slice() == data) {
                self.stats.duplicates += 1;
                eprintln!(
                    "[+] B1 real advertisement page (dup of page {}) via {source}",
                    self.pages
                        .iter()
                        .position(|p| p.as_slice() == data)
                        .unwrap_or(0)
                        + 1
                );
                return CaptureOutcome::Duplicate;
            }
            if self.pages.len() >= SIM_PAGE_COUNT {
                // Full set already held: a NEW page beyond the 22 cannot extend the set
                // (the fixture's 22 pages define the reply format). Count it as rejected -
                // the set is closed, and a 23rd distinct page is outside the contract.
                self.stats.rejected += 1;
                return CaptureOutcome::FullRejected;
            }
            self.pages.push(data.to_vec());
            self.stats.captured += 1;
            eprintln!(
                "[+] B1 real advertisement page {}/{} captured via {source}",
                self.pages.len(),
                SIM_PAGE_COUNT
            );
            CaptureOutcome::Captured
        } else {
            CaptureOutcome::NotAPage
        }
    }
}

// ----------------------------------------------------------------- F2 datapath observation
//
// codex review F2-DATAPATH-REVIEW-20261114.md:
//   §2.1  --bind-ip is mandatory, host-local only, fail-closed (no silent fallback).
//   §2.2  Agent never binds :62056, never sets SO_REUSEADDR, never infers H2/R1 from any
//         bind/deliver result. Datapath frames arrive via CVLH2; the reply uses an
//         independent ephemeral UDP socket.
//   D4    At most ONE 20-byte fixed probe per run, only to a source confirmed local with a
//         non-zero port; 0.0.0.0:0 / non-local / incomplete endpoints are only recorded.
//         The reply is a local probe, NOT a real-host protocol answer.
#[derive(Default)]
struct DatapathStats {
    frames_seen: u64,
    frames_on_datapath_port: u64, // dst port == 62056 (the F2 question)
    reply_sent: u64,
    reply_skipped_no_endpoint: u64,
    reply_skipped_not_local: u64,
    reply_already_sent: u64,
    send_fail: u64,
    bytes: u64,
}

struct DatapathState {
    bind_ip: [u8; 4], // host-local address, fail-closed (--bind-ip)
    stats: DatapathStats,
    reply_sock: UdpSocket, // ephemeral source port, NOT bound to :62056
}

impl DatapathState {
    /// bind_ip must be a current host-local address; the caller (driver) verifies it via
    /// Get-NetIPConfiguration. The agent only sanity-checks the dotted quad and stores it.
    fn new(bind_ip: &str) -> Result<Self, String> {
        let ip = parse_dotted_ip(bind_ip)
            .map_err(|e| format!("bad --bind-ip: {e} (must be a current host-local address)"))?;
        if ip == [0, 0, 0, 0] || ip == [255, 255, 255, 255] {
            return Err(
                "--bind-ip must be a host-local address, not 0.0.0.0/255.255.255.255".to_string(),
            );
        }
        let reply_sock = UdpSocket::bind("0.0.0.0:0")
            .map_err(|e| format!("cannot create datapath reply socket: {e}"))?;
        Ok(DatapathState {
            bind_ip: ip,
            stats: DatapathStats::default(),
            reply_sock,
        })
    }

    fn local_port(&self) -> u16 {
        self.reply_sock.local_addr().map(|a| a.port()).unwrap_or(0)
    }

    /// Called for every ACCEPTED frame that is NOT a discovery request (i.e. any outbound
    /// frame that the game sent outside the 62900..62999 discovery window - typically the
    /// 62056 datapath). Records the frame; under D4 sends at most ONE 20-byte fixed probe.
    fn consider(&mut self, frame: &Frame, mut log: Option<&mut dyn Write>) {
        let src_ip = ipv4_from_be(frame.src_ip_be);
        let src_port = port_from_be16(frame.src_port_be);
        let dst_port = port_from_be16(frame.dst_port_be);
        if let Some(w) = log.as_mut() {
            let _ = writeln!(
                w,
                "{} datapath src={}:{} dst={}:{} len={} flags=0x{:02x} head={}",
                wallclock_stamp(),
                src_ip,
                src_port,
                ipv4_from_be(frame.dst_ip_be),
                dst_port,
                frame.payload_len,
                frame.flags,
                if frame.payload_len == 0 {
                    "-".to_string()
                } else {
                    hex4(&frame.payload[..frame.payload.len().min(8)])
                }
            );
        }
        self.stats.frames_seen += 1;
        if dst_port == DATAPATH_PORT {
            self.stats.frames_on_datapath_port += 1;
        }

        if frame.src_port_be == 0 {
            // D4: 0.0.0.0:0 (unbound socket first frame) -> record only, never reply.
            self.stats.reply_skipped_no_endpoint += 1;
            return;
        }
        if frame.src_ip_be == 0 || frame.src_ip_be != be_bytes_to_u32(&self.bind_ip) {
            // D4: source must be confirmed local. The frame's src_ip is the raw network-order
            // bytes of sin_addr, read little-endian by get_u32le. Compare against bind_ip.
            self.stats.reply_skipped_not_local += 1;
            return;
        }
        if self.stats.reply_sent >= 1 {
            // D4: at most ONE 20B probe for the whole run.
            self.stats.reply_already_sent += 1;
            return;
        }
        let dst = SocketAddr::from((self.bind_ip, src_port));
        match self.reply_sock.send_to(&DATAPATH_REPLY_PAYLOAD, dst) {
            Ok(n) if n == DATAPATH_REPLY_LEN => {
                self.stats.reply_sent += 1;
                self.stats.bytes += n as u64;
                if let Some(w) = log.as_mut() {
                    let _ = writeln!(
                        w,
                        "{} datapath reply sent {}B to {} (ephemeral src port {}) - local probe only",
                        wallclock_stamp(),
                        n,
                        dst,
                        self.local_port()
                    );
                }
            }
            _ => self.stats.send_fail += 1,
        }
    }
}

/// Convert a host-order [u8;4] to the little-endian u32 that the frame's src_ip_be carries
/// for the same address (get_u32le of the network-order bytes).
fn be_bytes_to_u32(ip: &[u8; 4]) -> u32 {
    u32::from(ip[0]) | (u32::from(ip[1]) << 8) | (u32::from(ip[2]) << 16) | (u32::from(ip[3]) << 24)
}

// ---------------------------------------------------------------------------
// F3-A: direct forward prototype (loopback only, no game-process injection)
// ---------------------------------------------------------------------------
//
// Design v0.3 §3.2: a datapath outbound frame is forwarded to ONE target - the peer
// Agent's forward-receive port - never to the peer's game socket or :62056. The mapping
// key is the same shape the civlink-fakeip crate defines
// (session_id, logical_socket_id, socket_generation, dst); the crate stays the reference
// implementation for M0-B, this prototype allocates the entry on first traffic (§4.3
// lifecycle rule) and only ever points it at the single configured target.

#[derive(Default)]
struct ForwardStats {
    frames_seen: u64,
    forwarded: u64,
    forward_fail: u64,
    // Frames deliberately not forwarded, split by reason (F3-A audit finding B-2: the old
    // single counter was described as "no mapping" but only ever counted "dst != 62056").
    skip_not_datapath: u64,
    skip_key_table_full: u64,
    // Frames recognised as discovery requests and therefore left to the F1 path (design v0.3
    // §3.2 rule 3). Counted here because otherwise a discovery frame would vanish from every
    // counter and the forward stage would look like it had silently lost traffic.
    skip_discovery: u64,
    // Frames the Hook itself could not carry (REJECTED_OVERSIZE | NO_PAYLOAD). They reach the
    // forward stage but have no payload to forward, so they are counted as SEEN and skipped here
    // (F3-A audit round 3, finding L5). Without this they were invisible to the forward stage
    // entirely, which made "every accepted frame is accounted for" true only for the frames this
    // stage happened to look at.
    skip_rejected_flags: u64,
    bytes: u64,
    mappings_created: u64,
}

/// Prototype scale: a fixed-size key list, not the crate's HashMap. The cap is what makes the
/// "no mapping -> do not forward" branch of design v0.3 §3.2 reachable at all; without it the
/// prototype would always have a mapping and the branch could never be exercised (F3-A audit
/// finding B-2).
const MAX_FORWARD_KEYS: usize = 64;

struct ForwardMapKey {
    session_id: u64,
    logical_socket_id: u32,
    socket_generation: u32,
    dst_ip_be: u32,
    dst_port_be: u16,
}

struct ForwardState {
    target: SocketAddr,
    sock: UdpSocket,
    stats: ForwardStats,
    keys: Vec<ForwardMapKey>, // prototype scale: a linear list, not the crate's HashMap
}

impl ForwardState {
    fn new(target: &str) -> Result<Self, String> {
        let target: SocketAddr = target
            .parse()
            .map_err(|e| format!("bad --forward-to '{target}': {e} (want ip:port)"))?;
        let sock = UdpSocket::bind("0.0.0.0:0")
            .map_err(|e| format!("cannot create forward socket: {e}"))?;
        Ok(ForwardState {
            target,
            sock,
            stats: ForwardStats::default(),
            keys: Vec::new(),
        })
    }

    /// Ensures a mapping exists for this key. Returns false when the table is full, so the
    /// caller can honour design v0.3 §3.2 step 2 "no mapping -> do not forward" instead of
    /// forwarding unconditionally (F3-A audit finding B-2).
    fn ensure_mapping(&mut self, frame: &Frame) -> bool {
        if self.keys.iter().any(|k| {
            k.session_id == frame.session_id
                && k.logical_socket_id == frame.logical_socket_id
                && k.socket_generation == frame.socket_generation
                && k.dst_ip_be == frame.dst_ip_be
                && k.dst_port_be == frame.dst_port_be
        }) {
            return true;
        }
        if self.keys.len() >= MAX_FORWARD_KEYS {
            return false;
        }
        self.keys.push(ForwardMapKey {
            session_id: frame.session_id,
            logical_socket_id: frame.logical_socket_id,
            socket_generation: frame.socket_generation,
            dst_ip_be: frame.dst_ip_be,
            dst_port_be: frame.dst_port_be,
        });
        self.stats.mappings_created += 1;
        true
    }

    /// Forwards the payload of one accepted non-discovery frame, verbatim, to the peer
    /// Agent's forward-receive port. Never retransmits, never rewrites the payload.
    fn consider(&mut self, frame: &Frame, mut log: Option<&mut dyn Write>) {
        self.stats.frames_seen += 1;
        let dst_port = port_from_be16(frame.dst_port_be);
        if dst_port != DATAPATH_PORT {
            self.stats.skip_not_datapath += 1;
            if let Some(w) = log.as_mut() {
                let _ = writeln!(
                    w,
                    "{} forward skip dst_port={} (not the 62056 datapath)",
                    wallclock_stamp(),
                    dst_port
                );
            }
            return;
        }
        if !self.ensure_mapping(frame) {
            self.stats.skip_key_table_full += 1;
            if let Some(w) = log.as_mut() {
                let _ = writeln!(
                    w,
                    "{} forward skip seq={} (no mapping: key table full at {})",
                    wallclock_stamp(),
                    frame.seq,
                    MAX_FORWARD_KEYS
                );
            }
            return;
        }
        let digest = sha256_hex(&frame.payload);
        match self.sock.send_to(&frame.payload, self.target) {
            Ok(n) if n == frame.payload.len() => {
                self.stats.forwarded += 1;
                self.stats.bytes += n as u64;
                if let Some(w) = log.as_mut() {
                    let _ = writeln!(
                        w,
                        "{} forward seq={} sock={} gen={} dst={}:{} len={} sha256={} payload={} -> {}",
                        wallclock_stamp(),
                        frame.seq,
                        frame.logical_socket_id,
                        frame.socket_generation,
                        ipv4_from_be(frame.dst_ip_be),
                        dst_port,
                        frame.payload_len,
                        digest,
                        hex4(&frame.payload[..frame.payload.len().min(8)]),
                        self.target
                    );
                }
            }
            _ => {
                self.stats.forward_fail += 1;
                if let Some(w) = log.as_mut() {
                    let _ = writeln!(
                        w,
                        "{} forward FAILED seq={} len={} sha256={} -> {} (send_to failed; see forward fail counter)",
                        wallclock_stamp(),
                        frame.seq,
                        frame.payload_len,
                        digest,
                        self.target
                    );
                }
            }
        }
    }
}

/// Peer side of the F3-A prototype: records what actually arrived, with a timestamp, so the
/// evidence can show delivery rather than just "the sender said it sent".
#[derive(Default)]
struct PeerStats {
    received: u64,
    bytes: u64,
    last_from: String,
    /// First sender address seen, so the driver can assert that what arrived came from the
    /// forwarder's own socket (identity binding) rather than from anywhere on loopback.
    first_from: String,
}

struct ForwardListener {
    sock: UdpSocket, // bound to 127.0.0.1:<--forward-listen>, never :62056
    stats: PeerStats,
}

impl ForwardListener {
    fn new(port: u16) -> Result<Self, String> {
        if port == DATAPATH_PORT {
            // Fail-closed (F3-A audit round 2, finding M2): the Agent must never own the game's
            // data-plane port, even by accident. --forward-listen already rejects it in
            // parse_args; this is the second, unforgeable guard at the bind site itself, so a
            // future caller cannot reintroduce the hole.
            return Err(format!(
                "forward-listener must not use port {DATAPATH_PORT}: the game's data-plane port is never owned by a CivLink process"
            ));
        }
        let addr = SocketAddr::from(([127, 0, 0, 1], port));
        let sock = UdpSocket::bind(addr)
            .map_err(|e| format!("cannot bind forward-listener {addr}: {e}"))?;
        sock.set_nonblocking(true)
            .map_err(|e| format!("set_nonblocking failed: {e}"))?;
        Ok(ForwardListener {
            sock,
            stats: PeerStats::default(),
        })
    }

    fn drain(&mut self, buf: &mut [u8], mut log: Option<&mut dyn Write>) {
        loop {
            match self.sock.recv_from(buf) {
                Ok((len, from)) => {
                    self.stats.received += 1;
                    self.stats.bytes += len as u64;
                    self.stats.last_from = from.to_string();
                    if self.stats.first_from.is_empty() {
                        self.stats.first_from = from.to_string();
                    }
                    if let Some(w) = log.as_mut() {
                        let _ = writeln!(
                            w,
                            "{} peer-recv n={} from={} len={} sha256={} payload={}",
                            wallclock_stamp(),
                            self.stats.received,
                            from,
                            len,
                            sha256_hex(&buf[..len]),
                            hex4(&buf[..len.min(8)])
                        );
                    }
                }
                Err(ref e) if e.kind() == io::ErrorKind::WouldBlock => return,
                Err(_) => return,
            }
        }
    }
}

fn decode(buf: &[u8]) -> Result<Frame, FrameError> {
    if buf.len() < FRAME_HDR {
        return Err(FrameError::TooShort(buf.len()));
    }
    if buf[0..4] != FRAME_MAGIC {
        return Err(FrameError::BadMagic);
    }
    if buf[4] != FRAME_VER {
        return Err(FrameError::BadVersion(buf[4]));
    }
    let payload_len = usize::from(get_u16le(&buf[40..42]));
    if payload_len > MAX_PAYLOAD {
        return Err(FrameError::PayloadTooLarge(payload_len));
    }
    if buf.len() < FRAME_HDR + payload_len {
        return Err(FrameError::Truncated {
            declared: payload_len,
            actual: buf.len().saturating_sub(FRAME_HDR),
        });
    }
    let dir = buf[5];
    if dir != DIR_HOOK_TO_AGENT {
        return Err(FrameError::WrongDirection(dir));
    }
    let af = buf[26];
    if af != 2 {
        return Err(FrameError::BadAddressFamily(af));
    }
    Ok(Frame {
        dir,
        seq: get_u32le(&buf[6..10]),
        session_id: get_u64le(&buf[10..18]),
        logical_socket_id: get_u32le(&buf[18..22]),
        socket_generation: get_u32le(&buf[22..26]),
        af,
        src_ip_be: get_u32le(&buf[27..31]),
        src_port_be: get_u16le(&buf[31..33]),
        dst_ip_be: get_u32le(&buf[33..37]),
        dst_port_be: get_u16le(&buf[37..39]),
        flags: buf[39],
        payload_len,
        payload: buf[FRAME_HDR..FRAME_HDR + payload_len].to_vec(),
    })
}

// ----------------------------------------------------------------- session bookkeeping
#[derive(Default)]
struct SessionStats {
    frames: u64,
    first_seq: Option<u32>,
    last_seq: Option<u32>,
    seq_gaps: u64,
    seq_missing_frames: u64,
    duplicates: u64,
    out_of_order: u64,
    payload_bytes: u64,
    discovery_magic: u64,
    not_discovery_magic: u64,
    rejected_oversize_frames: u64,
    no_payload_frames: u64,
    via_wsasendto: u64,
    limited_bcast: u64,
    discovery_flagged: u64,
    sockets: BTreeMap<u32, u64>,
    ports: BTreeMap<u16, u64>,
    src_endpoints: BTreeMap<String, u64>,
}

impl SessionStats {
    fn note_seq(&mut self, seq: u32) {
        match (self.first_seq, self.last_seq) {
            (None, _) => {
                self.first_seq = Some(seq);
                self.last_seq = Some(seq);
            }
            (Some(first), Some(last)) => {
                if seq == last {
                    self.duplicates += 1;
                } else if seq > last {
                    let expected = last.wrapping_add(1);
                    if seq > expected {
                        self.seq_gaps += 1;
                        self.seq_missing_frames += u64::from(seq - expected);
                    }
                    self.last_seq = Some(seq);
                } else if seq < first {
                    // Older than anything seen: count as out of order, keep the window.
                    self.out_of_order += 1;
                } else if seq < last {
                    self.out_of_order += 1;
                    if seq > first {
                        self.duplicates += 1;
                    }
                }
            }
            _ => {}
        }
    }
}

#[derive(Default)]
struct Totals {
    datagrams: u64,
    received: u64,
    processed: u64,
    rejected: u64,
    notify_frames: u64,
    reject_by_kind: BTreeMap<&'static str, u64>,
    sessions: BTreeMap<u64, SessionStats>,
    bytes: u64,
    large_datagrams: u64,
}

fn hex4(b: &[u8]) -> String {
    let mut s = String::with_capacity(b.len() * 2);
    for x in b {
        s.push_str(&format!("{:02X}", x));
    }
    s
}

fn wallclock_stamp() -> String {
    // HH:MM:SS.mmm from the system clock. Not used for interval math (that uses Instant).
    let now = SystemTime::now();
    let since = now
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap_or(Duration::ZERO);
    let total = since.as_millis();
    let ms = total % 1000;
    let secs = (total / 1000) % 86_400;
    format!(
        "{:02}:{:02}:{:02}.{:03}",
        secs / 3600,
        (secs / 60) % 60,
        secs % 60,
        ms
    )
}

struct Args {
    port: u16,
    listen_seconds: u64,
    out_dir: Option<String>,
    quiet: bool,
    stop_file: Option<String>,
    simulate: Option<String>,
    sim_max_replies: u64,
    sim_src_ip: String,
    sim_room_name: String,
    /// F5 (REV-016 双机发现): bind all 100 discovery ports on a LAN address and answer
    /// real Civ6 discovery broadcasts directly, without the Hook chain. The reply source
    /// is <listen-ip>:62900 (SIM_REPLY_PORT), same shape as the hook-chain simulated host.
    sim_lan_listen: Option<String>,
    /// B1: capture REAL advertisement pages (1104 B, magic 59 60 69 9B) that A-machine
    /// Civ6 sends - via the Hook chain (P1) or on the LAN discovery ports (P2) - and
    /// answer discovery with the real pages instead of the anonymized fixture once a
    /// full 22-page set is captured. Default off = the F5 behaviour is unchanged.
    sim_real_capture: bool,
    /// M0-C C1 (v0.4.6): the A-host (room owner) integration must never block the game
    /// from (re-)creating a room. Civ6's LAN-host socket binds 0.0.0.0:62900
    /// (DISCOVERY_FIRST), and an Agent that started first and holds all 100 discovery
    /// ports makes that bind fail (WSAEADDRINUSE) - the historical "cannot create room"
    /// bug (RUNBOOK step-2 ordering). With --reserve-62900 the Agent skips binding
    /// 62900 itself and replies from the first port it DID bind (62901..), leaving
    /// 62900 permanently free for the game. Discovery still works: the client sends one
    /// magic per port and the Agent dedups by (src ip, src port), so a reply only needs
    /// ONE of the remaining 99 datagrams to arrive.
    reserve_62900: bool,
    /// M0-E: discovery completion mode.
    /// Instead of fabricating a reply, the Agent replays the client's magic back into the
    /// LOCAL game over loopback and forwards whatever the game answers to the client. The
    /// reply is therefore always the REAL room, generated by the game itself: the Agent
    /// never invents protocol content and never caches a stale advert. Requires
    /// --sim-lan-listen, needs no fixture (--simulate is not used in this mode), and always
    /// implies --reserve-62900 (binding 62900 would hijack the game's own unicast - the
    /// SO_REUSEADDR trap documented in the independent research).
    discovery_completion: bool,
    /// Where the local game listens for discovery (M0-E). Loopback by default: the replay
    /// must reach the game's own socket, never cross the network.
    game_discovery_addr: String,
    /// How long one replay waits for the game's pages before giving up (M0-E).
    completion_timeout_ms: u64,
    /// Defensive cap on pages collected from a single replay (M0-E).
    completion_max_pages: usize,
    /// M0-E audit B-2: total full rounds before the Agent refuses to ask the game any more.
    completion_max_replies: u64,
    /// M0-E audit B-2: how long one client endpoint is suppressed after a round, so the 100
    /// magics of a single refresh collapse into one round.
    completion_cooldown_ms: u64,
    simulate_datapath: bool,
    bind_ip: Option<String>,
    loopback_selftest: bool,
    forward_to: Option<String>,
    forward_listen: Option<u16>,
    /// M0-G: peer discovery + multi-path probe mode (mutually exclusive with all above).
    peer_discover: bool,
    discover_interval_ms: u64,
    discover_port: u16,
    probe_port: u16,
    include_vpn: bool,
    peers_dir: Option<String>,
    /// Comma-separated IPv4 list: participate ONLY on NICs carrying one of these addresses.
    /// This is the GUI NIC checkbox selection; without it the agent enumerates every
    /// eligible NIC and silently ignores what the operator ticked.
    ifaces: Option<String>,
    /// Hidden: run the pure-core selftest (works in the default zero-dependency build).
    peer_discover_selftest: bool,
}

fn parse_args() -> Result<Args, String> {
    let mut args = Args {
        port: DEFAULT_PORT,
        listen_seconds: 60,
        out_dir: None,
        quiet: false,
        stop_file: None,
        simulate: None,
        sim_max_replies: 20,
        sim_src_ip: "127.0.0.1".to_string(),
        sim_room_name: "CivLink-Test-Room-2222".to_string(),
        sim_lan_listen: None,
        sim_real_capture: false,
        reserve_62900: false,
        discovery_completion: false,
        game_discovery_addr: "127.0.0.1:62900".to_string(),
        completion_timeout_ms: 1000,
        completion_max_pages: SIM_PAGE_COUNT,
        completion_max_replies: 1000,
        completion_cooldown_ms: 750,
        simulate_datapath: false,
        bind_ip: None,
        loopback_selftest: false,
        forward_to: None,
        forward_listen: None,
        peer_discover: false,
        discover_interval_ms: 3000,
        discover_port: 63010,
        probe_port: 63011,
        include_vpn: false,
        peers_dir: None,
        ifaces: None,
        peer_discover_selftest: false,
    };
    let mut it = env::args().skip(1);
    while let Some(a) = it.next() {
        match a.as_str() {
            "--port" => {
                // F3-A audit finding B-1: --forward-listen refused 62056 but --port did not,
                // so the D2 red line (the Agent never owns the game's data-plane port) was
                // only closed on one of two paths. Fail closed here as well.
                let v = it.next().ok_or("--port needs a value")?;
                let p: u16 = v.parse().map_err(|_| format!("bad port: {v}"))?;
                if p == DATAPATH_PORT {
                    return Err(format!(
                        "--port must not be {DATAPATH_PORT}: the Agent never binds the game's data-plane port"
                    ));
                }
                args.port = p;
            }
            "--listen-seconds" => {
                let v = it.next().ok_or("--listen-seconds needs a value")?;
                args.listen_seconds = v.parse().map_err(|_| format!("bad seconds: {v}"))?;
            }
            "--out-dir" => {
                args.out_dir = Some(it.next().ok_or("--out-dir needs a value")?);
            }
            "--stop-file" => {
                // A live run has no fixed deadline: the driver creates this file to ask for a
                // clean stop, so the summary is still written. Killing the process would lose it.
                args.stop_file = Some(it.next().ok_or("--stop-file needs a value")?);
            }
            "--simulate" => {
                args.simulate = Some(it.next().ok_or("--simulate needs a fixture directory")?);
            }
            "--sim-max-replies" => {
                let v = it.next().ok_or("--sim-max-replies needs a value")?;
                args.sim_max_replies = v.parse().map_err(|_| format!("bad count: {v}"))?;
            }
            "--sim-src-ip" => {
                let v = it.next().ok_or("--sim-src-ip needs a value")?;
                parse_dotted_ip(&v).map_err(|e| format!("bad --sim-src-ip: {e}"))?;
                args.sim_src_ip = v;
            }
            "--sim-room-name" => {
                let v = it.next().ok_or("--sim-room-name needs a value")?;
                if v.as_bytes().len() > SIM_NAME_LEN {
                    return Err(format!(
                        "--sim-room-name must be at most {SIM_NAME_LEN} bytes (got {})",
                        v.as_bytes().len()
                    ));
                }
                args.sim_room_name = v;
            }
            "--sim-lan-listen" => {
                // F5: answer real Civ6 discovery broadcasts on the LAN directly (no Hook
                // chain). 0.0.0.0 binds all interfaces. This is the cross-machine discovery
                // path that does NOT depend on native broadcast routing, interface metrics
                // or firewall program rules for the game: the Agent itself owns the
                // discovery ports and answers from <ip>:62900.
                let v = it.next().ok_or("--sim-lan-listen needs an IP")?;
                parse_dotted_ip(&v).map_err(|e| format!("bad --sim-lan-listen: {e}"))?;
                args.sim_lan_listen = Some(v);
            }
            "--sim-real-capture" => args.sim_real_capture = true,
            "--reserve-62900" => args.reserve_62900 = true,
            "--discovery-completion" => args.discovery_completion = true,
            "--game-discovery-addr" => {
                // M0-E: the replay target. Loopback keeps the request on this machine; a
                // non-loopback address would send the client's magic out on the network as
                // a fresh discovery probe, which is NOT what this mode is for.
                let v = it.next().ok_or("--game-discovery-addr needs IP:PORT")?;
                let ep: SocketAddr = v
                    .parse()
                    .map_err(|e| format!("bad --game-discovery-addr '{v}': {e}"))?;
                args.game_discovery_addr = ep.to_string();
            }
            "--completion-timeout-ms" => {
                let v = it.next().ok_or("--completion-timeout-ms needs a value")?;
                let n: u64 = v
                    .parse()
                    .map_err(|_| format!("bad --completion-timeout-ms: {v}"))?;
                if n == 0 || n > 60_000 {
                    return Err(format!(
                        "--completion-timeout-ms must be in 1..=60000 (got {n})"
                    ));
                }
                args.completion_timeout_ms = n;
            }
            "--completion-max-pages" => {
                let v = it.next().ok_or("--completion-max-pages needs a value")?;
                let n: usize = v
                    .parse()
                    .map_err(|_| format!("bad --completion-max-pages: {v}"))?;
                if n == 0 || n > 256 {
                    return Err(format!("--completion-max-pages must be in 1..=256 (got {n})"));
                }
                args.completion_max_pages = n;
            }
            "--completion-max-replies" => {
                let v = it.next().ok_or("--completion-max-replies needs a value")?;
                let n: u64 = v
                    .parse()
                    .map_err(|_| format!("bad --completion-max-replies: {v}"))?;
                if n == 0 || n > 100_000 {
                    return Err(format!(
                        "--completion-max-replies must be in 1..=100000 (got {n})"
                    ));
                }
                args.completion_max_replies = n;
            }
            "--completion-cooldown-ms" => {
                let v = it.next().ok_or("--completion-cooldown-ms needs a value")?;
                let n: u64 = v
                    .parse()
                    .map_err(|_| format!("bad --completion-cooldown-ms: {v}"))?;
                if n > 60_000 {
                    return Err(format!(
                        "--completion-cooldown-ms must be in 0..=60000 (got {n})"
                    ));
                }
                args.completion_cooldown_ms = n;
            }
            "--simulate-datapath" => args.simulate_datapath = true,
            "--bind-ip" => {
                let v = it.next().ok_or("--bind-ip needs a value")?;
                args.bind_ip = Some(v);
            }
            "--loopback-selftest" => args.loopback_selftest = true,
            "--forward-to" => {
                // F3-A: verbatim forward of 62056 datapath payloads to ONE peer target
                // (the peer Agent's forward-receive port, never its game socket).
                let v = it.next().ok_or("--forward-to needs ip:port")?;
                let ep: SocketAddr = v
                    .parse()
                    .map_err(|e| format!("bad --forward-to '{v}': {e}"))?;
                // F3-A audit finding B-1: the same D2 red line applies to the target. The
                // forward socket must never be aimed at the game's data-plane port, because
                // that would make the Agent a second sender into the real game socket.
                if ep.port() == DATAPATH_PORT {
                    return Err(format!(
                        "--forward-to must not target port {DATAPATH_PORT}: the Agent never sends to the game's data-plane port"
                    ));
                }
                args.forward_to = Some(v);
            }
            "--forward-listen" => {
                // F3-A peer side: record what actually arrives at this loopback port.
                let v = it.next().ok_or("--forward-listen needs a port")?;
                let p: u16 = v.parse().map_err(|_| format!("bad port: {v}"))?;
                if p == DATAPATH_PORT {
                    return Err(format!(
                        "--forward-listen must not be {DATAPATH_PORT}: the Agent never binds the game's data-plane port"
                    ));
                }
                args.forward_listen = Some(p);
            }
            "--peer-discover" => args.peer_discover = true,
            "--discover-interval-ms" => {
                let v = it
                    .next()
                    .ok_or("--discover-interval-ms needs a value")?;
                let n: u64 = v
                    .parse()
                    .map_err(|_| format!("bad --discover-interval-ms: {v}"))?;
                if n < 1000 {
                    return Err(format!(
                        "--discover-interval-ms must be >= 1000 (got {n}): 广播周期过短会放大反射风险"
                    ));
                }
                args.discover_interval_ms = n;
            }
            "--discover-port" => {
                let v = it.next().ok_or("--discover-port needs a value")?;
                let p: u16 = v.parse().map_err(|_| format!("bad --discover-port: {v}"))?;
                if p == DATAPATH_PORT {
                    return Err(format!("--discover-port must not be {DATAPATH_PORT}"));
                }
                args.discover_port = p;
            }
            "--probe-port" => {
                let v = it.next().ok_or("--probe-port needs a value")?;
                let p: u16 = v.parse().map_err(|_| format!("bad --probe-port: {v}"))?;
                if p == DATAPATH_PORT {
                    return Err(format!("--probe-port must not be {DATAPATH_PORT}"));
                }
                args.probe_port = p;
            }
            "--include-vpn" => args.include_vpn = true,
            "--peers-dir" => {
                args.peers_dir = Some(it.next().ok_or("--peers-dir needs a path")?);
            }
            "--ifaces" => {
                args.ifaces = Some(it.next().ok_or("--ifaces needs a comma list of IPv4")?);
            }
            "--peer-discover-selftest" => args.peer_discover_selftest = true,
            "--version" | "-V" => {
                println!("civlink-agent {}", env!("CARGO_PKG_VERSION"));
                std::process::exit(0);
            }
            "--quiet" => args.quiet = true,
            "--help" | "-h" => {
                println!(
                    "civlink-agent {}\n\n\
                     Usage: civlink-agent [--port N] [--listen-seconds N] [--out-dir DIR] [--quiet]\n\
                     \x20                 [--stop-file PATH] [--simulate FIXTURE-DIR]\n\
                     \x20                 [--sim-max-replies N] [--sim-src-ip IP] [--sim-room-name NAME]\n\
                     \x20                 [--sim-lan-listen IP] [--sim-real-capture]\n\
                     \x20                 [--reserve-62900] [--discovery-completion]\n\
                     \x20                 [--game-discovery-addr IP:PORT] [--completion-timeout-ms N]\n\
                     \x20                 [--completion-max-pages N]\n\
                     \x20                 [--simulate-datapath --bind-ip HOSTLOCAL] [--loopback-selftest]\n\
                     \x20                 [--forward-to IP:PORT] [--forward-listen PORT]\n\n\
                     Listens on 127.0.0.1:<port> (default {DEFAULT_PORT}) for CVLH2 frames from\n\
                     civlink_hook.dll, then writes frame-log.txt and summary.txt into --out-dir\n\
                     (default: console only).\n\
                     --simulate FIXTURE-DIR additionally answers discovery requests with the 22-page\n\
                     fixture (reply-01.bin..reply-22.bin, 1104 B each) injected into the game's\n\
                     socket over loopback from --sim-src-ip:62900 (F1 integration evidence).\n\
                     --sim-lan-listen IP (F5, REV-016 双机发现) binds ALL discovery ports\n\
                     (62900..62999) on the given IP and answers real Civ6 discovery broadcasts\n\
                     directly - the Agent owns the discovery ports, so it works without the Hook\n\
                     chain and without native broadcast routing/metric/firewall dependence. Use\n\
                     0.0.0.0 for all interfaces. Requires --simulate. Simulated-host evidence\n\
                     only - NOT a two-real-hosts multiplayer result, NOT E2-B/E3.\n\
                     \x20--reserve-62900 (M0-C C1, v0.4.6) skips binding 62900 and leaves it\n\
                     \x20 permanently free for the game's LAN-host socket, so the room owner can\n\
                     \x20 always (re-)create a room even when this Agent started first. The reply\n\
                     \x20 source falls back to the first bound port (62901..) and is logged as\n\
                     \x20 `reply source`. Discovery still works (dedup is per (src ip, src port),\n\
                     \x20 one magic per port - one of the 99 remaining copies suffices).\n\
                     \x20 Note: only effective with --sim-lan-listen; plain --simulate (F1 loopback)\n\
                     \x20 still binds 62900, so pass --sim-lan-listen with it for the reserve to apply.\n\
                     --discovery-completion (M0-E) turns --sim-lan-listen into a completion\n\
                     service: instead of answering from a fixture, the Agent replays the client's\n\
                     4-byte magic into the LOCAL game (loopback only) and forwards the game's own\n\
                     reply pages back to the client. The client therefore sees the REAL room, and\n\
                     a room created or renamed after the Agent started is picked up immediately.\n\
                     No --simulate is used in this mode (there is no fixture), --reserve-62900 is\n\
                     implied (binding 62900 would hijack the game's own unicast), and\n\
                     --sim-real-capture is rejected as contradictory. If the game does not answer\n\
                     within --completion-timeout-ms the client gets NOTHING (fail-closed) rather\n\
                     than an invented advert. --game-discovery-addr defaults to 127.0.0.1:62900\n\
                     and must stay loopback.\n\
                     --sim-real-capture (B1) additionally captures REAL advertisement pages\n\
                     (1104 B, magic 59 60 69 9B) sent by A-machine Civ6 - via the Hook chain\n\
                     (path P1) or on the discovery ports (path P2, LAN broadcast loopback) -\n\
                     and answers discovery with the real pages instead of the fixture once a\n\
                     full 22-page set is captured. Default off: F5 behaviour unchanged.\n\
                     --simulate-datapath (F2) additionally OBSERVES datapath (62056) frames via the\n\
                     Hook chain and sends at most ONE 20-byte fixed local probe (D4). --bind-ip is\n\
                     MANDATORY with it and must be a current host-local address (fail-closed).\n\
                     --forward-to IP:PORT (F3-A) forwards 62056 datapath payloads VERBATIM to one\n\
                     peer Agent port (never the game socket, never :62056); --forward-listen PORT\n\
                     (F3-A peer side) records delivered payloads with timestamps. No game-process\n\
                     injection: that is M0-B. Exit codes: 0 ok, 1 usage, 2 cannot bind.\n",
                    env!("CARGO_PKG_VERSION")
                );
                std::process::exit(0);
            }
            other => return Err(format!("unknown argument: {other}")),
        }
    }
    // M0-G peer-discover: mutually exclusive with all other operational modes, and its
    // network I/O requires the optional feature to be compiled in (fail closed with a clear
    // message rather than silently doing nothing).
    if args.peer_discover {
        let conflicts: Vec<&str> = [
            ("--simulate", args.simulate.is_some()),
            ("--sim-lan-listen", args.sim_lan_listen.is_some()),
            ("--sim-real-capture", args.sim_real_capture),
            ("--discovery-completion", args.discovery_completion),
            ("--simulate-datapath", args.simulate_datapath),
            ("--forward-to", args.forward_to.is_some()),
            ("--forward-listen", args.forward_listen.is_some()),
            ("--reserve-62900", args.reserve_62900),
        ]
        .into_iter()
        .filter(|(_, on)| *on)
        .map(|(n, _)| n)
        .collect();
        if !conflicts.is_empty() {
            return Err(format!(
                "--peer-discover is mutually exclusive with: {}",
                conflicts.join(", ")
            ));
        }
        if args.discover_port == args.probe_port {
            return Err("--discover-port and --probe-port must differ".to_string());
        }
        #[cfg(not(feature = "peer-discover"))]
        {
            return Err(
                "--peer-discover needs the feature compiled in: rebuild with `cargo +1.75.0 build --offline --features peer-discover`"
                    .to_string(),
            );
        }
    }
    // M0-E cross-flag rules (validated here so --help and unit tests see one code path).
    if args.discovery_completion {
        if args.sim_lan_listen.is_none() {
            return Err(
                "--discovery-completion requires --sim-lan-listen IP (the Agent must own the discovery ports to see the client's magic)"
                    .to_string(),
            );
        }
        if args.simulate.is_some() {
            return Err(
                "--discovery-completion does not take --simulate: completion mode forwards the local game's own reply and never serves a fixture"
                    .to_string(),
            );
        }
        if args.sim_real_capture {
            return Err(
                "--discovery-completion and --sim-real-capture are mutually exclusive (one answers from the live game, the other from captured pages)"
                    .to_string(),
            );
        }
        // Binding 62900 would take the port away from the game's own LAN-host socket and
        // hijack its unicast replies (the SO_REUSEADDR trap measured in the independent
        // research). Completion mode therefore always reserves it.
        if !args.reserve_62900 {
            return Err(
                "--discovery-completion implies --reserve-62900: the Agent must never bind 62900, the game's own host port"
                    .to_string(),
            );
        }
        if let Err(e) = validate_game_discovery_addr(&args.game_discovery_addr) {
            return Err(e);
        }
    }
    Ok(args)
}

/// Pure check on the replay target, kept separate from `CompletionState::new` so argument
/// parsing has no socket side effects.
fn validate_game_discovery_addr(addr: &str) -> Result<(), String> {
    let ep: SocketAddr = addr
        .parse()
        .map_err(|e| format!("bad --game-discovery-addr '{addr}': {e}"))?;
    if !ep.ip().is_loopback() {
        return Err(format!(
            "--game-discovery-addr must be a loopback address (got {ep}): the replay must reach the local game, not re-broadcast the client's magic onto the network"
        ));
    }
    Ok(())
}

fn run(args: &Args) -> Result<Totals, String> {
    // M0-G: peer-discover is a standalone mode — no CVLH2 socket, no game protocol. Dispatch
    // before any of the F1/F2/F5/E2 state machines are constructed.
    #[cfg(feature = "peer-discover")]
    if args.peer_discover {
        use std::sync::Arc;
        let stop = Arc::new(AtomicBool::new(false));
        // Separate flag for a user-requested abort (--stop-file). The listen-window timer uses
        // `stop` so the normal flow still advances into the probe phase; an explicit stop must
        // also cut the probe phase short (it can otherwise run for minutes).
        let abort = Arc::new(AtomicBool::new(false));
        // A watcher thread flips the ABORT flag when --stop-file appears. An explicit stop must
        // interrupt the probe phase too, unlike the listen-window timer below.
        if let Some(sf) = &args.stop_file {
            let sf = sf.clone();
            let s = abort.clone();
            std::thread::spawn(move || {
                let p = Path::new(&sf);
                while !p.exists() {
                    std::thread::sleep(Duration::from_millis(200));
                }
                s.store(true, Ordering::Relaxed);
            });
        }
        // Without --stop-file the run is bounded by --listen-seconds.
        let stop2 = stop.clone();
        let secs = args.listen_seconds;
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_secs(secs));
            stop2.store(true, Ordering::Relaxed);
        });
        peer_discover_net::run_peer_discover(
            args.discover_interval_ms,
            args.discover_port,
            args.probe_port,
            args.include_vpn,
            args.listen_seconds,
            args.ifaces.as_deref(),
            args.peers_dir.as_deref(),
            args.out_dir.as_deref(),
            stop.as_ref(),
            abort.as_ref(),
        )?;
        return Ok(Totals::default());
    }

    let bind_addr = SocketAddr::from(([127, 0, 0, 1], args.port));
    let sock = UdpSocket::bind(bind_addr)
        .map_err(|e| format!("cannot bind {bind_addr}: {e} (is another Agent already running?)"))?;
    sock.set_read_timeout(Some(Duration::from_millis(250)))
        .map_err(|e| format!("set_read_timeout failed: {e}"))?;

    let (mut frame_writer, mut report_path) = match &args.out_dir {
        Some(dir) => {
            fs::create_dir_all(dir).map_err(|e| format!("cannot create {dir}: {e}"))?;
            let path = format!("{dir}/frame-log.txt");
            let f = File::create(&path).map_err(|e| format!("cannot create {path}: {e}"))?;
            (Some(BufWriter::new(f)), Some(dir.clone()))
        }
        None => (None, None),
    };

    if let Some(w) = frame_writer.as_mut() {
        let _ = writeln!(
            w,
            "# civlink-agent {} - one line per accepted CVLH2 frame\n\
             # time seq session socket gen dst_port payload_len flags src payload_head",
            env!("CARGO_PKG_VERSION")
        );
        let _ = w.flush();
    }

    if !args.quiet {
        println!(
            "civlink-agent {} listening on {} for {}s",
            env!("CARGO_PKG_VERSION"),
            bind_addr,
            args.listen_seconds
        );
    }

    // F1 integration: when --simulate is given, answer discovery requests that arrive via
    // the Hook chain with the 22-page fixture, injected back into the game's socket over
    // loopback. A fixture problem is fatal (a simulated host that cannot load its pages is
    // not a working fixture), while a bind failure only disables replies and is counted.
    // F1 loopback sim and F5 LAN sim both bind 127.0.0.1:62900 (SIM_REPLY_PORT) to answer
    // discovery, so they are mutually exclusive: --sim-lan-listen takes precedence.
    let mut sim_state = match (&args.simulate, &args.sim_lan_listen) {
        (Some(dir), None) => Some(SimState::new(
            dir,
            &args.sim_src_ip,
            args.sim_max_replies,
            &args.sim_room_name,
            args.out_dir.as_deref(),
        )?),
        _ => None,
    };

    // F5 (REV-016 双机发现): the LAN simulated host owns the discovery ports itself, so it
    // works without the Hook chain and without native broadcast routing/metric/firewall
    // dependence. It uses the same fixture; 0.0.0.0 binds all interfaces.
    let mut lan_sim_state = match &args.sim_lan_listen {
        Some(ip) => {
            // M0-E: completion mode needs no fixture at all (the local game supplies the
            // reply), every other LAN-sim mode still requires --simulate.
            let fixture: Option<&str> = if args.discovery_completion {
                None
            } else {
                Some(
                    args.simulate
                        .as_deref()
                        .ok_or("--sim-lan-listen requires --simulate (fixture directory)")?,
                )
            };
            let completion = if args.discovery_completion {
                Some(CompletionState::new(
                    &args.game_discovery_addr,
                    args.completion_timeout_ms,
                    args.completion_max_pages,
                    args.completion_max_replies,
                    args.completion_cooldown_ms,
                )?)
            } else {
                None
            };
            Some(LanSimState::new(
                fixture,
                ip,
                args.sim_max_replies,
                &args.sim_room_name,
                args.out_dir.as_deref(),
                args.reserve_62900,
                completion,
            )?)
        }
        None => None,
    };

    // F2 datapath observation: mandatory --bind-ip is fail-closed (codex review §2.1).
    // The agent never binds :62056; the reply socket is an independent ephemeral UDP socket.
    let mut datapath_state = if args.simulate_datapath {
        let bind_ip = args
            .bind_ip
            .clone()
            .ok_or("--simulate-datapath requires --bind-ip (current host-local address)")?;
        if args.loopback_selftest {
            let ip = parse_dotted_ip(&bind_ip).map_err(|e| format!("bad --bind-ip: {e}"))?;
            if ip != [127, 0, 0, 1] {
                return Err(
                    "--loopback-selftest requires --bind-ip 127.0.0.1 (self-test only, not a real-machine result)"
                        .to_string(),
                );
            }
        }
        Some(DatapathState::new(&bind_ip)?)
    } else {
        None
    };
    let mut datapath_log: Option<BufWriter<File>> = match (&args.simulate_datapath, &args.out_dir) {
        (true, Some(dir)) => {
            let path = format!("{dir}/datapath-log.txt");
            let f = File::create(&path).map_err(|e| format!("cannot create {path}: {e}"))?;
            Some(BufWriter::new(f))
        }
        _ => None,
    };
    if let Some(w) = datapath_log.as_mut() {
        let _ = writeln!(
            w,
            "# civlink-agent {} - F2 datapath observation (frames via CVLH2, no :62056 bind)",
            env!("CARGO_PKG_VERSION")
        );
        let _ = w.flush();
    }

    // F3-A direct forward prototype: forwarding and the peer-side listener are separate
    // roles and may be combined in one process for a loopback self-test. Neither binds
    // :62056 and neither touches the game process (injection is M0-B).
    let mut forward_state = match &args.forward_to {
        Some(t) => Some(ForwardState::new(t)?),
        None => None,
    };
    let mut forward_listener = match args.forward_listen {
        Some(p) => Some(ForwardListener::new(p)?),
        None => None,
    };
    let mut forward_log: Option<BufWriter<File>> = match (
        args.forward_to.is_some() || args.forward_listen.is_some(),
        &args.out_dir,
    ) {
        (true, Some(dir)) => {
            let path = format!("{dir}/forward-log.txt");
            let f = File::create(&path).map_err(|e| format!("cannot create {path}: {e}"))?;
            Some(BufWriter::new(f))
        }
        _ => None,
    };
    if let Some(w) = forward_log.as_mut() {
        let _ = writeln!(
            w,
            "# civlink-agent {} - F3-A forward prototype (loopback only, verbatim payload, no retransmit)",
            env!("CARGO_PKG_VERSION")
        );
        let _ = w.flush();
    }

    let start = Instant::now();
    let deadline = start + Duration::from_secs(args.listen_seconds);
    let mut totals = Totals::default();
    let mut buf = vec![0u8; 2048];

    // B1 (--sim-real-capture): the real advertisement cache. A capture via the Hook chain
    // (path P1, frames below) or via the LAN discovery ports (path P2, inside lan_sim.poll)
    // only becomes the active reply set once a full 22-page set is held.
    let mut real_ad_cache = if args.sim_real_capture {
        Some(RealAdCache::new())
    } else {
        None
    };

    // --listen-seconds 0 means "until Ctrl+C" (used by the self-test driver).
    let unbounded = args.listen_seconds == 0;
    let stop_path = args.stop_file.clone();
    let mut stop_seen = false;

    while unbounded || Instant::now() < deadline {
        if !stop_seen {
            if let Some(p) = stop_path.as_ref() {
                if Path::new(p).exists() {
                    stop_seen = true;
                    if !args.quiet {
                        println!("stop file {p} found - finishing the window cleanly");
                    }
                }
            }
        }
        if stop_seen {
            // Final drain (F3-A audit round 3, finding L3): the stop file can appear after a
            // datagram has already landed in the listener's socket buffer. Breaking out here
            // without draining would lose that last delivery, and the peer "payloads recv"
            // count would then disagree with `forwarded` - which the driver treats as a
            // failure. One extra drain costs nothing and makes the accounting exact.
            if let Some(pl) = forward_listener.as_mut() {
                let mut pbuf = [0u8; 2048];
                pl.drain(&mut pbuf, forward_log.as_mut().map(|w| w as &mut dyn Write));
            }
            // F5: same reasoning for the LAN discovery ports. B1 (--sim-real-capture) lets
            // the same drain capture real advertisement pages (path P2).
            if let Some(ls) = lan_sim_state.as_mut() {
                let mut lbuf = [0u8; 2048];
                ls.poll(&mut lbuf, real_ad_cache.as_mut());
            }
            break;
        }
        // F3-A peer side: the loopback listener is non-blocking, so each loop pass drains
        // whatever was delivered. This is where "the peer Agent actually received it" is
        // recorded - the evidence for the F3-A acceptance criterion.
        if let Some(pl) = forward_listener.as_mut() {
            let mut pbuf = [0u8; 2048];
            pl.drain(&mut pbuf, forward_log.as_mut().map(|w| w as &mut dyn Write));
        }
        // F5 (REV-016 双机发现): drain the LAN discovery ports every pass. Non-blocking,
        // so a magic broadcast is answered within one loop cadence (~250 ms). B1
        // (--sim-real-capture) captures real advertisement pages on the same drain (P2).
        if let Some(ls) = lan_sim_state.as_mut() {
            let mut lbuf = [0u8; 2048];
            ls.poll(&mut lbuf, real_ad_cache.as_mut());
        }
        match sock.recv_from(&mut buf) {
            Ok((len, _from)) => {
                totals.datagrams += 1;
                totals.bytes += len as u64;
                if len > FRAME_HDR + MAX_PAYLOAD {
                    totals.large_datagrams += 1;
                }
                match decode(&buf[..len]) {
                    Ok(frame) => {
                        totals.received += 1;
                        if frame.flags & (FLAG_REJECTED_OVERSIZE | FLAG_NO_PAYLOAD) != 0 {
                            // The Hook could not carry the payload; it is a counted reject,
                            // not a processed discovery observation. The Hook reports these
                            // in its `sentNotify` counter, so keep them separable here.
                            totals.rejected += 1;
                            totals.notify_frames += 1;
                            *totals
                                .reject_by_kind
                                .entry("hook-rejected-oversize")
                                .or_insert(0) += 1;
                        } else {
                            totals.processed += 1;
                        }

                        let session = totals.sessions.entry(frame.session_id).or_default();
                        session.frames += 1;
                        session.note_seq(frame.seq);
                        session.payload_bytes += frame.payload_len as u64;
                        if frame.flags & FLAG_VIA_WSASENDTO != 0 {
                            session.via_wsasendto += 1;
                        }
                        if frame.flags & FLAG_LIMITED_BCAST != 0 {
                            session.limited_bcast += 1;
                        }
                        if frame.flags & FLAG_DISCOVERY != 0 {
                            session.discovery_flagged += 1;
                        }
                        if frame.flags & FLAG_REJECTED_OVERSIZE != 0 {
                            session.rejected_oversize_frames += 1;
                        }
                        if frame.flags & FLAG_NO_PAYLOAD != 0 {
                            session.no_payload_frames += 1;
                        }
                        let dst_port = port_from_be16(frame.dst_port_be);
                        *session.ports.entry(dst_port).or_insert(0) += 1;
                        *session.sockets.entry(frame.logical_socket_id).or_insert(0) += 1;
                        let src = format!(
                            "{}:{}",
                            ipv4_from_be(frame.src_ip_be),
                            port_from_be16(frame.src_port_be)
                        );
                        *session.src_endpoints.entry(src.clone()).or_insert(0) += 1;

                        let is_magic = frame.payload_len == 4
                            && frame.payload.len() == 4
                            && frame.payload[..4] == DISCOVERY_MAGIC;
                        if is_magic {
                            session.discovery_magic += 1;
                        } else if frame.payload_len > 0 {
                            session.not_discovery_magic += 1;
                        }

                        // Simulated host: only ACCEPTED frames are eligible (the Hook's own
                        // oversize/empty reject frames are never answered).
                        if let Some(sim) = sim_state.as_mut() {
                            if frame.flags & (FLAG_REJECTED_OVERSIZE | FLAG_NO_PAYLOAD) == 0 {
                                sim.consider(&frame);
                            }
                        }

                        // B1 capture path P1: a discovery-flagged frame whose payload is a
                        // full advertisement page (1104 B, magic 59 60 69 9B) is a REAL page
                        // sent by A-machine Civ6, forwarded verbatim by civlink_hook.dll.
                        // Accepted frames only - Hook rejects are never pages. The active
                        // flag flips once a full 22-page set is captured.
                        if let Some(cache) = real_ad_cache.as_mut() {
                            if frame.flags & (FLAG_REJECTED_OVERSIZE | FLAG_NO_PAYLOAD) == 0
                                && frame.flags & FLAG_DISCOVERY != 0
                            {
                                match cache.try_capture(&frame.payload, "P1-hook") {
                                    CaptureOutcome::NotAPage => {}
                                    _ => {
                                        if cache.pages.len() == SIM_PAGE_COUNT {
                                            cache.active = true;
                                        }
                                    }
                                }
                            }
                        }

                        // F2 datapath observation: frames that are NOT discovery requests are
                        // the game's outbound non-discovery traffic (typically the 62056 data
                        // plane). Observed via CVLH2 only; reply is the D4 single probe.
                        if let Some(dp) = datapath_state.as_mut() {
                            if frame.flags & (FLAG_REJECTED_OVERSIZE | FLAG_NO_PAYLOAD) == 0 {
                                if !is_discovery_request(&frame) {
                                    dp.consider(
                                        &frame,
                                        datapath_log.as_mut().map(|w| w as &mut dyn Write),
                                    );
                                }
                            }
                        }

                        // F3-A direct forward: datapath (62056) payloads, verbatim, to the one
                        // configured peer Agent port. Discovery frames keep the F1 path
                        // (design v0.3 §3.2 rule 3), so they are excluded here - and counted,
                        // so the forward accounting closes over every frame that reaches it.
                        if let Some(fw) = forward_state.as_mut() {
                            // Every accepted frame that reaches this stage is counted as SEEN, and
                            // then classified exactly once. `consider` bumps frames_seen itself,
                            // so the two skip branches bump it here; a discovery frame or a
                            // Hook-rejected frame skipped without a SEEN bump would appear in a
                            // skip counter while being absent from frames_seen, and the identity
                            // forward+notDp+disco+keyTable+rejected+fail == frames_seen would not
                            // close (F3-A audit rounds 2 and 3).
                            if frame.flags & (FLAG_REJECTED_OVERSIZE | FLAG_NO_PAYLOAD) != 0 {
                                fw.stats.frames_seen += 1;
                                fw.stats.skip_rejected_flags += 1;
                            } else if is_discovery_request(&frame) {
                                fw.stats.frames_seen += 1;
                                fw.stats.skip_discovery += 1;
                            } else {
                                fw.consider(
                                    &frame,
                                    forward_log.as_mut().map(|w| w as &mut dyn Write),
                                );
                            }
                        }

                        if let Some(w) = frame_writer.as_mut() {
                            let _ = writeln!(
                                w,
                                "{} dir={} af={} seq={} session=0x{:x} sock={} gen={} dst={}:{} len={} flags=0x{:02x} src={} head={}",
                                wallclock_stamp(),
                                frame.dir,
                                frame.af,
                                frame.seq,
                                frame.session_id,
                                frame.logical_socket_id,
                                frame.socket_generation,
                                ipv4_from_be(frame.dst_ip_be),
                                dst_port,
                                frame.payload_len,
                                frame.flags,
                                src,
                                if frame.payload_len == 0 {
                                    "-".to_string()
                                } else {
                                    hex4(&frame.payload[..frame.payload.len().min(8)])
                                }
                            );
                            if totals.received % 64 == 0 {
                                let _ = w.flush();
                            }
                        }
                    }
                    Err(e) => {
                        totals.rejected += 1;
                        *totals.reject_by_kind.entry(e.kind()).or_insert(0) += 1;
                        if !args.quiet {
                            println!(
                                "[!] rejected datagram len={len} kind={} ({})",
                                e.kind(),
                                e.detail()
                            );
                        }
                    }
                }
            }
            Err(ref e)
                if e.kind() == io::ErrorKind::WouldBlock || e.kind() == io::ErrorKind::TimedOut =>
            {
                // Normal: the 250 ms read timeout is what keeps this loop responsive.
            }
            Err(e) => return Err(format!("recv_from failed: {e}")),
        }
    }

    if let Some(w) = frame_writer.as_mut() {
        let _ = w.flush();
    }
    if let Some(w) = datapath_log.as_mut() {
        let _ = w.flush();
    }

    if let Some(w) = forward_log.as_mut() {
        let _ = w.flush();
    }

    let elapsed = start.elapsed();
    let fw_sock = forward_state
        .as_ref()
        .and_then(|f| f.sock.local_addr().ok())
        .map(|a| a.to_string())
        .unwrap_or_else(|| "(none)".to_string());

    // B1: write the captured real advertisement pages and their manifest into --out-dir.
    // The manifest carries the capture time, the source path (P1 hook chain / P2 LAN), the
    // page count and each page's sha256, so a later reader can compare the captured pages
    // byte-for-byte against the sender's own bytes (the C1/C3 mechanical evidence).
    if let Some(cache) = real_ad_cache.as_ref() {
        if !cache.pages.is_empty() {
            if let Some(dir) = args.out_dir.as_deref() {
                fs::create_dir_all(dir).map_err(|e| format!("cannot create {dir}: {e}"))?;
                for (i, p) in cache.pages.iter().enumerate() {
                    let path = format!("{dir}/real-page-{:02}.bin", i + 1);
                    fs::write(&path, p).map_err(|e| format!("cannot write {path}: {e}"))?;
                }
                let mut manifest = String::new();
                manifest.push_str(&format!(
                    "# B1 real advertisement capture (civlink-agent {})\n\
                     # captured at: {} (run end)\n\
                     # pages: {} (active reply set once full {}: {})\n",
                    env!("CARGO_PKG_VERSION"),
                    wallclock_stamp(),
                    cache.pages.len(),
                    SIM_PAGE_COUNT,
                    if cache.active { "yes" } else { "no (fixture still used)" }
                ));
                manifest.push_str("# source: P1 = hook chain frames (A-machine Civ6 sendto); P2 = LAN discovery-port broadcast loopback\n");
                for (i, p) in cache.pages.iter().enumerate() {
                    manifest.push_str(&format!(
                        "page {:02}: sha256={} bytes={}\n",
                        i + 1,
                        sha256_hex(p),
                        p.len()
                    ));
                }
                let path = format!("{dir}/real-ad-manifest.txt");
                fs::write(&path, manifest).map_err(|e| format!("cannot write {path}: {e}"))?;
            }
        }
    }

    let report = summarize(
        &totals,
        args,
        elapsed,
        sim_state.as_ref().map(|s| &s.stats),
        lan_sim_state.as_ref().map(|s| &s.stats),
        real_ad_cache.as_ref().map(|c| &c.stats),
        datapath_state.as_ref().map(|d| &d.stats),
        forward_state.as_ref().map(|f| &f.stats),
        forward_listener.as_ref().map(|p| &p.stats),
        &fw_sock,
        forward_listener.as_ref().map(|p| &p.stats.first_from),
        lan_sim_state
            .as_ref()
            .and_then(|s| s.completion.as_ref())
            .map(|c| &c.stats),
        lan_sim_state
            .as_ref()
            .and_then(|s| s.completion.as_ref())
            .map(|c| c.game_addr),
    );
    if !args.quiet {
        print!("{report}");
    }
    if let Some(dir) = report_path.take() {
        let path = format!("{dir}/summary.txt");
        fs::write(&path, &report).map_err(|e| format!("cannot write {path}: {e}"))?;
        if !args.quiet {
            println!("\n[*] wrote {dir}/frame-log.txt and {path}");
        }
    }
    Ok(totals)
}

fn summarize(
    t: &Totals,
    args: &Args,
    elapsed: Duration,
    sim: Option<&SimStats>,
    lan_sim: Option<&SimStats>,
    real_ad: Option<&RealAdStats>,
    datapath: Option<&DatapathStats>,
    forward: Option<&ForwardStats>,
    peer: Option<&PeerStats>,
    fw_sock: &str,
    peer_first_from: Option<&String>,
    completion: Option<&CompletionStats>,
    completion_game: Option<SocketAddr>,
) -> String {
    let mut s = String::new();
    s.push_str(&format!(
        "civlink-agent {} - CVLH2 receive summary\n",
        env!("CARGO_PKG_VERSION")
    ));
    s.push_str(&format!("run time        : {}\n", wallclock_stamp()));
    s.push_str(&format!(
        "listen window   : 127.0.0.1:{} for {:.1} s\n",
        args.port,
        elapsed.as_secs_f64()
    ));
    s.push_str(&format!("datagrams       : {}\n", t.datagrams));
    s.push_str(&format!("bytes           : {}\n", t.bytes));
    s.push_str(&format!(
        "received frames : {} (processed {}, rejected {})\n",
        t.received, t.processed, t.rejected
    ));
    s.push_str(&format!(
        "reconciliation  : processed + rejected = {} {} received = {}\n",
        t.processed + t.rejected,
        if t.processed + t.rejected == t.received {
            "=="
        } else {
            "!="
        },
        t.received
    ));
    if !t.reject_by_kind.is_empty() {
        let mut kinds: Vec<_> = t.reject_by_kind.iter().collect();
        kinds.sort_by(|a, b| b.1.cmp(a.1));
        let joined: Vec<String> = kinds.iter().map(|(k, v)| format!("{k}={v}")).collect();
        s.push_str(&format!("reject kinds    : {}\n", joined.join(", ")));
    }
    s.push_str(&format!("large datagrams : {}\n", t.large_datagrams));
    s.push_str(&format!(
        "oversize notify : {} frame(s) (in `received`, outside `processed`)\n",
        t.notify_frames
    ));
    s.push_str(&format!("sessions        : {}\n", t.sessions.len()));
    for (sid, st) in &t.sessions {
        s.push_str(&format!("  session 0x{sid:x}\n"));
        s.push_str(&format!(
            "    frames={} first_seq={:?} last_seq={:?}\n",
            st.frames, st.first_seq, st.last_seq
        ));
        s.push_str(&format!(
            "    seq gaps={} missing_frames={} duplicates={} out_of_order={}\n",
            st.seq_gaps, st.seq_missing_frames, st.duplicates, st.out_of_order
        ));
        s.push_str(&format!(
            "    payload bytes={} discovery_magic={} other_payload={}\n",
            st.payload_bytes, st.discovery_magic, st.not_discovery_magic
        ));
        s.push_str(&format!(
            "    via_wsasendto={} limited_bcast={} discovery_flag={} no_payload={} rejected_oversize={}\n",
            st.via_wsasendto, st.limited_bcast, st.discovery_flagged, st.no_payload_frames,
            st.rejected_oversize_frames
        ));
        s.push_str(&format!("    logical sockets={}\n", st.sockets.len()));
        let mut ports: Vec<_> = st.ports.iter().collect();
        ports.sort_by_key(|(p, _)| **p);
        let port_min = ports.first().map(|(p, _)| **p).unwrap_or(0);
        let port_max = ports.last().map(|(p, _)| **p).unwrap_or(0);
        let in_range = ports
            .iter()
            .filter(|(p, _)| **p >= DISCOVERY_FIRST && **p <= DISCOVERY_LAST)
            .count();
        s.push_str(&format!(
            "    dst ports={} (min {port_min}, max {port_max}, in {DISCOVERY_FIRST}..{DISCOVERY_LAST}: {in_range})\n",
            ports.len()
        ));
        let mut srcs: Vec<_> = st.src_endpoints.iter().collect();
        srcs.sort_by(|a, b| b.1.cmp(a.1));
        let shown: Vec<String> = srcs
            .iter()
            .take(4)
            .map(|(k, v)| format!("{k} x{v}"))
            .collect();
        s.push_str(&format!("    src endpoints : {}\n", shown.join(", ")));
    }
    if let Some(sim) = sim {
        s.push_str("\nsimulated host (F1 integration)\n");
        s.push_str(&format!(
            "  room            : '{}' (anonymized at offset {SIM_NAME_OFFSET}..{})\n",
            args.sim_room_name,
            SIM_NAME_OFFSET + SIM_NAME_LEN
        ));
        s.push_str(&format!(
            "  reply source    : {}:{}\n",
            args.sim_src_ip, SIM_REPLY_PORT
        ));
        s.push_str(&format!(
            "  reply budget    : {} socket(s)\n",
            args.sim_max_replies
        ));
        s.push_str(&format!("  requests seen   : {}\n", sim.requests_seen));
        s.push_str(&format!("  replied sockets : {}\n", sim.replied_sockets));
        s.push_str(&format!(
            "  pages sent      : {} (== replied * {SIM_PAGE_COUNT})\n",
            sim.pages_sent
        ));
        s.push_str(&format!("  send fail       : {}\n", sim.send_fail));
        s.push_str(&format!(
            "  no endpoint     : {} (first frame of an unbound socket)\n",
            sim.no_endpoint
        ));
        s.push_str(&format!(
            "  max reached     : {}\n",
            sim.max_replies_reached
        ));
        s.push_str(&format!("  bind fail       : {}\n", sim.bind_fail));
    }
    if let Some(ls) = lan_sim {
        s.push_str("\nLAN simulated host (F5, REV-016 双机发现)\n");
        s.push_str(&format!(
            "  listen ip       : {} on {DISCOVERY_FIRST}..{DISCOVERY_LAST} (Agent owns the discovery ports; no native broadcast routing/metric/firewall dependence)\n",
            args.sim_lan_listen.as_deref().unwrap_or("(none)")
        ));
        s.push_str(&format!(
            "  port 62900      : {} (M0-C C1: --reserve-62900 leaves it free for the game's LAN-host socket)\n",
            if args.reserve_62900 { "reserved, not bound" } else { "bound by Agent" }
        ));
        s.push_str(&format!("  room            : '{}'\n", args.sim_room_name));
        s.push_str(&format!(
            "  reply source    : {} (actual bound socket; falls back from {SIM_REPLY_PORT} when the game owns it or --reserve-62900 is set)\n",
            ls.reply_addr.map(|a| a.to_string()).unwrap_or_else(|| "(none)".to_string())
        ));
        s.push_str(&format!(
            "  reply budget    : {} socket(s)\n",
            args.sim_max_replies
        ));
        s.push_str(&format!("  requests seen   : {}\n", ls.requests_seen));
        s.push_str(&format!("  replied sockets : {}\n", ls.replied_sockets));
        s.push_str(&format!(
            "  pages sent      : {} (== replied * {SIM_PAGE_COUNT})\n",
            ls.pages_sent
        ));
        s.push_str(&format!("  send fail       : {}\n", ls.send_fail));
        s.push_str(&format!(
            "  no endpoint     : {} (datagram with source port 0)\n",
            ls.no_endpoint
        ));
        s.push_str(&format!("  max reached     : {}\n", ls.max_replies_reached));
        s.push_str(&format!("  bind fail       : {} port(s)\n", ls.bind_fail));
    }
    if let Some(cp) = completion {
        s.push_str("\ndiscovery completion (M0-E: the real room comes from the local game, not a fixture)\n");
        s.push_str(&format!(
            "  replay target   : {} (loopback only - never leaves this machine)\n",
            completion_game
                .map(|a| a.to_string())
                .unwrap_or_else(|| "(none)".to_string())
        ));
        s.push_str(&format!(
            "  requests seen   : {} (magic datagrams on the Agent-owned discovery ports)\n",
            cp.requests_intercepted
        ));
        s.push_str(&format!("  replays sent    : {}\n", cp.replays_sent));
        s.push_str(&format!("  replays failed  : {}\n", cp.replays_failed));
        s.push_str(&format!(
            "  pages collected : {} (from the local game; {SIM_PAGE_COUNT} == one full advert)\n",
            cp.pages_collected
        ));
        s.push_str(&format!("  pages forwarded : {}\n", cp.pages_forwarded));
        s.push_str(&format!("  forwards failed : {}\n", cp.forwards_failed));
        s.push_str(&format!(
            "  timeouts        : {} (game silent - the client got NOTHING, fail-closed)\n",
            cp.timeouts
        ));
        s.push_str(&format!(
            "  short replies   : {} (game stopped before {SIM_PAGE_COUNT} pages; forwarded as-is)\n",
            cp.empty_replies
        ));
        s.push_str(&format!(
            "  odd page sizes  : {} (len != {SIM_PAGE_SIZE}; forwarded as-is)\n",
            cp.odd_page_sizes
        ));
        // M0-E audit B-2: the counters that show one client refresh costs ONE round.
        s.push_str(&format!(
            "  duplicate magic : {} (same client endpoint inside the cooldown; this is what collapses one 100-port refresh into a single round)\n",
            cp.duplicate_magic
        ));
        s.push_str(&format!("  budget exhausted: {}\n", cp.budget_exhausted));
        s.push_str(&format!(
            "  backlog cleared : {} (stale pages dropped before a round)\n",
            cp.backlog_cleared
        ));
        // M0-E audit B-1: the reply's source address is pinned to the address the client
        // probed, so a multi-homed host answers from the interface the client can reach.
        s.push_str(&format!(
            "  egress pinned   : {} page(s) sent from the probed address\n",
            cp.egress_pinned
        ));
        s.push_str(&format!(
            "  egress unpinned : {} page(s) left to the routing table (probe address unknown)\n",
            cp.egress_unpinned
        ));
        s.push_str(&format!(
            "  egress api      : {} (WSARecvMsg/WSASendMsg extension)\n",
            if cp.egress_available {
                "available"
            } else {
                "MISSING - every reply is unpinned"
            }
        ));
        s.push_str(&format!(
            "  pktinfo         : {}\n",
            if cp.pktinfo_enabled {
                "enabled (the probed address is knowable)"
            } else {
                "NOT enabled - the probed address cannot be learned"
            }
        ));
        s.push_str(&format!(
            "  recv errors     : {} (last errno {})\n",
            cp.recv_errors, cp.last_recv_error
        ));
        s.push_str(&format!(
            "  probed address  : {} round(s) known, {} unknown; last = '{}'\n",
            cp.probe_addr_seen, cp.probe_addr_missing, cp.last_probe_addr
        ));
    }
    if let Some(ra) = real_ad {
        s.push_str("\nreal advertisement capture (B1)\n");
        s.push_str(&format!("  captured        : {}\n", ra.captured));
        s.push_str(&format!("  rejected        : {}\n", ra.rejected));
        s.push_str(&format!(
            "  duplicates      : {} (byte-identical pages already held; P1+P2 double delivery)\n",
            ra.duplicates
        ));
        s.push_str(&format!(
            "  noise on disc   : {} (non-page datagrams on discovery ports)\n",
            ra.noise_on_discovery_port
        ));
        s.push_str(&format!("  replies real    : {}\n", ra.replies_used_real));
        s.push_str(&format!("  replies fixture : {}\n", ra.replies_used_fixture));
        s.push_str(&format!(
            "  replies skipped : {} (not answered: dedup / no endpoint / max reached / no socket / send fail)\n",
            ra.replies_skipped
        ));
        s.push_str(&format!(
            "  active          : {} (full {SIM_PAGE_COUNT}-page set captured)\n",
            if ra.captured >= SIM_PAGE_COUNT as u64 {
                "yes"
            } else {
                "no"
            }
        ));
        if args.out_dir.is_some() {
            s.push_str(
                "  files           : real-page-01.bin.. and real-ad-manifest.txt (--out-dir)\n",
            );
        }
    }
    if let Some(dp) = datapath {
        s.push_str("\ndatapath observation (F2)\n");
        s.push_str(&format!(
            "  bind ip         : {}\n",
            args.bind_ip.as_deref().unwrap_or("(none)")
        ));
        s.push_str(&format!(
            "  frames seen     : {} (outbound non-discovery frames via CVLH2)\n",
            dp.frames_seen
        ));
        s.push_str(&format!(
            "  frames on 62056 : {} (dst port == 62056, the F2 datapath question)\n",
            dp.frames_on_datapath_port
        ));
        s.push_str(&format!(
            "  reply sent      : {} (D4: at most ONE 20B local probe per run)\n",
            dp.reply_sent
        ));
        s.push_str(&format!(
            "  reply skipped   : no_endpoint={} not_local={} already_sent={}\n",
            dp.reply_skipped_no_endpoint, dp.reply_skipped_not_local, dp.reply_already_sent
        ));
        s.push_str(&format!("  send fail       : {}\n", dp.send_fail));
        s.push_str(&format!("  reply bytes     : {}\n", dp.bytes));
        if args.loopback_selftest {
            s.push_str(
                "  mode            : LOOPBACK SELF-TEST (--loopback-selftest) - NOT a real-machine result\n",
            );
        }
    }
    if let Some(fw) = forward {
        s.push_str("\ndirect forward prototype (F3-A)\n");
        s.push_str(&format!(
            "  target          : {} (peer Agent port - NOT the game socket, NOT :62056)\n",
            args.forward_to.as_deref().unwrap_or("(none)")
        ));
        s.push_str(&format!(
            "  forward sock    : {} (sender identity the peer sees)\n",
            fw_sock
        ));
        s.push_str(&format!(
            "  frames seen     : {} (accepted frames that reached the forward stage, discovery included; the discovery ones are then counted under `skip discovery`)\n",
            fw.frames_seen
        ));
        s.push_str(&format!(
            "  forwarded       : {} (payload bytes sent verbatim)\n",
            fw.forwarded
        ));
        s.push_str(&format!("  forward bytes   : {}\n", fw.bytes));
        s.push_str(&format!("  forward fail    : {}\n", fw.forward_fail));
        s.push_str(&format!(
            "  skip not datapath: {} (dst port != {DATAPATH_PORT})\n",
            fw.skip_not_datapath
        ));
        s.push_str(&format!(
            "  skip key table  : {} (PROTOTYPE LIMIT, not a design rule: this prototype keeps at most {} mapping keys, and a frame whose key does not fit is not forwarded. The design (v0.3 §3.2) has no capacity cap - the crate's FakeEndpoint pool is the reference - so this counter exists to make a never-forward branch reachable at all, not to describe product behaviour.)\n",
            fw.skip_key_table_full, MAX_FORWARD_KEYS
        ));
        s.push_str(&format!("  mappings created: {}\n", fw.mappings_created));
        s.push_str(&format!(
            "  skip discovery  : {} (recognised as discovery, left to the F1 path; counted so the forward accounting closes)\n",
            fw.skip_discovery
        ));
        s.push_str(&format!(
            "  skip rejected   : {} (REJECTED_OVERSIZE | NO_PAYLOAD frames, which have no payload to forward; counted so the forward accounting closes - F3-A audit round 3, finding L5)\n",
            fw.skip_rejected_flags
        ));
    }
    if let Some(p) = peer {
        s.push_str("\nforward listener (F3-A peer side)\n");
        s.push_str(&format!(
            "  listen port     : {} (loopback only, never {DATAPATH_PORT})\n",
            args.forward_listen.unwrap_or(0)
        ));
        s.push_str(&format!("  payloads recv   : {}\n", p.received));
        s.push_str(&format!("  payload bytes   : {}\n", p.bytes));
        s.push_str(&format!(
            "  first sender    : {}\n",
            match peer_first_from {
                Some(f) if !f.is_empty() => f.as_str(),
                _ => "(none)",
            }
        ));
        s.push_str(&format!(
            "  last sender     : {}\n",
            if p.last_from.is_empty() {
                "(none)"
            } else {
                p.last_from.as_str()
            }
        ));
    }
    s.push_str(
        "\nnotes\n\
         - 'received frames' counts validated CVLH2 frames; 'datagrams' counts every UDP\n\
           datagram, so a mismatch means malformed input reached the Agent.\n\
         - Reconciliation against the Hook: hook.sent == agent.processed and\n\
           hook.sentNotify == agent 'oversize notify'. Compare with\n\
           `civlink_ctl.exe counters -x <exe>` on the game process.\n\
         - Without --simulate this Agent observes only. With --simulate it additionally\n\
           answers discovery requests as a local simulated host, injected over loopback\n\
           only. Without --forward-to it never forwards to a peer (with --forward-to it does,\n\
           see the F3-A bullet below) and no mode ever modifies game traffic. F1 evidence\n\
           only - NOT a multiplayer, E2-B or Gate A result.\n\
         - F5 --sim-lan-listen: the LAN simulated host binds ALL discovery ports on the given\n\
            IP and answers real Civ6 discovery broadcasts directly (no Hook chain, no native\n\
            broadcast routing/metric/firewall dependence). It is a SIMULATED HOST seen by a\n\
            real client - evidence for the cross-machine discovery path, NOT a\n\
            two-real-hosts multiplayer result and NOT E2-B/E3. The Agent never binds :62056,\n\
            never sets SO_REUSEADDR.\n\
         - F2 --simulate-datapath: the 20B reply is a LOCAL PROBE ONLY (codex D4) - it does\n\
            not claim a real peer source port, a game protocol answer, Relay RTT, or that\n\
            H2/R1 bind/deliver semantics were tested. The agent never binds :62056.\n\
         - F3-A --forward-to/--forward-listen: a LOOPBACK PROTOTYPE. Payloads are forwarded\n\
            verbatim once per frame (no retransmit, no rewrite) to ONE configured peer Agent\n\
            port; nothing is injected into a game process (Design I/II is M0-B) and no real\n\
            player join, H2/R1 bind semantics, Relay RTT or encryption is claimed. The\n\
            forward mapping key mirrors the civlink-fakeip crate shape but is a prototype\n\
            allocator; the crate remains the reference implementation.\n",
    );
    s
}

fn main() -> ExitCode {
    let args = match parse_args() {
        Ok(a) => a,
        Err(e) => {
            eprintln!("[!] {e}");
            return ExitCode::from(1);
        }
    };
    // M0-G hidden selftest: pure core, available in the default zero-dependency build.
    if args.peer_discover_selftest {
        let (checks, fails) = peer_discover_core::run_core_selftest();
        println!("PEER-CORE-SELFTEST: checks={checks} failed={fails}");
        return if fails == 0 {
            ExitCode::from(0)
        } else {
            ExitCode::from(1)
        };
    }
    match run(&args) {
        Ok(_) => ExitCode::from(0),
        Err(e) => {
            eprintln!("[!] {e}");
            ExitCode::from(2)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Test-only encoder. Port arguments are HOST order; on the wire `sin_port` holds them
    /// big-endian, so they are written with `to_be_bytes`.
    #[allow(clippy::too_many_arguments)]
    fn encode(
        seq: u32,
        sid: u64,
        sock: u32,
        gen: u32,
        src_ip: u32,
        src_port: u16,
        dst_ip: u32,
        dst_port: u16,
        flags: u8,
        payload: &[u8],
    ) -> Vec<u8> {
        let mut v = vec![0u8; FRAME_HDR + payload.len()];
        v[0..4].copy_from_slice(&FRAME_MAGIC);
        v[4] = FRAME_VER;
        v[5] = DIR_HOOK_TO_AGENT;
        v[6..10].copy_from_slice(&seq.to_le_bytes());
        v[10..18].copy_from_slice(&sid.to_le_bytes());
        v[18..22].copy_from_slice(&sock.to_le_bytes());
        v[22..26].copy_from_slice(&gen.to_le_bytes());
        v[26] = 2;
        v[27..31].copy_from_slice(&src_ip.to_le_bytes());
        v[31..33].copy_from_slice(&src_port.to_be_bytes());
        v[33..37].copy_from_slice(&dst_ip.to_le_bytes());
        v[37..39].copy_from_slice(&dst_port.to_be_bytes());
        v[39] = flags;
        v[40..42].copy_from_slice(&(payload.len() as u16).to_le_bytes());
        v[FRAME_HDR..].copy_from_slice(payload);
        v
    }

    #[test]
    fn decodes_a_valid_discovery_frame() {
        // Host ports go in; the helper stores the raw sin_port value (byte-swapped), exactly
        // like cvlh_encode does on the C++ side.
        let bytes = encode(
            7,
            0xAABB,
            3,
            1,
            0x0100007F,
            51234,
            0xFFFFFFFF,
            62918,
            FLAG_LIMITED_BCAST | FLAG_DISCOVERY,
            &DISCOVERY_MAGIC,
        );
        let f = decode(&bytes).expect("valid frame");
        assert_eq!(f.seq, 7);
        assert_eq!(f.session_id, 0xAABB);
        assert_eq!(f.logical_socket_id, 3);
        assert_eq!(f.socket_generation, 1);
        assert_eq!(f.flags, FLAG_LIMITED_BCAST | FLAG_DISCOVERY);
        assert_eq!(f.payload_len, 4);
        assert_eq!(f.payload, DISCOVERY_MAGIC.to_vec());
        // The frame stores address bytes in network order; reading them back must produce the
        // dotted quad as written on the wire.
        assert_eq!(ipv4_from_be(f.src_ip_be), "127.0.0.1");
        assert_eq!(ipv4_from_be(f.dst_ip_be), "255.255.255.255");
        assert_eq!(port_from_be16(f.src_port_be), 51234);
        assert_eq!(port_from_be16(f.dst_port_be), 62918);
    }

    #[test]
    fn rejects_a_wrong_address_family() {
        let mut bytes = encode(1, 1, 1, 1, 0, 0, 0, 0, 0, &[]);
        bytes[26] = 23; // AF_INET6
        assert_eq!(decode(&bytes).unwrap_err().kind(), "bad-address-family");
    }

    #[test]
    fn rejects_bad_magic_version_and_short_frames() {
        let mut bytes = encode(1, 1, 1, 1, 0, 0, 0, 0, 0, &[]);
        let mut bad = bytes.clone();
        bad[0] = b'X';
        assert_eq!(decode(&bad).unwrap_err().kind(), "bad-magic");

        bytes[4] = 9;
        assert_eq!(decode(&bytes).unwrap_err().kind(), "bad-version");

        assert_eq!(decode(&[0u8; 10]).unwrap_err().kind(), "short-frame");
    }

    #[test]
    fn rejects_oversize_payload_and_truncation() {
        let mut bytes = encode(1, 1, 1, 1, 0, 0, 0, 0, 0, &[0u8; 8]);
        // Claim more payload than the limit allows.
        bytes[40..42].copy_from_slice(&(MAX_PAYLOAD as u16 + 1).to_le_bytes());
        assert_eq!(decode(&bytes).unwrap_err().kind(), "payload-too-large");

        // Claim 32 payload bytes but supply only 8.
        let mut bytes = encode(1, 1, 1, 1, 0, 0, 0, 0, 0, &[0u8; 8]);
        bytes[40..42].copy_from_slice(&32u16.to_le_bytes());
        assert_eq!(decode(&bytes).unwrap_err().kind(), "truncated");
    }

    #[test]
    fn rejects_agent_to_hook_direction() {
        let mut bytes = encode(1, 1, 1, 1, 0, 0, 0, 0, 0, &[]);
        bytes[5] = 1;
        assert_eq!(decode(&bytes).unwrap_err().kind(), "wrong-direction");
    }

    #[test]
    fn sequence_tracking_counts_gaps_duplicates_and_reordering() {
        let mut st = SessionStats::default();
        for seq in [1u32, 2, 3] {
            st.note_seq(seq);
        }
        assert_eq!(st.seq_gaps, 0);
        assert_eq!(st.duplicates, 0);

        st.note_seq(6); // 4 and 5 missing
        assert_eq!(st.seq_gaps, 1);
        assert_eq!(st.seq_missing_frames, 2);

        st.note_seq(6); // repeated
        assert_eq!(st.duplicates, 1);

        st.note_seq(4); // older than last: out of order
        assert_eq!(st.out_of_order, 1);
        assert_eq!(st.first_seq, Some(1));
        assert_eq!(st.last_seq, Some(6));
    }

    #[test]
    fn parses_dotted_ip_and_rejects_bad_octets() {
        assert_eq!(parse_dotted_ip("127.0.0.1"), Ok([127, 0, 0, 1]));
        assert_eq!(parse_dotted_ip("192.168.31.59"), Ok([192, 168, 31, 59]));
        assert!(
            parse_dotted_ip("256.1.1.1").is_err(),
            "octet > 255 must fail"
        );
        assert!(parse_dotted_ip("1.2.3").is_err(), "three octets must fail");
        assert!(parse_dotted_ip("a.b.c.d").is_err(), "non-numeric must fail");
    }

    #[test]
    fn resolve_destination_uses_loopback_for_unresolved_or_loopback_sources() {
        // 0.0.0.0:59473 (unbound UDP socket's first send) -> loopback delivery.
        let d = resolve_destination(0, 59473u16.to_be(), [127, 0, 0, 1]);
        assert_eq!(d, SocketAddr::from(([127, 0, 0, 1], 59473)));
        // Frame bytes 7F 00 00 01 (get_u32le -> 0x0100007F) is loopback too.
        let d = resolve_destination(0x0100007F, 59473u16.to_be(), [127, 0, 0, 1]);
        assert_eq!(d, SocketAddr::from(([127, 0, 0, 1], 59473)));
        // A real LAN source stays as-is (frame bytes C0 A8 1F 3B, get_u32le -> 0x3B1FA8C0).
        let d = resolve_destination(0x3B1FA8C0, 51234u16.to_be(), [127, 0, 0, 1]);
        assert_eq!(d, SocketAddr::from(([192, 168, 31, 59], 51234)));
    }

    #[test]
    fn fixture_pages_are_validated_and_anonymized() {
        let mut pages: Vec<Vec<u8>> = (0..SIM_PAGE_COUNT)
            .map(|i| {
                let mut p = vec![0u8; SIM_PAGE_SIZE];
                p[0..4].copy_from_slice(&SIM_MAGIC);
                p[156..160].copy_from_slice(&(SIM_PAGE_COUNT as u32).to_le_bytes());
                p[160..164].copy_from_slice(&(i as u32).to_le_bytes());
                p[SIM_NAME_OFFSET..SIM_NAME_OFFSET + SIM_NAME_LEN]
                    .copy_from_slice(b"abcdefghijklmnopqrstuv");
                p
            })
            .collect();
        for i in 0..SIM_PAGE_COUNT {
            validate_page(&pages[i], i).expect("synthetic page must validate");
        }
        // Wrong index must fail, oversized page must fail.
        assert!(
            validate_page(&pages[0], 1).is_err(),
            "wrong index must fail"
        );
        let mut short = pages[0].clone();
        short.pop();
        assert!(validate_page(&short, 0).is_err(), "short page must fail");

        anonymize_pages(&mut pages, "CivLink-Test-Room-2222");
        for p in &pages {
            assert_eq!(
                &p[SIM_NAME_OFFSET..SIM_NAME_OFFSET + SIM_NAME_LEN],
                b"CivLink-Test-Room-2222"
            );
        }
        // Short names are padded with spaces, bytes beyond the name are zeroed out.
        anonymize_pages(&mut pages, "Hi");
        for p in &pages {
            let field = &p[SIM_NAME_OFFSET..SIM_NAME_OFFSET + SIM_NAME_LEN];
            assert_eq!(&field[..2], b"Hi");
            assert!(field[2..].iter().all(|&b| b == b' '));
        }
    }

    #[test]
    fn sim_replies_once_per_socket_with_budget_and_no_endpoint_handling() {
        let pages: Vec<Vec<u8>> = (0..SIM_PAGE_COUNT)
            .map(|i| {
                let mut p = vec![0u8; SIM_PAGE_SIZE];
                p[0..4].copy_from_slice(&SIM_MAGIC);
                p[156..160].copy_from_slice(&(SIM_PAGE_COUNT as u32).to_le_bytes());
                p[160..164].copy_from_slice(&(i as u32).to_le_bytes());
                p
            })
            .collect();
        // The reply socket binds a loopback port; no network involvement.
        let reply_sock = UdpSocket::bind("127.0.0.1:0").expect("test reply socket");
        let mut st = SimState {
            pages,
            reply_sock: Some(reply_sock),
            max_replies: 2,
            fallback_ip: [127, 0, 0, 1],
            stats: SimStats::default(),
            sockets: BTreeMap::new(),
        };
        let mk = |sock: u32, src_port: u16| Frame {
            dir: 0,
            seq: 1,
            session_id: 1,
            logical_socket_id: sock,
            socket_generation: 1,
            af: 2,
            src_ip_be: 0,
            src_port_be: src_port.to_be(),
            dst_ip_be: 0xFFFFFFFF,
            dst_port_be: 62907u16.to_be(),
            flags: FLAG_DISCOVERY,
            payload_len: 4,
            payload: DISCOVERY_MAGIC.to_vec(),
        };
        // First frame of an unbound socket: 0.0.0.0:0 -> deferred, counted as no_endpoint.
        st.consider(&mk(11, 0));
        assert_eq!(st.stats.no_endpoint, 1);
        assert_eq!(st.stats.replied_sockets, 0);
        // Second frame on the same socket exposes the real port -> one reply of 22 pages.
        st.consider(&mk(11, 59473));
        assert_eq!(st.stats.requests_seen, 2);
        assert_eq!(st.stats.replied_sockets, 1);
        assert_eq!(st.stats.pages_sent, 22);
        assert_eq!(st.stats.send_fail, 0);
        // Same socket again: no second reply.
        st.consider(&mk(11, 59473));
        assert_eq!(st.stats.replied_sockets, 1);
        assert_eq!(st.stats.pages_sent, 22);
        // New socket, budget 2 allows one more reply.
        st.consider(&mk(12, 0));
        st.consider(&mk(12, 60231));
        assert_eq!(st.stats.replied_sockets, 2);
        assert_eq!(st.stats.pages_sent, 44);
        // Budget exhausted: further new sockets are counted, never answered.
        st.consider(&mk(13, 0));
        st.consider(&mk(13, 61439));
        assert_eq!(st.stats.max_replies_reached, 1);
        assert_eq!(st.stats.replied_sockets, 2);
        assert_eq!(st.stats.pages_sent, 44);
    }

    #[test]
    fn datapath_requires_bind_ip_and_rejects_non_local() {
        // 0.0.0.0 and 255.255.255.255 are rejected by --bind-ip validation.
        assert!(DatapathState::new("0.0.0.0").is_err());
        assert!(DatapathState::new("255.255.255.255").is_err());
        assert!(DatapathState::new("not-an-ip").is_err());
        // A syntactically valid host-local dotted quad is accepted (the driver verifies it
        // against Get-NetIPConfiguration; the agent fail-closes on format only).
        let st = DatapathState::new("192.168.31.59").expect("local-looking ip");
        assert_eq!(st.stats.reply_sent, 0);
    }

    #[test]
    fn datapath_d4_single_probe_with_local_source_only() {
        let bind_ip = [127, 0, 0, 1];
        // The reply socket must be ephemeral (port 0) and never :62056.
        let reply_sock = UdpSocket::bind("0.0.0.0:0").expect("ephemeral reply socket");
        assert_ne!(reply_sock.local_addr().unwrap().port(), DATAPATH_PORT);
        let mut dp = DatapathState {
            bind_ip,
            stats: DatapathStats::default(),
            reply_sock,
        };
        let frame = |src_port: u16, src_ip: u32, dst_port: u16| Frame {
            dir: 0,
            seq: 1,
            session_id: 1,
            logical_socket_id: 1,
            socket_generation: 1,
            af: 2,
            src_ip_be: src_ip,
            src_port_be: src_port.to_be(),
            dst_ip_be: 0x0100007F,
            dst_port_be: dst_port.to_be(),
            flags: 0,
            payload_len: 4,
            payload: vec![0xAA, 0xBB, 0xCC, 0xDD],
        };
        // 0.0.0.0:0 -> no_endpoint, no reply.
        dp.consider(&frame(0, 0, DATAPATH_PORT), None);
        assert_eq!(dp.stats.reply_skipped_no_endpoint, 1);
        assert_eq!(dp.stats.reply_sent, 0);
        // src 0.0.0.0 with a port -> not_local (src must be confirmed local).
        dp.consider(&frame(51234, 0, DATAPATH_PORT), None);
        assert_eq!(dp.stats.reply_skipped_not_local, 1);
        // src = loopback (127.0.0.1, be 0x0100007F) matches bind_ip 127.0.0.1 -> reply.
        dp.consider(&frame(51234, 0x0100007F, DATAPATH_PORT), None);
        assert_eq!(dp.stats.reply_sent, 1);
        assert_eq!(dp.stats.bytes, DATAPATH_REPLY_LEN as u64);
        // Any further frame: already_sent, never a second reply (D4: at most one per run).
        dp.consider(&frame(51235, 0x0100007F, DATAPATH_PORT), None);
        assert_eq!(dp.stats.reply_sent, 1);
        assert_eq!(dp.stats.reply_already_sent, 1);
        assert_eq!(dp.stats.frames_seen, 4);
        assert_eq!(dp.stats.frames_on_datapath_port, 4);
    }

    #[test]
    fn datapath_sends_probe_to_confirmed_local_source_endpoint() {
        // Realistic: a UDP socket that sendto()ed with the game's bound source - the frame
        // src is a non-zero host-local address, dst is the datapath port.
        let dp_ip: [u8; 4] = [192, 168, 31, 59];
        let mut dp = DatapathState {
            bind_ip: dp_ip,
            stats: DatapathStats::default(),
            reply_sock: UdpSocket::bind("0.0.0.0:0").expect("ephemeral reply socket"),
        };
        // Build the same src_ip_be that decode() would produce for 192.168.31.59:
        // sin_addr network bytes C0 A8 1F 3B read little-endian.
        let src_ip_be = be_bytes_to_u32(&dp_ip);
        let f = Frame {
            dir: 0,
            seq: 1,
            session_id: 1,
            logical_socket_id: 1,
            socket_generation: 1,
            af: 2,
            src_ip_be,
            src_port_be: 62056u16.to_be(),
            dst_ip_be: be_bytes_to_u32(&[26, 74, 126, 98]),
            dst_port_be: DATAPATH_PORT.to_be(),
            flags: 0,
            payload_len: 4,
            payload: vec![0x11, 0x22, 0x33, 0x44],
        };
        // The probe is sent from the ephemeral socket to <bind_ip>:src_port. We cannot
        // observe the wire without a listener; we assert the counters and the target logic
        // via the recorded bytes (send to a local listener would require the same host).
        dp.consider(&f, None);
        assert_eq!(dp.stats.reply_sent, 1);
        assert_eq!(dp.stats.bytes, DATAPATH_REPLY_LEN as u64);
    }

    // ------------------------------------------------------------------ F3-A forward tests
    // Added for F3-A audit finding B-4: none of the tests covered ForwardState or
    // ForwardListener, so the forward path was only ever exercised by the driver script.

    fn mk_forward_frame(sock: u32, gen: u32, dst_port: u16, payload: &[u8]) -> Frame {
        mk_forward_frame_flags(sock, gen, dst_port, payload, 0)
    }

    /// Same frame with an explicit flags byte. Needed because the discovery predicate is an
    /// AND over flags, port and magic: with flags hard-coded to 0 the `is_discovery_request`
    /// branch could not be exercised at all (F3-A audit round 2, finding 5/M1).
    fn mk_forward_frame_flags(
        sock: u32,
        gen: u32,
        dst_port: u16,
        payload: &[u8],
        flags: u8,
    ) -> Frame {
        Frame {
            dir: 0,
            seq: 1,
            session_id: 0xABCD,
            logical_socket_id: sock,
            socket_generation: gen,
            af: 2,
            src_ip_be: 0x0100007F,
            src_port_be: 62056u16.to_be(),
            dst_ip_be: 0x0100007F,
            dst_port_be: dst_port.to_be(),
            flags,
            payload_len: payload.len(),
            payload: payload.to_vec(),
        }
    }

    #[test]
    fn forward_listener_refuses_the_datapath_port() {
        // F3-A audit round 2, finding 5: the earlier version of this guard only existed in
        // parse_args (--forward-listen), so ForwardListener::new(62056) was accepted. The
        // guard now also sits at the bind site, which is the only place that cannot be
        // bypassed by a future caller.
        let err = match ForwardListener::new(DATAPATH_PORT) {
            Ok(_) => panic!("ForwardListener must refuse :{DATAPATH_PORT}"),
            Err(e) => e,
        };
        assert!(
            err.contains("62056"),
            "error must name the refused port, got: {err}"
        );
    }

    #[test]
    fn discovery_predicate_is_an_and_not_an_or() {
        // The design defines a discovery request as: destination port inside the discovery
        // window AND a 4-byte payload equal to the discovery magic (v0.3 §3.2 rule 3). The
        // first revision treated "flag set OR port in range" as discovery, so a real 62056
        // data-plane frame carrying FLAG_DISCOVERY was silently dropped by the forward path
        // without being counted anywhere (audit round 2, M1). These four cases pin the AND.
        let magic = DISCOVERY_MAGIC.to_vec();
        // Port in window + magic -> discovery.
        assert!(is_discovery_request(&mk_forward_frame_flags(
            1, 1, 62905, &magic, 0
        )));
        // Datapath port + magic but port NOT in window -> not discovery, so it must forward.
        assert!(!is_discovery_request(&mk_forward_frame_flags(
            1,
            1,
            DATAPATH_PORT,
            &magic,
            0
        )));
        // Window port + FLAG_DISCOVERY but a non-magic payload -> NOT discovery: the flag
        // alone must never be enough, or real game traffic would be swallowed.
        assert!(!is_discovery_request(&mk_forward_frame_flags(
            1,
            1,
            62905,
            &[0x17, 0x32, 0x00, 0x00],
            FLAG_DISCOVERY
        )));
        // Window port + magic payload + FLAG_DISCOVERY -> discovery.
        assert!(is_discovery_request(&mk_forward_frame_flags(
            1,
            1,
            62905,
            &magic,
            FLAG_DISCOVERY
        )));
    }

    #[test]
    fn sha256_matches_known_vectors() {
        // SHA-256 of the empty string and of "abc", from FIPS 180-4 / the usual test vectors.
        assert_eq!(
            sha256_hex(b""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        // 120 bytes (the F3-A long payload) must hash without panicking on the pad path.
        let long = vec![0xABu8; 120];
        assert_eq!(sha256_hex(&long).len(), 64);
    }

    #[test]
    fn forward_skips_non_datapath_frames_by_reason() {
        let mut fw = ForwardState::new("127.0.0.1:21399").expect("forward state");
        // dst != 62056 -> skip_not_datapath, never forwarded.
        fw.consider(&mk_forward_frame(1, 1, 50999, &[0xDE, 0xAD]), None);
        assert_eq!(fw.stats.skip_not_datapath, 1);
        assert_eq!(fw.stats.forwarded, 0);
        assert_eq!(fw.stats.mappings_created, 0);
        assert_eq!(fw.stats.skip_key_table_full, 0);
    }

    #[test]
    fn forward_key_table_full_refuses_to_forward() {
        // Design v0.3 §3.2 step 2: with no mapping the frame is NOT forwarded. The prototype
        // table has a hard cap, so this branch is reachable and must be counted separately.
        let mut fw = ForwardState::new("127.0.0.1:21399").expect("forward state");
        for i in 0..MAX_FORWARD_KEYS {
            fw.consider(
                &mk_forward_frame(i as u32, 1, DATAPATH_PORT, &[0x17, 0x32]),
                None,
            );
        }
        assert_eq!(fw.stats.mappings_created, MAX_FORWARD_KEYS as u64);
        let before = fw.stats.forwarded;
        // A new key beyond the cap: no mapping -> skip, and the counter says why.
        fw.consider(
            &mk_forward_frame(MAX_FORWARD_KEYS as u32 + 1, 1, DATAPATH_PORT, &[0x17]),
            None,
        );
        assert_eq!(fw.stats.skip_key_table_full, 1);
        assert_eq!(fw.stats.forwarded, before);
        // Re-sending a key that is already mapped still goes through.
        fw.consider(&mk_forward_frame(0, 1, DATAPATH_PORT, &[0x17]), None);
        assert_eq!(fw.stats.forwarded, before + 1);
    }

    #[test]
    fn forward_delivers_payload_verbatim_and_peer_records_sender() {
        // End-to-end inside one process: ForwardState on an ephemeral socket, a real
        // ForwardListener on a fixed loopback port. This is what the driver script does, but
        // as a unit test so a regression fails `cargo test` instead of only the script.
        let listener_port = 21398;
        let mut listener = ForwardListener::new(listener_port).expect("listener");
        let mut fw = ForwardState::new(&format!("127.0.0.1:{listener_port}")).expect("forward");
        let payload: Vec<u8> = (0..120u8).collect();
        fw.consider(&mk_forward_frame(7, 1, DATAPATH_PORT, &payload), None);
        assert_eq!(fw.stats.forwarded, 1);
        assert_eq!(fw.stats.bytes, 120);
        // Give the datagram a moment to arrive, then drain.
        std::thread::sleep(Duration::from_millis(120));
        let mut buf = [0u8; 2048];
        listener.drain(&mut buf, None);
        assert_eq!(listener.stats.received, 1);
        assert_eq!(listener.stats.bytes, 120);
        assert_eq!(&buf[..120], &payload[..]);
        // Identity binding: the peer must have been reached from the forwarder's own socket.
        // The forward socket is bound to 0.0.0.0:0 (it must work for a real peer on any local
        // address), so the peer sees the route-selected address - on loopback that is
        // 127.0.0.1 - with the same port. Comparing the port is the part that ties the
        // delivery to this ForwardState and not to some other process.
        let fw_port = fw.sock.local_addr().expect("local addr").port();
        let seen: SocketAddr = listener.stats.first_from.parse().expect("peer sender addr");
        assert_eq!(seen.port(), fw_port);
        assert!(seen.ip().is_loopback(), "loopback test, saw {}", seen.ip());
        assert_eq!(listener.stats.first_from, listener.stats.last_from);
    }

    // ---- C1 (M0-C) --reserve-62900: the port plan is pure, so it is unit-tested here
    // instead of occupying 100 real sockets. C1 review suggestion 2 asked for exactly this:
    // the rule must fail `cargo test`, not only the PowerShell driver.

    #[test]
    fn discovery_port_plan_binds_all_100_by_default() {
        let plan = plan_discovery_ports(false);
        assert_eq!(plan.len(), 100);
        assert_eq!(plan.first().copied(), Some(DISCOVERY_FIRST));
        assert_eq!(plan.last().copied(), Some(DISCOVERY_LAST));
        assert!(plan.contains(&SIM_REPLY_PORT), "62900 must be bound by default");
    }

    #[test]
    fn reserve_62900_leaves_the_game_host_port_free() {
        let plan = plan_discovery_ports(true);
        assert_eq!(plan.len(), 99);
        assert!(
            !plan.contains(&SIM_REPLY_PORT),
            "--reserve-62900 must never bind the game's host port"
        );
        // Everything else is still ours, and the first bound port is the reply-source
        // fall-back that LAN requests will actually see.
        assert_eq!(plan.first().copied(), Some(DISCOVERY_FIRST + 1));
        assert_eq!(plan.last().copied(), Some(DISCOVERY_LAST));
    }

    #[test]
    fn reserve_62900_only_drops_the_one_port() {
        let all: std::collections::BTreeSet<u16> = plan_discovery_ports(false).into_iter().collect();
        let reserved: std::collections::BTreeSet<u16> =
            plan_discovery_ports(true).into_iter().collect();
        let dropped: Vec<u16> = all.difference(&reserved).copied().collect();
        assert_eq!(dropped, vec![SIM_REPLY_PORT]);
    }
}
