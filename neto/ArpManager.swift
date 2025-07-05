//
//  ArpManager.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Network
import SystemConfiguration
#if os(macOS)
import Darwin
#endif

/// Manager class responsible for ARP table operations across all platforms
/// 
/// This implementation provides cross-platform access to network neighbor information
/// using BSD system APIs that are available on both macOS and iOS/iPadOS:
/// - Uses `getifaddrs()` to enumerate network interfaces and their MAC addresses
/// - Uses `sysctl()` to access the routing table and neighbor cache
/// - Parses routing messages to extract ARP/NDP entries
///
/// This approach works within app sandbox constraints by using only
/// approved BSD networking APIs available to all Darwin-based platforms.
final class ArpManager {
    
    // MARK: - BSD Constants and Structures
    private let RTAX_MAX: Int32 = 8
    private let RTAX_DST: Int32 = 0
    private let RTAX_GATEWAY: Int32 = 1
    private let RTF_LLINFO: Int32 = 0x400
    private let NET_RT_FLAGS: Int32 = 1
    private let RTF_STATIC: Int32 = 0x800
    private let RTF_WASCLONED: Int32 = 0x20000
    private let AF_LINK: Int32 = 18
    
    /// Helper struct to represent network interface information
    private struct NetworkInterface {
        let name: String
        let family: AddressFamily
        let flags: UInt32
        let ipAddress: String?
        let macAddress: String?
        
        enum AddressFamily {
            case ipv4, ipv6, link
        }
    }
    
    /// Retrieves the current ARP table from the system
    /// 
    /// - Returns: ArpResult containing all ARP entries grouped by interface
    /// - Throws: ArpError if the operation fails
    /// 
    /// **Implementation Notes:**
    /// - Uses BSD system APIs for cross-platform compatibility
    /// - Works on both macOS and iOS/iPadOS within sandbox constraints
    /// - Returns neighbor cache entries when available, or interface information as fallback
    func getArpTable() async throws -> ArpResult {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    #if os(macOS)
                    let entries = try self.getNeighborCacheEntries()
                    #else
                    // On iOS/iPadOS, we can only get basic interface information
                    let entries = try self.getBasicInterfaceEntries()
                    #endif
                    let result = ArpResult(entries: entries)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Core Implementation
    
    #if os(macOS)
    /// Retrieves neighbor cache entries using BSD sysctl APIs
    private func getNeighborCacheEntries() throws -> [ArpEntry] {
        var entries: [ArpEntry] = []
        
        // Get network interfaces with their MAC addresses
        let interfaces = try getNetworkInterfaces()
        
        // First, add interface entries showing the MAC addresses of local interfaces
        entries.append(contentsOf: createInterfaceEntries(interfaces))
        
        // Then try to get neighbor entries from routing table
        for interface in interfaces.filter({ $0.family != .link }) {
            do {
                let neighborEntries = try getNeighborEntriesForInterface(interface)
                entries.append(contentsOf: neighborEntries)
            } catch {
                // Continue with other interfaces if one fails
                print("Debug: Failed to get neighbor entries for interface \(interface.name): \(error)")
                continue
            }
        }
        
        return entries
    }
    
    /// Creates entries showing network interface information including MAC addresses
    private func createInterfaceEntries(_ interfaces: [NetworkInterface]) -> [ArpEntry] {
        var entries: [ArpEntry] = []
        
        // Group interfaces by name to combine IP and MAC information
        let interfaceGroups = Dictionary(grouping: interfaces) { $0.name }
        
        for (interfaceName, interfaceList) in interfaceGroups {
            // Skip loopback interfaces
            if interfaceName.hasPrefix("lo") { continue }
            
            // Find the link-layer interface (has MAC address)
            let linkInterface = interfaceList.first { $0.family == .link }
            let ipInterfaces = interfaceList.filter { $0.family != .link }
            
            guard let macAddress = linkInterface?.macAddress else { continue }
            
            // Create entries for each IP address on this interface
            if !ipInterfaces.isEmpty {
                for ipInterface in ipInterfaces {
                    if let ipAddress = ipInterface.ipAddress {
                        let entry = ArpEntry(
                            ipAddress: ipAddress,
                            macAddress: macAddress,
                            interface: interfaceName,
                            status: "interface"
                        )
                        entries.append(entry)
                    }
                }
            } else {
                // Interface with MAC but no IP configured
                let entry = ArpEntry(
                    ipAddress: "N/A",
                    macAddress: macAddress,
                    interface: interfaceName,
                    status: "interface"
                )
                entries.append(entry)
            }
        }
        
        return entries
    }
    
    /// Gets network interface information using getifaddrs, including MAC addresses
    private func getNetworkInterfaces() throws -> [NetworkInterface] {
        var ifaddrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrs) == 0 else {
            throw ArpError.systemCallFailed("getifaddrs failed")
        }
        defer { freeifaddrs(ifaddrs) }
        
        var interfaces: [NetworkInterface] = []
        var current = ifaddrs
        
        while current != nil {
            defer { current = current?.pointee.ifa_next }
            
            guard let ifa = current?.pointee,
                  let name = ifa.ifa_name,
                  let addr = ifa.ifa_addr else { continue }
            
            let interfaceName = String(cString: name)
            let flags = ifa.ifa_flags
            
            // Skip inactive interfaces, but allow loopback for now (we'll filter later)
            guard (flags & UInt32(IFF_UP)) != 0 else { continue }
            
            var networkInterface: NetworkInterface?
            
            // Process different address families
            switch addr.pointee.sa_family {
            case UInt8(AF_INET), UInt8(AF_INET6):
                // IP addresses
                let ipAddress = parseSocketAddress(UnsafeMutablePointer(mutating: addr))
                networkInterface = NetworkInterface(
                    name: interfaceName,
                    family: addr.pointee.sa_family == UInt8(AF_INET) ? .ipv4 : .ipv6,
                    flags: flags,
                    ipAddress: ipAddress,
                    macAddress: nil
                )
                
            case UInt8(AF_LINK):
                // Link-layer addresses (MAC addresses)
                let macAddress = parseLinkLayerAddress(UnsafeMutablePointer(mutating: addr))
                networkInterface = NetworkInterface(
                    name: interfaceName,
                    family: .link,
                    flags: flags,
                    ipAddress: nil,
                    macAddress: macAddress
                )
                
            default:
                continue
            }
            
            if let interface = networkInterface {
                interfaces.append(interface)
            }
        }
        
        return interfaces
    }
    
    /// Gets neighbor entries for a specific interface using routing table access
    private func getNeighborEntriesForInterface(_ interface: NetworkInterface) throws -> [ArpEntry] {
        var entries: [ArpEntry] = []
        
        // Use sysctl to access routing table with neighbor discovery information
        let mib: [Int32] = [CTL_NET, PF_ROUTE, 0, interface.family == .ipv4 ? AF_INET : AF_INET6, NET_RT_FLAGS, RTF_LLINFO]
        
        var size = 0
        let result = mib.withUnsafeBufferPointer { mibPtr in
            sysctl(UnsafeMutablePointer(mutating: mibPtr.baseAddress), UInt32(mib.count), nil, &size, nil, 0)
        }
        guard result == 0 else {
            // Routing table access not available, return empty array
            return entries
        }
        
        guard size > 0 else {
            // No routing entries available
            return entries
        }
        
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 1)
        defer { buffer.deallocate() }
        
        let result2 = mib.withUnsafeBufferPointer { mibPtr in
            sysctl(UnsafeMutablePointer(mutating: mibPtr.baseAddress), UInt32(mib.count), buffer, &size, nil, 0)
        }
        guard result2 == 0 else {
            // Failed to read routing table data
            return entries
        }
        
        // Parse routing messages with error handling
        do {
            entries = try parseRoutingMessages(buffer: buffer, size: size, interface: interface)
        } catch {
            // If parsing fails, we'll continue without neighbor entries
            print("Debug: Failed to parse routing messages for \(interface.name): \(error)")
        }
        
        return entries
    }
    
    /// Parses routing messages to extract neighbor cache entries
    private func parseRoutingMessages(buffer: UnsafeMutableRawPointer, size: Int, interface: NetworkInterface) throws -> [ArpEntry] {
        var entries: [ArpEntry] = []
        var offset = 0
        
        while offset < size {
            // Ensure we don't read beyond the buffer
            guard offset + MemoryLayout<rt_msghdr>.size <= size else { break }
            
            let rtm = buffer.advanced(by: offset).assumingMemoryBound(to: rt_msghdr.self)
            let msgLen = Int(rtm.pointee.rtm_msglen)
            
            // Ensure message length is reasonable
            guard msgLen > 0 && msgLen >= MemoryLayout<rt_msghdr>.size && offset + msgLen <= size else { 
                break 
            }
            
            // Parse this routing message for neighbor information
            if let entry = parseRoutingMessage(rtm: rtm, interface: interface) {
                entries.append(entry)
            }
            
            offset += msgLen
        }
        
        return entries
    }
    
    /// Parses a single routing message to extract ARP entry information
    private func parseRoutingMessage(rtm: UnsafeMutablePointer<rt_msghdr>, interface: NetworkInterface) -> ArpEntry? {
        let addrs = UnsafeMutableRawPointer(rtm).advanced(by: MemoryLayout<rt_msghdr>.size)
        let flags = rtm.pointee.rtm_flags
        
        // Only process entries with link-layer info
        guard (flags & RTF_LLINFO) != 0 else { return nil }
        
        var ipAddress: String?
        var macAddress: String?
        var currentAddr = addrs
        let addrMask = rtm.pointee.rtm_addrs
        
        // Parse socket addresses based on the address mask
        for i in 0..<RTAX_MAX {
            let addrBit = 1 << i
            if (addrMask & Int32(addrBit)) == 0 { continue }
            
            let sa = currentAddr.assumingMemoryBound(to: sockaddr.self)
            let saLen = Int(sa.pointee.sa_len)
            
            // Ensure we don't read beyond bounds
            guard saLen > 0 && saLen >= MemoryLayout<sockaddr>.size else { break }
            
            switch Int32(i) {
            case RTAX_DST:
                // Destination address (IP address)
                ipAddress = parseSocketAddress(sa)
            case RTAX_GATEWAY:
                // Gateway address (MAC address for neighbor entries)
                macAddress = parseLinkLayerAddress(sa)
            default:
                break
            }
            
            // Move to next address (align to pointer boundary)
            let alignedLen = (saLen + 3) & ~3
            currentAddr = currentAddr.advanced(by: max(alignedLen, MemoryLayout<sockaddr>.size))
        }
        
        guard let ip = ipAddress, let mac = macAddress else { return nil }
        
        // Determine status based on flags
        let status: String
        if (flags & RTF_STATIC) != 0 {
            status = "permanent"
        } else if (flags & RTF_WASCLONED) != 0 {
            status = "active"
        } else {
            status = "reachable"
        }
        
        return ArpEntry(
            ipAddress: ip,
            macAddress: mac,
            interface: interface.name,
            status: status
        )
    }
    
    /// Parses a socket address to extract IP address string
    private func parseSocketAddress(_ sa: UnsafeMutablePointer<sockaddr>) -> String? {
        switch sa.pointee.sa_family {
        case UInt8(AF_INET):
            let sin = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var addr = sin.sin_addr
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
            return String(cString: buffer)
            
        case UInt8(AF_INET6):
            let sin6 = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
            var addr = sin6.sin6_addr
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &addr, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else { return nil }
            return String(cString: buffer)
            
        default:
            return nil
        }
    }
    
    /// Parses a link-layer address to extract MAC address string
    private func parseLinkLayerAddress(_ sa: UnsafeMutablePointer<sockaddr>) -> String? {
        guard sa.pointee.sa_family == UInt8(AF_LINK) else { return nil }
        
        // Cast to sockaddr_dl to access the structure properly
        let sdl = sa.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { $0.pointee }
        let addrLen = Int(sdl.sdl_alen)
        
        // Standard Ethernet MAC address should be 6 bytes
        guard addrLen == 6 else { return nil }
        
        // Calculate the offset to the link-layer address
        // It comes after the sockaddr_dl structure and the interface name
        let nameLen = Int(sdl.sdl_nlen)
        let baseOffset = MemoryLayout<sockaddr_dl>.size
        let lladdr = UnsafeMutableRawPointer(sa).advanced(by: baseOffset + nameLen)
        let macBytes = lladdr.assumingMemoryBound(to: UInt8.self)
        
        // Convert bytes to hex string
        var macParts: [String] = []
        for i in 0..<addrLen {
            macParts.append(String(format: "%02x", macBytes[i]))
        }
        
        return macParts.joined(separator: ":")
    }
    #endif
    
    #if !os(macOS)
    /// Retrieves basic interface information for iOS/iPadOS
    /// Note: iOS/iPadOS sandbox restrictions limit access to detailed ARP information
    private func getBasicInterfaceEntries() throws -> [ArpEntry] {
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