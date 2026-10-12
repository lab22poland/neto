//
//  ArpManager.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
#if os(macOS)
import Darwin
#endif

/// Reads the neighbor tables: IPv4 ARP (like `arp -an`) and IPv6 neighbor discovery (like `ndp -an`).
///
/// On macOS both come from the routing table via `sysctl(NET_RT_FLAGS, RTF_LLINFO)`, parsed the way
/// FreeBSD/Darwin `arp` and `ndp` do it. iOS/iPadOS does not expose the routing table to apps.
final class ArpManager {
    
    /// Retrieves the current ARP (IPv4) and NDP (IPv6) neighbor tables from the system
    /// - Returns: ArpResult containing all entries grouped by interface
    /// - Throws: ArpError if the operation fails
    func getArpTable() async throws -> ArpResult {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    #if os(macOS)
                    // IPv4 must work; a failing IPv6 dump only drops the IPv6 part
                    let entries = try Self.readNeighborTable(family: AF_INET) + ((try? Self.readNeighborTable(family: AF_INET6)) ?? [])
                    #else
                    // On iOS/iPadOS, we can only get basic interface information
                    let entries = try Self.getBasicInterfaceEntries()
                    #endif
                    continuation.resume(returning: ArpResult(entries: entries))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    #if os(macOS)
    // MARK: - Routing Table (macOS)
    
    /// Dumps the link-layer entries of one address family from the routing table
    static func readNeighborTable(family: Int32) throws -> [ArpEntry] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, family, NET_RT_FLAGS, RTF_LLINFO]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else {
            throw ArpError.systemCallFailed("sysctl size: \(String(cString: strerror(errno)))")
        }
        guard size > 0 else { return [] }
        // The table can grow between the two calls: retry with 1/8 more space, like Darwin arp/ndp
        var buffer: [UInt8]
        while true {
            buffer = [UInt8](repeating: 0, count: size)
            if sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 { break }
            guard errno == ENOMEM else {
                throw ArpError.systemCallFailed("sysctl dump: \(String(cString: strerror(errno)))")
            }
            size += size / 8
        }
        var now = timeval()
        gettimeofday(&now, nil)
        let ndSocket = family == AF_INET6 ? socket(AF_INET6, SOCK_DGRAM, 0) : -1
        defer { if ndSocket >= 0 { close(ndSocket) } }
        return parseNeighborTable(Array(buffer.prefix(size)), now: Int(now.tv_sec), interfaceName: { index in
            var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
            return if_indextoname(UInt32(index), &name) != nil ? String(cString: name) : "if\(index)"
        }, neighborInfo: { address, interfaceIndex in
            ndSocket >= 0 ? neighborDiscoveryInfo(socket: ndSocket, address: address, interfaceIndex: interfaceIndex) : nil
        })
    }
    
    /// IPv6 neighbor state from the kernel (what `ndp` shows), via ioctl(SIOCGNBRINFO_IN6)
    struct NeighborInfo: Equatable {
        /// ND6_LLINFO_* state: 0 incomplete, 1 reachable, 2 stale, 3 delay, 4 probe
        let state: Int32
        /// Expiry in seconds since 1970, 0 = never
        let expire: Int
    }
    
    /// Mirror of `struct in6_nbrinfo` (netinet6/nd6.h, not imported into Swift)
    private struct In6NeighborInfo {
        var ifname: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                     CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        var addr = in6_addr()
        var asked: Int = 0
        var isrouter: Int32 = 0
        var state: Int32 = 0
        var expire: Int32 = 0
    }
    
    private static func neighborDiscoveryInfo(socket: Int32, address: String, interfaceIndex: Int) -> NeighborInfo? {
        var info = In6NeighborInfo()
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        guard inet_pton(AF_INET6, address, &info.addr) == 1,
              if_indextoname(UInt32(interfaceIndex), &name) != nil else { return nil }
        withUnsafeMutableBytes(of: &info.ifname) { raw in
            for (index, byte) in name.prefix(Int(IFNAMSIZ) - 1).enumerated() where byte != 0 { raw[index] = UInt8(bitPattern: byte) }
        }
        // The kernel expects link-local addresses with the interface index embedded in bytes 2-3 (KAME)
        let index = UInt32(interfaceIndex)
        withUnsafeMutableBytes(of: &info.addr) { raw in
            if raw[0] == 0xfe && raw[1] & 0xc0 == 0x80 {
                raw[2] = UInt8(index >> 8)
                raw[3] = UInt8(index & 0xff)
            }
        }
        // _IOWR('i', 78, struct in6_nbrinfo); the C size includes trailing padding, i.e. the Swift stride
        let request = UInt(0xC000_0000) | (UInt(MemoryLayout<In6NeighborInfo>.stride & 0x1fff) << 16) | (UInt(UInt8(ascii: "i")) << 8) | 78
        guard ioctl(socket, request, &info) == 0 else { return nil }
        return NeighborInfo(state: info.state, expire: Int(info.expire))
    }
    
    /// Parses a `sysctl(NET_RT_FLAGS, RTF_LLINFO)` dump: a sequence of `rt_msghdr`, each followed by
    /// the destination (`sockaddr_in` / `sockaddr_in6`) and the gateway (`sockaddr_dl` with the MAC).
    /// - Parameters:
    ///   - now: Current time in seconds since 1970 (`rmx_expire` uses the same clock)
    ///   - interfaceName: Maps an interface index to its name
    ///   - neighborInfo: IPv6 only – kernel state for an address and interface index; its expiry replaces `rmx_expire`,
    ///     which is always 0 for IPv6. Without it the IPv6 status is "unknown" (like `ndp`, which prints nothing then).
    static func parseNeighborTable(_ buffer: [UInt8], now: Int, interfaceName: (Int) -> String,
                                   neighborInfo: (String, Int) -> NeighborInfo? = { _, _ in nil }) -> [ArpEntry] {
        let headerSize = MemoryLayout<rt_msghdr>.size
        let flagsOffset = MemoryLayout<rt_msghdr>.offset(of: \rt_msghdr.rtm_flags)!
        let addrsOffset = MemoryLayout<rt_msghdr>.offset(of: \rt_msghdr.rtm_addrs)!
        let expireOffset = MemoryLayout<rt_msghdr>.offset(of: \rt_msghdr.rtm_rmx)! + MemoryLayout<rt_metrics>.offset(of: \rt_metrics.rmx_expire)!
        
        func load<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
            buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
        }
        /// Socket addresses are padded to 4 bytes (Darwin ROUNDUP)
        func roundUp(_ length: Int) -> Int { length > 0 ? 1 + ((length - 1) | 3) : 4 }
        
        var entries: [ArpEntry] = []
        var offset = 0
        while offset + headerSize <= buffer.count {
            let messageLength = Int(load(UInt16.self, at: offset))
            guard messageLength >= headerSize, offset + messageLength <= buffer.count else { break }
            defer { offset += messageLength }
            
            let flags = load(Int32.self, at: offset + flagsOffset)
            let addresses = load(Int32.self, at: offset + addrsOffset)
            let expire = Int(load(Int32.self, at: offset + expireOffset))
            guard addresses & RTA_DST != 0, addresses & RTA_GATEWAY != 0 else { continue }
            
            let destination = offset + headerSize
            guard destination < offset + messageLength else { continue }
            let gateway = destination + roundUp(Int(buffer[destination]))
            guard gateway + 8 <= offset + messageLength,
                  let ipAddress = neighborAddress(buffer, at: destination),
                  buffer[gateway + 1] == UInt8(AF_LINK) else { continue }
            let isIPv6 = buffer[destination + 1] == UInt8(AF_INET6)
            // ndp skips multicast groups
            if isIPv6, buffer[destination + 8] == 0xff { continue }
            
            // sockaddr_dl: len, family, index (2), type, nlen, alen, slen, then name and LLADDR = sdl_data + nlen
            let index = Int(load(UInt16.self, at: gateway + 2))
            let linkType = buffer[gateway + 4]
            let nameLength = Int(buffer[gateway + 5])
            let addressLength = Int(buffer[gateway + 6])
            let macStart = gateway + 8 + nameLength
            let macAddress: String
            if addressLength > 0, macStart + addressLength <= offset + messageLength {
                macAddress = buffer[macStart..<(macStart + addressLength)].map { String(format: "%02x", $0) }.joined(separator: ":")
            } else {
                macAddress = "(incomplete)"
            }
            
            let interface = interfaceName(index)
            let info = isIPv6 ? neighborInfo(ipAddress, index) : nil
            let effectiveExpire = info?.expire ?? expire
            var status: String
            if isIPv6 && info == nil {
                status = "unknown"
            } else if effectiveExpire == 0 {
                status = "permanent"
            } else if effectiveExpire <= now {
                status = "expired"
            } else {
                status = "expires in \(formatDuration(effectiveExpire - now))"
            }
            if let info, let state = neighborStateName(info.state) {
                status = "\(state), \(status)"
            }
            entries.append(ArpEntry(
                ipAddress: ipAddress,
                macAddress: macAddress,
                interface: interface,
                status: status,
                linkType: linkTypeName(linkType),
                isScoped: flags & RTF_IFSCOPE != 0
            ))
        }
        return entries
    }
    
    /// Numeric IPv4/IPv6 destination; clears the KAME-embedded scope of link-local IPv6 addresses
    private static func neighborAddress(_ buffer: [UInt8], at offset: Int) -> String? {
        guard offset + 2 <= buffer.count else { return nil }
        let length = Int(buffer[offset])
        switch Int32(buffer[offset + 1]) {
        case AF_INET where length >= 8 && offset + 8 <= buffer.count:
            return buffer[(offset + 4)..<(offset + 8)].map(String.init).joined(separator: ".")
        case AF_INET6 where length >= 24 && offset + 24 <= buffer.count:
            var address = Array(buffer[(offset + 8)..<(offset + 24)])
            // Multicast is skipped before this point, so only unicast link-local carries an embedded scope
            if address[0] == 0xfe && address[1] & 0xc0 == 0x80 {
                address[2] = 0
                address[3] = 0
            }
            var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            return address.withUnsafeBytes { raw in
                inet_ntop(AF_INET6, raw.baseAddress, &text, socklen_t(text.count)) != nil ? String(cString: text) : nil
            }
        default:
            return nil
        }
    }
    
    /// Link type label exactly as printed by Darwin `arp` (empty for types it does not name)
    static func linkTypeName(_ type: UInt8) -> String {
        switch Int32(type) {
        case IFT_ETHER: return "ethernet"
        case IFT_FDDI: return "fddi"
        case IFT_ATM: return "atm"
        case IFT_L2VLAN: return "vlan"
        case IFT_IEEE1394: return "firewire"
        case IFT_BRIDGE: return "bridge"
        default: return ""
        }
    }
    
    /// ND6_LLINFO_* state names (netinet6/nd6.h)
    static func neighborStateName(_ state: Int32) -> String? {
        switch state {
        case 0: return "incomplete"
        case 1: return "reachable"
        case 2: return "stale"
        case 3: return "delay"
        case 4: return "probe"
        default: return nil
        }
    }
    
    /// Duration like `ndp`'s sec2str: "1d0h0m5s", "23h59m28s", "44s"
    static func formatDuration(_ seconds: Int) -> String {
        let days = seconds / 86_400, hours = seconds / 3600 % 24, minutes = seconds / 60 % 60, rest = seconds % 60
        var text = ""
        if days > 0 { text += "\(days)d" }
        if !text.isEmpty || hours > 0 { text += "\(hours)h" }
        if !text.isEmpty || minutes > 0 { text += "\(minutes)m" }
        return text + "\(rest)s"
    }
    #endif
    
    #if !os(macOS)
    /// Retrieves basic interface information for iOS/iPadOS
    /// Note: iOS/iPadOS sandbox restrictions limit access to detailed ARP information
    private static func getBasicInterfaceEntries() throws -> [ArpEntry] {
        var entries: [ArpEntry] = []
        
        // On iOS/iPadOS, we can only get basic network interface information
        // due to sandbox restrictions that prevent access to detailed ARP tables
        
        // Create a basic entry showing that ARP information is limited on iOS/iPadOS
        let entry = ArpEntry(
            ipAddress: "N/A",
            macAddress: "N/A", 
            interface: "iOS/iPadOS",
            status: "Limited access due to sandbox restrictions"
        )
        entries.append(entry)
        
        return entries
    }
    #endif
}

/// Errors that can occur during ARP operations
enum ArpError: LocalizedError {
    case systemCallFailed(String)
    case parsingFailed
    case platformNotSupported
    
    var errorDescription: String? {
        switch self {
        case .systemCallFailed(let message):
            return "System call failed: \(message)"
        case .parsingFailed:
            return "Failed to parse neighbor cache data"
        case .platformNotSupported:
            return "Platform not supported for ARP operations"
        }
    }
} 