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
import Darwin

/// Manager class responsible for ARP table operations across all platforms
/// 
/// This implementation provides cross-platform access to network neighbor information
/// using BSD system APIs that are available on both macOS and iOS/iPadOS:
/// - Uses `getifaddrs()` to enumerate network interfaces
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
    
    // Simplified sockaddr_dl structure for cross-platform compatibility
    private struct sockaddr_dl_simple {
        let sdl_len: UInt8
        let sdl_family: UInt8
        let sdl_index: UInt16
        let sdl_type: UInt8
        let sdl_nlen: UInt8
        let sdl_alen: UInt8
        let sdl_slen: UInt8
        // data would follow...
    }
    
    // Simplified routing message header (subset of rt_msghdr)
    private struct RoutingMsgHeader {
        let msglen: UInt16
        let version: UInt8
        let type: UInt8
        let addrs: Int32
        let flags: Int32
        let index: UInt16
        let _pad1: UInt16
        let errno: Int32
        let use: Int32
        let inits: UInt32
        // Additional fields would follow in the real rt_msghdr
    }
    
    /// Helper struct to represent network interface information
    private struct NetworkInterface {
        let name: String
        let family: AddressFamily
        let flags: UInt32
        let ipAddress: String?
        
        enum AddressFamily {
            case ipv4, ipv6
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
    /// - Returns neighbor cache entries when available, or basic interface information as fallback
    func getArpTable() async throws -> ArpResult {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let entries = try self.getNeighborCacheEntries()
                    let result = ArpResult(entries: entries)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Core Implementation
    
    /// Retrieves neighbor cache entries using BSD sysctl APIs
    private func getNeighborCacheEntries() throws -> [ArpEntry] {
        var entries: [ArpEntry] = []
        
        // Get network interfaces first
        let interfaces = try getNetworkInterfaces()
        
        // For each interface, try to get neighbor information
        for interface in interfaces {
            do {
                let interfaceEntries = try getNeighborEntriesForInterface(interface)
                entries.append(contentsOf: interfaceEntries)
            } catch {
                // Continue with other interfaces if one fails
                print("Warning: Failed to get neighbor entries for interface \(interface.name): \(error)")
                continue
            }
        }
        
        // If we couldn't get any entries from routing table, at least return interface information
        if entries.isEmpty {
            entries = createBasicInterfaceEntries(interfaces)
        }
        
        return entries
    }
    
    /// Creates basic entries showing network interfaces (fallback when routing table access fails)
    private func createBasicInterfaceEntries(_ interfaces: [NetworkInterface]) -> [ArpEntry] {
        var entries: [ArpEntry] = []
        
        for interface in interfaces {
            // Create a basic entry showing the interface is available
            // This isn't a real ARP entry, but provides useful network information
            let entry = ArpEntry(
                ipAddress: interface.ipAddress ?? (interface.family == .ipv4 ? "0.0.0.0" : "::"),
                macAddress: "N/A (Interface Info)",
                interface: interface.name,
                status: "interface-available"
            )
            entries.append(entry)
        }
        
        return entries
    }
    
    /// Gets network interface information using getifaddrs
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
            
            // Skip loopback and inactive interfaces
            let flags = ifa.ifa_flags
            if (flags & UInt32(IFF_LOOPBACK)) != 0 || (flags & UInt32(IFF_UP)) == 0 {
                continue
            }
            
            // Process IPv4 and IPv6 addresses
            if addr.pointee.sa_family == AF_INET || addr.pointee.sa_family == AF_INET6 {
                // Extract the IP address from this interface
                let ipAddress = parseSocketAddress(UnsafeMutablePointer(mutating: addr))
                
                let networkInterface = NetworkInterface(
                    name: interfaceName,
                    family: addr.pointee.sa_family == AF_INET ? .ipv4 : .ipv6,
                    flags: flags,
                    ipAddress: ipAddress
                )
                
                if !interfaces.contains(where: { $0.name == interfaceName && $0.family == networkInterface.family }) {
                    interfaces.append(networkInterface)
                }
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
            // If parsing fails, we'll fall back to basic interface information
            print("Warning: Failed to parse routing messages for \(interface.name): \(error)")
        }
        
        return entries
    }
    
    /// Parses routing messages to extract neighbor cache entries
    private func parseRoutingMessages(buffer: UnsafeMutableRawPointer, size: Int, interface: NetworkInterface) throws -> [ArpEntry] {
        var entries: [ArpEntry] = []
        var offset = 0
        
        while offset < size {
            // Ensure we don't read beyond the buffer
            guard offset + MemoryLayout<RoutingMsgHeader>.size <= size else { break }
            
            let rtm = buffer.advanced(by: offset).assumingMemoryBound(to: RoutingMsgHeader.self)
            let msgLen = Int(rtm.pointee.msglen)
            
            // Ensure message length is reasonable
            guard msgLen > 0 && msgLen >= MemoryLayout<RoutingMsgHeader>.size && offset + msgLen <= size else { 
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
    private func parseRoutingMessage(rtm: UnsafeMutablePointer<RoutingMsgHeader>, interface: NetworkInterface) -> ArpEntry? {
        let addrs = UnsafeMutableRawPointer(rtm).advanced(by: MemoryLayout<RoutingMsgHeader>.size)
        let flags = rtm.pointee.flags
        
        // Only process entries with link-layer info
        guard (flags & RTF_LLINFO) != 0 else { return nil }
        
        var ipAddress: String?
        var macAddress: String?
        var currentAddr = addrs
        let addrMask = rtm.pointee.addrs
        
        // Parse socket addresses based on the address mask
        for i in 0..<RTAX_MAX {
            let addrBit = 1 << i
            if (addrMask & Int32(addrBit)) == 0 { continue }
            
            let sa = currentAddr.assumingMemoryBound(to: sockaddr.self)
            let saLen = Int(sa.pointee.sa_len)
            
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
            status = "incomplete"
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
        
        let sdl = sa.withMemoryRebound(to: sockaddr_dl_simple.self, capacity: 1) { $0.pointee }
        let addrLen = Int(sdl.sdl_alen)
        
        guard addrLen == 6 else { return nil } // Standard Ethernet MAC address length
        
        let lladdr = UnsafeMutableRawPointer(sa).advanced(by: Int(sdl.sdl_nlen) + MemoryLayout<sockaddr_dl_simple>.size)
        let macBytes = lladdr.assumingMemoryBound(to: UInt8.self)
        
        var macParts: [String] = []
        for i in 0..<addrLen {
            macParts.append(String(format: "%02x", macBytes[i]))
        }
        
        return macParts.joined(separator: ":")
    }
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