//! M0-G Peer Discover 鈥?feature-gated network I/O (`--features peer-discover`).
//!
//! All protocol logic, thresholds and classification live in `peer_discover_core` (always
//! compiled, unit-tested in the default build). This module only does sockets + timing +
//! file output. It is compiled ONLY with `peer-discover`; the default build stays zero-dep.
//!
//! Sockets (design 搂2 M1, 搂9):
//!   * one RECEIVE socket per eligible NIC bound to <ip>:discover_port (SO_EXCLUSIVEADDRUSE,
//!     non-blocking) 鈥?so 搂5 source-subnet filtering has an explicit bind object (never 0.0.0.0).
//!   * one SEND socket per NIC bound to <ip>:0 with SO_BROADCAST, sending to the NIC's directed
//!     subnet broadcast (Windows limited broadcast would only use the preferred interface).
//!   * one PROBE reflector/initiator socket bound to 0.0.0.0:probe_port (unicast only).
//!   * NO :62056 bind, NO SO_REUSEADDR, NO game-protocol bytes touched.

use crate::peer_discover_core as core;
use if_addrs::{get_if_addrs, IfAddr, IfOperStatus};
use socket2::{Domain, Protocol, SockAddr, Socket, Type};
use std::collections::BTreeMap;
use std::fs::{self, File};
use std::io::{BufWriter, Write};
use std::net::{IpAddr, Ipv4Addr, SocketAddr, SocketAddrV4, UdpSocket};
use std::os::windows::io::AsRawSocket;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

// SOL_SOCKET on Windows = 0xffff (ws2def.h). The earlier 0x1 constant was wrong and made
// every setsockopt(SO_EXCLUSIVEADDRUSE) fail with WSAEINVAL 10022; SO_REUSEADDR/SO_BROADCAST
// passed only because I had passed their level as 0xffff in the probe by accident.
const SOL_SOCKET: i32 = 0xffff;
const SO_EXCLUSIVEADDRUSE: i32 = -5; // (int)(~SO_REUSEADDR), SO_REUSEADDR = 0x0004
const IPPROTO_IP: i32 = 0;
const IP_UNICAST_IF: i32 = 31; // force the egress interface (C2-verified mechanism)

#[link(name = "ws2_32")]
extern "system" {
    fn setsockopt(s: usize, level: i32, optname: i32, optval: *const u8, optlen: i32) -> i32;
}

fn set_exclusive(sock: &Socket) -> Result<(), String> {
    let raw = sock.as_raw_socket() as usize;
    let one: i32 = 1;
    let rc = unsafe {
        setsockopt(
            raw,
            SOL_SOCKET,
            SO_EXCLUSIVEADDRUSE,
            &one as *const i32 as *const u8,
            std::mem::size_of::<i32>() as i32,
        )
    };
    if rc != 0 {
        Err(format!(
            "setsockopt(SO_EXCLUSIVEADDRUSE) failed: {} (another process may own the port)",
            std::io::Error::last_os_error()
        ))
    } else {
        Ok(())
    }
}

/// Checkbox enforcement (2026-11-22): the unbound limited-broadcast socket egresses via the
/// OS's default route (lowest InterfaceMetric NIC), NOT via the operator's checked set. On a
/// VM whose Radmin adapter has a lower metric than the checked ETHERNET0, the 255.255.255.255
/// broadcast leaves via Radmin and its UNCHECKED source address leaks into the peer table
/// (observed 2026-11-22: A learned B's Radmin addr although B only checked ETHERNET0).
/// Detect the source IP the OS would choose for the limited broadcast (UDP connect() only
/// pins the default peer - it sends nothing - and getsockname then reports the chosen local
/// address) and return false when that NIC is not checked; the per-NIC pinned sockets still
/// broadcast on every checked NIC, so discovery keeps working.
fn limited_egress_checked(discover_port: u16, ifaces: &[LocalIface]) -> bool {
    let sock = match Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP)) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("[peer-discover] cannot detect limited-broadcast egress ({e}); sending anyway");
            return true;
        }
    };
    if let Err(e) = sock.set_broadcast(true) {
        eprintln!("[peer-discover] limited egress probe: SO_BROADCAST failed ({e}); sending anyway");
        return true;
    }
    let dst = SockAddr::from(SocketAddrV4::new(Ipv4Addr::new(255, 255, 255, 255), discover_port));
    if let Err(e) = sock.connect(&dst) {
        eprintln!("[peer-discover] limited egress probe: connect failed ({e}); sending anyway");
        return true;
    }
    match sock.local_addr() {
        Ok(la) => match la.as_socket() {
            Some(sa) => match sa.ip() {
                IpAddr::V4(v4) => {
                    let ok = ifaces.iter().any(|f| f.ip == v4);
                    if !ok {
                        eprintln!(
                            "[peer-discover] limited broadcast would egress via {} (unchecked NIC): suppressed",
                            v4
                        );
                    }
                    ok
                }
                _ => true,
            },
            None => true,
        },
        Err(_) => true,
    }
}

/// Pin the egress interface for this socket (VM cross-machine lesson: a host with a VPN
/// adapter at metric 1 sends its directed broadcast out the VPN, where no one listens).
/// if_index in network byte order per the IP_UNICAST_IF contract (C2-verified).
fn pin_egress(sock: &Socket, if_index: u32, label: &str) {
    let raw = sock.as_raw_socket() as usize;
    let idx_be = if_index.to_be(); // u32::to_be == htonl for this purpose
    let rc = unsafe {
        setsockopt(
            raw,
            IPPROTO_IP,
            IP_UNICAST_IF,
            &idx_be as *const u32 as *const u8,
            std::mem::size_of::<u32>() as i32,
        )
    };
    if rc != 0 {
        eprintln!(
            "[peer-discover] WARNING: setsockopt(IP_UNICAST_IF) failed on {}: {} (broadcast may leave via the wrong NIC)",
            label,
            std::io::Error::last_os_error()
        );
    }
}

/// Build a UDP Socket bound to a specific local IP:port with SO_EXCLUSIVEADDRUSE, then hand
/// it back as a std UdpSocket (socket2 has From<Socket> for UdpSocket).
fn exclusive_udp_bind(ip: Ipv4Addr, port: u16) -> Result<UdpSocket, String> {
    let s = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))
        .map_err(|e| format!("socket() failed: {e}"))?;
    set_exclusive(&s)?;
    let addr = SockAddr::from(SocketAddrV4::new(ip, port));
    s.bind(&addr)
        .map_err(|e| format!("bind {ip}:{port} failed: {e}"))?;
    let udp: UdpSocket = s.into();
    Ok(udp)
}

#[derive(Clone, Debug)]
struct LocalIface {
    name: String,
    index: u32,
    ip: Ipv4Addr,
    mask: Ipv4Addr,
    bcast: Ipv4Addr,
    vpn: bool,
}

fn enumerate(include_vpn: bool, ifaces_filter: Option<&str>) -> Result<Vec<LocalIface>, String> {
    // The GUI lets the operator tick exactly which NICs take part. Honour that: an
    // unchecked NIC must not broadcast, or the privacy warning above would be a lie.
    // Empty / "ALL" => no filter (CLI use).
    let allow: Option<Vec<Ipv4Addr>> = ifaces_filter.and_then(|s| {
        let t = s.trim();
        if t.is_empty() || t.eq_ignore_ascii_case("all") {
            return None;
        }
        let v: Vec<Ipv4Addr> = t
            .split(',')
            .filter_map(|p| p.trim().parse::<Ipv4Addr>().ok())
            .collect();
        if v.is_empty() {
            None
        } else {
            Some(v)
        }
    });
    let mut out = Vec::new();
    let ifs = get_if_addrs().map_err(|e| format!("get_if_addrs failed: {e}"))?;
    for it in ifs {
        if it.oper_status != IfOperStatus::Up {
            continue;
        }
        let (ip, mask, bcast) = match it.addr {
            IfAddr::V4(v4) => {
                if v4.is_loopback() {
                    continue;
                }
                let b = v4.broadcast.unwrap_or_else(|| {
                    Ipv4Addr::from(core::directed_broadcast(v4.ip.octets(), v4.netmask.octets()))
                });
                (v4.ip, v4.netmask, b)
            }
            IfAddr::V6(_) => continue, // IPv4 MVP
        };
        let adapter = it.adapter_name.clone();
        let cls = core::classify_iface(&it.name, &adapter, ip.octets());
        if cls == core::IfClass::Skip {
            continue;
        }
        if let Some(list) = &allow {
            if !list.contains(&ip) {
                continue; // operator did not tick this NIC
            }
        }
        let vpn = cls == core::IfClass::Vpn;
        // An explicitly ticked NIC always participates: --ifaces is the operator's choice,
        // so the VPN safety gate must not silently drop a checked VPN adapter. The GUI's
        // vpnSelected regex and core::classify_iface can disagree on adapter names (e.g.
        // "vEthernet (WSL)" or a VPN whose name does not match), and dropping a checked
        // NIC here made the checkbox meaningless (observed 2026-11-22). The gate still
        // applies when NO explicit allow-list is given (CLI default: physical NICs only).
        if vpn && !include_vpn && allow.is_none() {
            continue; // default: physical NICs only (safety decision); explicit ticks override
        }
        out.push(LocalIface {
            name: it.name.clone(),
            index: it.index.unwrap_or(0),
            ip,
            mask,
            // Send BOTH the subnet directed broadcast and the limited broadcast. Windows
            // delivery differs per path (VM cross-machine lesson: limited broadcast from the
            // VM arrives at A, the directed one did not in the same run).
            bcast: Ipv4Addr::new(255, 255, 255, 255),
            vpn,
        });
        out.push(LocalIface {
            name: it.name.clone(),
            index: it.index.unwrap_or(0),
            ip,
            mask,
            bcast,
            vpn,
        });
    }
    if out.is_empty() {
        return Err("no eligible IPv4 interface (try --include-vpn or check adapter state)".into());
    }
    Ok(out)
}

fn uuid_now() -> [u8; 16] {
    // No rand crate: mix system time + process id into 16 bytes. Identity is per-process only.
    let n = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let pid = std::process::id() as u64;
    let mut u = [0u8; 16];
    let seed = (n as u64) ^ (pid.wrapping_mul(0x9E37_79B9_7F4A_7C15));
    u[0..8].copy_from_slice(&seed.to_be_bytes());
    let hi = (n >> 64) as u32; // high bits of the 128-bit nanosecond value
    u[8..12].copy_from_slice(&hi.to_be_bytes());
    let mix2 = seed.wrapping_mul(0xBF58_476D_1CE4_E5B9);
    u[12..16].copy_from_slice(&mix2.to_be_bytes()[0..4]);
    u
}

fn ts_ns(start: Instant) -> u64 {
    start.elapsed().as_nanos() as u64
}

#[derive(Default)]
struct RunStats {
    discovery_sent: u64,
    discovery_recv: u64,
    cross_subnet_recv: u64,
    responses_sent: u64,
    peers_seen: u64,
    probe_sent: u64,
    probe_recv: u64,
    probe_reflected: u64,
}

/// Discover + probe run. `stop` is polled each loop; when set we write outputs and exit 0.
pub fn run_peer_discover(
    discover_interval_ms: u64,
    discover_port: u16,
    probe_port: u16,
    include_vpn: bool,
    listen_secs: u64,
    ifaces_filter: Option<&str>,
    peers_dir: Option<&str>,
    out_dir: Option<&str>,
    stop: &AtomicBool,
    abort: &AtomicBool,
) -> Result<(), String> {
    let start = Instant::now();
    let uuid = uuid_now();
    let ifaces = enumerate(include_vpn, ifaces_filter)?;

    // 鈽匯eceive socket (VM cross-machine test revision of design M1): a socket bound to the
    // NIC's UNICAST address does NOT receive remote directed broadcasts on Windows (only its
    // own loopback) - proven 2026-11-20: A(192.168.31.60) 鈫?B(192.168.31.176) broadcasts were
    // seen by neither side, while a 0.0.0.0-bound PS listener got them. So: ONE wildcard
    // socket 0.0.0.0:discover_port + IP_PKTINFO to learn the destination address per packet,
    // then match that against each NIC's broadcast address for the 搂5 source-subnet filter.
    let recv_wild = exclusive_udp_bind(Ipv4Addr::UNSPECIFIED, discover_port)?;
    recv_wild
        .set_nonblocking(true)
        .map_err(|e| format!("set_nonblocking failed: {e}"))?;
    if !crate::egress::enable_pktinfo(&recv_wild) {
        eprintln!("[peer-discover] WARNING: IP_PKTINFO unavailable - falling back to per-NIC subnet match on source only");
    }
    // Per-NIC send socket bound to <ip>:0 with SO_BROADCAST and the egress pinned to that
    // NIC (IP_UNICAST_IF), so the directed broadcast leaves via the right interface even
    // when a VPN adapter owns the lowest metric.
    let mut send_socks: Vec<(LocalIface, UdpSocket)> = Vec::new();
    // Plus ONE un-pinned broadcast socket (default routing). Cross-machine lesson (vm-raw
    // experiment 2026-11-20): a pinned socket that also carries a bound source IP fails to
    // deliver limited broadcast 255.255.255.255 cross-machine even though send_to() returns
    // Ok; the same packet from an unbound UdpClient arrives fine. So limited broadcast goes
    // out via this socket, directed broadcast via the pinned per-NIC sockets.
    let mut limited_sock: Option<UdpSocket> = None;
    for ifc in &ifaces {
        let sock = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))
            .map_err(|e| format!("socket() failed: {e}"))?;
        sock.set_broadcast(true)
            .map_err(|e| format!("SO_BROADCAST failed on {}: {e}", ifc.name))?;
        pin_egress(&sock, ifc.index, &ifc.name);
        let addr = SockAddr::from(SocketAddrV4::new(ifc.ip, 0));
        sock.bind(&addr)
            .map_err(|e| format!("bind {} failed: {e}", ifc.ip))?;
        let udp: UdpSocket = sock.into();
        send_socks.push((ifc.clone(), udp));
    }
    // Non-blocking clones of the per-NIC send sockets, polled every loop iteration for
    // discovery RESPONSES (a peer replies to the source port of our discovery packet,
    // which is this socket's ephemeral port). std's try_recv_from exists on &UdpSocket
    // since 1.62 but the 1.75 toolchain here refused the method on a shared reference;
    // owned clones + set_nonblocking avoid the issue entirely.
    let mut resp_clones: Vec<UdpSocket> = Vec::new();
    for (_, s) in &send_socks {
        if let Ok(c) = s.try_clone() {
            let _ = c.set_nonblocking(true);
            resp_clones.push(c);
        }
    }
    {
        let sock = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))
            .map_err(|e| format!("socket() failed: {e}"))?;
        sock.set_broadcast(true)
            .map_err(|e| format!("SO_BROADCAST failed (limited socket): {e}"))?;
        // no bind: default routing table decides the egress NIC (vm-raw proven path)
        let udp: UdpSocket = sock.into();
        limited_sock = Some(udp);
    }
    // Checkbox enforcement: the unbound limited broadcast must only fire when the OS-chosen
    // egress NIC is one the operator checked - otherwise it leaks an unchecked NIC's source
    // address into the peer table and the checkbox stops meaning anything (observed 2026-11-22:
    // B only checked ETHERNET0 yet A learned B's Radmin addr and measured Radmin paths).
    let limited_ok = limited_egress_checked(discover_port, &ifaces);
    // Probe reflector/initiator socket on 0.0.0.0:probe_port (unicast).
    // A second instance on the same machine gets WSAEACCES here (EXCLUSIVEADDRUSE held by
    // instance A on a different port is fine; the clash is this wildcard bind). That is
    // by design: two same-machine instances sharing one probe port cannot distinguish
    // reflections; the operator runs one instance per machine.
    let probe_sock = exclusive_udp_bind(Ipv4Addr::UNSPECIFIED, probe_port)?;
    probe_sock
        .set_nonblocking(true)
        .map_err(|e| format!("probe set_nonblocking: {e}"))?;
    // Checkbox enforcement (2026-11-22): learn the DESTINATION of every incoming probe via
    // IP_PKTINFO so we can refuse to answer probes addressed to an unchecked NIC - otherwise
    // the wildcard probe socket answers on every NIC and the operator's checkbox stops
    // meaning anything on the answering side too.
    if !crate::egress::enable_pktinfo(&probe_sock) {
        eprintln!(
            "[peer-discover] WARNING: probe IP_PKTINFO unavailable - answering probes on every NIC"
        );
    }

    let dir = match (peers_dir, out_dir) {
        (Some(p), _) => p.to_string(),
        (None, Some(o)) => format!("{o}/peers"),
        (None, None) => "peers".to_string(),
    };
    fs::create_dir_all(&dir).map_err(|e| format!("cannot create {dir}: {e}"))?;

    let mut stats = RunStats::default();
    // uuid(16) -> last-seen Instant + source addrs learned
    let mut peers: BTreeMap<[u8; 16], (Instant, Vec<SocketAddr>, u16)> = BTreeMap::new();
    let mut last_broadcast = Instant::now()
        .checked_sub(Duration::from_millis(discover_interval_ms))
        .unwrap_or_else(Instant::now);
    // live peer table for the GUI (rewritten on change, throttled to 500 ms)
    let mut last_live = Instant::now();
    // Fast mode: instant the FIRST peer was seen; probing starts shortly after.
    let mut first_peer_at: Option<Instant> = None;
    // Probe results, published as soon as the inline probe finishes (see the loop below).
    let mut probed = false;
    let mut paths: Vec<PathResult> = Vec::new();
    // Seconds of the window that had elapsed when probing started (live-table basis).
    let mut listen_used = listen_secs;
    // Frozen elapsed for phase "done": the results are published seconds after the run starts
    // (inline probe), but the loop keeps broadcasting for the rest of the window; without a
    // frozen value the panel would keep counting "已用" up to the full window length.
    let mut done_elapsed: Option<u64> = None;

    eprintln!(
        "[peer-discover] ifaces={} discover_port={} probe_port={} interval={}ms include_vpn={}",
        ifaces.len(),
        discover_port,
        probe_port,
        discover_interval_ms,
        include_vpn
    );

    let mut buf = [0u8; 1024];
    while !stop.load(Ordering::Relaxed) && !abort.load(Ordering::Relaxed) {
        // --- periodic discovery broadcast on every eligible NIC, from that NIC's own IP
        if last_broadcast.elapsed() >= Duration::from_millis(discover_interval_ms) {
            let pkt = core::encode_discovery(&uuid, probe_port, if include_vpn {
                core::DISC_FLAG_INCLUDE_VPN
            } else {
                0
            });
            for (ifc, sock) in &send_socks {
                let dst = SocketAddrV4::new(ifc.bcast, discover_port);
                match sock.send_to(&pkt, dst) {
                    Ok(_) => stats.discovery_sent += 1,
                    Err(e) => eprintln!(
                        "[peer-discover] send failed on {} -> {}: {}",
                        ifc.name, dst, e
                    ),
                }
            }
            // Limited broadcast via the un-pinned socket (vm-raw proven path), but only when
            // the OS-chosen egress NIC is one the operator checked (see limited_egress_checked).
            if limited_ok {
                if let Some(ls) = &limited_sock {
                    let dst = SocketAddrV4::new(Ipv4Addr::new(255, 255, 255, 255), discover_port);
                    match ls.send_to(&pkt, dst) {
                        Ok(_) => stats.discovery_sent += 1,
                        Err(e) => eprintln!(
                            "[peer-discover] limited-broadcast send failed -> {}: {}",
                            dst, e
                        ),
                    }
                }
            }
            last_broadcast = Instant::now();
        }

        // --- receive discovery/response on the wildcard socket; the arriving NIC is learned
        // from IP_PKTINFO's destination address (equals that NIC's broadcast address for a
        // directed broadcast) and the source must be inside THAT NIC's subnet (搂5 filter).
        loop {
            let info = match crate::egress::recv_with_dst(&recv_wild, &mut buf) {
                Ok(Some(i)) => i,
                Ok(None) => break,          // nothing queued
                Err(_) => break,
            };
            let n = info.len;
            let from = info.from;
            if std::env::var("CIVLINK_PD_DEBUG").as_deref() == Ok("1") {
                eprintln!(
                    "[pd-dbg] recv {}B from {} dst={:?}",
                    n,
                    from,
                    info.local_addr.as_ref().map(|a| a.to_string())
                );
            }
            let ip = match from.ip() {
                IpAddr::V4(v4) => v4,
                IpAddr::V6(_) => continue,
            };
            // Which NIC did this packet arrive on? Match the pktinfo destination against each
            // NIC's directed broadcast; fall back to source-subnet match when pktinfo is off.
            let arrived: Option<&LocalIface> = match info.local_addr {
                Some(sa) => match sa.ip() {
                    IpAddr::V4(dst) => ifaces.iter().find(|f| f.bcast == dst),
                    IpAddr::V6(_) => None,
                },
                None => None,
            };
            let ifc = match arrived {
                Some(f) => f,
                None => match ifaces
                    .iter()
                    .find(|f| core::in_subnet(ip.octets(), f.ip.octets(), f.mask.octets()))
                {
                    Some(f) => f,
                    // Cross-machine lesson (m0g-dual): a peer's LIMITED broadcast can leave
                    // via ITS lowest-metric NIC (e.g. its Radmin), so the source IP is NOT
                    // in any of our subnets. Instead of dropping it, accept it on the first
                    // interface - the reply will go back unicast via the routing table and
                    // still reach the peer (unicast VM->A was verified to work).
                    None => match ifaces.first() {
                        Some(f) => {
                            stats.cross_subnet_recv += 1;
                            f
                        }
                        None => continue,
                    },
                },
            };
            stats.discovery_recv += 1;
            // Discovery or response: both carry uuid + probe_port (+ flags).
            let is_disc = buf.get(0..4) == Some(core::DISC_MAGIC.as_slice());
            let is_resp = buf.get(0..4) == Some(core::RESP_MAGIC.as_slice());
            if !is_disc && !is_resp {
                continue;
            }
            let (peer_uuid, peer_probe_port, _flags) = match core::decode_discovery(
                &buf[..n],
                if is_disc {
                    core::DISC_MAGIC
                } else {
                    core::RESP_MAGIC
                },
            ) {
                Some(v) => v,
                None => continue,
            };
            if peer_uuid == uuid {
                continue; // ignore our own broadcast looped back
            }
            let entry = peers
                .entry(peer_uuid)
                .or_insert_with(|| (Instant::now(), Vec::new(), peer_probe_port));
            entry.0 = Instant::now();
            entry.2 = peer_probe_port;
            // One entry per peer IP: the source port of a discovery datagram is ephemeral and
            // is not what we probe (we probe the peer's advertised probe port), so keeping
            // every (ip,port) pair only multiplies identical probe paths.
            if !entry.1.iter().any(|a| a.ip() == from.ip()) {
                entry.1.push(from);
            }
            stats.peers_seen = peers.len() as u64;
            // Respond to a discovery (equal-size 24 B response; no amplification).
            if is_disc {
                let r = core::encode_discovery_resp(&uuid, probe_port, if include_vpn {
                    core::DISC_FLAG_INCLUDE_VPN
                } else {
                    0
                });
                // Reply from the per-NIC socket whose index matches the arrival NIC: the
                // source address then names OUR real NIC (the peer adds it to its addr
                // list). The reply lands on the requester's per-NIC send socket (its
                // discovery source port), which the requester polls for responses too.
                let ssock = send_socks
                    .iter()
                    .find(|(sifc, _)| sifc.index == ifc.index)
                    .map(|(_, s)| s);
                if let Some(s) = ssock.or_else(|| send_socks.first().map(|(_, s)| s)) {
                    let _ = s.send_to(&r, from);
                    stats.responses_sent += 1;
                }
            }
        }

        // --- response receive on the per-NIC send sockets: a peer replies to the source
        // port of our discovery packet (this socket's ephemeral port), and the reply's
        // source address names the peer's REAL NIC. Poll every send socket non-blocking
        // and fold the CLPR source into the peer's address list (m0g-dual lesson: without
        // this, a peer whose broadcasts leave via a different NIC than ours stays known
        // only by its broadcast-side address and can never be probed on its LAN NIC).
        for ssock in &resp_clones {
            loop {
                match ssock.recv_from(&mut buf) {
                    Ok((n, rfrom)) => {
                        if std::env::var("CIVLINK_PD_DEBUG").as_deref() == Ok("1") {
                            eprintln!("[pd-dbg] resp-on-nic-socket {}B from {}", n, rfrom);
                        }
                        if buf.get(0..4) != Some(core::RESP_MAGIC.as_slice()) {
                            continue;
                        }
                        let rip = match rfrom.ip() {
                            IpAddr::V4(v4) => v4,
                            IpAddr::V6(_) => continue,
                        };
                        if let Some((ruuid, rport, _)) =
                            core::decode_discovery(&buf[..n], core::RESP_MAGIC)
                        {
                            if ruuid != uuid {
                                let entry = peers
                                    .entry(ruuid)
                                    .or_insert_with(|| (Instant::now(), Vec::new(), rport));
                                entry.0 = Instant::now();
                                entry.2 = rport;
                                let raddr = SocketAddr::new(
                                    IpAddr::V4(rip),
                                    rfrom.port(),
                                );
                                if !entry.1.iter().any(|a| a.ip() == raddr.ip()) {
                                    entry.1.push(raddr);
                                }
                                stats.peers_seen = peers.len() as u64;
                            }
                        }
                    }
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                    Err(_) => break,
                }
            }
        }

        // --- probe receive: reflect requests (TWAMP Light) or collect our responses.
        // Checkbox enforcement: with pktinfo on, only answer probes addressed to a CHECKED
        // NIC's IP. A probe to an unchecked NIC (e.g. a leaked Radmin address) gets no
        // answer, so the far side can never measure a path through a NIC we did not pick.
        loop {
            let info = match crate::egress::recv_with_dst(&probe_sock, &mut buf) {
                Ok(Some(i)) => i,
                Ok(None) => break, // WouldBlock: nothing queued
                Err(_) => break,
            };
            let n = info.len;
            let from = info.from;
            if let Some(sa) = info.local_addr {
                if let IpAddr::V4(dst) = sa.ip() {
                    let checked = ifaces.iter().any(|f| f.ip == dst);
                    if !checked {
                        // Not addressed to a checked NIC: refuse to reflect (checkbox rule).
                        if std::env::var("CIVLINK_PD_DEBUG").as_deref() == Ok("1") {
                            eprintln!(
                                "[pd-dbg] probe from {} to unchecked dst {}: not answered",
                                from, dst
                            );
                        }
                        continue;
                    }
                }
            }
            let pf = match core::decode_probe(&buf[..n]) {
                Some(p) => p,
                None => continue,
            };
            if !pf.is_response {
                // Reflect: copy seq + T1, stamp T2 (arrival) and T3 (departure).
                let t2 = ts_ns(start);
                let t3 = ts_ns(start);
                let reply = core::encode_probe(pf.seq, true, pf.t1, t2, t3);
                let _ = probe_sock.send_to(&reply, from);
                stats.probe_reflected += 1;
            } else {
                // Response to our own probe — recorded by the probe phase below via a
                // shared measure socket. Here we only count for diagnostics.
                stats.probe_recv += 1;
            }
        }

        // Publish the peer table so the GUI can render discovered devices live. Once the
        // inline probe has finished we keep publishing the results (phase "done") for the
        // rest of the window, so the panel keeps showing the measured paths while the
        // broadcast loop continues.
        if last_live.elapsed() >= Duration::from_millis(500) {
            if probed {
                write_live(&uuid, &dir, &peers, start, "done", &paths, listen_used, done_elapsed);
            } else {
                write_live(&uuid, &dir, &peers, start, "listening", &[], listen_secs, None);
            }
            last_live = Instant::now();
        }
        // Fast pairing WITHOUT ending the window (2026-11-22): as soon as the first peer is
        // known, probe it inline - per-path numbers appear in seconds - but the loop keeps
        // running, so broadcasting and answering continue for the rest of the listen window
        // and a peer that starts later is still discovered. (The earlier fast mode broke out
        // of the loop, which stopped broadcasting right after the probe.)
        if first_peer_at.is_none() && !peers.is_empty() {
            first_peer_at = Some(Instant::now());
        }
        if !probed
            && first_peer_at
                .map_or(false, |t| t.elapsed() >= Duration::from_millis(EARLY_PROBE_AFTER_PEER_MS))
        {
            eprintln!("[peer-discover] peer seen: probing now, window keeps running");
            listen_used = start.elapsed().as_secs().max(1);
            write_live(&uuid, &dir, &peers, start, "probing", &[], listen_used, None);
            paths = probe_paths(&ifaces, &peers, PROBES_PER_PATH, abort, Some(&probe_sock), start, &mut stats);
            done_elapsed = Some(start.elapsed().as_secs().max(1));
            write_live(&uuid, &dir, &peers, start, "done", &paths, listen_used, done_elapsed);
            probed = true;
        }
        // The listen window is over - end the run. Results were already published inline if
        // a peer was found; grace answering below still covers probes arriving afterwards.
        if start.elapsed().as_secs() >= listen_secs {
            break;
        }
        std::thread::sleep(Duration::from_millis(20)); // no busy-spin
    }

    // --- write outputs
    // Fallback: the listen window ended without an inline probe (no peer ever seen, or the
    // run was stopped before the fast trigger fired). Probe whatever peers exist now; the
    // probe phase is abortable (user stop / stop-file) and bounded by its own hard deadline,
    // so it cannot spin.
    if !probed {
        let listen_used = start.elapsed().as_secs().max(1);
        write_live(&uuid, &dir, &peers, start, "probing", &[], listen_used, None);
        let p = probe_paths(&ifaces, &peers, PROBES_PER_PATH, abort, Some(&probe_sock), start, &mut stats);
        let done_at = start.elapsed().as_secs().max(1);
        write_live(&uuid, &dir, &peers, start, "done", &p, listen_used, Some(done_at));
        paths = p;
    }
    // Keep answering a little after the window: a peer that started later still gets its
    // probes reflected (observed 2026-11-20: the side that started 2 s earlier saw 100%
    // loss on every path without this grace window).
    stats.probe_reflected += grace_answer(&probe_sock, &ifaces, abort, PEER_GRACE_MS, start);
    write_outputs(&dir, &uuid, &peers, &ifaces, &stats, start, &paths)
}

// ---------------------------------------------------------------- path probing (design 搂7)
const PROBES_PER_PATH: u16 = 100;
const PROBE_RTT_TIMEOUT_MS: u64 = 120;
const PROBE_GAP_MS: u64 = 10;
// Hard wall-clock cap for the whole probe phase. Without it, a peer set that stopped
// answering turns into 120 ms of dead wait per probe, and one NIC fed by duplicate
// interface entries could multiply that by every (addr x iface) pair.
// 2026-11-22: 45s -> 20s (probe now runs inline as soon as a peer is seen, so it only
// needs to outlast the per-path dead-streak limit, not the whole listen window).
const PROBE_PHASE_BUDGET_MS: u64 = 20_000;
// A path with this many CONSECUTIVE unanswered probes (each costs PROBE_RTT_TIMEOUT_MS) is
// treated as unreachable and abandoned early - a dead cross-subnet combo then costs ~2 s
// instead of its whole share of the phase budget. A live (or merely lossy) link never
// accumulates a streak this long.
const DEAD_STREAK_MAX: u32 = 15;
const MAX_PROBE_PATHS: usize = 16;
// Fast pairing (2026-11-22): how long to keep broadcasting after the FIRST peer was seen,
// before starting the probe phase. The listen loop then keeps running for the rest of the
// window, so a peer that starts later is still discovered and answered (sustained
// broadcast + fast pairing in one run - no fast/standard mode split).
const EARLY_PROBE_AFTER_PEER_MS: u64 = 3_000;
/// After our own probe phase we keep ANSWERING for a while: the peer may have started
/// later than us (two humans never press Start at the same instant), so its probes arrive
/// while we are already done measuring. Without this grace window that peer sees 100%
/// loss on every path even though the link is fine (observed 2026-11-20).
/// 2026-11-22: the listen loop itself already answers while it runs (up to the 60 s
/// window); this grace covers probes that arrive after the window ended.
const PEER_GRACE_MS: u64 = 15_000;

/// Why a path ended with ZERO probes sent. The GUI renders this instead of implying a real
/// network problem ("无可用路径") when the run never actually measured anything (observed
/// 2026-11-20: pressing 停止 during the listen window cut every path to sent=0 and the panel
/// misreported "no usable path").
#[derive(Clone, Copy, PartialEq)]
enum ProbeCancel {
    None,
    Stopped,
    Deadline,
    SendError,
}

impl ProbeCancel {
    fn as_str(self) -> &'static str {
        match self {
            ProbeCancel::None => "",
            ProbeCancel::Stopped => "stopped",
            ProbeCancel::Deadline => "deadline",
            ProbeCancel::SendError => "send_error",
        }
    }
}

struct PathResult {
    iface_name: String,
    local_ip: Ipv4Addr,
    peer: SocketAddr,
    stats: core::ProbeStats,
    cancel: ProbeCancel,
}

/// Answer probe requests that arrive while WE are probing. Both sides enter the probe phase
/// at the same instant, so the main-loop reflector is no longer running and each peer would
/// otherwise be measured against a silent socket (every path reads 100% loss).
/// Checkbox enforcement (2026-11-22): same rule as the main loop - only answer probes
/// addressed to a CHECKED NIC's IP.
fn reflect_pending(
    reflector: Option<&UdpSocket>,
    ifaces: &[LocalIface],
    buf: &mut [u8],
    start: Instant,
) -> u64 {
    let sock = match reflector {
        Some(s) => s,
        None => return 0,
    };
    let mut answered = 0u64;
    loop {
        let info = match crate::egress::recv_with_dst(sock, buf) {
            Ok(Some(i)) => i,
            Ok(None) => return answered, // WouldBlock: nothing queued
            Err(_) => return answered,
        };
        let n = info.len;
        let from = info.from;
        if let Some(sa) = info.local_addr {
            if let IpAddr::V4(dst) = sa.ip() {
                let checked = ifaces.iter().any(|f| f.ip == dst);
                if !checked {
                    continue; // addressed to an unchecked NIC: refuse to reflect
                }
            }
        }
        let pf = match core::decode_probe(&buf[..n]) {
            Some(p) => p,
            None => continue,
        };
        if pf.is_response {
            continue; // a peer answer for us: the caller's own socket handles it
        }
        let t2 = ts_ns(start);
        let reply = core::encode_probe(pf.seq, true, pf.t1, t2, t2);
        let _ = sock.send_to(&reply, from);
        answered += 1;
    }
}

/// Keep answering peer probes for `budget` after our own probe phase ended, so a peer that
/// started later (the normal case: two humans pressing Start) still gets measured against a
/// live reflector instead of a closed process. Bounded by wall clock and abortable.
/// Checkbox enforcement (2026-11-22): same rule as everywhere - only answer probes addressed
/// to a CHECKED NIC's IP.
fn grace_answer(
    sock: &UdpSocket,
    ifaces: &[LocalIface],
    abort: &AtomicBool,
    budget_ms: u64,
    start: Instant,
) -> u64 {
    let deadline = Instant::now() + Duration::from_millis(budget_ms);
    let mut buf = [0u8; 256];
    let mut answered = 0u64;
    while Instant::now() < deadline && !abort.load(Ordering::Relaxed) {
        let now = Instant::now();
        let remain = deadline.saturating_duration_since(now);
        let wait = if remain > Duration::from_millis(20) { Duration::from_millis(20) } else { remain };
        let _ = sock.set_read_timeout(Some(wait));
        let info = match crate::egress::recv_with_dst(sock, &mut buf) {
            Ok(Some(i)) => i,
            Ok(None) => {
                // probe_sock is NON-blocking (set_nonblocking(true) at setup), so the
                // set_read_timeout above never blocks and WouldBlock comes back instantly:
                // without a sleep this loop busy-spins for the whole grace budget (~15 s of
                // 100% CPU after every run). Pace the drain instead.
                std::thread::sleep(Duration::from_millis(10));
                continue;
            }
            Err(_) => continue,
        };
        let n = info.len;
        let from = info.from;
        if let Some(sa) = info.local_addr {
            if let IpAddr::V4(dst) = sa.ip() {
                let checked = ifaces.iter().any(|f| f.ip == dst);
                if !checked {
                    continue; // addressed to an unchecked NIC: refuse to reflect
                }
            }
        }
        let pf = match core::decode_probe(&buf[..n]) {
            Some(p) => p,
            None => continue,
        };
        if pf.is_response {
            continue;
        }
        let t2 = ts_ns(start);
        let reply = core::encode_probe(pf.seq, true, pf.t1, t2, t2);
        let _ = sock.send_to(&reply, from);
        answered += 1;
    }
    answered
}

/// Active TWAMP-Light probes to every discovered peer address, from every local NIC that
/// shares that peer's subnet (one ephemeral socket per path, bound to the NIC's own IP).
/// Jitter follows design N2: r = T4' and s = T1, both from THIS process's monotonic clock.
fn probe_paths(
    ifaces: &[LocalIface],
    peers: &BTreeMap<[u8; 16], (Instant, Vec<SocketAddr>, u16)>,
    probes_per_path: u16,
    stop: &AtomicBool,
    reflector: Option<&UdpSocket>,
    start: Instant,
    stats: &mut RunStats,
) -> Vec<PathResult> {
    let mut out = Vec::new();
    // Bounded probe phase (see PROBE_PHASE_BUDGET_MS / MAX_PROBE_PATHS).
    let phase_deadline = Instant::now() + Duration::from_millis(PROBE_PHASE_BUDGET_MS);
    // Dedupe identical paths: enumerate() deliberately lists each NIC twice (limited +
    // directed broadcast targets), and a peer can be learned from several source ports,
    // so without this every probe would run two or more times over the same wire.
    let mut seen_paths: std::collections::HashSet<(Ipv4Addr, Ipv4Addr, u16)> = std::collections::HashSet::new();
    // Cross-subnet lesson (m0g-dual): a peer may be discovered via a limited broadcast that
    // left ITS lowest-metric NIC (e.g. its Radmin), so its source address is NOT in any of
    // our subnets. Probing is unicast, so try EVERY local NIC for every peer address; the
    // pinned-egress send makes each attempt leave via that NIC regardless of the routing
    // table, and the reply rides the same path back.
    for (_uuid, (_seen, addrs, pport)) in peers {
        for peer_addr in addrs {
            let pip = match peer_addr.ip() {
                IpAddr::V4(v4) => v4,
                IpAddr::V6(_) => continue,
            };
            for ifc in ifaces {
                if out.len() >= MAX_PROBE_PATHS || Instant::now() >= phase_deadline {
                    break;
                }
                if !seen_paths.insert((ifc.ip, pip, *pport)) {
                    continue; // duplicate NIC entry or repeated addr for the same peer port
                }
                let sock = match Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP)) {
                    Ok(s) => s,
                    Err(e) => {
                        eprintln!("[peer-discover] probe socket on {}: {e}", ifc.name);
                        continue;
                    }
                };
                // Pin the egress to the NIC being tested (design intent, see comment at
                // the top of this loop). A bound source address is NOT the egress NIC on
                // Windows (weak-host send): without the pin, a probe labeled "Radmin VPN"
                // can actually leave via WLAN while carrying a Radmin source address, so
                // the panel would claim a path the injected game (which pins egress to
                // the chosen NIC) can never reproduce (observed 2026-11-22: "Radmin ->
                // 192.168.31.176" showed 0% loss although the packet never rode the
                // tunnel). Pinning makes each row mean "if I pin my game to this NIC,
                // can I reach this peer address?" - honest per-NIC reachability.
                if sock
                    .bind(&SockAddr::from(SocketAddrV4::new(ifc.ip, 0)))
                    .is_err()
                {
                    continue;
                }
                pin_egress(&sock, ifc.index, &ifc.name);
                let udp: UdpSocket = match sock.into() {
                    u => u,
                };
                let _ = udp.set_read_timeout(Some(Duration::from_millis(PROBE_RTT_TIMEOUT_MS)));
                let dst = SocketAddrV4::new(pip, *pport);
                let mut rbuf_refl = [0u8; 256];
                let mut st = core::ProbeStats::new();
                let mut last_r = 0u64;
                let mut last_s = 0u64;
                let mut have_prev = false;
                let mut cancel = ProbeCancel::None;
                let mut send_fail = 0u64;
                let mut dead_streak = 0u32;
                for seq in 0..probes_per_path {
                    if stop.load(Ordering::Relaxed) {
                        cancel = ProbeCancel::Stopped;
                        break;
                    }
                    if Instant::now() >= phase_deadline {
                        cancel = ProbeCancel::Deadline;
                        break;
                    }
                    let samples_before = st.samples.len();
                    let t1 = ts_ns(start);
                    let pkt = core::encode_probe(seq, false, t1, 0, 0);
                    if udp.send_to(&pkt, dst).is_err() {
                        send_fail += 1;
                        continue;
                    }
                    st.sent += 1;
                    // Wait for THE response to this seq (own ephemeral socket, peer-filtered).
                    let deadline = Instant::now() + Duration::from_millis(PROBE_RTT_TIMEOUT_MS);
                    loop {
                        let now = Instant::now();
                        if now >= deadline {
                            break;
                        }
                        // ★ Both machines enter their probe phase at the same moment, so the
                        // main loop that used to reflect their probes is already gone: without
                        // reflecting here as well, each side probes a silent peer and every path
                        // measures 100% loss (observed 2026-11-20: A recv=0, B recv=0 for all
                        // paths). Keep answering while waiting for our own reply.
                        reflect_pending(reflector, ifaces, &mut rbuf_refl, start);
                        let _ = udp.set_read_timeout(Some(deadline - now));
                        let mut rbuf = [0u8; 128];
                        match udp.recv_from(&mut rbuf) {
                            Ok((n, from)) => {
                                if std::env::var("CIVLINK_PD_DEBUG").as_deref() == Ok("1") {
                                    eprintln!("[pd-probe] recv {}B from {}", n, from);
                                }
                                // Cross-subnet lesson: the reply may leave the peer via a
                                // DIFFERENT NIC than the one we probed (its lowest-metric
                                // adapter), so the source IP need not equal the probed IP.
                                // The seq + response magic in the payload is the real
                                // correlation; the port must match our probed port.
                                if from.port() != dst.port() {
                                    continue;
                                }
                                if let Some(pf) = core::decode_probe(&rbuf[..n]) {
                                    if pf.is_response && pf.seq == seq {
                                        let t4 = ts_ns(start);
                                        if let Some(rtt) =
                                            core::rtt_ns(pf.t1, pf.t2, pf.t3, t4)
                                        {
                                            st.samples.push(rtt);
                                            st.seq_seen.push(pf.seq);
                                            st.jitter_ns = core::jitter_ns(
                                                st.jitter_ns,
                                                last_r,
                                                last_s,
                                                t4,
                                                t1,
                                            );
                                            last_r = t4;
                                            last_s = t1;
                                            have_prev = true;
                                        }
                                        break;
                                    }
                                }
                            }
                            Err(_) => break, // timeout: counts as loss (gap in seq_seen)
                        }
                    }
                    let _ = have_prev;
                    // Dead-streak early stop: count CONSECUTIVE unanswered probes and abandon
                    // the path once the streak is long enough (a dead cross-subnet combo is
                    // abandoned after ~2 s; a live/lossy link never accumulates the streak).
                    if st.samples.len() as usize > samples_before {
                        dead_streak = 0;
                    } else {
                        dead_streak += 1;
                        if dead_streak >= DEAD_STREAK_MAX {
                            break;
                        }
                    }
                    std::thread::sleep(Duration::from_millis(PROBE_GAP_MS));
                }
                if st.sent == 0 && cancel == ProbeCancel::None && send_fail > 0 {
                    cancel = ProbeCancel::SendError;
                }
                stats.probe_sent += st.sent;
                stats.probe_recv += st.samples.len() as u64;
                out.push(PathResult {
                    iface_name: ifc.name.clone(),
                    local_ip: ifc.ip,
                    peer: SocketAddr::V4(dst),
                    stats: st,
                    cancel,
                });
            }
        }
    }
    out
}

/// Live peer table for the GUI: rewritten whenever the peer set or its addresses change so the
/// operator sees discovered devices on screen instead of scrolling the log. Plain JSON, one
/// object, small enough to rewrite whole each time (no partial reads).
fn write_live(
    self_uuid: &[u8; 16],
    dir: &str,
    peers: &BTreeMap<[u8; 16], (Instant, Vec<SocketAddr>, u16)>,
    start: Instant,
    phase: &str,
    paths: &[PathResult],
    listen_secs: u64,
    // 2026-11-22 (timing fix): "done" carries the elapsed value frozen at the moment the
    // results were published. The listen window keeps running after the inline probe, so a
    // live start.elapsed() would keep counting to the full window length and the GUI would
    // read "已完成 · 已用 59s" although the data appeared after a few seconds.
    frozen_elapsed: Option<u64>,
) {
    let file = format!("{dir}/peers-live.json");
    let self_hex: String = self_uuid.iter().map(|b| format!("{b:02x}")).collect();
    let elapsed = frozen_elapsed.unwrap_or_else(|| start.elapsed().as_secs());
    // Countdown to the end of the current phase (saturating). The GUI renders it as-is, so the
    // countdown and the phase transitions always agree (one clock, the agent's).
    // 2026-11-22: probing now runs INLINE inside the listen window (fast pairing), so its
    // countdown continues from the window base instead of a fresh 80s budget — otherwise the
    // "剩余 Ns" would jump UP at the listening -> probing transition.
    let remain_s: u64 = match phase {
        "listening" => listen_secs.saturating_sub(elapsed),
        "probing" => listen_secs.saturating_sub(elapsed),
        "answering" => (listen_secs + PEER_GRACE_MS / 1000).saturating_sub(elapsed),
        _ => 0,
    };
    let mut s = String::new();
    s.push_str(&format!(
        "{{\"self\":{{\"uuid\":\"{}\",\"short\":\"{}\"}},\"phase\":\"{}\",\"elapsed_s\":{},\"remain_s\":{},\"peers\":[",
        self_hex,
        &self_hex[..8.min(self_hex.len())],
        phase,
        elapsed,
        remain_s
    ));
    let mut first = true;
    for (id, (seen, addrs, probe_port)) in peers {
        if !first {
            s.push_str(",");
        }
        first = false;
        let hex: String = id.iter().map(|b| format!("{b:02x}")).collect();
        let addr_str = addrs
            .iter()
            .map(|a| format!("\"{}\"", a))
            .collect::<Vec<_>>()
            .join(",");
        s.push_str(&format!(
            "{{\"uuid\":\"{}\",\"short\":\"{}\",\"addrs\":[{}],\"probe_port\":{},\"last_seen_s\":{}}}",
            hex,
            &hex[..8.min(hex.len())],
            addr_str,
            probe_port,
            Instant::now().saturating_duration_since(*seen).as_secs()
        ));
    }
    s.push_str("],\"paths\":[");
    let mut pfirst = true;
    for p in paths {
        if !pfirst {
            s.push_str(",");
        }
        pfirst = false;
        let p50 = p.stats.p50_ns();
        let p95 = p.stats.p95_ns();
        let loss = p.stats.loss_x100(p.stats.sent);
        let ok = core::is_recommendable(&p.stats);
        let sent = p.stats.sent;
        let recv = p.stats.samples.len() as u64;
        let penalty = sent > 0 && (recv * 100 / sent) < 75;
        let sc = core::score(p50, p95, p.stats.jitter_ns, loss, penalty);
        let reason = if sent == 0 && p.cancel != ProbeCancel::None {
            format!(",\"reason\":\"{}\"", p.cancel.as_str())
        } else {
            String::new()
        };
        s.push_str(&format!(
            "{{\"iface\":\"{}\",\"local_ip\":\"{}\",\"peer\":\"{}\",\"sent\":{},\"recv\":{},\"p50_ms\":{:.2},\"p95_ms\":{:.2},\"jitter_ms\":{:.2},\"loss_pct\":{:.2},\"score\":{:.4},\"ok\":{}{}}}",
            p.iface_name,
            p.local_ip,
            p.peer,
            sent,
            recv,
            p50 as f64 / core::NS_PER_MS,
            p95 as f64 / core::NS_PER_MS,
            p.stats.jitter_ns / core::NS_PER_MS,
            loss as f64 / 100.0,
            sc,
            ok,
            reason
        ));
    }
    s.push_str("]}");
    if let Err(e) = fs::write(&file, s) {
        eprintln!("[peer-discover] cannot write {file}: {e}");
    }
}

fn write_outputs(
    dir: &str,
    uuid: &[u8; 16],
    peers: &BTreeMap<[u8; 16], (Instant, Vec<SocketAddr>, u16)>,
    ifaces: &[LocalIface],
    stats: &RunStats,
    start: Instant,
    paths: &[PathResult],
) -> Result<(), String> {
    let jsonl = format!("{dir}/peers.jsonl");
    let mut w = BufWriter::new(
        File::create(&jsonl).map_err(|e| format!("cannot create {jsonl}: {e}"))?,
    );
    for (id, (seen, addrs, probe_port)) in peers {
        let hex: String = id.iter().map(|b| format!("{b:02x}")).collect();
        let secs = Instant::now().saturating_duration_since(*seen).as_secs();
        let addr_str = addrs
            .iter()
            .map(|a| format!("\"{}\"", a))
            .collect::<Vec<_>>()
            .join(",");
        writeln!(
            w,
            "{{\"uuid\":\"{}\",\"last_seen_s\":{},\"addrs\":[{}],\"probe_port\":{}}}",
            hex, secs, addr_str, probe_port
        )
        .map_err(|e| format!("write {jsonl}: {e}"))?;
    }
    w.flush().map_err(|e| format!("flush {jsonl}: {e}"))?;

    let summary = format!("{dir}/summary.txt");
    let mut s = BufWriter::new(
        File::create(&summary).map_err(|e| format!("cannot create {summary}: {e}"))?,
    );
    writeln!(s, "M0-G peer-discover summary").ok();
    writeln!(s, "uuid      : {}", uuid.iter().map(|b| format!("{b:02x}")).collect::<String>()).ok();
    writeln!(s, "elapsed_s : {}", start.elapsed().as_secs()).ok();
    // enumerate() lists each NIC twice (limited broadcast + directed broadcast target). That is
    // what the sender needs, but the operator should see one line per physical NIC.
    let mut nic_seen: Vec<std::net::Ipv4Addr> = Vec::new();
    let mut nic_desc: Vec<String> = Vec::new();
    for i in ifaces {
        if nic_seen.contains(&i.ip) { continue; }
        nic_seen.push(i.ip);
        nic_desc.push(format!("{}({} vpn={})", i.name, i.ip, i.vpn));
    }
    writeln!(s, "ifaces    : {} ({} broadcast target(s))", nic_desc.join(", "), ifaces.len()).ok();
    writeln!(s, "discovery sent/recv : {}/{}", stats.discovery_sent, stats.discovery_recv).ok();
    writeln!(s, "cross-subnet recv   : {} (peers whose src IP is outside every local subnet)", stats.cross_subnet_recv).ok();
    writeln!(s, "responses sent      : {}", stats.responses_sent).ok();
    writeln!(s, "peers discovered    : {}", peers.len()).ok();
    writeln!(s, "probes reflected    : {}", stats.probe_reflected).ok();
    writeln!(s, "").ok();

    // --- path quality section (design 搂7): per-path stats + recommendation
    writeln!(s, "== path quality (active probes) ==").ok();
    struct Rank {
        label: String,
        score: f64,
        ok: bool,
        p50: u64,
        p95: u64,
        j_ms: f64,
        loss_x100: u64,
    }
    let mut ranked: Vec<Rank> = Vec::new();
    for p in paths {
        let p50 = p.stats.p50_ns();
        let p95 = p.stats.p95_ns();
        let loss = p.stats.loss_x100(p.stats.sent);
        let ok = core::is_recommendable(&p.stats);
        // stability penalty: >25% of the window empty (crude first cut, design 搂7 label)
        let sent = p.stats.sent;
        let recv = p.stats.samples.len() as u64;
        let penalty = sent > 0 && (recv * 100 / sent) < 75;
        let sc = core::score(p50, p95, p.stats.jitter_ns, loss, penalty);
        let label = format!("{}({}) -> {}", p.iface_name, p.local_ip, p.peer);
        let rs = if sent == 0 && p.cancel != ProbeCancel::None {
            format!(" reason={}", p.cancel.as_str())
        } else {
            String::new()
        };
        writeln!(
            s,
            "path {} : sent={} recv={} p50={:.1}ms p95={:.1}ms J={:.2}ms loss={:.2}% score={:.4} recommendable={}{}",
            label,
            sent,
            recv,
            p50 as f64 / core::NS_PER_MS,
            p95 as f64 / core::NS_PER_MS,
            p.stats.jitter_ns / core::NS_PER_MS,
            loss as f64 / 100.0,
            sc,
            ok,
            rs
        )
        .ok();
        ranked.push(Rank { label, score: sc, ok, p50, p95, j_ms: p.stats.jitter_ns / core::NS_PER_MS, loss_x100: loss });
    }
    ranked.retain(|r| r.ok);
    ranked.sort_by(|a, b| a.score.partial_cmp(&b.score).unwrap_or(std::cmp::Ordering::Equal));
    if let Some(best) = ranked.first() {
        writeln!(s, "RECOMMENDED: {} (score {:.4})", best.label, best.score).ok();
        println!(
            "PEERDISCOVER: discovered={} paths={} recommended={}",
            peers.len(),
            paths.len(),
            best.label
        );
    } else {
        // Distinguish "measured and failed the gate" from "never measured at all" (the panel
        // must not imply a network problem when the run was stopped before probing).
        let all_cancelled = !paths.is_empty()
            && paths
                .iter()
                .all(|p| p.stats.sent == 0 && p.cancel != ProbeCancel::None);
        if all_cancelled {
            writeln!(s, "RECOMMENDED: none (no probe was actually sent - stopped/deadline/send error; see per-path reason)").ok();
        } else {
            writeln!(s, "RECOMMENDED: none (no path passed the hard gate)").ok();
        }
        println!(
            "PEERDISCOVER: discovered={} paths={} recommended=none",
            peers.len(),
            paths.len()
        );
    }
    writeln!(s, "").ok();
    writeln!(s, "WARNING (R4): no authentication - any same-tool member of the broadcast domain can discover you and see your NIC IPs; trusted networks only").ok();
    writeln!(s, "WARNING (M5): with VPN NICs included, every member of the same VPN room can see your broadcast (Radmin is a layer-2 broadcast domain, verified)").ok();
    s.flush().ok();

    Ok(())
}
