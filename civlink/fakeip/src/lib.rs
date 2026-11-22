//! civlink-fakeip: F2 data-structure prototype — in-memory FakeEndpoint <-> PeerEndpoint
//! mapping table.
//!
//! Scope (codex F2 review D2/D5, design v0.2 §3.4):
//! - Pure in-memory data structure prototype. It must NOT claim to implement a usable
//!   DLL lifecycle link (no injection, no real sockets, no NIC configuration).
//! - Candidate pool 127.0.127.1..=127.0.127.100 is used in memory only; never bound,
//!   sent to, or configured on a NIC (D5). 198.18.0.0/15 is reserved as the H1
//!   comparison pool and is NOT part of the allocatable set here.
//! - FakeEndpoint keys carry (session_id, logical_socket_id, socket_generation) so a
//!   reused Windows SOCKET handle or a restarted game session cannot hit a stale
//!   mapping (v2.1 §4.3, F2 §2.3).
//! - Discovery-phase entries idle for DISCOVERY_TTL_TICKS are reaped; IN_ROOM/IN_GAME
//!   entries are retained (v2.1 §5 lifecycle rule).
//! - Conflicts are explicit errors, never silent overwrites.

use std::collections::{HashMap, VecDeque};
use std::net::{Ipv4Addr, SocketAddr};
use std::sync::Mutex;

/// First fake IP of the allocatable pool: 127.0.127.1
pub const FAKE_POOL_FIRST: u8 = 1;
/// Last fake IP of the allocatable pool: 127.0.127.100
pub const FAKE_POOL_LAST: u8 = 100;
/// Fake port assigned to every allocated FakeEndpoint (data plane port the local
/// game expects as the peer's port).
pub const FAKE_PORT: u16 = 62056;
/// TTL for discovery-phase entries (ticks of the caller-provided clock; 600 ticks
/// represents 10 minutes at 1 tick/second).
pub const DISCOVERY_TTL_TICKS: u64 = 600;

/// A fake endpoint as presented to the local game (D5: 127.0.127.x in memory only).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct FakeEndpoint {
    pub fake_ip: Ipv4Addr,
    pub fake_port: u16,
}

impl FakeEndpoint {
    pub fn new(fake_ip: Ipv4Addr, fake_port: u16) -> Self {
        Self { fake_ip, fake_port }
    }
}

impl std::fmt::Display for FakeEndpoint {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}:{}", self.fake_ip, self.fake_port)
    }
}

/// The real remote peer behind a FakeEndpoint.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct PeerEndpoint {
    pub peer_id: u32,
    pub tunnel_session_id: u64,
    pub addr: SocketAddr,
}

impl PeerEndpoint {
    pub fn new(peer_id: u32, tunnel_session_id: u64, addr: SocketAddr) -> Self {
        Self {
            peer_id,
            tunnel_session_id,
            addr,
        }
    }
}

/// Unique key for a forward mapping (v2.1 §4.3 + F2 §2.3).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct MappingKey {
    pub session_id: u64,
    pub logical_socket_id: u32,
    pub socket_generation: u32,
    pub fake: FakeEndpoint,
}

impl MappingKey {
    pub fn new(
        session_id: u64,
        logical_socket_id: u32,
        socket_generation: u32,
        fake: FakeEndpoint,
    ) -> Self {
        Self {
            session_id,
            logical_socket_id,
            socket_generation,
            fake,
        }
    }
}

/// Lifecycle state of a mapping (v2.1 §5): discovery-phase entries are reaped after
/// DISCOVERY_TTL_TICKS of idle; IN_ROOM / IN_GAME entries are retained.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MappingState {
    Discovery,
    InRoom,
    InGame,
}

/// Explicit allocation/lookup errors — conflicts are never silently overwritten.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TableError {
    /// The whole allocatable pool is in use.
    PoolExhausted,
    /// The exact key already exists.
    KeyExists(MappingKey),
    /// The chosen fake endpoint is already held by a different key.
    FakeInUse(FakeEndpoint),
    /// The reverse key (peer_id, tunnel_session_id, peer source port) already maps
    /// to a different fake endpoint.
    ReverseConflict(PeerEndpoint),
    /// The requested fake endpoint is outside the allocatable pool.
    NotInPool(FakeEndpoint),
}

/// Per-operation counters (design §3.4 "每操作计数").
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct OpCounters {
    pub allocations: u64,
    pub allocation_failures: u64,
    pub forward_lookups: u64,
    pub reverse_lookups: u64,
    pub touches: u64,
    pub releases: u64,
    pub session_ends: u64,
    pub reaped: u64,
    pub state_changes: u64,
}

struct Entry {
    peer: PeerEndpoint,
    state: MappingState,
    last_seen: u64,
}

struct Inner {
    /// forward: MappingKey -> Entry
    forward: HashMap<MappingKey, Entry>,
    /// reverse: (peer_id, tunnel_session_id, peer_source_port_be) -> MappingKey
    reverse: HashMap<(u32, u64, u16), MappingKey>,
    /// free fake endpoints (pool). Allocation pops the front; release pushes back.
    pool: VecDeque<FakeEndpoint>,
    counters: OpCounters,
}

/// The mapping table. Thread-safe via Mutex; `now` is supplied by the caller so
/// tests can drive the TTL deterministically.
pub struct FakeIpTable {
    inner: Mutex<Inner>,
}

impl FakeIpTable {
    /// Build a table with the full candidate pool 127.0.127.1..=127.0.127.100.
    pub fn new() -> Self {
        let mut pool = VecDeque::with_capacity(100);
        for n in FAKE_POOL_FIRST..=FAKE_POOL_LAST {
            pool.push_back(FakeEndpoint::new(Ipv4Addr::new(127, 0, 127, n), FAKE_PORT));
        }
        Self {
            inner: Mutex::new(Inner {
                forward: HashMap::new(),
                reverse: HashMap::new(),
                pool,
                counters: OpCounters::default(),
            }),
        }
    }

    /// True if the endpoint lies inside the allocatable range 127.0.127.1..=100:62056.
    /// This is the D5 memory-only pool; 198.18.0.0/15 is not part of it.
    fn in_allocatable_range(fake: &FakeEndpoint) -> bool {
        let o = fake.fake_ip.octets();
        o[0] == 127
            && o[1] == 0
            && o[2] == 127
            && (FAKE_POOL_FIRST..=FAKE_POOL_LAST).contains(&o[3])
            && fake.fake_port == FAKE_PORT
    }

    /// Allocate the next free pool endpoint for the given key and peer.
    /// Errors: PoolExhausted, KeyExists (same key), ReverseConflict (same reverse key
    /// already mapped to a different fake endpoint).
    pub fn allocate(
        &self,
        session_id: u64,
        logical_socket_id: u32,
        socket_generation: u32,
        peer: PeerEndpoint,
        state: MappingState,
        now: u64,
    ) -> Result<FakeEndpoint, TableError> {
        let mut inner = self.inner.lock().unwrap();

        let fake = match inner.pool.pop_front() {
            Some(f) => f,
            None => {
                inner.counters.allocation_failures += 1;
                return Err(TableError::PoolExhausted);
            }
        };

        match self.allocate_inner(
            &mut inner,
            fake,
            session_id,
            logical_socket_id,
            socket_generation,
            peer,
            state,
            now,
        ) {
            Ok(f) => Ok(f),
            Err(e) => {
                // return the endpoint to the pool on failure
                inner.pool.push_front(fake);
                Err(e)
            }
        }
    }

    /// Allocate a specific fake endpoint (used to exercise conflict paths in tests).
    /// The endpoint must lie inside the allocatable range, else NotInPool.
    pub fn allocate_fixed(
        &self,
        fake: FakeEndpoint,
        session_id: u64,
        logical_socket_id: u32,
        socket_generation: u32,
        peer: PeerEndpoint,
        state: MappingState,
        now: u64,
    ) -> Result<FakeEndpoint, TableError> {
        if !Self::in_allocatable_range(&fake) {
            self.inner.lock().unwrap().counters.allocation_failures += 1;
            return Err(TableError::NotInPool(fake));
        }
        let mut inner = self.inner.lock().unwrap();
        self.allocate_inner(
            &mut inner,
            fake,
            session_id,
            logical_socket_id,
            socket_generation,
            peer,
            state,
            now,
        )
    }

    fn allocate_inner(
        &self,
        inner: &mut Inner,
        fake: FakeEndpoint,
        session_id: u64,
        logical_socket_id: u32,
        socket_generation: u32,
        peer: PeerEndpoint,
        state: MappingState,
        now: u64,
    ) -> Result<FakeEndpoint, TableError> {
        let key = MappingKey::new(session_id, logical_socket_id, socket_generation, fake);
        if inner.forward.contains_key(&key) {
            inner.counters.allocation_failures += 1;
            return Err(TableError::KeyExists(key));
        }
        // same fake already held by a different key -> explicit conflict
        if let Some((other_key, _)) = inner.forward.iter().find(|(k, _)| k.fake == fake) {
            if *other_key != key {
                inner.counters.allocation_failures += 1;
                return Err(TableError::FakeInUse(fake));
            }
        }
        // reverse conflict: (peer_id, tunnel, src_port) already mapped elsewhere
        let reverse_key = (peer.peer_id, peer.tunnel_session_id, peer.addr.port());
        if let Some(existing_key) = inner.reverse.get(&reverse_key) {
            if *existing_key != key {
                inner.counters.allocation_failures += 1;
                return Err(TableError::ReverseConflict(peer));
            }
        }

        // Reserve the endpoint: for fixed allocation it is still in the free pool;
        // for pool-based allocation it was already popped.
        inner.pool.retain(|f| *f != fake);

        inner.forward.insert(
            key,
            Entry {
                peer,
                state,
                last_seen: now,
            },
        );
        inner.reverse.insert(reverse_key, key);
        inner.counters.allocations += 1;
        Ok(fake)
    }

    /// Forward lookup: (session, sock, gen, fake) -> PeerEndpoint. Touches last_seen.
    pub fn lookup_forward(
        &self,
        session_id: u64,
        logical_socket_id: u32,
        socket_generation: u32,
        fake: FakeEndpoint,
        now: u64,
    ) -> Option<PeerEndpoint> {
        let mut inner = self.inner.lock().unwrap();
        inner.counters.forward_lookups += 1;
        let key = MappingKey::new(session_id, logical_socket_id, socket_generation, fake);
        let peer = {
            let entry = inner.forward.get_mut(&key)?;
            entry.last_seen = now;
            entry.peer
        };
        inner.counters.touches += 1;
        Some(peer)
    }

    /// Reverse lookup: (peer_id, tunnel_session_id, peer source port) -> FakeEndpoint.
    /// Touches last_seen.
    pub fn lookup_reverse(
        &self,
        peer_id: u32,
        tunnel_session_id: u64,
        peer_src_port_be: u16,
        now: u64,
    ) -> Option<FakeEndpoint> {
        let mut inner = self.inner.lock().unwrap();
        inner.counters.reverse_lookups += 1;
        let reverse_key = (peer_id, tunnel_session_id, peer_src_port_be);
        let key = {
            let key = *inner.reverse.get(&reverse_key)?;
            let entry = inner.forward.get_mut(&key)?;
            entry.last_seen = now;
            key
        };
        inner.counters.touches += 1;
        Some(key.fake)
    }

    /// Transition a mapping's lifecycle state (Discovery -> InRoom -> InGame). Retained
    /// states are exempt from reaping (v2.1 §5).
    pub fn set_state(
        &self,
        session_id: u64,
        logical_socket_id: u32,
        socket_generation: u32,
        fake: FakeEndpoint,
        state: MappingState,
        now: u64,
    ) -> Result<(), TableError> {
        let mut inner = self.inner.lock().unwrap();
        let key = MappingKey::new(session_id, logical_socket_id, socket_generation, fake);
        let entry = inner
            .forward
            .get_mut(&key)
            .ok_or(TableError::KeyExists(key))?;
        entry.state = state;
        entry.last_seen = now;
        inner.counters.state_changes += 1;
        Ok(())
    }

    /// Remove every mapping belonging to a socket (both directions) — socket close /
    /// session end path (design §3.4 "socket 关闭/会话结束 → 正反向双向删除").
    pub fn release_socket(
        &self,
        session_id: u64,
        logical_socket_id: u32,
        socket_generation: u32,
    ) -> usize {
        let mut inner = self.inner.lock().unwrap();
        let keys: Vec<MappingKey> = inner
            .forward
            .keys()
            .filter(|k| {
                k.session_id == session_id
                    && k.logical_socket_id == logical_socket_id
                    && k.socket_generation == socket_generation
            })
            .copied()
            .collect();
        let removed = keys.len();
        for key in &keys {
            let entry = inner.forward.remove(key).expect("key present");
            inner.reverse.remove(&(
                entry.peer.peer_id,
                entry.peer.tunnel_session_id,
                entry.peer.addr.port(),
            ));
            inner.pool.push_front(key.fake);
        }
        inner.counters.releases += removed as u64;
        removed
    }

    /// Remove every mapping of a session (all sockets, both directions).
    pub fn end_session(&self, session_id: u64) -> usize {
        let mut inner = self.inner.lock().unwrap();
        let keys: Vec<MappingKey> = inner
            .forward
            .keys()
            .filter(|k| k.session_id == session_id)
            .copied()
            .collect();
        let removed = keys.len();
        for key in &keys {
            let entry = inner.forward.remove(key).expect("key present");
            inner.reverse.remove(&(
                entry.peer.peer_id,
                entry.peer.tunnel_session_id,
                entry.peer.addr.port(),
            ));
            inner.pool.push_front(key.fake);
        }
        inner.counters.session_ends += 1;
        removed
    }

    /// Reap discovery-phase entries idle for more than DISCOVERY_TTL_TICKS. Retained
    /// states (IN_ROOM / IN_GAME) are never reaped. Returns how many were removed.
    pub fn reap_expired(&self, now: u64) -> usize {
        let mut inner = self.inner.lock().unwrap();
        let expired_keys: Vec<MappingKey> = inner
            .forward
            .iter()
            .filter(|(_, e)| {
                e.state == MappingState::Discovery
                    && now.saturating_sub(e.last_seen) >= DISCOVERY_TTL_TICKS
            })
            .map(|(k, _)| *k)
            .collect();
        let n = expired_keys.len();
        for key in &expired_keys {
            let entry = inner.forward.remove(key).expect("key present");
            inner.reverse.remove(&(
                entry.peer.peer_id,
                entry.peer.tunnel_session_id,
                entry.peer.addr.port(),
            ));
            inner.pool.push_front(key.fake);
        }
        inner.counters.reaped += n as u64;
        n
    }

    /// Number of live mappings.
    pub fn len(&self) -> usize {
        self.inner.lock().unwrap().forward.len()
    }

    /// Free endpoints remaining in the pool.
    pub fn pool_available(&self) -> usize {
        self.inner.lock().unwrap().pool.len()
    }

    /// Snapshot of per-operation counters.
    pub fn counters(&self) -> OpCounters {
        self.inner.lock().unwrap().counters
    }

    /// The allocatable pool (for tests/observability, read-only snapshot).
    pub fn pool_snapshot(&self) -> Vec<FakeEndpoint> {
        self.inner.lock().unwrap().pool.iter().copied().collect()
    }
}

impl Default for FakeIpTable {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn peer(peer_id: u32, tunnel: u64, port: u16) -> PeerEndpoint {
        PeerEndpoint::new(
            peer_id,
            tunnel,
            SocketAddr::new(std::net::IpAddr::V4(Ipv4Addr::new(192, 168, 31, 59)), port),
        )
    }

    #[test]
    fn allocation_uses_pool_in_order() {
        let t = FakeIpTable::new();
        let f1 = t
            .allocate(1, 1, 1, peer(1, 7, 53787), MappingState::Discovery, 0)
            .unwrap();
        let f2 = t
            .allocate(1, 2, 1, peer(1, 7, 53788), MappingState::Discovery, 0)
            .unwrap();
        assert_eq!(f1.fake_ip, Ipv4Addr::new(127, 0, 127, 1));
        assert_eq!(f2.fake_ip, Ipv4Addr::new(127, 0, 127, 2));
        assert_eq!(f1.fake_port, FAKE_PORT);
        assert_eq!(t.pool_available(), 98);
        assert_eq!(t.len(), 2);
    }

    #[test]
    fn pool_exhaustion_is_explicit() {
        let t = FakeIpTable::new();
        for n in 0..100 {
            t.allocate(
                1,
                n,
                1,
                peer(1, 7, 50000 + n as u16),
                MappingState::Discovery,
                0,
            )
            .unwrap();
        }
        let err = t.allocate(2, 999, 1, peer(9, 9, 40000), MappingState::Discovery, 0);
        assert_eq!(err, Err(TableError::PoolExhausted));
        assert_eq!(t.pool_available(), 0);
        assert_eq!(t.counters().allocation_failures, 1);
    }

    #[test]
    fn same_key_is_explicit_error_not_silent_overwrite() {
        let t = FakeIpTable::new();
        let f = t
            .allocate(1, 1, 1, peer(1, 7, 53787), MappingState::Discovery, 0)
            .unwrap();
        // same key, different peer -> KeyExists, mapping unchanged
        let err = t.allocate_fixed(f, 1, 1, 1, peer(2, 8, 53789), MappingState::InRoom, 1);
        assert_eq!(err, Err(TableError::KeyExists(MappingKey::new(1, 1, 1, f))));
        // forward lookup still returns the ORIGINAL peer
        assert_eq!(t.lookup_forward(1, 1, 1, f, 1), Some(peer(1, 7, 53787)));
    }

    #[test]
    fn fake_in_use_by_different_key_is_explicit_conflict() {
        let t = FakeIpTable::new();
        let f = t
            .allocate(1, 1, 1, peer(1, 7, 53787), MappingState::Discovery, 0)
            .unwrap();
        let err = t.allocate_fixed(f, 1, 2, 1, peer(1, 7, 53788), MappingState::Discovery, 1);
        assert_eq!(err, Err(TableError::FakeInUse(f)));
    }

    #[test]
    fn reverse_conflict_is_explicit() {
        let t = FakeIpTable::new();
        let f1 = t
            .allocate(1, 1, 1, peer(1, 7, 53787), MappingState::Discovery, 0)
            .unwrap();
        // same reverse key (peer 1, tunnel 7, src port 53787) but a different fake
        // endpoint via fixed allocation
        let err = t.allocate_fixed(
            FakeEndpoint::new(Ipv4Addr::new(127, 0, 127, 50), FAKE_PORT),
            1,
            1,
            1,
            peer(1, 7, 53787),
            MappingState::Discovery,
            1,
        );
        assert_eq!(err, Err(TableError::ReverseConflict(peer(1, 7, 53787))));
        assert_eq!(t.len(), 1);
        assert_eq!(t.lookup_reverse(1, 7, 53787, 1), Some(f1));
    }

    #[test]
    fn forward_and_reverse_lookup_roundtrip() {
        let t = FakeIpTable::new();
        let f = t
            .allocate(3, 5, 2, peer(11, 4, 53787), MappingState::Discovery, 10)
            .unwrap();
        assert_eq!(t.lookup_forward(3, 5, 2, f, 11), Some(peer(11, 4, 53787)));
        assert_eq!(t.lookup_reverse(11, 4, 53787, 11), Some(f));
        // wrong session / sock / generation miss
        assert_eq!(t.lookup_forward(3, 5, 3, f, 11), None);
        assert_eq!(t.lookup_forward(3, 6, 2, f, 11), None);
        assert_eq!(t.lookup_forward(4, 5, 2, f, 11), None);
        assert_eq!(t.lookup_reverse(11, 5, 53787, 11), None);
    }

    #[test]
    fn generation_isolation() {
        let t = FakeIpTable::new();
        let f = t
            .allocate(1, 1, 1, peer(1, 7, 53787), MappingState::InRoom, 0)
            .unwrap();
        // socket handle reused: new generation 2 must not hit gen 1's mapping
        assert_eq!(t.lookup_forward(1, 1, 2, f, 1), None);
        // and allocating gen 2 on the same logical socket gets a NEW fake
        let f2 = t
            .allocate(1, 1, 2, peer(1, 7, 53788), MappingState::InRoom, 1)
            .unwrap();
        assert_ne!(f, f2);
        assert_eq!(t.lookup_forward(1, 1, 1, f, 2), Some(peer(1, 7, 53787)));
        assert_eq!(t.lookup_forward(1, 1, 2, f2, 2), Some(peer(1, 7, 53788)));
    }

    #[test]
    fn session_isolation() {
        let t = FakeIpTable::new();
        let f1 = t
            .allocate(1, 1, 1, peer(1, 7, 53787), MappingState::Discovery, 0)
            .unwrap();
        let f2 = t
            .allocate(2, 1, 1, peer(2, 7, 53788), MappingState::Discovery, 0)
            .unwrap();
        // same logical socket id in different sessions -> independent
        assert_ne!(f1, f2);
        t.end_session(1);
        assert_eq!(t.len(), 1);
        assert_eq!(t.lookup_forward(1, 1, 1, f1, 1), None);
        assert_eq!(t.lookup_forward(2, 1, 1, f2, 1), Some(peer(2, 7, 53788)));
        assert_eq!(t.lookup_reverse(2, 7, 53788, 1), Some(f2));
    }

    #[test]
    fn release_socket_removes_both_directions() {
        let t = FakeIpTable::new();
        let f1 = t
            .allocate(1, 1, 1, peer(1, 7, 53787), MappingState::Discovery, 0)
            .unwrap();
        let f2 = t
            .allocate(1, 2, 1, peer(1, 7, 53788), MappingState::Discovery, 0)
            .unwrap();
        assert_eq!(t.release_socket(1, 1, 1), 1);
        assert_eq!(t.len(), 1);
        assert_eq!(t.lookup_forward(1, 1, 1, f1, 1), None);
        assert_eq!(t.lookup_reverse(1, 7, 53787, 1), None);
        // other socket untouched, reverse intact
        assert_eq!(t.lookup_forward(1, 2, 1, f2, 1), Some(peer(1, 7, 53788)));
        assert_eq!(t.lookup_reverse(1, 7, 53788, 1), Some(f2));
        // released endpoint is returned to the pool
        assert_eq!(t.pool_available(), 99);
    }

    #[test]
    fn same_peer_multiple_sockets_get_independent_fakes() {
        let t = FakeIpTable::new();
        let f_a = t
            .allocate(1, 1, 1, peer(5, 3, 53787), MappingState::InRoom, 0)
            .unwrap();
        let f_b = t
            .allocate(1, 2, 1, peer(5, 3, 53788), MappingState::InRoom, 0)
            .unwrap();
        assert_ne!(f_a, f_b);
        // reverse lookups by different source ports resolve to different fakes
        assert_eq!(t.lookup_reverse(5, 3, 53787, 1), Some(f_a));
        assert_eq!(t.lookup_reverse(5, 3, 53788, 1), Some(f_b));
        // releasing one socket does not disturb the other
        t.release_socket(1, 1, 1);
        assert_eq!(t.lookup_reverse(5, 3, 53788, 1), Some(f_b));
    }

    #[test]
    fn discovery_entries_are_reaped_after_ttl() {
        let t = FakeIpTable::new();
        let f = t
            .allocate(1, 1, 1, peer(1, 7, 53787), MappingState::Discovery, 0)
            .unwrap();
        assert_eq!(t.reap_expired(DISCOVERY_TTL_TICKS - 1), 0); // not yet expired
        assert_eq!(t.reap_expired(DISCOVERY_TTL_TICKS), 1); // now expired
        assert_eq!(t.len(), 0);
        assert_eq!(t.lookup_forward(1, 1, 1, f, DISCOVERY_TTL_TICKS), None);
        assert_eq!(t.lookup_reverse(1, 7, 53787, DISCOVERY_TTL_TICKS), None);
        // the endpoint returns to the pool
        assert_eq!(t.pool_available(), 100);
    }

    #[test]
    fn touches_refresh_discovery_ttl() {
        let t = FakeIpTable::new();
        let f = t
            .allocate(1, 1, 1, peer(1, 7, 53787), MappingState::Discovery, 0)
            .unwrap();
        // activity at tick 599 keeps it alive past the TTL
        assert_eq!(t.lookup_forward(1, 1, 1, f, 599), Some(peer(1, 7, 53787)));
        assert_eq!(t.reap_expired(600), 0); // last_seen refreshed to 599
        assert_eq!(t.reap_expired(1199), 1); // expired again after another TTL window
    }

    #[test]
    fn in_room_and_in_game_are_never_reaped() {
        let t = FakeIpTable::new();
        let f_room = t
            .allocate(1, 1, 1, peer(1, 7, 53787), MappingState::Discovery, 0)
            .unwrap();
        t.set_state(1, 1, 1, f_room, MappingState::InRoom, 0)
            .unwrap();
        let f_game = t
            .allocate(1, 2, 1, peer(1, 7, 53788), MappingState::Discovery, 0)
            .unwrap();
        t.set_state(1, 2, 1, f_game, MappingState::InGame, 0)
            .unwrap();
        let f_disc = t
            .allocate(1, 3, 1, peer(1, 7, 53789), MappingState::Discovery, 0)
            .unwrap();
        assert_eq!(t.reap_expired(DISCOVERY_TTL_TICKS + 100), 1); // only discovery reaped
        assert_eq!(t.len(), 2);
        assert_eq!(
            t.lookup_forward(1, 1, 1, f_room, 1000),
            Some(peer(1, 7, 53787))
        );
        assert_eq!(
            t.lookup_forward(1, 2, 1, f_game, 1000),
            Some(peer(1, 7, 53788))
        );
        assert_eq!(t.lookup_forward(1, 3, 1, f_disc, 1000), None);
    }

    #[test]
    fn restart_rebuild_starts_empty() {
        // a fresh table (game restart / process restart) must not inherit mappings
        let t1 = FakeIpTable::new();
        let f = t1
            .allocate(1, 1, 1, peer(1, 7, 53787), MappingState::InGame, 0)
            .unwrap();
        drop(t1);
        let t2 = FakeIpTable::new();
        assert_eq!(t2.len(), 0);
        assert_eq!(t2.pool_available(), 100);
        // the same fake can be allocated again in the new table
        let f2 = t2
            .allocate(1, 1, 1, peer(1, 7, 53787), MappingState::InGame, 0)
            .unwrap();
        assert_eq!(f, f2);
    }

    #[test]
    fn pool_freed_endpoints_come_back() {
        let t = FakeIpTable::new();
        let f1 = t
            .allocate(1, 1, 1, peer(1, 7, 53787), MappingState::Discovery, 0)
            .unwrap();
        let f2 = t
            .allocate(1, 2, 1, peer(1, 7, 53788), MappingState::Discovery, 0)
            .unwrap();
        assert_eq!(t.release_socket(1, 1, 1), 1);
        // released endpoint is reusable
        let f3 = t
            .allocate(1, 3, 1, peer(1, 7, 53789), MappingState::Discovery, 1)
            .unwrap();
        assert_eq!(f3, f1);
        assert_ne!(f3, f2);
    }

    #[test]
    fn counters_track_operations() {
        let t = FakeIpTable::new();
        let f = t
            .allocate(1, 1, 1, peer(1, 7, 53787), MappingState::Discovery, 0)
            .unwrap();
        t.lookup_forward(1, 1, 1, f, 1);
        t.lookup_reverse(1, 7, 53787, 1);
        t.set_state(1, 1, 1, f, MappingState::InRoom, 2).unwrap();
        t.release_socket(1, 1, 1);
        let c = t.counters();
        assert_eq!(c.allocations, 1);
        assert_eq!(c.forward_lookups, 1);
        assert_eq!(c.reverse_lookups, 1);
        assert_eq!(c.state_changes, 1);
        assert_eq!(c.releases, 1);
        assert_eq!(c.touches, 2);
    }

    #[test]
    fn fixed_alloc_outside_pool_is_rejected() {
        let t = FakeIpTable::new();
        let err = t.allocate_fixed(
            FakeEndpoint::new(Ipv4Addr::new(198, 18, 0, 1), FAKE_PORT),
            1,
            1,
            1,
            peer(1, 7, 53787),
            MappingState::Discovery,
            0,
        );
        assert_eq!(
            err,
            Err(TableError::NotInPool(FakeEndpoint::new(
                Ipv4Addr::new(198, 18, 0, 1),
                FAKE_PORT,
            )))
        );
        // 198.18.0.0/15 is reserved for H1 comparison, never allocated here (D5)
        assert_eq!(t.len(), 0);
    }
}
