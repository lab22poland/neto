//
//  PingManager.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation

/// Sends ICMP echo requests through SimplePing and reports one PingResult per packet
final class PingManager: NSObject {
    
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
    // All mutable state is touched only on the main actor (SimplePing delivers callbacks on the main queue).
    
    private var simplePing: SimplePing?
    private var pingStates: [UInt16: PingState] = [:]   // keyed by the ICMP sequence number SimplePing used
    private var displaySequence: [UInt16: Int] = [:]     // ICMP seq -> 1-based sequence shown to the caller
    private var currentConfig: PingConfig = .default
    private var onResult: ((PingResult) -> Void)?
    private var pingTask: Task<Void, Never>?
    private var sendingIndex = 0
    private var runtimeError: Error?
    private var startContinuation: CheckedContinuation<Error?, Never>?
    
    // MARK: - Public Methods
    
    /// Pings the host with ICMP echo requests
    /// - Parameters:
    ///   - host: The target host (IP address or domain name)
    ///   - config: Packet count, interval, per-packet timeout and payload size
    ///   - onResult: Called on the main actor for each reply, timeout or error
    ///   - onComplete: Called exactly once when the run ends, including after cancellation
    /// - Returns: A Task that can be cancelled
    func performPing(
        to host: String,
        config: PingConfig = .default,
        onResult: @escaping (PingResult) -> Void,
        onComplete: @escaping () -> Void
    ) -> Task<Void, Never> {
        // Runs share this manager's state, so a new run waits until the previous (cancelled) one has finished.
        let previousTask = pingTask
        previousTask?.cancel()
        let task = Task { @MainActor [weak self] in
            await previousTask?.value
            guard let self else { onComplete(); return }
            await self.executePingSequence(host: host, config: config, onResult: onResult)
            self.finish()
            onComplete()
        }
        pingTask = task
        return task
    }
    
    /// Stops the current ping operation; onComplete is still called once, no further results are delivered.
    func stopPing() {
        pingTask?.cancel()
    }
    
    // MARK: - Private Methods
    
    @MainActor
    private func executePingSequence(host: String, config: PingConfig, onResult: @escaping (PingResult) -> Void) async {
        guard !Task.isCancelled, config.count > 0 else { return }
        
        currentConfig = config
        self.onResult = onResult
        pingStates.removeAll()
        displaySequence.removeAll()
        runtimeError = nil
        
        let pinger = SimplePing(hostName: host, identifier: UInt16.random(in: 1...UInt16.max), delegate: self)
        simplePing = pinger
        
        // Wait for didStart / didFail instead of a fixed 1 s sleep.
        let startError: Error? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                startContinuation = continuation
                pinger.start()
            }
        } onCancel: {
            Task { @MainActor in self.resumeStart(with: CancellationError()) }
        }
        if Task.isCancelled { return }
        if let startError {
            deliver(PingResult(id: UUID(), sequenceNumber: 1, success: false, responseTime: 0,
                               message: "Failed to start ping: \(startError.localizedDescription)"))
            return
        }
        
        for i in 0..<config.count {
            if Task.isCancelled { return }
            let sendTime = Date()
            sendingIndex = i + 1
            if let seq = pinger.sendPingWithPayload(createPayload(size: config.payloadSize)) {
                displaySequence[seq] = i + 1
                pingStates[seq] = PingState(startTime: sendTime, sequenceNumber: seq, sentTime: sendTime)
            } else if let runtimeError {
                deliver(PingResult(id: UUID(), sequenceNumber: i + 1, success: false, responseTime: 0,
                                   message: "Ping failed seq=\(i + 1): \(runtimeError.localizedDescription)"))
            }
            // Expire anything overdue so results keep their order.
            expireTimedOutPings()
            if i < config.count - 1 {
                do { try await Task.sleep(nanoseconds: UInt64(config.interval * 1_000_000_000)) } catch { return }
            }
        }
        await waitForCompletion()
    }
    
    @MainActor
    private func waitForCompletion() async {
        while !Task.isCancelled, pingStates.values.contains(where: { !$0.isComplete }) {
            expireTimedOutPings()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
    
    @MainActor
    private func expireTimedOutPings() {
        for seq in pingStates.keys.sorted(by: { displaySequence[$0, default: 0] < displaySequence[$1, default: 0] }) {
            if let state = pingStates[seq], !state.isComplete,
               Date().timeIntervalSince(state.startTime) >= currentConfig.timeout {
                handlePingTimeout(sequenceNumber: seq)
            }
        }
    }
    
    @MainActor
    private func handlePingTimeout(sequenceNumber: UInt16) {
        guard var state = pingStates[sequenceNumber], !state.isComplete else { return }
        state.isComplete = true
        pingStates[sequenceNumber] = state
        let display = displaySequence[sequenceNumber, default: Int(sequenceNumber) + 1]
        deliver(PingResult(id: UUID(), sequenceNumber: display, success: false, responseTime: 0,
                           message: String(format: "Request timeout seq=%d", display)))
    }
    
    @MainActor
    private func deliver(_ result: PingResult) {
        guard !Task.isCancelled, pingTask?.isCancelled != true else { return }
        onResult?(result)
    }
    
    @MainActor
    private func resumeStart(with error: Error?) {
        startContinuation?.resume(returning: error)
        startContinuation = nil
    }
    
    @MainActor
    private func finish() {
        resumeStart(with: CancellationError())
        simplePing?.stop()
        simplePing = nil
        pingStates.removeAll()
        displaySequence.removeAll()
        onResult = nil
    }
    
    private func createPayload(size: Int) -> Data {
        Data((0..<size).map { UInt8($0 % 256) })
    }
}

// MARK: - SimplePing Delegate (called on the main queue)

extension PingManager: SimplePing.Delegate {
    
    func simplePing(_ pinger: SimplePing, didStartWithAddress address: Data) {
        MainActor.assumeIsolated { resumeStart(with: nil) }
    }
    
    func simplePing(_ pinger: SimplePing, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            if startContinuation != nil { resumeStart(with: error); return }
            runtimeError = error
            // Fail outstanding pings right away (in order) instead of letting them time out later.
            for seq in pingStates.keys.sorted(by: { displaySequence[$0, default: 0] < displaySequence[$1, default: 0] }) {
                guard var state = pingStates[seq], !state.isComplete else { continue }
                state.isComplete = true
                pingStates[seq] = state
                let display = displaySequence[seq, default: Int(seq) + 1]
                deliver(PingResult(id: UUID(), sequenceNumber: display, success: false, responseTime: 0,
                                   message: "Ping failed seq=\(display): \(error.localizedDescription)"))
            }
        }
    }
    
    func simplePing(_ pinger: SimplePing, didSendPacket packet: Data, sequenceNumber: UInt16) {}
    
    func simplePing(_ pinger: SimplePing, didFailToSendPacket packet: Data, sequenceNumber: UInt16, error: Error) {
        MainActor.assumeIsolated {
            let display = sendingIndex
            deliver(PingResult(id: UUID(), sequenceNumber: display, success: false, responseTime: 0,
                               message: String(format: "Failed to send packet seq=%d: %@", display, error.localizedDescription)))
        }
    }
    
    func simplePing(_ pinger: SimplePing, didReceivePingResponsePacket packet: Data, sequenceNumber: UInt16) {
        MainActor.assumeIsolated {
            guard pinger === simplePing, var state = pingStates[sequenceNumber], !state.isComplete else { return }
            let now = Date()
            state.receivedTime = now
            state.isComplete = true
            pingStates[sequenceNumber] = state
            let responseTime = now.timeIntervalSince(state.sentTime ?? state.startTime) * 1000
            let display = displaySequence[sequenceNumber, default: Int(sequenceNumber) + 1]
            deliver(PingResult(id: UUID(), sequenceNumber: display, success: true, responseTime: responseTime,
                               message: String(format: "Reply from %@: time=%.2fms seq=%d", pinger.targetHostName, responseTime, display)))
        }
    }
    
    func simplePing(_ pinger: SimplePing, didReceiveUnexpectedPacket packet: Data) {}
}
