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
    
    init(
        id: UUID = UUID(),
        hopNumber: Int,
        success: Bool,
        ipAddress: String? = nil,
        hostname: String? = nil,
        responseTime: Double,
        message: String,
        isDestination: Bool = false,
        probeTimes: [Double?] = []
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
    }
    
    /// Probe times as shown by traceroute, e.g. "1.23 ms  4.56 ms  *"
    var formattedProbeTimes: String {
        probeTimes.map { $0.map { String(format: "%.2f ms", $0) } ?? "*" }.joined(separator: "  ")
    }
} 