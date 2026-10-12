//
//  ArpResult.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation

/// Represents a single ARP table entry
struct ArpEntry: Identifiable, Hashable {
    /// Unique identifier for the ARP entry
    let id = UUID()
    
    /// IP address of the host
    let ipAddress: String
    
    /// MAC address (hardware address) of the host
    let macAddress: String
    
    /// Network interface name (en0, en4, lo0, etc.)
    let interface: String
    
    /// Status of the entry: "permanent", "expired", "expires in …" or "unknown"; IPv6 entries are prefixed with the ND state ("stale, …")
    let status: String
    
    /// Link type as printed by `arp` ("ethernet", "bridge", …); empty when `arp` prints none
    var linkType: String = "ethernet"
    
    /// Whether the entry is bound to its interface (RTF_IFSCOPE, shown as "ifscope")
    var isScoped: Bool = true
    
    /// Indicates if the entry is permanent
    var isPermanent: Bool {
        status.lowercased().contains("permanent")
    }
    
    /// Human-readable description of the entry
    var description: String {
        "\(ipAddress) -> \(macAddress) (\(interface)) [\(status)]"
    }
    
    /// Orders addresses numerically: IPv4 before IPv6, then byte by byte
    var addressSortKey: [UInt8] {
        var v4 = in_addr(), v6 = in6_addr()
        if inet_pton(AF_INET, ipAddress, &v4) == 1 {
            return [4] + withUnsafeBytes(of: &v4) { Array($0) }
        }
        if inet_pton(AF_INET6, ipAddress, &v6) == 1 {
            return [6] + withUnsafeBytes(of: &v6) { Array($0) }
        }
        return [255] + Array(ipAddress.utf8)
    }
}

/// Container for ARP table results grouped by interface
struct ArpResult {
    /// All ARP entries
    let allEntries: [ArpEntry]
    
    /// ARP entries grouped by interface name
    let entriesByInterface: [String: [ArpEntry]]
    
    /// List of available interface names
    var interfaces: [String] {
        Array(entriesByInterface.keys).sorted()
    }
    
    /// Timestamp when the ARP table was retrieved
    let timestamp: Date
    
    /// Entries are sorted numerically by address (IPv4 before IPv6), then by interface
    init(entries: [ArpEntry]) {
        let sorted = entries
            .map { (key: $0.addressSortKey, entry: $0) }
            .sorted { $0.key.lexicographicallyPrecedes($1.key) || ($0.key == $1.key && $0.entry.interface < $1.entry.interface) }
            .map(\.entry)
        self.allEntries = sorted
        self.entriesByInterface = Dictionary(grouping: sorted) { $0.interface }
        self.timestamp = Date()
    }
}
