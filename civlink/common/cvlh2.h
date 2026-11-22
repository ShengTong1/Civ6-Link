// cvlh2.h - CivLink F1 Hook<->Agent local frame contract (CVLH2, spec v2.1 §4.4)
//
// SINGLE definition of the frame layout shared by the Hook DLL (C++) and the Agent (Rust).
// Both sides must agree byte for byte. If you change anything here, bump CIVLINK_FRAME_VER
// and update agent/src/frame.rs in the same commit.
//
//   offset  size  field
//   0       4     magic 'C','V','L','H'
//   4       1     ver = 2
//   5       1     dir  0 = hook->agent, 1 = agent->hook (Design II only; unused in F1)
//   6       4     seq   LE, per-session monotonically increasing frame sequence number
//                       (spec §4.4 transport rule 2: the loopback-UDP transport MUST carry
//                        a frame sequence number so the Agent can prove continuity)
//   10      8     session_id        (LE; process generation id)
//   18      4     logical_socket_id (LE; NOT the Windows SOCKET value - handles get reused)
//   22      4     socket_generation (LE; +1 when a logical id is reused)
//   26      1     af = 2 (AF_INET)
//   27      4     src ipv4 (stored as in sockaddr_in.sin_addr: network byte order)
//   31      2     src port (stored as in sockaddr_in.sin_port: BIG endian on the wire)
//   33      4     dst ipv4 (network byte order)
//   37      2     dst port (BIG endian)
//   39      1     flags
//   40      2     payload_len (LE, <= CIVLINK_FRAME_MAX_PAYLOAD)
//   42      ...   payload
//
// flags bits:
//   0x01  original call was WSASendTo            (0 = sendto)
//   0x02  destination was 255.255.255.255        (limited broadcast)
//   0x04  destination port is in the discovery range (62900..62999)
//   0x08  payload was oversize and got REJECTED  (never sent; payload_len is 0)
//   0x10  frame carries no payload (rejected-oversize notification frame)
//   0x20  F2 observation frame: outbound send outside the discovery path (e.g. the
//         62056 data plane). Observation only - the game's call is never altered.
//
// The payload limit is 1280 bytes. Anything larger is REJECTED and counted - silent
// truncation of game data is forbidden by spec v2.1 §4.4.
#ifndef CIVLINK_CVLH2_H
#define CIVLINK_CVLH2_H

#include <cstdint>
#include <cstring>

#define CIVLINK_FRAME_MAGIC0 'C'
#define CIVLINK_FRAME_MAGIC1 'V'
#define CIVLINK_FRAME_MAGIC2 'L'
#define CIVLINK_FRAME_MAGIC3 'H'
#define CIVLINK_FRAME_VER    2
#define CIVLINK_FRAME_HDR    42
#define CIVLINK_FRAME_MAX_PAYLOAD 1280
#define CIVLINK_FRAME_MAX_TOTAL (CIVLINK_FRAME_HDR + CIVLINK_FRAME_MAX_PAYLOAD)

#define CIVLINK_DIR_HOOK_TO_AGENT 0
#define CIVLINK_DIR_AGENT_TO_HOOK 1

#define CIVLINK_FLAG_VIA_WSASENDTO 0x01
#define CIVLINK_FLAG_LIMITED_BCAST 0x02
#define CIVLINK_FLAG_DISCOVERY     0x04
#define CIVLINK_FLAG_REJECTED_OVERSIZE 0x08
#define CIVLINK_FLAG_NO_PAYLOAD    0x10
#define CIVLINK_FLAG_OBSERVED      0x20

// Discovery port range observed on the wire (F1 / F0 evidence: 62900..62999).
#define CIVLINK_DISCOVERY_PORT_FIRST 62900
#define CIVLINK_DISCOVERY_PORT_LAST  62999
#define CIVLINK_DATAPATH_PORT        62056   // F2: Civ6 LAN data plane

static inline void cvlh_put_u16le(uint8_t* p, uint16_t v) { p[0] = (uint8_t)(v & 0xFF); p[1] = (uint8_t)(v >> 8); }
static inline void cvlh_put_u32le(uint8_t* p, uint32_t v) { for (int i = 0; i < 4; i++) p[i] = (uint8_t)((v >> (8 * i)) & 0xFF); }
static inline void cvlh_put_u64le(uint8_t* p, uint64_t v) { for (int i = 0; i < 8; i++) p[i] = (uint8_t)((v >> (8 * i)) & 0xFF); }

static inline uint16_t cvlh_get_u16le(const uint8_t* p) { return (uint16_t)(p[0] | (p[1] << 8)); }
static inline uint32_t cvlh_get_u32le(const uint8_t* p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }
static inline uint64_t cvlh_get_u64le(const uint8_t* p) { uint64_t v = 0; for (int i = 7; i >= 0; i--) v = (v << 8) | p[i]; return v; }

struct CvlhFrameView {
    uint8_t        dir;
    uint32_t       seq;
    uint64_t       session_id;
    uint32_t       logical_socket_id;
    uint32_t       socket_generation;
    uint8_t        af;
    uint32_t       src_ip_be;
    uint16_t       src_port_be;
    uint32_t       dst_ip_be;
    uint16_t       dst_port_be;
    uint8_t        flags;
    uint16_t       payload_len;
    const uint8_t* payload;
};

// Encodes one hook->agent frame. Returns total bytes written, or 0 when the payload
// exceeds CIVLINK_FRAME_MAX_PAYLOAD / the buffer is too small (caller counts a reject).
static inline size_t cvlh_encode(uint8_t* out, size_t out_cap,
                                 uint32_t seq,
                                 uint64_t session_id,
                                 uint32_t logical_socket_id, uint32_t socket_generation,
                                 uint32_t src_ip_be, uint16_t src_port_be,
                                 uint32_t dst_ip_be, uint16_t dst_port_be,
                                 uint8_t flags,
                                 const uint8_t* payload, size_t payload_len)
{
    if (payload_len > CIVLINK_FRAME_MAX_PAYLOAD) return 0;
    const size_t total = CIVLINK_FRAME_HDR + payload_len;
    if (total > out_cap) return 0;

    out[0] = CIVLINK_FRAME_MAGIC0; out[1] = CIVLINK_FRAME_MAGIC1;
    out[2] = CIVLINK_FRAME_MAGIC2; out[3] = CIVLINK_FRAME_MAGIC3;
    out[4] = CIVLINK_FRAME_VER;
    out[5] = CIVLINK_DIR_HOOK_TO_AGENT;
    cvlh_put_u32le(out + 6, seq);
    cvlh_put_u64le(out + 10, session_id);
    cvlh_put_u32le(out + 18, logical_socket_id);
    cvlh_put_u32le(out + 22, socket_generation);
    out[26] = 2; // AF_INET
    cvlh_put_u32le(out + 27, src_ip_be);   // keep raw bytes as stored in sin_addr
    cvlh_put_u16le(out + 31, src_port_be); // keep raw bytes as stored in sin_port
    cvlh_put_u32le(out + 33, dst_ip_be);
    cvlh_put_u16le(out + 37, dst_port_be);
    out[39] = flags;
    cvlh_put_u16le(out + 40, (uint16_t)payload_len);
    if (payload_len) memcpy(out + CIVLINK_FRAME_HDR, payload, payload_len);
    return total;
}

// Validates and decodes a received frame. Returns 1 on success. On failure returns 0 and
// the caller increments its own reject counter (bad magic / unknown ver / short / oversize).
static inline int cvlh_decode(const uint8_t* in, size_t in_len, CvlhFrameView* v)
{
    if (!v || in_len < CIVLINK_FRAME_HDR) return 0;
    if (in[0] != CIVLINK_FRAME_MAGIC0 || in[1] != CIVLINK_FRAME_MAGIC1 ||
        in[2] != CIVLINK_FRAME_MAGIC2 || in[3] != CIVLINK_FRAME_MAGIC3) return 0;
    if (in[4] != CIVLINK_FRAME_VER) return 0;
    const uint16_t plen = cvlh_get_u16le(in + 40);
    if (plen > CIVLINK_FRAME_MAX_PAYLOAD) return 0;
    if (in_len < (size_t)CIVLINK_FRAME_HDR + plen) return 0;

    v->dir = in[5];
    v->seq = cvlh_get_u32le(in + 6);
    v->session_id = cvlh_get_u64le(in + 10);
    v->logical_socket_id = cvlh_get_u32le(in + 18);
    v->socket_generation = cvlh_get_u32le(in + 22);
    v->af = in[26];
    v->src_ip_be = cvlh_get_u32le(in + 27);
    v->src_port_be = cvlh_get_u16le(in + 31);
    v->dst_ip_be = cvlh_get_u32le(in + 33);
    v->dst_port_be = cvlh_get_u16le(in + 37);
    v->flags = in[39];
    v->payload_len = plen;
    v->payload = in + CIVLINK_FRAME_HDR;
    return 1;
}

// Port helpers: the header stores the raw 16-bit value found in sin_port, which is a
// big-endian representation of the host-order port on little-endian Windows.
static inline uint16_t cvlh_port_from_be16(uint16_t be) { return (uint16_t)((be >> 8) | (be << 8)); }
static inline uint16_t cvlh_port_to_be16(uint16_t host) { return (uint16_t)((host >> 8) | (host << 8)); }

// Default local IPC endpoint (spec §4.4 fallback transport; loopback UDP).
#define CIVLINK_IPC_AGENT_PORT 34718
#define CIVLINK_IPC_HOST_STR   "127.0.0.1"

#endif // CIVLINK_CVLH2_H
