import Darwin

/// Sends a Wake-on-LAN magic packet, for a TV that is fully off and so has
/// no Glasshouse server answering.
enum WakeOnLAN {
    /// - Parameters:
    ///   - mac: `aa:bb:cc:dd:ee:ff` (colons or dashes).
    ///   - host: the TV's IPv4 address; its /24 broadcast is tried as well
    ///     as the limited broadcast.
    @discardableResult
    static func wake(mac: String, host: String?) -> Bool {
        let octets = mac.split { $0 == ":" || $0 == "-" }.compactMap { UInt8($0, radix: 16) }
        guard octets.count == 6 else { return false }
        let packet = [UInt8](repeating: 0xFF, count: 6) + Array([[UInt8]](repeating: octets, count: 16).joined())

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))

        var targets = ["255.255.255.255"]
        if let host {
            let parts = host.split(separator: ".")
            if parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }) {
                targets.append(parts.prefix(3).joined(separator: ".") + ".255")
                targets.append(host)
            }
        }

        var sent = false
        for target in targets {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = in_port_t(9).bigEndian
            guard inet_pton(AF_INET, target, &address.sin_addr) == 1 else { continue }
            let result = packet.withUnsafeBytes { bytes in
                withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            if result == packet.count { sent = true }
        }
        return sent
    }
}
