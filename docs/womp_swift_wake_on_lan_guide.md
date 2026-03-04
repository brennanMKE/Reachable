# Wake-on-Magic-Packet (WOMP) with Swift

This document explains how to trigger macOS Wake-on-Magic-Packet (WOMP)
using Swift. It includes protocol details, macOS configuration, and
example Swift code for sending Wake-on-LAN packets.

------------------------------------------------------------------------

## 1. macOS Configuration

macOS must allow Wake-on-Magic-Packet.

Check settings:

    pmset -g

Look for:

    womp 1

If disabled, enable it:

    sudo pmset -a womp 1

Recommended additional settings:

    sudo pmset -a tcpkeepalive 1
    sudo pmset -a autopoweroff 0
    sudo pmset -a proximitywake 1

------------------------------------------------------------------------

## 2. Wake-on-LAN Protocol

Wake-on-LAN uses a "magic packet" to wake sleeping computers.

Magic packet structure:

    +----------------------------------------------------------+
    | 6 bytes | FF FF FF FF FF FF                              |
    +----------------------------------------------------------+
    | 16 repetitions of the target MAC address (6 bytes each) |
    +----------------------------------------------------------+

Total packet size:

    6 bytes header
    + (16 * 6) MAC address repetitions
    = 102 bytes total

Example packet:

    FF FF FF FF FF FF
    AA BB CC DD EE FF
    AA BB CC DD EE FF
    AA BB CC DD EE FF
    (repeated 16 times)

The packet is typically sent using UDP broadcast on port 7 or 9.

------------------------------------------------------------------------

## 3. Swift Implementation

### Build the Magic Packet

    func createMagicPacket(mac: String) -> Data {
        let macBytes = mac.split(separator: ":").compactMap {
            UInt8($0, radix: 16)
        }

        var packet = Data(repeating: 0xFF, count: 6)

        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }

        return packet
    }

------------------------------------------------------------------------

### Send the Packet Using UDP

    import Network

    func sendWOL(mac: String, broadcast: String = "255.255.255.255", port: UInt16 = 9) {

        let packet = createMagicPacket(mac: mac)

        let connection = NWConnection(
            host: NWEndpoint.Host(broadcast),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .udp
        )

        connection.start(queue: .global())

        connection.send(content: packet, completion: .contentProcessed { error in
            if let error = error {
                print("Send error:", error)
            } else {
                print("Magic packet sent")
            }
            connection.cancel()
        })
    }

Example usage:

    sendWOL(mac: "3C:22:FB:12:34:56")

------------------------------------------------------------------------

## 4. Monitoring Workflow

Typical wake workflow for monitoring tools:

    +-------------------+
    | check reachability |
    +---------+---------+
              |
              v
       host unreachable?
              |
             yes
              |
              v
    +-------------------+
    | send WOL packet   |
    +---------+---------+
              |
              v
         wait 5-10 sec
              |
              v
    +-------------------+
    | retry connection  |
    +-------------------+

------------------------------------------------------------------------

## 5. Important Notes

Normal traffic will NOT wake sleeping Macs:

    ping
    ssh
    tcp connect
    netcat

Only specific wake signals work:

    magic packet (Wake-on-LAN)
    Apple Sleep Proxy
    Apple Remote Desktop wake

Ethernet connections provide the most reliable wake behavior.

------------------------------------------------------------------------

## 6. Useful References

Apple pmset manual:

https://developer.apple.com/library/archive/documentation/Darwin/Reference/ManPages/man1/pmset.1.html

Apple Wake-on-LAN constant:

https://developer.apple.com/documentation/iokit/wake_on_lan_filters/kioethernetwakeonmagicpacket

Wake-on-LAN protocol:

https://en.wikipedia.org/wiki/Wake-on-LAN

Example Swift implementation repository:

https://github.com/feritbolezek/WakeOnLan

------------------------------------------------------------------------

End of document.
