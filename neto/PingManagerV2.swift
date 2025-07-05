//
//  PingManagerV2.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Combine

/// Enhanced PingManager using SimplePing for proper ICMP echo request/response
/// This implementation provides more accurate ping functionality compared to the Network framework approach
final class PingManagerV2: NSObject {
    
    // MARK: - Types
    
    /// Configuration for ping operations
    struct PingConfig {
        let count: Int
        let interval: TimeInterval
        let timeout: TimeInterval
        let payloadSize: Int
        
        static let `default` = PingConfig(
            count: 5,
            interval: 1.0,
            timeout: 5.0,
            payloadSize: 56
        )
    }
    
    /// Internal state for tracking ping operations
    private struct PingState {
        let startTime: Date
        let sequenceNumber: UInt16
        var sentTime: Date?
        var receivedTime: Date?
        var isComplete: Bool = false
    }
    
    // MARK: - Properties
    
    private var simplePing: SimplePing?
    private var pingStates: [UInt16: PingState] = [:]
    private var currentConfig: PingConfig = .default
    private var onResult: ((PingResult) -> Void)?
    private var onComplete: (() -> Void)?
    private var pingTask: Task<Void, Never>?
    private var isRunning = false
    
    // MARK: - Public Methods
    
    /// Performs a series of ping operations to the specified host using ICMP
    /// - Parameters:
    ///   - host: The target host (IP address or domain name)
    ///   - config: Configuration for the ping operation (optional)
    ///   - onResult: Callback called for each ping result
    ///   - onComplete: Callback called when all pings are complete
    /// - Returns: A Task that can be cancelled
    func performPing(
        to host: String,
        config: PingConfig = .default,
        onResult: @escaping (PingResult) -> Void,
        onComplete: @escaping () -> Void
    ) -> Task<Void, Never> {
        return Task {
            await executePingSequence(
                host: host,
                config: config,
                onResult: onResult,
                onComplete: onComplete
            )
        }
    }
    
    /// Stops the current ping operation
    func stopPing() {
        pingTask?.cancel()
        simplePing?.stop()
        isRunning = false
        pingStates.removeAll()
    }
    
    // MARK: - Private Methods
    
    /// Executes a sequence of ping operations
    private func executePingSequence(
        host: String,
        config: PingConfig,
        onResult: @escaping (PingResult) -> Void,
        onComplete: @escaping () -> Void
    ) async {
        // Check if task was cancelled
        if Task.isCancelled {
            return
        }
        
        self.currentConfig = config
        self.onResult = onResult
        self.onComplete = onComplete
        self.isRunning = true
        
        // Create SimplePing instance
        let identifier = UInt16.random(in: 1...65535)
        simplePing = SimplePing(hostName: host, identifier: identifier, delegate: self)
        
        // Start the ping operation
        simplePing?.start()
        
        // Wait for the ping to start
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Send ping packets
        for i in 0..<config.count {
            // Check if task was cancelled
            if Task.isCancelled {
                break
            }
            
            let sequenceNumber = UInt16(i + 1)
            let startTime = Date()
            
            // Create ping state
            pingStates[sequenceNumber] = PingState(
                startTime: startTime,
                sequenceNumber: sequenceNumber
            )
            
            // Send the ping
            simplePing?.sendPingWithPayload(createPayload(size: config.payloadSize))
            
            // Wait for interval (except for the last ping)
            if i < config.count - 1 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(config.interval * 1_000_000_000))
                } catch {
                    // Task was cancelled during sleep
                    break
                }
            }
        }
        
        // Wait for all pings to complete or timeout
        await waitForCompletion()
        
        // Clean up
        simplePing?.stop()
        simplePing = nil
        isRunning = false
        
        await MainActor.run {
            onComplete()
        }
    }
    
    /// Waits for all ping operations to complete
    private func waitForCompletion() async {
        let timeout = currentConfig.timeout
        let startTime = Date()
        
        while isRunning && Date().timeIntervalSince(startTime) < timeout {
            // Check if all pings are complete
            let incompletePings = pingStates.values.filter { !$0.isComplete }
            if incompletePings.isEmpty {
                break
            }
            
            // Check for timeouts
            for (sequenceNumber, state) in pingStates {
                if !state.isComplete && Date().timeIntervalSince(state.startTime) > timeout {
                    handlePingTimeout(sequenceNumber: sequenceNumber)
                }
            }
            
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        // Handle any remaining incomplete pings as timeouts
        for (sequenceNumber, state) in pingStates {
            if !state.isComplete {
                handlePingTimeout(sequenceNumber: sequenceNumber)
            }
        }
    }
    
    /// Handles a ping timeout
    private func handlePingTimeout(sequenceNumber: UInt16) {
        guard var state = pingStates[sequenceNumber], !state.isComplete else { return }
        
        state.isComplete = true
        pingStates[sequenceNumber] = state
        
        let result = PingResult(
            id: UUID(),
            sequenceNumber: Int(sequenceNumber),
            success: false,
            responseTime: 0,
            message: String(format: "Request timeout seq=%d", sequenceNumber)
        )
        
        Task { @MainActor in
            onResult?(result)
        }
    }
    
    /// Creates a payload for the ICMP packet
    private func createPayload(size: Int) -> Data {
        var payload = Data()
        for i in 0..<size {
            payload.append(UInt8(i % 256))
        }
        return payload
    }
}

// MARK: - SimplePing Delegate

extension PingManagerV2: SimplePing.Delegate {
    
    func simplePing(_ pinger: SimplePing, didStartWithAddress address: Data) {
        // Ping started successfully
    }
    
    func simplePing(_ pinger: SimplePing, didFailWithError error: Error) {
        let result = PingResult(
            id: UUID(),
            sequenceNumber: 1,
            success: false,
            responseTime: 0,
            message: "Failed to start ping: \(error.localizedDescription)"
        )
        
        Task { @MainActor in
            onResult?(result)
            onComplete?()
        }
    }
    
    func simplePing(_ pinger: SimplePing, didSendPacket packet: Data, sequenceNumber: UInt16) {
        // Update ping state with sent time
        if var state = pingStates[sequenceNumber] {
            state.sentTime = Date()
            pingStates[sequenceNumber] = state
        }
    }
    
    func simplePing(_ pinger: SimplePing, didFailToSendPacket packet: Data, sequenceNumber: UInt16, error: Error) {
        let result = PingResult(
            id: UUID(),
            sequenceNumber: Int(sequenceNumber),
            success: false,
            responseTime: 0,
            message: String(format: "Failed to send packet seq=%d: %@", sequenceNumber, error.localizedDescription)
        )
        
        Task { @MainActor in
            onResult?(result)
        }
    }
    
    func simplePing(_ pinger: SimplePing, didReceivePingResponsePacket packet: Data, sequenceNumber: UInt16) {
        guard var state = pingStates[sequenceNumber] else { return }
        
        state.receivedTime = Date()
        state.isComplete = true
        pingStates[sequenceNumber] = state
        
        // Calculate response time
        let responseTime: Double
        if let sentTime = state.sentTime {
            responseTime = state.receivedTime!.timeIntervalSince(sentTime) * 1000
        } else {
            responseTime = state.receivedTime!.timeIntervalSince(state.startTime) * 1000
        }
        
        let result = PingResult(
            id: UUID(),
            sequenceNumber: Int(sequenceNumber),
            success: true,
            responseTime: responseTime,
            message: String(format: "Reply from %@: time=%.2fms seq=%d", pinger.targetHostName, responseTime, sequenceNumber)
        )
        
        Task { @MainActor in
            onResult?(result)
        }
    }
    
    func simplePing(_ pinger: SimplePing, didReceiveUnexpectedPacket packet: Data) {
        // Ignore unexpected packets for now
        // Could be used for traceroute functionality in the future
    }
} 