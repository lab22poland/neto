//
//  TracerouteManager.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Network

/// Manager class responsible for traceroute operations and path discovery
final class TracerouteManager {
    
    /// Performs a traceroute operation to the specified host
    /// - Parameters:
    ///   - host: The target host (IP address or domain name)
    ///   - maxHops: Maximum number of hops to attempt (default: 30)
    ///   - timeout: Timeout for each hop in seconds (default: 5.0)
    ///   - onResult: Callback called for each hop result
    ///   - onComplete: Callback called when traceroute is complete
    /// - Returns: A Task that can be cancelled
    func performTraceroute(
        to host: String,
        maxHops: Int = 30,
        timeout: TimeInterval = 5.0,
        onResult: @escaping (TracerouteResult) -> Void,
        onComplete: @escaping () -> Void
    ) -> Task<Void, Never> {
        return Task {
            await executeTracerouteSequence(
                host: host,
                maxHops: maxHops,
                timeout: timeout,
                onResult: onResult,
                onComplete: onComplete
            )
        }
    }
    
    /// Executes the traceroute sequence
    private func executeTracerouteSequence(
        host: String,
        maxHops: Int,
        timeout: TimeInterval,
        onResult: @escaping (TracerouteResult) -> Void,
        onComplete: @escaping () -> Void
    ) async {
        var reachedDestination = false
        
        for hopNumber in 1...maxHops {
            // Check if task was cancelled
            if Task.isCancelled {
                return
            }
            
            let startTime = Date()
            
            do {
                let hopResult = try await probeHop(
                    host: host,
                    hopNumber: hopNumber,
                    timeout: timeout
                )
                
                let endTime = Date()
                let responseTime = endTime.timeIntervalSince(startTime) * 1000 // Convert to milliseconds
                
                let result = TracerouteResult(
                    hopNumber: hopNumber,
                    success: hopResult.success,
                    ipAddress: hopResult.ipAddress,
                    hostname: hopResult.hostname,
                    responseTime: responseTime,
                    message: hopResult.message,
                    isDestination: hopResult.isDestination
                )
                
                await MainActor.run {
                    onResult(result)
                }
                
                // If we reached the destination, stop the traceroute
                if hopResult.isDestination {
                    reachedDestination = true
                    break
                }
                
            } catch {
                // Check if task was cancelled
                if Task.isCancelled {
                    return
                }
                
                let result = TracerouteResult(
                    hopNumber: hopNumber,
                    success: false,
                    responseTime: 0,
                    message: String(format: "Hop %d: %@", hopNumber, error.localizedDescription),
                    isDestination: false
                )
                
                await MainActor.run {
                    onResult(result)
                }
            }
            
            // Add delay between hops, but check for cancellation
            if hopNumber < maxHops && !reachedDestination {
                do {
                    try await Task.sleep(nanoseconds: UInt64(0.1 * 1_000_000_000)) // 100ms delay
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
    
    /// Probes a specific hop in the route
    private func probeHop(
        host: String,
        hopNumber: Int,
        timeout: TimeInterval
    ) async throws -> (success: Bool, ipAddress: String?, hostname: String?, message: String, isDestination: Bool) {
        
        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { continuation in
                let queue = DispatchQueue(label: "traceroute.probe.\(hopNumber)")
                
                // Create endpoint based on host type
                let endpoint: NWEndpoint
                
                if let ipv4 = IPv4Address(host) {
                    endpoint = .hostPort(host: .ipv4(ipv4), port: 80)
                } else if let ipv6 = IPv6Address(host) {
                    endpoint = .hostPort(host: .ipv6(ipv6), port: 80)
                } else {
                    endpoint = .hostPort(host: .name(host, nil), port: 80)
                }
                
                // Use TCP for better hop discovery
                let parameters = NWParameters.tcp
                parameters.prohibitExpensivePaths = false
                parameters.prohibitConstrainedPaths = false
                
                // Simulate TTL by using shorter timeouts for earlier hops
                // This is an approximation since we can't set TTL directly
                let adjustedTimeout = min(timeout, Double(hopNumber) * 0.2 + 1.0)
                
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
                        
                        // Extract IP address from the connection
                        let ipAddress = self.extractIPAddress(from: connection)
                        let hostname = self.extractHostname(from: connection)
                        
                        // If we can connect, this might be the destination or a responsive intermediate hop
                        let isDestination = self.isTargetHost(ipAddress: ipAddress, hostname: hostname, target: host)
                        let message = self.formatHopMessage(
                            hopNumber: hopNumber,
                            ipAddress: ipAddress,
                            hostname: hostname,
                            isDestination: isDestination
                        )
                        
                        continuation.resume(returning: (
                            success: true,
                            ipAddress: ipAddress,
                            hostname: hostname,
                            message: message,
                            isDestination: isDestination
                        ))
                        
                    case .failed(let error):
                        hasCompleted = true
                        connection.cancel()
                        
                        // For traceroute, connection failures can still provide useful information
                        let ipAddress = self.extractIPAddress(from: connection)
                        let hostname = self.extractHostname(from: connection)
                        
                        if let ipAddress = ipAddress {
                            // We got an IP address but connection failed - this is a valid hop
                            let message = self.formatHopMessage(
                                hopNumber: hopNumber,
                                ipAddress: ipAddress,
                                hostname: hostname,
                                isDestination: false
                            )
                            continuation.resume(returning: (
                                success: true,
                                ipAddress: ipAddress,
                                hostname: hostname,
                                message: message,
                                isDestination: false
                            ))
                        } else {
                            // Handle different types of network errors
                            if let nwError = error as? NWError {
                                switch nwError {
                                case .dns(_):
                                    continuation.resume(returning: (
                                        success: false,
                                        ipAddress: nil,
                                        hostname: nil,
                                        message: String(format: "Hop %d: DNS resolution failed", hopNumber),
                                        isDestination: false
                                    ))
                                case .posix(let posixError) where posixError == .ETIMEDOUT:
                                    continuation.resume(returning: (
                                        success: false,
                                        ipAddress: nil,
                                        hostname: nil,
                                        message: String(format: "Hop %d: * * * Request timed out", hopNumber),
                                        isDestination: false
                                    ))
                                default:
                                    continuation.resume(returning: (
                                        success: false,
                                        ipAddress: nil,
                                        hostname: nil,
                                        message: String(format: "Hop %d: * * * No response", hopNumber),
                                        isDestination: false
                                    ))
                                }
                            } else {
                                continuation.resume(throwing: error)
                            }
                        }
                        
                    case .cancelled:
                        hasCompleted = true
                        continuation.resume(returning: (
                            success: false,
                            ipAddress: nil,
                            hostname: nil,
                            message: String(format: "Hop %d: * * * Request cancelled", hopNumber),
                            isDestination: false
                        ))
                    default:
                        break
                    }
                }
                
                connection.start(queue: queue)
                
                // Timeout for this specific hop
                DispatchQueue.global().asyncAfter(deadline: .now() + adjustedTimeout) {
                    lock.lock()
                    defer { lock.unlock() }
                    
                    guard !hasCompleted else { return }
                    hasCompleted = true
                    connection.cancel()
                    continuation.resume(returning: (
                        success: false,
                        ipAddress: nil,
                        hostname: nil,
                        message: String(format: "Hop %d: * * * Request timed out", hopNumber),
                        isDestination: false
                    ))
                }
            }
        } onCancel: {
            // This handler will be called when the task is cancelled
        }
    }
    
    /// Extracts IP address from a network connection
    private func extractIPAddress(from connection: NWConnection) -> String? {
        // This is a simplified extraction - in a real implementation,
        // you might need more sophisticated IP address extraction
        guard case let .hostPort(host, _) = connection.endpoint else { return nil }
        
        switch host {
        case .ipv4(let ipv4):
            return ipv4.debugDescription
        case .ipv6(let ipv6):
            return ipv6.debugDescription
        case .name(let name, _):
            return name
        @unknown default:
            return nil
        }
    }
    
    /// Extracts hostname from a network connection
    private func extractHostname(from connection: NWConnection) -> String? {
        guard case let .hostPort(host, _) = connection.endpoint else { return nil }
        
        switch host {
        case .name(let name, _):
            return name
        default:
            return nil
        }
    }
    
    /// Determines if the given IP/hostname matches the target host
    private func isTargetHost(ipAddress: String?, hostname: String?, target: String) -> Bool {
        if let ipAddress = ipAddress, ipAddress == target {
            return true
        }
        if let hostname = hostname, hostname == target {
            return true
        }
        return false
    }
    
    /// Formats the hop message for display
    private func formatHopMessage(
        hopNumber: Int,
        ipAddress: String?,
        hostname: String?,
        isDestination: Bool
    ) -> String {
        var components: [String] = []
        
        if let hostname = hostname, hostname != ipAddress {
            components.append(hostname)
        }
        
        if let ipAddress = ipAddress {
            components.append("(\(ipAddress))")
        }
        
        let hostInfo = components.isEmpty ? "* * *" : components.joined(separator: " ")
        
        if isDestination {
            return String(format: "Hop %d: %@ [DESTINATION REACHED]", hopNumber, hostInfo)
        } else {
            return String(format: "Hop %d: %@", hopNumber, hostInfo)
        }
    }
} 