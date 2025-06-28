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
    
    /// Status of the ARP entry (permanent, incomplete, or ttl value)
    let status: String
    
    /// Indicates if the entry is permanent
    var isPermanent: Bool {
        status.lowercased().contains("permanent")
    }
    
    /// Human-readable description of the entry
    var description: String {
        "\(ipAddress) -> \(macAddress) (\(interface)) [\(status)]"
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
} 