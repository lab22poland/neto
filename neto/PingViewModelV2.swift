//
//  PingViewModelV2.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Combine

/// Enhanced ViewModel for the Ping functionality using SimplePing implementation
/// Provides more accurate ping results with proper ICMP echo request/response handling
@MainActor
final class PingViewModelV2: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var targetHost: String = ""
    @Published var pingResults: [PingResult] = []
    @Published var isPinging: Bool = false
    @Published var errorMessage: String?
    @Published var pingCount: Int = 5
    @Published var pingInterval: Double = 1.0
    @Published var pingTimeout: Double = 5.0
    @Published var payloadSize: Int = 56
    
    // MARK: - Private Properties
    
    private let pingManager = PingManagerV2()
    private var pingTask: Task<Void, Never>?
    
    // MARK: - Public Methods
    
    /// Starts a ping operation to the target host using ICMP
    func startPing() {
        let host = targetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !host.isEmpty else {
            errorMessage = "Please enter a valid host address"
            return
        }
        
        guard !isPinging else {
            return
        }
        
        // Reset state
        isPinging = true
        errorMessage = nil
        pingResults.removeAll()
        
        // Create ping configuration
        let config = PingManagerV2.PingConfig(
            count: pingCount,
            interval: pingInterval,
            timeout: pingTimeout,
            payloadSize: payloadSize
        )
        
        // Start ping operation
        pingTask = pingManager.performPing(
            to: host,
            config: config,
            onResult: { [weak self] result in
                self?.handlePingResult(result)
            },
            onComplete: { [weak self] in
                self?.handlePingComplete()
            }
        )
    }
    
    /// Stops the current ping operation
    func stopPing() {
        pingTask?.cancel()
        pingManager.stopPing()
        isPinging = false
        
        // Add a final result to show the ping was stopped
        if !pingResults.isEmpty {
            let result = PingResult(
                id: UUID(),
                sequenceNumber: pingResults.count + 1,
                success: false,
                responseTime: 0,
                message: "Ping stopped by user"
            )
            pingResults.append(result)
        }
    }
    
    /// Checks if the target host input is valid
    var isTargetHostValid: Bool {
        !targetHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Gets ping statistics
    var pingStatistics: PingStatistics {
        let successfulPings = pingResults.filter { $0.success }
        let failedPings = pingResults.filter { !$0.success }
        
        let totalPings = pingResults.count
        let successCount = successfulPings.count
        let failureCount = failedPings.count
        
        let responseTimes = successfulPings.map { $0.responseTime }
        let minTime = responseTimes.min() ?? 0
        let maxTime = responseTimes.max() ?? 0
        let avgTime = responseTimes.isEmpty ? 0 : responseTimes.reduce(0, +) / Double(responseTimes.count)
        
        let packetLoss = totalPings > 0 ? Double(failureCount) / Double(totalPings) * 100 : 0
        
        return PingStatistics(
            totalPings: totalPings,
            successCount: successCount,
            failureCount: failureCount,
            packetLoss: packetLoss,
            minResponseTime: minTime,
            maxResponseTime: maxTime,
            avgResponseTime: avgTime
        )
    }
    
    // MARK: - Private Methods
    
    /// Handles individual ping results
    private func handlePingResult(_ result: PingResult) {
        pingResults.append(result)
    }
    
    /// Handles completion of all ping operations
    private func handlePingComplete() {
        isPinging = false
        pingTask = nil
    }
    
    // MARK: - Deinitializer
    
    deinit {
        pingTask?.cancel()
        pingManager.stopPing()
    }
}

// MARK: - Ping Statistics

/// Statistics for a ping operation
struct PingStatistics {
    let totalPings: Int
    let successCount: Int
    let failureCount: Int
    let packetLoss: Double
    let minResponseTime: Double
    let maxResponseTime: Double
    let avgResponseTime: Double
    
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