//
//  PingResult.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation

/// One row of the ping output: a reply, a timeout or an error. Statistics are kept separately in PingStatistics,
/// because not every packet has a row (a late reply, packets in flight at Stop) and not every row is a packet.
struct PingResult: Identifiable {
    /// What the row reports
    enum Kind {
        /// An echo reply within the timeout
        case reply
        /// No reply within the timeout (a reply arriving later still counts as received in the statistics, like `ping -W`)
        case timeout
        /// The packet could not be sent or the socket failed
        case error
        /// The run could not start (e.g. the host does not resolve); nothing was sent
        case startFailure
        /// The user stopped the run; not a packet
        case stopped
    }
    
    /// Unique identifier for the ping result
    let id: UUID
    
    /// Sequence number of the ping in the series (1-based)
    let sequenceNumber: Int
    
    /// What the row reports
    let kind: Kind
    
    /// Response time in milliseconds
    let responseTime: Double
    
    /// Human-readable message describing the result
    let message: String
    
    /// Whether the row is an echo reply within the timeout
    var success: Bool { kind == .reply }
}

/// Run statistics with the semantics of /sbin/ping's summary ("N packets transmitted, M packets received, X% packet loss")
struct PingStatistics: Equatable {
    /// The host as entered
    let host: String
    /// The resolved address that is pinged
    let address: String
    /// Echo requests handed to sendto(), including failed attempts (ping counts those as transmitted too)
    private(set) var transmitted = 0
    /// Echo requests answered while the run was going, including late replies
    private(set) var received = 0
    /// Replies that arrived after the timeout ("packets out of wait time" in `ping -W`)
    private(set) var late = 0
    /// Round-trip times of all received replies in milliseconds
    private(set) var roundTripTimes: [Double] = []
    
    init(host: String, address: String) {
        self.host = host
        self.address = address
    }
    
    /// Counts one send attempt
    mutating func recordTransmitted() {
        transmitted += 1
    }
    
    /// Counts one reply; late replies count as received like in `ping -W`, and their RTT is included
    mutating func recordReply(roundTripTime: Double, late isLate: Bool) {
        received += 1
        if isLate { late += 1 }
        roundTripTimes.append(roundTripTime)
    }
    
    /// Packet loss in percent: (transmitted - received) / transmitted, as ping computes it
    var packetLoss: Double {
        transmitted > 0 ? Double(transmitted - received) / Double(transmitted) * 100 : 0
    }
    
    var minResponseTime: Double { roundTripTimes.min() ?? 0 }
    var maxResponseTime: Double { roundTripTimes.max() ?? 0 }
    var avgResponseTime: Double { roundTripTimes.isEmpty ? 0 : roundTripTimes.reduce(0, +) / Double(roundTripTimes.count) }
    
    /// Formatted packet loss percentage
    var formattedPacketLoss: String {
        String(format: "%.1f%%", packetLoss)
    }
    
    /// Formatted minimum response time
    var formattedMinTime: String {
        String(format: "%.2fms", minResponseTime)
    }
    
    /// Formatted maximum response time
    var formattedMaxTime: String {
        String(format: "%.2fms", maxResponseTime)
    }
    
    /// Formatted average response time
    var formattedAvgTime: String {
        String(format: "%.2fms", avgResponseTime)
    }
}
