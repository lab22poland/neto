//
//  WhoisManager.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Network

/// Manager class responsible for WHOIS operations and domain information lookup
final class WhoisManager {
    
    /// Performs a WHOIS lookup for the specified domain or IP address
    /// - Parameters:
    ///   - domain: The target domain name or IP address
    ///   - onResult: Callback called when the WHOIS result is available
    /// - Returns: A Task that can be cancelled
    func performWhois(
        for domain: String,
        onResult: @escaping (WhoisResult) -> Void
    ) -> Task<Void, Never> {
        return Task {
            await executeWhoisLookup(
                domain: domain,
                onResult: onResult
            )
        }
    }
    
    /// Executes a WHOIS lookup operation
    private func executeWhoisLookup(
        domain: String,
        onResult: @escaping (WhoisResult) -> Void
    ) async {
        let startTime = Date()
        let cleanDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        do {
            // Check if task was cancelled
            if Task.isCancelled {
                return
            }
            
            let whoisServer = await determineWhoisServer(for: cleanDomain)
            let whoisData = try await queryWhoisServer(server: whoisServer, domain: cleanDomain)
            let endTime = Date()
            let responseTime = endTime.timeIntervalSince(startTime) * 1000 // Convert to milliseconds
            
            let parsedResult = parseWhoisResponse(whoisData, for: cleanDomain)
            
            let result = WhoisResult(
                domain: cleanDomain,
                success: true,
                rawResponse: whoisData,
                registrar: parsedResult.registrar,
                registrationDate: parsedResult.registrationDate,
                expirationDate: parsedResult.expirationDate,
                nameServers: parsedResult.nameServers,
                whoisServer: whoisServer,
                statusMessage: "WHOIS lookup successful",
                responseTime: responseTime
            )
            
            await MainActor.run {
                onResult(result)
            }
            
        } catch {
            // Check if task was cancelled
            if Task.isCancelled {
                return
            }
            
            let endTime = Date()
            let responseTime = endTime.timeIntervalSince(startTime) * 1000
            
            let result = WhoisResult(
                domain: cleanDomain,
                success: false,
                statusMessage: "WHOIS lookup failed: \(error.localizedDescription)",
                responseTime: responseTime
            )
            
            await MainActor.run {
                onResult(result)
            }
        }
    }
    
    /// Determines the appropriate WHOIS server for a given domain
    private func determineWhoisServer(for domain: String) async -> String {
        // Check if it's an IP address
        if IPv4Address(domain) != nil || IPv6Address(domain) != nil {
            return "whois.arin.net" // Default for IP addresses
        }
        
        // Extract TLD from domain
        let components = domain.components(separatedBy: ".")
        guard let tld = components.last else {
            return "whois.internic.net" // Default fallback
        }
        
        // Common TLD to WHOIS server mappings
        let whoisServers: [String: String] = [
            "com": "whois.verisign-grs.com",
            "net": "whois.verisign-grs.com",
            "org": "whois.pir.org",
            "edu": "whois.educause.edu",
            "gov": "whois.dotgov.gov",
            "mil": "whois.nic.mil",
            "int": "whois.iana.org",
            "uk": "whois.nominet.uk",
            "de": "whois.denic.de",
            "fr": "whois.afnic.fr",
            "jp": "whois.jprs.jp",
            "au": "whois.auda.org.au",
            "ca": "whois.cira.ca",
            "ru": "whois.tcinet.ru",
            "cn": "whois.cnnic.cn",
            "in": "whois.registry.in",
            "br": "whois.registro.br",
            "pl": "whois.dns.pl",
            "io": "whois.nic.io",
            "me": "whois.nic.me"
        ]
        
        return whoisServers[tld] ?? "whois.internic.net"
    }
    
    /// Queries a WHOIS server for domain information
    private func queryWhoisServer(server: String, domain: String) async throws -> String {
        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { continuation in
                let queue = DispatchQueue(label: "whois.query")
                
                let endpoint = NWEndpoint.hostPort(host: .name(server, nil), port: 43)
                let parameters = NWParameters.tcp
                parameters.prohibitExpensivePaths = false
                parameters.prohibitConstrainedPaths = false
                
                let connection = NWConnection(to: endpoint, using: parameters)
                let hasCompleted = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
                hasCompleted.initialize(to: false)
                defer { 
                    hasCompleted.deinitialize(count: 1)
                    hasCompleted.deallocate()
                }
                let lock = NSLock()
                let receivedData = NSMutableData()
                
                connection.stateUpdateHandler = { [self] state in
                    lock.lock()
                    defer { lock.unlock() }
                    
                    guard !hasCompleted.pointee else { return }
                    
                    switch state {
                    case .ready:
                        // Send the domain query
                        let query = "\(domain)\r\n"
                        if let queryData = query.data(using: .utf8) {
                            connection.send(content: queryData, completion: .contentProcessed { error in
                                if let error = error {
                                    lock.lock()
                                    if !hasCompleted.pointee {
                                        hasCompleted.pointee = true
                                        connection.cancel()
                                        continuation.resume(throwing: error)
                                    }
                                    lock.unlock()
                                }
                            })
                            
                            // Start receiving data
                            receiveData(connection: connection, continuation: continuation, hasCompleted: hasCompleted, lock: lock, receivedData: receivedData)
                        }
                        
                    case .failed(let error):
                        hasCompleted.pointee = true
                        connection.cancel()
                        continuation.resume(throwing: error)
                        
                    case .cancelled:
                        hasCompleted.pointee = true
                        continuation.resume(throwing: URLError(.cancelled))
                        
                    default:
                        break
                    }
                }
                
                connection.start(queue: queue)
                
                // Timeout after 30 seconds
                DispatchQueue.global().asyncAfter(deadline: .now() + 30.0) {
                    lock.lock()
                    defer { lock.unlock() }
                    
                    guard !hasCompleted.pointee else { return }
                    hasCompleted.pointee = true
                    connection.cancel()
                    continuation.resume(throwing: URLError(.timedOut))
                }
            }
        } onCancel: {
            // This handler will be called when the task is cancelled
        }
    }
    
    /// Recursively receives data from the WHOIS server
    private func receiveData(
        connection: NWConnection,
        continuation: CheckedContinuation<String, Error>,
        hasCompleted: UnsafeMutablePointer<Bool>,
        lock: NSLock,
        receivedData: NSMutableData
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [self] data, _, isComplete, error in
            lock.lock()
            defer { lock.unlock() }
            
            guard !hasCompleted.pointee else { return }
            
            if let error = error {
                hasCompleted.pointee = true
                connection.cancel()
                continuation.resume(throwing: error)
                return
            }
            
            if let data = data {
                receivedData.append(data)
            }
            
            if isComplete {
                hasCompleted.pointee = true
                connection.cancel()
                
                if let responseString = String(data: receivedData as Data, encoding: .utf8) {
                    continuation.resume(returning: responseString)
                } else {
                    continuation.resume(returning: "Invalid response encoding")
                }
            } else {
                // Continue receiving data
                receiveData(connection: connection, continuation: continuation, hasCompleted: hasCompleted, lock: lock, receivedData: receivedData)
            }
        }
    }
    
    /// Parses WHOIS response data to extract structured information
    private func parseWhoisResponse(_ response: String, for domain: String) -> (
        registrar: String?,
        registrationDate: String?,
        expirationDate: String?,
        nameServers: [String]
    ) {
        let lines = response.components(separatedBy: .newlines)
        var registrar: String?
        var registrationDate: String?
        var expirationDate: String?
        var nameServers: [String] = []
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercaseLine = trimmedLine.lowercased()
            
            // Parse registrar
            if registrar == nil {
                if lowercaseLine.hasPrefix("registrar:") {
                    registrar = String(trimmedLine.dropFirst(10)).trimmingCharacters(in: .whitespacesAndNewlines)
                } else if lowercaseLine.hasPrefix("registrar name:") {
                    registrar = String(trimmedLine.dropFirst(15)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            
            // Parse registration date
            if registrationDate == nil {
                if lowercaseLine.hasPrefix("creation date:") {
                    registrationDate = String(trimmedLine.dropFirst(14)).trimmingCharacters(in: .whitespacesAndNewlines)
                } else if lowercaseLine.hasPrefix("created:") {
                    registrationDate = String(trimmedLine.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
                } else if lowercaseLine.hasPrefix("registered:") {
                    registrationDate = String(trimmedLine.dropFirst(11)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            
            // Parse expiration date
            if expirationDate == nil {
                if lowercaseLine.hasPrefix("registry expiry date:") {
                    expirationDate = String(trimmedLine.dropFirst(21)).trimmingCharacters(in: .whitespacesAndNewlines)
                } else if lowercaseLine.hasPrefix("expiry date:") {
                    expirationDate = String(trimmedLine.dropFirst(12)).trimmingCharacters(in: .whitespacesAndNewlines)
                } else if lowercaseLine.hasPrefix("expires:") {
                    expirationDate = String(trimmedLine.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            
            // Parse name servers
            if lowercaseLine.hasPrefix("name server:") {
                let nameServer = String(trimmedLine.dropFirst(12)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !nameServer.isEmpty && !nameServers.contains(nameServer) {
                    nameServers.append(nameServer)
                }
            } else if lowercaseLine.hasPrefix("nserver:") {
                let nameServer = String(trimmedLine.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !nameServer.isEmpty && !nameServers.contains(nameServer) {
                    nameServers.append(nameServer)
                }
            }
        }
        
        return (registrar, registrationDate, expirationDate, nameServers)
    }
} 