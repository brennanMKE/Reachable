import Foundation
import Network

enum WakeOnLAN {

    /// Sends a Wake-on-LAN magic packet to the given MAC address via UDP broadcast.
    /// Fire-and-forget — errors are silently discarded.
    static func send(mac: String, broadcast: String = "255.255.255.255", port: UInt16 = 9) {
        guard let packet = magicPacket(mac: mac) else { return }
        let conn = NWConnection(
            host: NWEndpoint.Host(broadcast),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .udp
        )
        conn.start(queue: .global())
        conn.send(content: packet, completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: - Private

    /// Builds the 102-byte magic packet: 6x 0xFF + 16 repetitions of the MAC.
    private static func magicPacket(mac: String) -> Data? {
        let bytes = mac.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6 else { return nil }
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: bytes) }
        return packet
    }
}
