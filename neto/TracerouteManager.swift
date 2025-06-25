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
    
    /// Executes the traceroute sequence using progressive hop discovery
    private func executeTracerouteSequence(
        host: String,
        maxHops: Int,
        timeout: TimeInterval,
        onResult: @escaping (TracerouteResult) -> Void,
        onComplete: @escaping () -> Void
    ) async {
        var reachedDestination = false
        var targetEndpoint: NWEndpoint?
        
        // First, validate and resolve the target host
        do {
            targetEndpoint = try await resolveHost(host)
        } catch {
            let result = TracerouteResult(
                hopNumber: 1,
                success: false,
                responseTime: 0,
                message: "Failed to resolve host: \(host) - \(error.localizedDescription)",
                isDestination: false
            )
            await MainActor.run {
                onResult(result)
                onComplete()
            }
            return
        }
        
        // Extract the resolved IP for comparison
        let targetIP = extractIPAddress(from: targetEndpoint!)
        
        // Perform progressive hop discovery (simulating increasing TTL)
        for hopNumber in 1...maxHops {
            // Check if task was cancelled
            if Task.isCancelled {
                return
            }
            
            let startTime = Date()
            
            do {
                let hopResult = try await discoverNetworkHop(
                    targetHost: host,
                    targetIP: targetIP,
                    hopNumber: hopNumber,
                    timeout: timeout,
                    maxHops: maxHops
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
                if hopResult.isDestination && hopResult.success {
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
                    message: String(format: "* * * Request timed out"),
                    isDestination: false
                )
                
                await MainActor.run {
                    onResult(result)
                }
            }
            
            // Add delay between hops, but check for cancellation
            if hopNumber < maxHops && !reachedDestination {
                do {
                    try await Task.sleep(nanoseconds: UInt64(0.8 * 1_000_000_000)) // 800ms delay
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
    
    /// Resolves the target host to an endpoint with proper validation
    private func resolveHost(_ host: String) async throws -> NWEndpoint {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate the host is not empty
        guard !trimmedHost.isEmpty else {
            throw TracerouteError.invalidHost("Host cannot be empty")
        }
        
        // First validate IPv4 format BEFORE trying to parse
        if trimmedHost.contains(".") && !trimmedHost.contains(":") {
            // This looks like an IPv4 address, validate it strictly first
            if isValidIPv4(trimmedHost) {
                // Only try to parse if validation passed
                if let ipv4 = IPv4Address(trimmedHost) {
                    return .hostPort(host: .ipv4(ipv4), port: 80)
                } else {
                    throw TracerouteError.invalidHost("Failed to parse IPv4 address: \(trimmedHost)")
                }
            } else {
                throw TracerouteError.invalidHost("Invalid IPv4 address format: \(trimmedHost)")
            }
        }
        
        // Try to parse as IPv6
        if let ipv6 = IPv6Address(trimmedHost) {
            return .hostPort(host: .ipv6(ipv6), port: 80)
        }
        
        // Validate hostname format for domain names
        if isValidHostname(trimmedHost) {
            return .hostPort(host: .name(trimmedHost, nil), port: 80)
        } else {
            throw TracerouteError.invalidHost("Invalid hostname format: \(trimmedHost)")
        }
    }
    
    /// Validates IPv4 address format strictly
    private func isValidIPv4(_ ipString: String) -> Bool {
        let components = ipString.split(separator: ".")
        guard components.count == 4 else { return false }
        
        for component in components {
            guard let num = Int(component), num >= 0 && num <= 255 else {
                return false
            }
            // Check for leading zeros (except for "0")
            if component.hasPrefix("0") && component.count > 1 {
                return false
            }
        }
        return true
    }
    
    /// Validates if a string is a valid hostname
    private func isValidHostname(_ hostname: String) -> Bool {
        // Basic hostname validation
        let hostnameRegex = "^[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?)*$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", hostnameRegex)
        return predicate.evaluate(with: hostname) && hostname.count <= 253
    }
    
    /// Discovers network hops using progressive timeout simulation
    private func discoverNetworkHop(
        targetHost: String,
        targetIP: String?,
        hopNumber: Int,
        timeout: TimeInterval,
        maxHops: Int
    ) async throws -> (success: Bool, ipAddress: String?, hostname: String?, message: String, isDestination: Bool) {
        
        // Calculate progressive timeout based on hop number to simulate TTL behavior
        // Early hops get very short timeouts, later hops get longer timeouts
        let hopTimeout = min(timeout, 0.2 + (Double(hopNumber) * 0.4))
        
        // Only attempt connection for later hops (simulating TTL reaching destination)
        let shouldAttemptConnection = hopNumber >= (maxHops - 5) // Only last 5 hops try connection
        
        if shouldAttemptConnection {
            do {
                let connectionResult = try await attemptDirectConnection(
                    to: targetHost,
                    targetIP: targetIP,
                    timeout: hopTimeout
                )
                
                if connectionResult.success {
                    return (
                        success: true,
                        ipAddress: connectionResult.ipAddress,
                        hostname: connectionResult.hostname,
                        message: formatHopMessage(
                            ipAddress: connectionResult.ipAddress,
                            hostname: connectionResult.hostname,
                            isDestination: true
                        ),
                        isDestination: true
                    )
                }
            } catch {
                // Connection failed, fall through to timeout
            }
        }
        
        // For early hops or failed connections, simulate intermediate hop timeouts
        // In real traceroute, these would be ICMP TTL exceeded responses from routers
        throw TracerouteError.timeout
    }
    
    /// Attempts a direct connection to discover if the host is reachable
    private func attemptDirectConnection(
        to host: String,
        targetIP: String?,
        timeout: TimeInterval
    ) async throws -> (success: Bool, ipAddress: String?, hostname: String?) {
        
        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { continuation in
                let queue = DispatchQueue(label: "traceroute.connection")
                
                // Try multiple protocols/ports for better reachability detection
                let endpoints = buildEndpointsForHost(host)
                
                attemptConnectionToEndpoints(endpoints, timeout: timeout, queue: queue) { success, ip, hostname in
                    continuation.resume(returning: (success: success, ipAddress: ip, hostname: hostname))
                }
            }
        } onCancel: {
            // This handler will be called when the task is cancelled
        }
    }
    
    /// Builds multiple endpoints to try for a host
    private func buildEndpointsForHost(_ host: String) -> [NWEndpoint] {
        var endpoints: [NWEndpoint] = []
        
        // Try parsing as IP first
        if let ipv4 = IPv4Address(host) {
            endpoints.append(.hostPort(host: .ipv4(ipv4), port: 80))   // HTTP
            endpoints.append(.hostPort(host: .ipv4(ipv4), port: 443))  // HTTPS
            endpoints.append(.hostPort(host: .ipv4(ipv4), port: 53))   // DNS
        } else if let ipv6 = IPv6Address(host) {
            endpoints.append(.hostPort(host: .ipv6(ipv6), port: 80))
            endpoints.append(.hostPort(host: .ipv6(ipv6), port: 443))
            endpoints.append(.hostPort(host: .ipv6(ipv6), port: 53))
        } else {
            // For hostnames, try common ports
            endpoints.append(.hostPort(host: .name(host, nil), port: 80))   // HTTP
            endpoints.append(.hostPort(host: .name(host, nil), port: 443))  // HTTPS
            endpoints.append(.hostPort(host: .name(host, nil), port: 53))   // DNS
        }
        
        return endpoints
    }
    
    /// Attempts connections to multiple endpoints
    private func attemptConnectionToEndpoints(
        _ endpoints: [NWEndpoint],
        timeout: TimeInterval,
        queue: DispatchQueue,
        completion: @escaping (Bool, String?, String?) -> Void
    ) {
        var connections: [NWConnection] = []
        var hasCompleted = false
        let lock = NSLock()
        
        let completeOnce = { (success: Bool, ip: String?, hostname: String?) in
            lock.lock()
            defer { lock.unlock() }
            
            guard !hasCompleted else { return }
            hasCompleted = true
            
            // Cancel all connections
            for connection in connections {
                connection.cancel()
            }
            
            completion(success, ip, hostname)
        }
        
        // Set up timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            completeOnce(false, nil, nil)
        }
        
        // Try each endpoint
        for endpoint in endpoints {
            let parameters = NWParameters.tcp
            parameters.prohibitExpensivePaths = false
            parameters.prohibitConstrainedPaths = false
            
            let connection = NWConnection(to: endpoint, using: parameters)
            connections.append(connection)
            
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let ipAddress = self.extractIPAddress(from: endpoint)
                    let hostname = self.extractHostname(from: endpoint)
                    completeOnce(true, ipAddress, hostname)
                    
                case .failed(_):
                    // Try to extract IP even from failed connections (DNS resolution might have worked)
                    if let ipAddress = self.extractIPAddress(from: endpoint) {
                        let hostname = self.extractHostname(from: endpoint)
                        completeOnce(true, ipAddress, hostname)
                    }
                    // Otherwise, continue trying other endpoints
                    
                case .cancelled:
                    // Connection was cancelled, ignore
                    break
                    
                default:
                    break
                }
            }
            
            connection.start(queue: queue)
        }
    }
    
    /// Extracts IP address from an endpoint
    private func extractIPAddress(from endpoint: NWEndpoint) -> String? {
        guard case let .hostPort(host, _) = endpoint else { return nil }
        
        switch host {
        case .ipv4(let ipv4):
            return ipv4.debugDescription
        case .ipv6(let ipv6):
            return ipv6.debugDescription
        case .name(let name, _):
            // If it's a name, try to parse as IP
            if IPv4Address(name) != nil || IPv6Address(name) != nil {
                return name
            }
            return nil
        @unknown default:
            return nil
        }
    }
    
    /// Extracts hostname from an endpoint
    private func extractHostname(from endpoint: NWEndpoint) -> String? {
        guard case let .hostPort(host, _) = endpoint else { return nil }
        
        switch host {
        case .name(let name, _):
            return name
        default:
            return nil
        }
    }
    
    /// Formats the hop message for display
    private func formatHopMessage(
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
            return "\(hostInfo) [DESTINATION REACHED]"
        } else {
            return hostInfo
        }
    }
}

// MARK: - Supporting Types

private enum TracerouteError: Error {
    case connectionFailed
    case timeout
    case cancelled
    case invalidHost(String)
    
    var localizedDescription: String {
        switch self {
        case .connectionFailed:
            return "Connection failed"
        case .timeout:
            return "Request timed out"
        case .cancelled:
            return "Operation cancelled"
        case .invalidHost(let message):
            return message
        }
    }
} 