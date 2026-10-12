//
//  TracerouteResult.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation

/// Represents the result of a single traceroute hop
struct TracerouteResult: Identifiable {
    /// Unique identifier for the traceroute result
    let id: UUID
    
    /// Hop number in the route (TTL value)
    let hopNumber: Int
    
    /// Whether the hop responded successfully
    let success: Bool
    
    /// IP address of the responding hop (if available)
    let ipAddress: String?
    
    /// Hostname of the responding hop (if resolved)
    let hostname: String?
    
    /// Response time in milliseconds
    let responseTime: Double
    
    /// Human-readable message describing the result
    let message: String
    
    /// Whether this hop is the final destination
    let isDestination: Bool
    
    /// Round-trip time of each probe sent to this hop in milliseconds, nil for a probe without reply
    let probeTimes: [Double?]
    
    /// traceroute annotation printed after each probe's time (e.g. "!H" for host unreachable), nil for none
    let probeAnnotations: [String?]
    
    /// Address that answered each probe (nil = no reply); differs between probes when paths are load-balanced (ECMP)
    let probeAddresses: [String?]
    
    init(
        id: UUID = UUID(),
        hopNumber: Int,
        success: Bool,
        ipAddress: String? = nil,
        hostname: String? = nil,
        responseTime: Double,
        message: String,
        isDestination: Bool = false,
        probeTimes: [Double?] = [],
        probeAnnotations: [String?] = [],
        probeAddresses: [String?] = []
    ) {
        self.id = id
        self.hopNumber = hopNumber
        self.success = success
        self.ipAddress = ipAddress
        self.hostname = hostname
        self.responseTime = responseTime
        self.message = message
        self.isDestination = isDestination
        self.probeTimes = probeTimes
        self.probeAnnotations = probeAnnotations
        self.probeAddresses = probeAddresses
    }
    
    /// Probe columns as printed by traceroute, in probe order: "1.234 ms  4.567 ms *" or "* * *". When a probe was
    /// answered by another address than the previous answer (load-balanced paths), that address precedes its time.
    var formattedProbeTimes: String {
        var shownAddress = ipAddress
        var text = ""
        for (index, time) in probeTimes.enumerated() {
            guard let time else {
                text += " *"
                continue
            }
            text += "  "
            if index < probeAddresses.count, let address = probeAddresses[index], address != shownAddress {
                text += "(\(address)) "
                shownAddress = address
            }
            text += String(format: "%.3f ms", time)
            if index < probeAnnotations.count, let annotation = probeAnnotations[index] {
                text += " " + annotation
            }
        }
        return String(text.drop { $0 == " " })
    }

    /// The hop as one traceroute line without the hop number: router, then the probe columns
    var line: String {
        let probes = formattedProbeTimes
        if message.isEmpty { return probes }
        return probes.isEmpty ? message : message + "  " + probes
    }
}
