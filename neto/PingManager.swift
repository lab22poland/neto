//
//  PingManager.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Network

/// Manager class responsible for ping operations and network connectivity testing
final class PingManager {
    
    /// Performs a series of ping operations to the specified host
    /// - Parameters:
    ///   - host: The target host (IP address or domain name)
    ///   - count: Number of ping packets to send (default: 5)
    ///   - interval: Interval between pings in seconds (default: 1.0)
    ///   - onResult: Callback called for each ping result
    ///   - onComplete: Callback called when all pings are complete
    /// - Returns: A Task that can be cancelled
    func performPing(
        to host: String,
        count: Int = 5,
        interval: TimeInterval = 1.0,
        onResult: @escaping (PingResult) -> Void,
        onComplete: @escaping () -> Void
    ) -> Task<Void, Never> {
        return Task {
            await executePingSequence(
                host: host,
                count: count,
                interval: interval,
                onResult: onResult,
                onComplete: onComplete
            )
        }
    }
    
    /// Executes a sequence of ping operations
    private func executePingSequence(
        host: String,
        count: Int,
        interval: TimeInterval,
        onResult: @escaping (PingResult) -> Void,
        onComplete: @escaping () -> Void
    ) async {
        for sequenceNumber in 1...count {
            // Check if task was cancelled
            if Task.isCancelled {
                return
            }
            
            let startTime = Date()
            
            do {
                let isReachable = try await checkHostReachability(host)
                let endTime = Date()
                let responseTime = endTime.timeIntervalSince(startTime) * 1000 // Convert to milliseconds
                
                let result = PingResult(
                    id: UUID(),
                    sequenceNumber: sequenceNumber,
                    success: isReachable,
                    responseTime: responseTime,
                    message: isReachable 
                        ? String(format: "Reply from %@: time=%.2fms seq=%d", host, responseTime, sequenceNumber)
                        : String(format: "Request timeout seq=%d", sequenceNumber)
                )
                
                await MainActor.run {
                    onResult(result)
                }
                
            } catch {
                // Check if task was cancelled
                if Task.isCancelled {
                    return
                }
                
                let result = PingResult(
                    id: UUID(),
                    sequenceNumber: sequenceNumber,
                    success: false,
                    responseTime: 0,
                    message: String(format: "Error seq=%d: %@", sequenceNumber, error.localizedDescription)
                )
                
                await MainActor.run {
                    onResult(result)
                }
            }
            
            // Add delay between pings, but check for cancellation
            if sequenceNumber < count {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    // Task was cancelled during sleep
                    return
                }
            }
        }
        
        await MainActor.run {
            onComplete()
        }
    }
    
    /// Checks if a host is reachable using Network framework
    /// - Parameter host: The target host to check
    /// - Returns: Boolean indicating if the host is reachable
    /// - Throws: Network errors if connection fails for reasons other than unreachability
    private func checkHostReachability(_ host: String) async throws -> Bool {
        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { continuation in
                let queue = DispatchQueue(label: "ping.monitor")
                
                // Create endpoint based on host type
                let endpoint: NWEndpoint
                
                if let ipv4 = IPv4Address(host) {
                    endpoint = .hostPort(host: .ipv4(ipv4), port: 80)
                } else if let ipv6 = IPv6Address(host) {
                    endpoint = .hostPort(host: .ipv6(ipv6), port: 80)
                } else {
                    endpoint = .hostPort(host: .name(host, nil), port: 80)
                }
                
                // Use UDP for a more ping-like experience (lighter weight than TCP)
                let parameters = NWParameters.udp
                parameters.prohibitExpensivePaths = false
                parameters.prohibitConstrainedPaths = false
                
                let connection = NWConnection(to: endpoint, using: parameters)
                var hasCompleted = false
                let lock = NSLock()
                
                connection.stateUpdateHandler = { state in
                    lock.lock()
                    defer { lock.unlock() }
                    
                    guard !hasCompleted else { return }
                    
                    switch state {
                    case .ready:
                        hasCompleted = true
                        connection.cancel()
                        continuation.resume(returning: true)
                    case .failed(let error):
                        hasCompleted = true
                        connection.cancel()
                        // For network unreachable errors, treat as timeout rather than error
                        if let nwError = error as? NWError {
                            switch nwError {
                            case .dns(DNSServiceErrorType(kDNSServiceErr_NoSuchRecord)):
                                continuation.resume(returning: false)
                            case .posix(let posixError) where posixError == .ENETUNREACH:
                                continuation.resume(returning: false)
                            case .posix(let posixError) where posixError == .EHOSTUNREACH:
                                continuation.resume(returning: false)
                            case .posix(let posixError) where posixError == .ETIMEDOUT:
                                continuation.resume(returning: false)
                            default:
                                continuation.resume(throwing: error)
                            }
                        } else {
                            continuation.resume(throwing: error)
                        }
                    case .cancelled:
                        hasCompleted = true
                        continuation.resume(returning: false)
                    default:
                        break
                    }
                }
                
                connection.start(queue: queue)
                
                // Timeout after 5 seconds
                DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
                    lock.lock()
                    defer { lock.unlock() }
                    
                    guard !hasCompleted else { return }
                    hasCompleted = true
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
        } onCancel: {
            // This handler will be called when the task is cancelled
        }
    }
} 