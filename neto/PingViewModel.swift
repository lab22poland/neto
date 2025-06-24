//
//  PingViewModel.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Combine

/// ViewModel for the Ping functionality, coordinating between PingView and PingManager
@MainActor
final class PingViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var targetHost: String = ""
    @Published var pingResults: [PingResult] = []
    @Published var isPinging: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private let pingManager = PingManager()
    private var pingTask: Task<Void, Never>?
    
    // MARK: - Public Methods
    
    /// Starts a ping operation to the target host
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
        
        // Start ping operation
        pingTask = pingManager.performPing(
            to: host,
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
        pingTask = nil
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
    }
} 