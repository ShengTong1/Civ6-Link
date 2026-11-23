//! M0-G Peer Discover — pure logic core (ALWAYS compiled, ZERO dependency).
//!
//! Everything in this module is deterministic, allocation-light and has no socket/IO side
//! effects, so it is unit-tested by `cargo test` and by the hidden `--peer-discover-selftest`
//! mode even in the DEFAULT (zero-dependency) build. The feature-gated network I/O lives in
//! `peer_discover_net.rs` and only consumes these primitives.
//!
//! Protocol (v1.2):
//!   Discovery/Response 24 B : "CLPD"/"CLPR" + version + uuid[16] + probe_port(u16 BE) + flags
//!   Probe 64 B              : "CLPP" + version + seq(u16 BE) + flags + T1,T2,T3(u64 BE) + reserved
//! Timestamps are u64 nanoseconds on a monotonic clock; only the OWNER's T1/T4' are compared.

// ---------------------------------------------------------------- constants
pub const DISC_MAGIC: &[u8; 4] = b"CLPD";
pub const RESP_MAGIC: &[u8; 4] = b"CLPR";
pub const PROBE_MAGIC: &[u8; 4] = b"CLPP";
pub const PD_VERSION: u8 = 1;
pub const DISC_LEN: usize = 24;
pub const PROBE_LEN: usize = 64;
pub const PROBE_FLAG_RESPONSE: u8 = 0x01;
pub const DISC_FLAG_INCLUDE_VPN: u8 = 0x01;

// Thresholds (ns) — design §7; all comparisons in ns, display divides by 1_000_000.0.
pub const NS_PER_MS: f64 = 1_000_000.0;
pub const P50_BASE_NS: u64 = 100_000_000; // 100 ms
pub const P95_BASE_NS: u64 = 150_000_000; // 150 ms
pub const JITTER_BASE_NS: f64 = 10_000_000.0; // 10 ms

/// Percent, stored as hundredths (300 = 3.00%). Keeps integers, no float drift in gates.
pub const LOSS_HARD_X100: u64 = 300;
pub const MIN_SAMPLES: usize = 80;
pub const SAME_LINK_CORR: f64 = 0.8;

// ---------------------------------------------------------------- broadcast address
/// Directed subnet broadcast = ip | (!netmask), computed BYTE BY BYTE.
/// PowerShell's whole-integer bitwise attempt produced garbage (byte order + precedence bug),
/// which is exactly why this is an isolated, unit-tested primitive (design M1/B1).
pub fn directed_broadcast(ip: [u8; 4], mask: [u8; 4]) -> [u8; 4] {
    let mut out = [0u8; 4];
    for i in 0..4 {
        out[i] = ip[i] | (255 & !mask[i]);
    }
    out
}

/// True when `ip` is inside the subnet (ip & mask) that the socket bound to `bind_ip`/`mask`.
pub fn in_subnet(ip: [u8; 4], bind_ip: [u8; 4], mask: [u8; 4]) -> bool {
    for i in 0..4 {
        if (ip[i] & mask[i]) != (bind_ip[i] & mask[i]) {
            return false;
        }
    }
    true
}

// ---------------------------------------------------------------- VPN classification
/// Conservative VPN / non-physical classifier (design M4).
///   VPN  -> name/adapter keyword OR ip in 26.0.0.0/8 (Radmin) -> excluded unless include_vpn
///   SKIP -> loopback, APIPA (169.254/16), unspecified
///   PHYS -> private RFC1918 with no VPN keyword -> eligible by default
/// Discriminant: a NIC whose NAME has no keyword but whose IP is 26.x MUST classify VPN.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IfClass {
    Physical,
    Vpn,
    Skip,
}

pub fn classify_iface(name: &str, adapter_name: &str, ip: [u8; 4]) -> IfClass {
    if ip == [0, 0, 0, 0] || ip[0] == 127 || (ip[0] == 169 && ip[1] == 254) {
        return IfClass::Skip;
    }
    let hay = format!("{} {}", name, adapter_name).to_ascii_lowercase();
    const KW: &[&str] = &[
        "radmin", "zerotier", "tailscale", "wireguard", "tap-windows", "vethernet",
        "ngrok", "virtualbox", "vmware", "hamachi", "openvpn", "tunnel",
    ];
    if KW.iter().any(|k| hay.contains(k)) || ip[0] == 26 {
        return IfClass::Vpn;
    }
    // RFC1918 physical; anything else is "uncertain" -> conservative exclude (漏发 not 泄露).
    let private = ip[0] == 10
        || (ip[0] == 172 && (16..=31).contains(&ip[1]))
        || (ip[0] == 192 && ip[1] == 168);
    if private {
        IfClass::Physical
    } else {
        IfClass::Vpn // uncertain == not enabled by default
    }
}

// ---------------------------------------------------------------- discovery codec
pub fn encode_discovery(uuid: &[u8; 16], probe_port: u16, flags: u8) -> [u8; DISC_LEN] {
    encode_discovery_with_magic(uuid, probe_port, flags, DISC_MAGIC)
}

/// Response variant: same 24 B layout, RESP_MAGIC so the requester can tell an ack apart
/// from a fresh discovery (m0g-dual lesson: responses written as CLPD were rejected by the
/// requester's CLPR check, and the peer's real-NIC address was never learned).
pub fn encode_discovery_resp(
    uuid: &[u8; 16],
    probe_port: u16,
    flags: u8,
) -> [u8; DISC_LEN] {
    encode_discovery_with_magic(uuid, probe_port, flags, RESP_MAGIC)
}

fn encode_discovery_with_magic(
    uuid: &[u8; 16],
    probe_port: u16,
    flags: u8,
    magic: &[u8; 4],
) -> [u8; DISC_LEN] {
    let mut b = [0u8; DISC_LEN];
    b[0..4].copy_from_slice(magic);
    b[4] = PD_VERSION;
    b[5..21].copy_from_slice(uuid);
    b[21..23].copy_from_slice(&probe_port.to_be_bytes());
    b[23] = flags;
    b
}

pub fn decode_discovery(b: &[u8], expected_magic: &[u8; 4]) -> Option<([u8; 16], u16, u8)> {
    if b.len() != DISC_LEN || &b[0..4] != expected_magic || b[4] != PD_VERSION {
        return None;
    }
    let mut uuid = [0u8; 16];
    uuid.copy_from_slice(&b[5..21]);
    let port = u16::from_be_bytes([b[21], b[22]]);
    Some((uuid, port, b[23]))
}

// ---------------------------------------------------------------- probe codec (TWAMP Light)
pub fn encode_probe(
    seq: u16,
    is_response: bool,
    t1: u64,
    t2: u64,
    t3: u64,
) -> [u8; PROBE_LEN] {
    let mut b = [0u8; PROBE_LEN];
    b[0..4].copy_from_slice(PROBE_MAGIC);
    b[4] = PD_VERSION;
    b[5..7].copy_from_slice(&seq.to_be_bytes());
    b[7] = if is_response { PROBE_FLAG_RESPONSE } else { 0 };
    b[8..16].copy_from_slice(&t1.to_be_bytes());
    b[16..24].copy_from_slice(&t2.to_be_bytes());
    b[24..32].copy_from_slice(&t3.to_be_bytes());
    // offset 32..64 reserved zero — T4' is NEVER on the wire (design M2).
    b
}

#[derive(Debug, Clone, Copy)]
pub struct ProbeFields {
    pub seq: u16,
    pub is_response: bool,
    pub t1: u64,
    pub t2: u64,
    pub t3: u64,
}

pub fn decode_probe(b: &[u8]) -> Option<ProbeFields> {
    if b.len() != PROBE_LEN || &b[0..4] != PROBE_MAGIC || b[4] != PD_VERSION {
        return None;
    }
    Some(ProbeFields {
        seq: u16::from_be_bytes([b[5], b[6]]),
        is_response: b[7] & PROBE_FLAG_RESPONSE != 0,
        t1: u64::from_be_bytes(b[8..16].try_into().unwrap()),
        t2: u64::from_be_bytes(b[16..24].try_into().unwrap()),
        t3: u64::from_be_bytes(b[24..32].try_into().unwrap()),
    })
}

// ---------------------------------------------------------------- RTT / jitter (ns, i128-safe)
/// TWAMP Light RTT (design M2): rtt = (T4' - T1) - (T3 - T2), all owner/reflector clock
/// domains separated. i128 intermediates prevent u64 underflow. Returns None on nonsensical
/// (negative RTT) input rather than wrapping.
pub fn rtt_ns(t1: u64, t2: u64, t3: u64, t4_prime: u64) -> Option<u64> {
    let total = t4_prime as i128 - t1 as i128;
    let reflect = t3 as i128 - t2 as i128; // reflector dwell, same clock domain
    let rtt = total - reflect;
    if rtt < 0 {
        None
    } else {
        Some(rtt as u64)
    }
}

/// RFC 3550 A.8 interarrival jitter, computed in NS end-to-end (design N2).
/// s = T1 (owner send), r = T4' (owner receive): SAME owner monotonic clock domain.
/// J is in ns; callers divide by NS_PER_MS only for display/scoring.
pub fn jitter_ns(prev_j: f64, r_prev: u64, s_prev: u64, r_cur: u64, s_cur: u64) -> f64 {
    let d = (r_cur as i128 - s_cur as i128) - (r_prev as i128 - s_prev as i128);
    let d = d.abs() as f64;
    prev_j + (d - prev_j) / 16.0
}

// ---------------------------------------------------------------- stats + scoring
pub struct ProbeStats {
    pub samples: Vec<u64>, // rtt ns, in arrival order
    pub sent: u64,
    pub seq_seen: Vec<u16>,
    pub jitter_ns: f64,
}

impl ProbeStats {
    pub fn new() -> Self {
        Self {
            samples: Vec::new(),
            sent: 0,
            seq_seen: Vec::new(),
            jitter_ns: 0.0,
        }
    }

    /// Loss by sequence gaps against the ACTUALLY-SENT count, hundredths of a percent.
    /// Denominator is `sent`, not the planned window: probes that were never sent (run
    /// stopped/deadline-hit mid-probe) must not count as lost (fix 2026-11-22; previously
    /// a healthy link cut short at 40/100 showed ~60% fake loss). Out-of-order is
    /// tolerated by counting DISTINCT seen seqs, so a reorder cannot be mistaken for a
    /// loss (design B3 乱序缓存 semantics, simplified to a set here).
    pub fn loss_x100(&self, sent: u64) -> u64 {
        if sent == 0 {
            return 0;
        }
        let mut seen = self.seq_seen.clone();
        seen.sort_unstable();
        seen.dedup();
        let lost = sent.saturating_sub(seen.len() as u64);
        ((lost as f64 / sent as f64) * 10_000.0).round() as u64
    }

    pub fn p50_ns(&self) -> u64 {
        percentile_ns(&self.samples, 50)
    }
    pub fn p95_ns(&self) -> u64 {
        percentile_ns(&self.samples, 95)
    }
}

/// Nearest-rank percentile on a copy; empty -> 0.
pub fn percentile_ns(samples: &[u64], pct: usize) -> u64 {
    if samples.is_empty() {
        return 0;
    }
    let mut v = samples.to_vec();
    v.sort_unstable();
    let rank = ((pct as f64 / 100.0) * v.len() as f64).ceil() as usize;
    let rank = if rank == 0 { 1 } else { rank };
    v[rank - 1]
}

/// Score (design §7, project-defined/inference): lower is better.
/// All inputs in ns; convert to the normalised ratios exactly once.
pub fn score(p50_ns: u64, p95_ns: u64, jitter_ns_f: f64, loss_x100: u64, stability_penalty: bool) -> f64 {
    let p50_norm = p50_ns as f64 / P50_BASE_NS as f64;
    let p95_norm = p95_ns as f64 / P95_BASE_NS as f64;
    let j_norm = jitter_ns_f / JITTER_BASE_NS;
    let l_norm = loss_x100 as f64 / 100.0; // 100 = 1.00%
    let pen = if stability_penalty { 1.0 } else { 0.0 };
    0.45 * p50_norm + 0.20 * p95_norm + 0.20 * j_norm + 0.10 * l_norm + 0.05 * pen
}

/// Hard gate (design §7): link is "not recommended" if loss>3%, p95>150ms, or samples<80.
/// Loss is judged against actually-sent probes (see loss_x100).
pub fn is_recommendable(stats: &ProbeStats) -> bool {
    stats.samples.len() >= MIN_SAMPLES
        && stats.p95_ns() <= P95_BASE_NS
        && stats.loss_x100(stats.sent) <= LOSS_HARD_X100
}

// ---------------------------------------------------------------- in-process selftest
/// Machine-readable selftest for the pure core. Available in the DEFAULT build.
/// Returns (checks, failures); each line is `check <name> PASS|FAIL`.
pub fn run_core_selftest() -> (usize, usize) {
    let mut checks = 0usize;
    let mut fails = 0usize;
    macro_rules! ck {
        ($name:expr, $cond:expr) => {{
            checks += 1;
            let ok = $cond;
            if !ok {
                fails += 1;
            }
            println!("check {} {}", $name, if ok { "PASS" } else { "FAIL" });
        }};
    }

    // (1) directed broadcast — three frozen vectors (design §10①②)
    ck!("broadcast-wifi", directed_broadcast([192, 168, 31, 60], [255, 255, 255, 0]) == [192, 168, 31, 255]);
    ck!("broadcast-radmin", directed_broadcast([26, 74, 126, 98], [255, 0, 0, 0]) == [26, 255, 255, 255]);
    ck!("broadcast-172", directed_broadcast([172, 16, 5, 7], [255, 240, 0, 0]) == [172, 31, 255, 255]);

    // (2) discovery codec round-trip
    let uuid = [0x42u8; 16];
    let d = encode_discovery(&uuid, 63011, DISC_FLAG_INCLUDE_VPN);
    let dec = decode_discovery(&d, DISC_MAGIC);
    ck!("disc-len", d.len() == DISC_LEN);
    ck!("disc-roundtrip", dec == Some((uuid, 63011, DISC_FLAG_INCLUDE_VPN)));
    let r = encode_discovery_resp(&[7u8;16], 1234, 0);
    ck!("resp-magic", &r[0..4] == RESP_MAGIC);
    ck!("resp-decode", decode_discovery(&r, RESP_MAGIC).is_some());
    ck!("resp-not-disc", decode_discovery(&r, DISC_MAGIC).is_none());
    ck!("disc-reject-bad-magic", decode_discovery(&d, RESP_MAGIC).is_none());
    ck!("disc-reject-short", decode_discovery(&d[..20], DISC_MAGIC).is_none());

    // (3) probe codec + wire invariant: T4' must never appear on the wire
    let p = encode_probe(7, true, 1_000, 1_100, 1_150);
    let pf = decode_probe(&p).expect("probe decode");
    ck!("probe-roundtrip", pf.seq == 7 && pf.is_response && pf.t1 == 1_000 && pf.t2 == 1_100 && pf.t3 == 1_150);
    ck!("probe-reserved-zero", p[32..64].iter().all(|&x| x == 0));

    // (4) N1 — RTT hard-coded 130 ms (design v1.2 §10④)
    //     (1.18e9 - 1.0e9) - (1.15e9 - 1.1e9) = 180e6 - 50e6 = 130_000_000 ns
    let t1: u64 = 1_000_000_000;
    let t2: u64 = 1_100_000_000;
    let t3: u64 = 1_150_000_000;
    let t4p: u64 = 1_180_000_000;
    ck!("rtt-130ms", rtt_ns(t1, t2, t3, t4p) == Some(130_000_000));
    ck!("rtt-negative-rejected", rtt_ns(1_000, 1_100, 1_900, 1_050).is_none());

    // (5) M3 — ns->ms threshold换算 (100 ns must NOT read as 100 ms)
    ck!("ns-to-ms", (100_000_000u64 as f64 / NS_PER_MS) == 100.0);
    ck!("threshold-not-ns", P50_BASE_NS == 100_000_000);

    // (6) N2 — jitter all-ns. First sample D = 0 -> J stays 0; second demonstrates update.
    let j0 = jitter_ns(0.0, t1, t1, t4p, t1); // r-s = 180e6, prev 0 -> D=180e6, J=11.25e6
    ck!("jitter-first", (j0 - 11_250_000.0).abs() < 1.0);

    // (7) loss by sequence gaps + duplicate dedup; denominator is ACTUAL sent (fix 2026-11-22):
    // 5 sent, distinct seen {0,1,3,4} = 4 -> 20%; a stopped run (sent 3, all seen) is 0%.
    let mut st = ProbeStats::new();
    st.sent = 5;
    st.seq_seen = vec![0, 1, 1, 3, 4]; // distinct {0,1,3,4}=4 of 5 -> 20% loss
    ck!("loss-20pct", st.loss_x100(st.sent) == 2000);
    let mut st2 = ProbeStats::new();
    st2.sent = 5;
    st2.seq_seen = vec![0, 1, 2, 3, 4];
    ck!("loss-zero", st2.loss_x100(st2.sent) == 0);
    let mut st3 = ProbeStats::new(); // stopped mid-window: 3 sent, all answered -> 0% loss
    st3.sent = 3;
    st3.seq_seen = vec![0, 1, 2];
    ck!("loss-stopped-not-fake", st3.loss_x100(st3.sent) == 0);

    // (8) percentile + score + hard gate
    let vals = vec![10u64, 20, 30, 40, 50, 60, 70, 80, 90, 100];
    ck!("p50", percentile_ns(&vals, 50) == 50);
    ck!("p95", percentile_ns(&vals, 95) == 100);
    // 0.45*0.5 + 0.20*0.6 + 0.20*0.5 + 0.10*1.0 + 0.05*0 = 0.545
    let sc = score(50_000_000, 90_000_000, 5_000_000.0, 100, false);
    ck!("score-finite", sc.is_finite() && sc > 0.0);
    ck!("score-pinned", (sc - 0.545).abs() < 1e-9);
    ck!("score-stability-penalty", (score(50_000_000, 90_000_000, 5_000_000.0, 100, true) - (sc + 0.05)).abs() < 1e-9);
    let mut good = ProbeStats::new();
    good.samples = vec![20_000_000; MIN_SAMPLES];
    good.seq_seen = (0..MIN_SAMPLES as u16).collect();
    good.sent = MIN_SAMPLES as u64;
    ck!("gate-good", is_recommendable(&good));
    let mut bad = ProbeStats::new();
    bad.samples = vec![200_000_000; MIN_SAMPLES]; // p95 200ms > 150ms
    bad.seq_seen = (0..MIN_SAMPLES as u16).collect();
    bad.sent = MIN_SAMPLES as u64;
    ck!("gate-bad-p95", !is_recommendable(&bad));
    // Two hard gates that previously had no failing case (audit 2026-11-22):
    let mut few = ProbeStats::new(); // 79 samples < MIN_SAMPLES(80)
    few.samples = vec![20_000_000; MIN_SAMPLES - 1];
    few.seq_seen = (0..(MIN_SAMPLES - 1) as u16).collect();
    few.sent = (MIN_SAMPLES - 1) as u64;
    ck!("gate-bad-samples", !is_recommendable(&few));
    let mut lossy = ProbeStats::new(); // 80 samples but 4/80 = 5% loss > 3%
    lossy.samples = vec![20_000_000; MIN_SAMPLES];
    lossy.seq_seen = (0..(MIN_SAMPLES - 4) as u16).collect();
    lossy.sent = MIN_SAMPLES as u64;
    ck!("gate-bad-loss", !is_recommendable(&lossy));

    // (9) VPN classification incl. M4 discriminant (no keyword but 26./8)
    ck!("vpn-radmin-name", classify_iface("Radmin VPN", "", [192, 168, 1, 2]) == IfClass::Vpn);
    ck!("vpn-by-ip-26", classify_iface("Ethernet 3", "{guid}", [26, 74, 1, 1]) == IfClass::Vpn);
    ck!("physical-wifi", classify_iface("WLAN", "{guid}", [192, 168, 31, 60]) == IfClass::Physical);
    ck!("skip-apipa", classify_iface("eth", "", [169, 254, 1, 2]) == IfClass::Skip);
    ck!("uncertain-excluded", classify_iface("weird", "", [8, 8, 8, 8]) == IfClass::Vpn);

    // (10) subnet filter
    ck!("subnet-in", in_subnet([192, 168, 31, 9], [192, 168, 31, 60], [255, 255, 255, 0]));
    ck!("subnet-out", !in_subnet([26, 1, 1, 1], [192, 168, 31, 60], [255, 255, 255, 0]));

    (checks, fails)
}
