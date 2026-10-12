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
    
    /// Where a sent echo request stands
    private enum PacketState {
        case pending, timedOut, replied, failed
    }
    
    /// A sent echo request
    private struct SentPacket {
        /// 1-based sequence number shown to the caller
        let display: Int
        /// Send time on the SimplePing.now() clock (nanoseconds)
        let sentAt: UInt64
        var state: PacketState = .pending
    }
    
    // MARK: - Properties
    // All mutable state is touched only on the main actor (SimplePing delivers callbacks on the main queue).
    
    private var simplePing: SimplePing?
    private var packets: [UInt16: SentPacket] = [:]   // keyed by the ICMP sequence number SimplePing used
    private var currentConfig: PingConfig = .default
    private var statistics: PingStatistics?
    private var onResult: ((PingResult) -> Void)?
    private var onStatistics: ((PingStatistics) -> Void)?
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
    ///   - onStatistics: Called on the main actor whenever the statistics change: once the host is resolved
    ///     (nothing transmitted yet), after every send attempt and every reply. Nothing is called after a stop,
    ///     so packets still in flight then stay counted as transmitted but not received, like ping's Ctrl-C summary.
    ///   - onComplete: Called exactly once when the run ends, including after cancellation
    /// - Returns: A Task that can be cancelled
    func performPing(
        to host: String,
        config: PingConfig = .default,
        onResult: @escaping (PingResult) -> Void,
        onStatistics: ((PingStatistics) -> Void)? = nil,
        onComplete: @escaping () -> Void
    ) -> Task<Void, Never> {
        // Runs share this manager's state, so a new run waits until the previous (cancelled) one has finished.
        let previousTask = pingTask
        previousTask?.cancel()
        let task = Task { @MainActor [weak self] in
            await previousTask?.value
            guard let self else { onComplete(); return }
            await self.executePingSequence(host: host, config: config, onResult: onResult, onStatistics: onStatistics)
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
    
    /// Whether a reply is late, i.e. outside the per-packet timeout. The same rule (`ping -W`: triptime > waittime)
    /// applies whether the reply or the expiry check comes first, so the outcome does not depend on scheduling.
    /// - Parameters:
    ///   - roundTripTime: Round-trip time in seconds
    ///   - timeout: Per-packet timeout in seconds
    static func isLate(roundTripTime: TimeInterval, timeout: TimeInterval) -> Bool {
        roundTripTime > timeout
    }
    
    // MARK: - Private Methods
    
    @MainActor
    private func executePingSequence(host: String, config: PingConfig,
                                     onResult: @escaping (PingResult) -> Void,
                                     onStatistics: ((PingStatistics) -> Void)?) async {
        guard !Task.isCancelled, config.count > 0 else { return }
        
        currentConfig = config
        self.onResult = onResult
        self.onStatistics = onStatistics
        packets.removeAll()
        statistics = nil
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
            deliver(PingResult(id: UUID(), sequenceNumber: 1, kind: .startFailure, responseTime: 0,
                               message: "Failed to start ping: \(startError.localizedDescription)"))
            return
        }
        publishStatistics()
        
        var lastSentAt = SimplePing.now()
        for i in 0..<config.count {
            if Task.isCancelled { return }
            sendingIndex = i + 1
            let sentAt = SimplePing.now()
            lastSentAt = sentAt
            if let seq = pinger.sendPingWithPayload(createPayload(size: config.payloadSize)) {
                packets[seq] = SentPacket(display: i + 1, sentAt: sentAt)
                statistics?.recordTransmitted()
                publishStatistics()
            } else if let runtimeError {
                // The socket is gone, so nothing was handed to sendto(): an error row, not a transmitted packet
                deliver(PingResult(id: UUID(), sequenceNumber: i + 1, kind: .error, responseTime: 0,
                                   message: "Ping failed seq=\(i + 1): \(runtimeError.localizedDescription)"))
            }
            // Expire anything overdue so results keep their order.
            expireTimedOutPings()
            if i < config.count - 1 {
                do { try await Task.sleep(nanoseconds: UInt64(config.interval * 1_000_000_000)) } catch { return }
            }
        }
        await waitForCompletion(lastSentAt: lastSentAt)
    }
    
    /// Waits after the last send like ping: until every transmitted packet is answered (late replies included),
    /// but at most one interval plus the timeout (ping waits its interval, then its -W wait time, then exits).
    @MainActor
    private func waitForCompletion(lastSentAt: UInt64) async {
        let deadline = lastSentAt + UInt64((currentConfig.interval + currentConfig.timeout) * 1_000_000_000)
        while !Task.isCancelled,
              packets.values.contains(where: { $0.state == .pending || $0.state == .timedOut }),
              SimplePing.now() < deadline {
            expireTimedOutPings()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        // Packets that are still pending past the deadline get their timeout row now
        if !Task.isCancelled { expireTimedOutPings() }
    }
    
    @MainActor
    private func expireTimedOutPings() {
        let now = SimplePing.now()
        for seq in packets.keys.sorted(by: { packets[$0]!.display < packets[$1]!.display }) {
            guard var packet = packets[seq], packet.state == .pending, now > packet.sentAt,
                  Self.isLate(roundTripTime: Double(now - packet.sentAt) / 1_000_000_000, timeout: currentConfig.timeout) else { continue }
            packet.state = .timedOut
            packets[seq] = packet
            deliverTimeout(display: packet.display)
        }
    }
    
    @MainActor
    private func deliverTimeout(display: Int) {
        deliver(PingResult(id: UUID(), sequenceNumber: display, kind: .timeout, responseTime: 0,
                           message: String(format: "Request timeout seq=%d", display)))
    }
    
    @MainActor
    private func deliver(_ result: PingResult) {
        guard !Task.isCancelled, pingTask?.isCancelled != true else { return }
        onResult?(result)
    }
    
    @MainActor
    private func publishStatistics() {
        guard let statistics, !Task.isCancelled, pingTask?.isCancelled != true else { return }
        onStatistics?(statistics)
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
        packets.removeAll()
        statistics = nil
        onResult = nil
        onStatistics = nil
    }
    
    private func createPayload(size: Int) -> Data {
        Data((0..<size).map { UInt8($0 % 256) })
    }
}

// MARK: - SimplePing Delegate (called on the main queue)

extension PingManager: SimplePing.Delegate {
    
    func simplePing(_ pinger: SimplePing, didStartWithAddress address: Data) {
        MainActor.assumeIsolated {
            guard pinger === simplePing else { return }
            statistics = PingStatistics(host: pinger.targetHostName,
                                        address: TracerouteManager.numericHost(address) ?? pinger.targetHostName)
            resumeStart(with: nil)
        }
    }
    
    func simplePing(_ pinger: SimplePing, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            if startContinuation != nil { resumeStart(with: error); return }
            runtimeError = error
            // Fail outstanding pings right away (in order) instead of letting them time out later.
            for seq in packets.keys.sorted(by: { packets[$0]!.display < packets[$1]!.display }) {
                guard var packet = packets[seq], packet.state == .pending else { continue }
                packet.state = .failed
                packets[seq] = packet
                deliver(PingResult(id: UUID(), sequenceNumber: packet.display, kind: .error, responseTime: 0,
                                   message: "Ping failed seq=\(packet.display): \(error.localizedDescription)"))
            }
        }
    }
    
    func simplePing(_ pinger: SimplePing, didSendPacket packet: Data, sequenceNumber: UInt16) {}
    
    func simplePing(_ pinger: SimplePing, didFailToSendPacket packet: Data, sequenceNumber: UInt16, error: Error) {
        MainActor.assumeIsolated {
            // sendto() was called, so ping counts the packet as transmitted (verified: `ping 0.0.0.1` reports
            // "sendto: No route to host" and still "N packets transmitted"); it can never be answered.
            let display = sendingIndex
            statistics?.recordTransmitted()
            publishStatistics()
            deliver(PingResult(id: UUID(), sequenceNumber: display, kind: .error, responseTime: 0,
                               message: String(format: "Failed to send packet seq=%d: %@", display, error.localizedDescription)))
        }
    }
    
    func simplePing(_ pinger: SimplePing, didReceivePingResponsePacket packet: Data, sequenceNumber: UInt16,
                    from address: Data, receivedAt: UInt64) {
        MainActor.assumeIsolated {
            // Like ping, replies are matched by identifier and sequence number only, not by sender
            // (a broadcast ping counts replies from other hosts), and the sender is what the row shows.
            guard pinger === simplePing, var sent = packets[sequenceNumber],
                  sent.state == .pending || sent.state == .timedOut else { return }
            let roundTrip = receivedAt > sent.sentAt ? Double(receivedAt - sent.sentAt) / 1_000_000_000 : 0
            let late = Self.isLate(roundTripTime: roundTrip, timeout: currentConfig.timeout)
            let wasTimedOut = sent.state == .timedOut
            sent.state = .replied
            packets[sequenceNumber] = sent
            let responseTime = roundTrip * 1000
            statistics?.recordReply(roundTripTime: responseTime, late: late)
            publishStatistics()
            if late {
                // `ping -W` prints nothing for a late reply but counts it in the statistics; the row stays a timeout.
                if !wasTimedOut { deliverTimeout(display: sent.display) }
            } else {
                // Classified by the kernel receive time, so a reply within the timeout is a reply even if the
                // expiry check already showed a timeout row (only when the main queue is late); then both rows appear.
                let sender = TracerouteManager.numericHost(address) ?? pinger.targetHostName
                deliver(PingResult(id: UUID(), sequenceNumber: sent.display, kind: .reply, responseTime: responseTime,
                                   message: String(format: "Reply from %@: time=%.2fms seq=%d", sender, responseTime, sent.display)))
            }
        }
    }
    
    func simplePing(_ pinger: SimplePing, didReceiveUnexpectedPacket packet: Data) {}
}
