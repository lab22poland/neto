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
            "es": "whois.nic.es",
            "cc": "whois.nic.cc"
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
    
    /// Queries a WHOIS server using a simple HTTP-based approach
    private func queryWhoisServer(server: String, domain: String) async throws -> String {
        // Use a WHOIS HTTP gateway service for stability
        // This avoids the low-level networking issues we've been having
        let urlString = "https://www.whois.com/whois/\(domain)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let request = URLRequest(url: url, timeoutInterval: 30.0)
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let htmlString = String(data: data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }
        
        // Extract WHOIS data from HTML response
        // This is a simplified approach - for a full implementation you'd want to parse the HTML properly
        if htmlString.contains("No match") || htmlString.contains("not found") {
            return "No match for \"\(domain.uppercased())\"."
        }
        
        // Try to extract the raw WHOIS data from the HTML
        if let startRange = htmlString.range(of: "<pre"),
           let endRange = htmlString.range(of: "</pre>", range: startRange.upperBound..<htmlString.endIndex) {
            let whoisData = String(htmlString[startRange.upperBound..<endRange.lowerBound])
            // Remove HTML tags
            let cleanData = whoisData.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
            return cleanData.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Fallback: try direct TCP connection for known reliable servers
        return try await queryWhoisDirectly(server: server, domain: domain)
    }
    
    /// Fallback method for direct WHOIS queries using raw TCP
    private func queryWhoisDirectly(server: String, domain: String) async throws -> String {
        // Very simple TCP implementation
        let host = server
        let port = 43
        
        // Create socket
        let sockfd = socket(AF_INET, SOCK_STREAM, 0)
        guard sockfd >= 0 else {
            throw URLError(.cannotConnectToHost)
        }
        
        defer { close(sockfd) }
        
        // Set timeout
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sockfd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        
        // Resolve hostname
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &result)
        guard status == 0, let addr = result else {
            throw URLError(.cannotFindHost)
        }
        
        defer { freeaddrinfo(result) }
        
        // Connect
        let connectStatus = connect(sockfd, addr.pointee.ai_addr, addr.pointee.ai_addrlen)
        guard connectStatus == 0 else {
            throw URLError(.cannotConnectToHost)
        }
        
        // Send query
        let query = "\(domain)\r\n"
        let queryData = query.data(using: .utf8)!
        let sent = queryData.withUnsafeBytes { bytes in
            send(sockfd, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, 0)
        }
        
        guard sent > 0 else {
            throw URLError(.networkConnectionLost)
        }
        
        // Receive response
        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        
        while true {
            let received = recv(sockfd, &buffer, buffer.count, 0)
            if received <= 0 {
                break
            }
            responseData.append(contentsOf: buffer[0..<received])
        }
        
        guard let responseString = String(data: responseData, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }
        
        return responseString
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