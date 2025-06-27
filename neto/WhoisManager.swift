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
            
            let result = try await performCascadedWhoisLookup(domain: cleanDomain, startTime: startTime)
            
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
    
    /// Performs a cascaded WHOIS lookup, following redirects as needed
    private func performCascadedWhoisLookup(domain: String, startTime: Date) async throws -> WhoisResult {
        let whoisServer = await determineWhoisServer(for: domain)
        let whoisData = try await queryWhoisServer(server: whoisServer, domain: domain)
        
        // Check if we got a redirect to another WHOIS server
        let redirectServer = checkForWhoisRedirect(in: whoisData)
        
        let finalData: String
        let finalServer: String
        
        if let redirect = redirectServer, redirect != whoisServer {
            // Follow the redirect for more detailed information
            finalData = try await queryWhoisServer(server: redirect, domain: domain)
            finalServer = redirect
        } else {
            finalData = whoisData
            finalServer = whoisServer
        }
        
        let endTime = Date()
        let responseTime = endTime.timeIntervalSince(startTime) * 1000
        
        let parsedResult = parseWhoisResponse(finalData, for: domain)
        
        return WhoisResult(
            domain: domain,
            success: true,
            rawResponse: finalData,
            registrar: parsedResult.registrar,
            registrationDate: parsedResult.registrationDate,
            expirationDate: parsedResult.expirationDate,
            nameServers: parsedResult.nameServers,
            whoisServer: finalServer,
            statusMessage: "WHOIS lookup successful",
            responseTime: responseTime
        )
    }
    
    /// Checks if the WHOIS response contains a redirect to another WHOIS server
    private func checkForWhoisRedirect(in response: String) -> String? {
        let lines = response.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercaseLine = trimmedLine.lowercased()
            
            // Look for various redirect patterns
            if lowercaseLine.hasPrefix("whois server:") ||
               lowercaseLine.hasPrefix("registrar whois server:") ||
               lowercaseLine.hasPrefix("whois:") {
                let parts = trimmedLine.components(separatedBy: .whitespaces)
                if parts.count >= 2 {
                    let server = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return server?.isEmpty == false ? server : nil
                }
            }
            
            // Look for "refer:" pattern used by IANA
            if lowercaseLine.hasPrefix("refer:") {
                let parts = trimmedLine.components(separatedBy: .whitespaces)
                if parts.count >= 2 {
                    return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        return nil
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
            return "whois.iana.org" // Default fallback
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
            "me": "whois.nic.me",
            "ua": "whois.ua",
            "se": "whois.iis.se",
            "dk": "whois.dk-hostmaster.dk",
            "fi": "whois.fi",
            "no": "whois.norid.no",
            "nl": "whois.domain-registry.nl",
            "be": "whois.dns.be",
            "ch": "whois.nic.ch",
            "at": "whois.nic.at",
            "it": "whois.nic.it",
            "es": "whois.nic.es"
        ]
        
        // If we have a known server, use it
        if let knownServer = whoisServers[tld] {
            return knownServer
        }
        
        // For unknown TLDs, query IANA to discover the correct WHOIS server
        return await discoverWhoisServer(for: tld)
    }
    
    /// Discovers the WHOIS server for a TLD by querying IANA
    private func discoverWhoisServer(for tld: String) async -> String {
        do {
            let ianaResponse = try await queryWhoisServer(server: "whois.iana.org", domain: tld)
            
            // Parse the IANA response to find the WHOIS server
            let lines = ianaResponse.components(separatedBy: .newlines)
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedLine.lowercased().hasPrefix("whois:") {
                    let parts = trimmedLine.components(separatedBy: .whitespaces)
                    if parts.count >= 2 {
                        return parts[1] // Return the server name
                    }
                }
            }
        } catch {
            // If IANA query fails, fall back to a reasonable default
            print("Failed to discover WHOIS server for TLD .\(tld): \(error)")
        }
        
        // Fallback to IANA for unknown TLDs
        return "whois.iana.org"
    }
    
    /// Queries a WHOIS server for domain information
    private func queryWhoisServer(server: String, domain: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let result = try await performNetworkQuery(server: server, domain: domain)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Performs the actual network query with proper async/await handling
    private func performNetworkQuery(server: String, domain: String) async throws -> String {
        let endpoint = NWEndpoint.hostPort(host: .name(server, nil), port: 43)
        let parameters = NWParameters.tcp
        parameters.prohibitExpensivePaths = false
        parameters.prohibitConstrainedPaths = false
        
        let connection = NWConnection(to: endpoint, using: parameters)
        
        // Set up connection state monitoring
        let connectionReady = await withCheckedContinuation { continuation in
            var hasResumed = false
            
            connection.stateUpdateHandler = { state in
                guard !hasResumed else { return }
                
                switch state {
                case .ready:
                    hasResumed = true
                    continuation.resume(returning: true)
                case .failed(let error):
                    hasResumed = true
                    continuation.resume(returning: false)
                case .cancelled:
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(returning: false)
                    }
                default:
                    break
                }
            }
            
            connection.start(queue: DispatchQueue(label: "whois.connection"))
        }
        
        guard connectionReady else {
            connection.cancel()
            throw URLError(.cannotConnectToHost)
        }
        
        // Send the query
        let query = "\(domain)\r\n"
        guard let queryData = query.data(using: .utf8) else {
            connection.cancel()
            throw URLError(.badURL)
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: queryData, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
        
        // Receive the response
        let responseData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let receivedData = NSMutableData()
            
            func receiveNextChunk() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    if let data = data {
                        receivedData.append(data)
                    }
                    
                    if isComplete {
                        continuation.resume(returning: Data(receivedData))
                    } else {
                        receiveNextChunk()
                    }
                }
            }
            
            receiveNextChunk()
        }
        
        connection.cancel()
        
        guard let responseString = String(data: responseData, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }
        
        return responseString
    }
    
    /// Safe state management for network operations
    private class NetworkState {
        private let lock = NSLock()
        private var _hasCompleted = false
        
        var hasCompleted: Bool {
            lock.lock()
            defer { lock.unlock() }
            return _hasCompleted
        }
        
        func markCompleted() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if _hasCompleted {
                return false // Already completed
            }
            _hasCompleted = true
            return true // Successfully marked as completed
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