fn main() { let s = std::net::UdpSocket::bind("127.0.0.1:0").unwrap(); let mut b=[0u8;10]; let _=s.try_recv_from(&mut b); }
