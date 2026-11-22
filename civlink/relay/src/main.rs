// civlink-relay - F3-B Relay prototype (non-publishable, loopback only).
//
// Design v0.3 section 4: the Relay routes by destination peer and forwards the payload
// VERBATIM. It does not decrypt, does not rewrite, does not retransmit, and does not
// reorder. There is no encryption in the F3 prototype (design section 4.1), so this
// process sees plaintext - it is a routing prototype, not the product Relay.
//
// Envelope (20-byte header, all integers little-endian):
//   0-3   magic 'CVLR'
//   4     version (1)
//   5     flags: 0x01 REGISTER (control), 0x00 DATA
//   6-9   dst_peer u32
//   10-13 src_peer u32 (filled by the Relay on forward; ignored on input)
//   14-17 seq u32 (echoed, never modified)
//   18-19 payload_len u16
//   20..  payload (<= 1280, verbatim)
//
// Every envelope the Relay forwards is logged with an FNV-1a 64 hash of the payload, so
// the evidence can compare "what was sent" == "what the Relay saw" == "what the peer
// received" byte for byte instead of only by length.

use std::collections::HashMap;
use std::env;
use std::fmt::Write as FmtWrite;
use std::fs::{self, File};
use std::io::{self, BufWriter, Write};
use std::net::{SocketAddr, UdpSocket};
use std::path::Path;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const MAGIC: [u8; 4] = *b"CVLR";
const VER: u8 = 1;
const HDR: usize = 20;
const MAX_PAYLOAD: usize = 1280;
const FLAG_REGISTER: u8 = 0x01;
/// The game's data-plane port. No CivLink process may own it (design v0.3 section 5.3).
const DATAPATH_PORT: u16 = 62056;
/// Largest datagram the receive buffer accepts. A UDP datagram bigger than the buffer makes
/// `recv_from` fail with WSAEMSGSIZE (os error 10040) on Windows; that is a property of the
/// input, not a fatal socket error, so it must be counted and skipped (F3-B audit H-1).
const RECV_BUF: usize = 65535;

fn wallclock_stamp() -> String {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_secs(0));
    let total = now.as_millis();
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

/// FNV-1a 64 over the payload. Cheap, dependency-free, and good enough to prove the
/// three copies are identical; it is explicitly NOT a security hash.
fn fnv1a64(data: &[u8]) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in data {
        h ^= u64::from(*b);
        h = h.wrapping_mul(0x0000_0100_0000_01B3);
    }
    h
}

fn get_u16le(b: &[u8]) -> u16 {
    u16::from(b[0]) | (u16::from(b[1]) << 8)
}

/// WSAEMSGSIZE (10040 / 0x2740) and the Unix equivalent EMSGSIZE (90): the datagram was
/// bigger than the receive buffer. Both are per-datagram conditions, not socket failures.
fn is_oversize_error(e: &io::Error) -> bool {
    matches!(e.raw_os_error(), Some(10040) | Some(90))
}

fn get_u32le(b: &[u8]) -> u32 {
    u32::from(b[0]) | (u32::from(b[1]) << 8) | (u32::from(b[2]) << 16) | (u32::from(b[3]) << 24)
}

fn hex_head(data: &[u8], max: usize) -> String {
    let mut s = String::new();
    for b in data.iter().take(max) {
        let _ = write!(s, "{b:02x}");
    }
    s
}

struct Envelope<'a> {
    flags: u8,
    dst_peer: u32,
    src_peer: u32,
    seq: u32,
    payload: &'a [u8],
}

fn parse(buf: &[u8]) -> Result<Envelope<'_>, &'static str> {
    if buf.len() < HDR {
        return Err("too-short");
    }
    if buf[0..4] != MAGIC {
        return Err("bad-magic");
    }
    if buf[4] != VER {
        return Err("bad-version");
    }
    let payload_len = usize::from(get_u16le(&buf[18..20]));
    if payload_len > MAX_PAYLOAD {
        return Err("payload-too-large");
    }
    if buf.len() < HDR + payload_len {
        return Err("truncated");
    }
    Ok(Envelope {
        flags: buf[5],
        dst_peer: get_u32le(&buf[6..10]),
        src_peer: get_u32le(&buf[10..14]),
        seq: get_u32le(&buf[14..18]),
        payload: &buf[HDR..HDR + payload_len],
    })
}

fn encode(dst_peer: u32, src_peer: u32, seq: u32, payload: &[u8], out: &mut [u8]) -> usize {
    out[0..4].copy_from_slice(&MAGIC);
    out[4] = VER;
    out[5] = 0;
    out[6..10].copy_from_slice(&dst_peer.to_le_bytes());
    out[10..14].copy_from_slice(&src_peer.to_le_bytes());
    out[14..18].copy_from_slice(&seq.to_le_bytes());
    out[18..20].copy_from_slice(&(payload.len() as u16).to_le_bytes());
    out[HDR..HDR + payload.len()].copy_from_slice(payload);
    HDR + payload.len()
}

#[derive(Default)]
struct Stats {
    datagrams: u64,
    bytes_in: u64,
    registers: u64,
    forward_requests: u64,
    forwarded: u64,
    forward_bytes: u64,
    forward_fail: u64,
    no_route: u64,
    self_drop: u64,
    bad_envelope: u64,
    control_frames: u64,
    /// Well-formed envelopes carrying a flag combination this prototype does not route
    /// (neither REGISTER nor DATA). Kept separately from `control_frames` so the datagram
    /// identity in the summary is a real identity rather than one that only holds for the
    /// inputs the fixture happens to send (F3-B audit, finding B-4).
    unknown_flags: u64,
    /// Datagrams that arrived but were larger than the receive buffer (WSAEMSGSIZE). Counted
    /// so "one bad datagram does not stop the Relay" is a measurable claim, not a slogan.
    oversize: u64,
    /// DATA frames whose sender could not be resolved to a registered peer. Fail-closed: the
    /// frame is dropped instead of trusting the envelope's src_peer (F3-B audit M-1).
    no_sender: u64,
    /// Set when the loop stopped because of a fatal socket error rather than a clean stop.
    fatal: Option<String>,
}

fn main() {
    let mut listen: SocketAddr = "127.0.0.1:34720".parse().unwrap();
    let mut listen_seconds: u64 = 60;
    let mut out_dir: Option<String> = None;
    let mut stop_file: Option<String> = None;
    let mut quiet = false;

    let mut it = env::args().skip(1);
    while let Some(a) = it.next() {
        match a.as_str() {
            "--listen" => {
                let v = it.next().unwrap_or_default();
                listen = match v.parse() {
                    Ok(s) => s,
                    Err(e) => {
                        eprintln!("[!] bad --listen '{v}': {e}");
                        std::process::exit(1);
                    }
                };
            }
            "--listen-seconds" => {
                listen_seconds = it.next().unwrap_or_default().parse().unwrap_or(60);
            }
            "--out-dir" => out_dir = Some(it.next().unwrap_or_default()),
            "--stop-file" => stop_file = Some(it.next().unwrap_or_default()),
            "--version" | "-V" => {
                println!("civlink-relay {}", env!("CARGO_PKG_VERSION"));
                std::process::exit(0);
            }
            "--quiet" => quiet = true,
            "--help" | "-h" => {
                println!(
                    "civlink-relay {}\n\n\
                     Usage: civlink-relay [--listen IP:PORT] [--listen-seconds N]\n\
                     \x20                   [--out-dir DIR] [--stop-file PATH] [--quiet]\n\n\
                     F3-B routing prototype: relays CVLR envelopes by dst_peer, payload\n\
                     VERBATIM (no decryption, no rewrite, no retransmit, no encryption).\n\
                     Default listen 127.0.0.1:34720. Exit codes: 0 ok, 1 usage, 2 cannot bind.\n",
                    env!("CARGO_PKG_VERSION")
                );
                std::process::exit(0);
            }
            other => {
                eprintln!("[!] unknown argument: {other}");
                std::process::exit(1);
            }
        }
    }

    // F3-B audit finding M-2: the Agent refuses to bind the game's data-plane port, but the
    // Relay had no such guard at all - `--listen 127.0.0.1:62056` bound successfully in the
    // audit run (pid 39372). Close it here so the H2 threshold holds at the binary level and
    // not only in the driver script's preconditions.
    if listen.port() == DATAPATH_PORT {
        eprintln!(
            "[!] --listen must not use port {DATAPATH_PORT}: the game's data-plane port is never owned by a CivLink process"
        );
        std::process::exit(1);
    }
    let sock = match UdpSocket::bind(listen) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("[!] cannot bind {listen}: {e}");
            std::process::exit(2);
        }
    };
    if let Err(e) = sock.set_read_timeout(Some(Duration::from_millis(100))) {
        eprintln!("[!] set_read_timeout failed: {e}");
        std::process::exit(2);
    }

    let (mut log, mut report_path) = match &out_dir {
        Some(dir) => {
            if let Err(e) = fs::create_dir_all(dir) {
                eprintln!("[!] cannot create {dir}: {e}");
                std::process::exit(1);
            }
            let path = format!("{dir}/relay-log.txt");
            let f = match File::create(&path) {
                Ok(f) => f,
                Err(e) => {
                    eprintln!("[!] cannot create {path}: {e}");
                    std::process::exit(1);
                }
            };
            (Some(BufWriter::new(f)), Some(dir.clone()))
        }
        None => (None, None),
    };
    if let Some(w) = log.as_mut() {
        let _ = writeln!(
            w,
            "# civlink-relay {} - F3-B routing prototype: forward by dst_peer, payload verbatim",
            env!("CARGO_PKG_VERSION")
        );
        let _ = w.flush();
    }

    if !quiet {
        println!(
            "civlink-relay {} listening on {} for {}s",
            env!("CARGO_PKG_VERSION"),
            listen,
            listen_seconds
        );
    }

    let mut peers: HashMap<u32, SocketAddr> = HashMap::new();
    let mut stats = Stats::default();
    let start = Instant::now();
    let deadline = start + Duration::from_secs(listen_seconds);
    let unbounded = listen_seconds == 0;
    let mut buf = vec![0u8; RECV_BUF];
    let mut out = vec![0u8; HDR + MAX_PAYLOAD];
    let mut stop_seen = false;

    while unbounded || Instant::now() < deadline {
        if !stop_seen {
            if let Some(p) = stop_file.as_ref() {
                if Path::new(p).exists() {
                    stop_seen = true;
                }
            }
        }
        if stop_seen {
            break;
        }
        let (len, from) = match sock.recv_from(&mut buf) {
            Ok(v) => v,
            Err(ref e)
                if e.kind() == io::ErrorKind::WouldBlock || e.kind() == io::ErrorKind::TimedOut =>
            {
                continue;
            }
            Err(ref e) if is_oversize_error(e) => {
                // A datagram larger than the buffer is a bad INPUT, not a broken socket:
                // count it, log it, and keep serving (F3-B audit H-1). It is still a
                // datagram the socket accepted, so `datagrams` counts it too - otherwise the
                // identity in the summary would silently stop being an identity.
                stats.datagrams += 1;
                stats.oversize += 1;
                stats.bad_envelope += 1;
                if let Some(w) = log.as_mut() {
                    let _ = writeln!(
                        w,
                        "{} reject kind=oversize-datagram (> {} B, os error {:?})",
                        wallclock_stamp(),
                        RECV_BUF,
                        e.raw_os_error()
                    );
                }
                continue;
            }
            Err(e) => {
                // Anything else is fatal. Record it so the summary cannot present a crashed
                // run as a clean one (the audit caught exactly that: break + exit 0).
                eprintln!("[!] recv_from failed: {e}");
                stats.fatal = Some(e.to_string());
                break;
            }
        };
        stats.datagrams += 1;
        stats.bytes_in += len as u64;

        let env = match parse(&buf[..len]) {
            Ok(e) => e,
            Err(kind) => {
                stats.bad_envelope += 1;
                if let Some(w) = log.as_mut() {
                    let _ = writeln!(
                        w,
                        "{} reject len={} kind={} from={}",
                        wallclock_stamp(),
                        len,
                        kind,
                        from
                    );
                }
                continue;
            }
        };

        if env.flags & FLAG_REGISTER != 0 {
            stats.registers += 1;
            stats.control_frames += 1;
            // Register by dst_peer: a caller says "I am peer N" by putting N in dst_peer.
            // Also honour a non-zero src_peer as an alias, but never invent one with max(),
            // which used to map an unrelated higher id onto this address (F3-B audit, M-5:
            // one address answering to two ids makes reverse lookup ambiguous).
            peers.insert(env.dst_peer, from);
            if env.src_peer != 0 && env.src_peer != env.dst_peer {
                peers.insert(env.src_peer, from);
            }
            if let Some(w) = log.as_mut() {
                let _ = writeln!(
                    w,
                    "{} register peer={} from={} (peers known: {})",
                    wallclock_stamp(),
                    env.dst_peer,
                    from,
                    peers.len()
                );
            }
            continue;
        }

        if env.flags != 0 {
            stats.control_frames += 1;
            stats.unknown_flags += 1;
            if let Some(w) = log.as_mut() {
                let _ = writeln!(
                    w,
                    "{} reject unknown-flags=0x{:02x} from={}",
                    wallclock_stamp(),
                    env.flags,
                    from
                );
            }
            continue;
        }

        // DATA: route by dst_peer. The sender must be a peer that actually registered from
        // this address; the envelope's src_peer is NOT trusted (docs/F3B-...md section 1 and
        // design v0.3 section 3.2). An unknown source is dropped and counted, never forwarded
        // under a self-declared identity (F3-B audit M-1).
        //
        // Every parsed DATA envelope is a forward request, counted before the sender is
        // resolved: a frame dropped for an unregistered source is still a request the Relay
        // received and rejected, so it has to appear on both sides of the reconciliation line.
        stats.forward_requests += 1;
        let sender = match peers.iter().find(|(_, a)| **a == from).map(|(p, _)| *p) {
            Some(p) => p,
            None => {
                stats.no_sender += 1;
                if let Some(w) = log.as_mut() {
                    let _ = writeln!(
                        w,
                        "{} drop seq={} from={} (unregistered source; envelope src_peer={} not trusted) len={}",
                        wallclock_stamp(),
                        env.seq,
                        from,
                        env.src_peer,
                        env.payload.len()
                    );
                }
                continue;
            }
        };

        if env.dst_peer == sender {
            stats.self_drop += 1;
            if let Some(w) = log.as_mut() {
                let _ = writeln!(
                    w,
                    "{} self-drop seq={} peer={} (dst == sender)",
                    wallclock_stamp(),
                    env.seq,
                    sender
                );
            }
            continue;
        }
        let target = match peers.get(&env.dst_peer) {
            Some(a) => *a,
            None => {
                stats.no_route += 1;
                if let Some(w) = log.as_mut() {
                    let _ = writeln!(
                        w,
                        "{} no-route seq={} dst_peer={} from={}",
                        wallclock_stamp(),
                        env.seq,
                        env.dst_peer,
                        from
                    );
                }
                continue;
            }
        };

        let n = encode(env.dst_peer, sender, env.seq, env.payload, &mut out);
        match sock.send_to(&out[..n], target) {
            Ok(sent) if sent == n => {
                stats.forwarded += 1;
                stats.forward_bytes += env.payload.len() as u64;
                if let Some(w) = log.as_mut() {
                    let _ = writeln!(
                        w,
                        "{} forward seq={} src_peer={} dst_peer={} len={} hash={:016x} head={} -> {}",
                        wallclock_stamp(),
                        env.seq,
                        sender,
                        env.dst_peer,
                        env.payload.len(),
                        fnv1a64(env.payload),
                        hex_head(env.payload, 8),
                        target
                    );
                }
            }
            _ => {
                stats.forward_fail += 1;
                if let Some(w) = log.as_mut() {
                    let _ = writeln!(
                        w,
                        "{} forward FAILED seq={} dst_peer={}",
                        wallclock_stamp(),
                        env.seq,
                        env.dst_peer
                    );
                }
            }
        }
    }

    if let Some(w) = log.as_mut() {
        let _ = w.flush();
    }

    let elapsed = start.elapsed();
    let mut s = String::new();
    s.push_str(&format!(
        "civlink-relay {} - F3-B relay summary\n",
        env!("CARGO_PKG_VERSION")
    ));
    s.push_str(&format!("run time          : {}\n", wallclock_stamp()));
    s.push_str(&format!(
        "listen            : {} for {:.1} s\n",
        listen,
        elapsed.as_secs_f64()
    ));
    s.push_str(&format!("datagrams         : {}\n", stats.datagrams));
    s.push_str(&format!("bytes in          : {}\n", stats.bytes_in));
    s.push_str(&format!("bad envelope      : {}\n", stats.bad_envelope));
    s.push_str(&format!("control frames    : {}\n", stats.control_frames));
    s.push_str(&format!(
        "unknown flags     : {} (well-formed control frames this prototype does not route)\n",
        stats.unknown_flags
    ));
    s.push_str(&format!("registers         : {}\n", stats.registers));
    s.push_str(&format!("forward requests  : {}\n", stats.forward_requests));
    s.push_str(&format!("forwarded         : {}\n", stats.forwarded));
    s.push_str(&format!("forward bytes     : {}\n", stats.forward_bytes));
    s.push_str(&format!("forward fail      : {}\n", stats.forward_fail));
    s.push_str(&format!("no route          : {}\n", stats.no_route));
    s.push_str(&format!("self drop         : {}\n", stats.self_drop));
    s.push_str(&format!(
        "no sender         : {} (unregistered source, dropped - src_peer not trusted)\n",
        stats.no_sender
    ));
    s.push_str(&format!(
        "oversize          : {} (datagram larger than {} B, skipped, not fatal; with a {} B buffer an IPv4 UDP payload of at most 65507 B cannot trigger this - the branch is a guard, not a reachable path)\n",
        stats.oversize, RECV_BUF, RECV_BUF
    ));
    s.push_str(&format!(
        "fatal             : {}\n",
        match stats.fatal.as_deref() {
            Some(e) => format!("RECV ERROR: {e}"),
            None => "none".to_string(),
        }
    ));
    // A real datagram identity: every datagram the socket accepted is classified exactly once
    // below. The earlier self-test asserted `datagrams == registers + forward requests + bad
    // envelope`, which holds only while the fixture sends nothing else - a control frame with
    // an unknown flag satisfied the counter sum but not the identity (F3-B audit, B-4).
    let classified =
        stats.registers + stats.forward_requests + stats.bad_envelope + stats.unknown_flags;
    s.push_str(&format!(
        "datagram identity : datagrams {} registers + forward_requests + bad_envelope + unknown_flags ({} + {} + {} + {}) = {}\n",
        if classified == stats.datagrams { "==" } else { "!=" },
        stats.registers,
        stats.forward_requests,
        stats.bad_envelope,
        stats.unknown_flags,
        classified
    ));
    s.push_str(&format!(
        "reconciliation    : forwarded + no_route + self_drop + forward_fail + no_sender = {} {} forward_requests = {}\n",
        stats.forwarded + stats.no_route + stats.self_drop + stats.forward_fail + stats.no_sender,
        if stats.forwarded
            + stats.no_route
            + stats.self_drop
            + stats.forward_fail
            + stats.no_sender
            == stats.forward_requests
        {
            "=="
        } else {
            "!="
        },
        stats.forward_requests
    ));
    s.push_str(&format!("peers seen        : {}\n", peers.len()));
    s.push_str(
        "\nnotes\n\
         - This Relay sees PLAINTEXT: the F3 prototype has no encryption (design section 4.1).\n\
         - It does not decrypt, rewrite, retransmit or reorder; one input envelope produces at\n\
           most one output datagram, and the payload bytes are copied unchanged.\n\
         - `hash` is FNV-1a 64 of the payload, for three-way byte comparison with the sender\n\
           and the receiving peer. It is not a security hash.\n\
         - Prototype only: not the product Relay, no identity/authentication, no rate limit\n\
           beyond loopback testing, no L1/L2 Noise keys (those are M0-B).\n",
    );
    if !quiet {
        print!("{s}");
    }
    if let Some(dir) = report_path.take() {
        let path = format!("{dir}/relay-summary.txt");
        if let Err(e) = fs::write(&path, &s) {
            eprintln!("[!] cannot write {path}: {e}");
            std::process::exit(1);
        }
        if !quiet {
            println!("\n[*] wrote {dir}/relay-log.txt and {path}");
        }
    }
    // F3-B audit H-1: a fatal receive error must not be laundered into a clean exit. The
    // summary is written first (so the evidence survives), then the exit code tells the truth.
    if stats.fatal.is_some() {
        std::process::exit(3);
    }
}
