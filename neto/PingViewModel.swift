//
//  PingViewModel.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Combine

/// ViewModel for the Ping tool, coordinating between PingView and PingManager (ICMP via SimplePing)
/// Provides more accurate ping results with proper ICMP echo request/response handling
@MainActor
final class PingViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var targetHost: String = ""
    @Published var pingResults: [PingResult] = []
    /// Statistics of the current or last run, nil before the host is resolved (and after a failed start or Clear)
    @Published var statistics: PingStatistics?
    @Published var isPinging: Bool = false
    @Published var errorMessage: String?
    @Published var pingCount: Int = 5
    @Published var pingInterval: Double = 1.0
    @Published var pingTimeout: Double = 5.0
    @Published var payloadSize: Int = 56
    
    // MARK: - Private Properties
    
    private let pingManager = PingManager()
    private var pingTask: Task<Void, Never>?
    /// Identifies the current run, so a late completion of a stopped run cannot reset a newer one
    private var currentRunID: UUID?
    
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
        statistics = nil
        
        // Create ping configuration
        let config = PingManager.PingConfig(
            count: pingCount,
            interval: pingInterval,
            timeout: pingTimeout,
            payloadSize: payloadSize
        )
        
        let runID = UUID()
        currentRunID = runID
        
        // Start ping operation
        pingTask = pingManager.performPing(
            to: host,
            config: config,
            onResult: { [weak self] result in
                guard self?.currentRunID == runID else { return }
                self?.handlePingResult(result)
            },
            onStatistics: { [weak self] statistics in
                guard self?.currentRunID == runID else { return }
                self?.statistics = statistics
            },
            onComplete: { [weak self] in
                guard self?.currentRunID == runID else { return }
                self?.handlePingComplete()
            }
        )
    }
    
    /// Stops the current ping operation. The statistics keep what was sent so far; packets still
    /// in flight count as lost, like the summary ping prints on Ctrl-C.
    func stopPing() {
        guard isPinging else { return }
        pingTask?.cancel()
        pingManager.stopPing()
        currentRunID = nil
        isPinging = false
        pingResults.append(PingResult(id: UUID(), sequenceNumber: pingResults.count + 1, kind: .stopped,
                                      responseTime: 0, message: "Ping stopped by user"))
    }
    
    /// Removes the result rows and the statistics
    func clearResults() {
        pingResults.removeAll()
        statistics = nil
    }
    
    /// Checks if the target host input is valid
    var isTargetHostValid: Bool {
        !targetHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Private Methods
    
    /// Handles individual ping results; a failed start is an error, not a result row
    private func handlePingResult(_ result: PingResult) {
        if result.kind == .startFailure {
            errorMessage = result.message
        } else {
            pingResults.append(result)
        }
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
