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
    
    /// Status of the entry: "permanent", "expired" or "expires in …"
    let status: String
    
    /// Link type as printed by `arp` ("ethernet", "bridge", …)
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
    
    /// Formats the entry to match 'arp -an' command output
    var commandLineFormat: String {
        let flags = [isScoped ? "ifscope" : nil, isPermanent ? "permanent" : nil].compactMap { $0 }
        return (["? (\(ipAddress)) at \(macAddress) on \(interface)"] + flags + ["[\(linkType)]"]).joined(separator: " ")
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
    
    init(entries: [ArpEntry]) {
        self.allEntries = entries
        self.entriesByInterface = Dictionary(grouping: entries) { $0.interface }
        self.timestamp = Date()
    }
    
    /// Returns all entries formatted as command-line output (like 'arp -an')
    var commandLineOutput: String {
        return allEntries
            .sorted { $0.addressSortKey.lexicographicallyPrecedes($1.addressSortKey) || ($0.addressSortKey == $1.addressSortKey && $0.interface < $1.interface) }
            .map { $0.commandLineFormat }
            .joined(separator: "\n")
    }
    
    /// Returns entries for a specific interface formatted as command-line output
    func commandLineOutput(for interface: String) -> String {
        let entries = interface == "All" ? allEntries : (entriesByInterface[interface] ?? [])
        return entries
            .sorted { $0.addressSortKey.lexicographicallyPrecedes($1.addressSortKey) }
            .map { $0.commandLineFormat }
            .joined(separator: "\n")
    }
} 