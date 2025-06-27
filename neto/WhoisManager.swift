//
//  WhoisManager.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Network

/// Manager class responsible for WHOIS operations following FreeBSD whois.c implementation
/// RFC 3912 compliant - supports domains, IP addresses, AS numbers, person and organization records
final class WhoisManager {
    
    // MARK: - FreeBSD Server Constants (exact match)
    private let abuseHost = "whois.abuse.net"
    private let anicHost = "whois.arin.net"
    private let denicHost = "whois.denic.de"
    private let dknicHost = "whois.dk-hostmaster.dk"
    private let fnicHost = "whois.afrinic.net"
    private let gnicHost = "whois.nic.gov"
    private let ianaHost = "whois.iana.org"
    private let inicHost = "whois.internic.net"
    private let knicHost = "whois.krnic.net"
    private let lnicHost = "whois.lacnic.net"
    private let mnicHost = "whois.ra.net"
    private let pdbHost = "whois.peeringdb.com"
    private let pnicHost = "whois.apnic.net"
    private let qnicHostTail = ".whois-servers.net"
    private let rnicHost = "whois.ripe.net"
    private let vnicHost = "whois.verisign-grs.com"
    
    private let connectionTimeout: TimeInterval = 30.0
    
    // MARK: - FreeBSD Suffix-to-Server Mapping (exact match)
    private lazy var whoisWhere: [(suffix: String, server: String)] = [
        /* Various handles */
        ("-ARIN", anicHost),
        ("-NICAT", "at" + qnicHostTail),
        ("-NORID", "no" + qnicHostTail),
        ("-RIPE", rnicHost),
        /* Nominet's whois server doesn't return referrals to JANET */
        (".ac.uk", "ac.uk" + qnicHostTail),
        (".gov.uk", "ac.uk" + qnicHostTail),
        ("", ianaHost) /* default */
    ]
    
    // MARK: - FreeBSD Referral Patterns (exact match)
    private let whoisReferral: [(prefix: String, len: Int)] = [
        ("whois:", 6), /* IANA */
        ("Whois Server:", 13),
        ("Registrar WHOIS Server:", 23), /* corporatedomains.com */
        ("ReferralServer:  whois://", 25), /* ARIN */
        ("ReferralServer:  rwhois://", 26), /* ARIN */
        ("descr:          region. Please query", 37) /* AfriNIC */
    ]
    
    // MARK: - RIR Loop Detection (FreeBSD logic)
    private var tryRir: [(loop: Bool, host: String)] = []
    
    /// Performs a WHOIS lookup for the specified query (domain, IP, AS number, etc.)
    /// - Parameters:
    ///   - query: The target query (domain name, IP address, AS number, person/org)
    ///   - onResult: Callback called when the WHOIS result is available
    /// - Returns: A Task that can be cancelled
    func performWhois(
        for query: String,
        onResult: @escaping (WhoisResult) -> Void
    ) -> Task<Void, Never> {
        return Task {
            await executeWhoisLookup(
                query: query,
                onResult: onResult
            )
        }
    }
    
    /// Executes a WHOIS lookup operation following FreeBSD implementation
    private func executeWhoisLookup(
        query: String,
        onResult: @escaping (WhoisResult) -> Void
    ) async {
        let startTime = Date()
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Initialize RIR tracking (FreeBSD behavior)
        resetRir()
        
        do {
            // Check if task was cancelled
            if Task.isCancelled {
                return
            }
            
            let result = try await performFreeBSDWhoisLookup(query: cleanQuery, startTime: startTime)
            
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
                domain: cleanQuery,
                success: false,
                statusMessage: "WHOIS lookup failed: \(error.localizedDescription)",
                responseTime: responseTime
            )
            
            await MainActor.run {
                onResult(result)
            }
        }
    }
    
    /// Performs WHOIS lookup following FreeBSD logic with recursion
    private func performFreeBSDWhoisLookup(query: String, startTime: Date, flags: Int = 1) async throws -> WhoisResult {
        let chosenServer = chooseServer(for: query)
        let whoisData = try await queryWhoisServerFreeBSD(server: chosenServer, query: query)
        
        // Check for referrals if recursion is enabled (FreeBSD default behavior)
        var finalData = whoisData
        var finalServer = chosenServer
        
        if flags & 1 != 0 { // WHOIS_RECURSE equivalent
            if let (referralHost, referralPort) = parseWhoisReferral(from: whoisData) {
                if referralHost != chosenServer { // Avoid self-referrals
                    finalData = try await queryWhoisServerFreeBSD(server: referralHost, query: query, port: referralPort)
                    finalServer = referralHost
                }
            }
        }
        
        let endTime = Date()
        let responseTime = endTime.timeIntervalSince(startTime) * 1000
        
        let parsedResult = parseWhoisResponse(finalData, for: query)
        
        return WhoisResult(
            domain: query,
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
    
    /// FreeBSD choose_server() function equivalent
    private func chooseServer(for query: String) -> String {
        let domain = query.lowercased()
        
        for (suffix, server) in whoisWhere {
            if suffix.isEmpty {
                return server // default case (IANA)
            }
            
            if domain.count > suffix.count {
                let domainSuffix = String(domain.suffix(suffix.count))
                if domainSuffix.caseInsensitiveCompare(suffix) == .orderedSame {
                    return server
                }
            }
        }
        
        return ianaHost // safety fallback
    }
    
    /// RFC 3912 compliant WHOIS query with FreeBSD server-specific formatting
    private func queryWhoisServerFreeBSD(server: String, query: String, port: String = "43") async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(server),
                port: NWEndpoint.Port(port) ?? 43,
                using: .tcp
            )
            
            var hasCompleted = false
            
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // FreeBSD server-specific query formatting
                    let formattedQuery = self.formatQueryForServer(query: query, server: server)
                    let requestData = formattedQuery.data(using: .utf8) ?? Data()
                    
                    connection.send(content: requestData, completion: .contentProcessed { error in
                        if let error = error {
                            if !hasCompleted {
                                hasCompleted = true
                                continuation.resume(throwing: error)
                            }
                            return
                        }
                        
                        // Start reading response
                        self.readWhoisResponseFreeBSD(connection: connection) { result in
                            if !hasCompleted {
                                hasCompleted = true
                                continuation.resume(with: result)
                            }
                        }
                    })
                    
                case .failed(let error):
                    if !hasCompleted {
                        hasCompleted = true
                        continuation.resume(throwing: error)
                    }
                    
                case .cancelled:
                    if !hasCompleted {
                        hasCompleted = true
                        continuation.resume(throwing: URLError(.cancelled))
                    }
                    
                default:
                    break
                }
            }
            
            connection.start(queue: .global())
            
            // Set timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + connectionTimeout) {
                if !hasCompleted {
                    hasCompleted = true
                    connection.cancel()
                    continuation.resume(throwing: URLError(.timedOut))
                }
            }
        }
    }
    
    /// FreeBSD server-specific query formatting
    private func formatQueryForServer(query: String, server: String) -> String {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // DENIC (German) special formatting
        if server.caseInsensitiveCompare(denicHost) == .orderedSame ||
           server.caseInsensitiveCompare("de" + qnicHostTail) == .orderedSame {
            // Check for IDN (non-ASCII characters)
            let hasIDN = cleanQuery.contains { !$0.isASCII }
            return "-T dn\(hasIDN ? "" : ",ace") \(cleanQuery)\r\n"
        }
        
        // DKNIC (Danish) special formatting
        if server.caseInsensitiveCompare(dknicHost) == .orderedSame ||
           server.caseInsensitiveCompare("dk" + qnicHostTail) == .orderedSame {
            return "--show-handles \(cleanQuery)\r\n"
        }
        
        // ARIN special formatting
        if server.caseInsensitiveCompare(anicHost) == .orderedSame {
            // AS number handling
            if cleanQuery.lowercased().hasPrefix("as") {
                let asNumber = String(cleanQuery.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                if asNumber.allSatisfy({ $0.isNumber }) {
                    return "+ a \(asNumber)\r\n"
                }
            }
            return "+ \(cleanQuery)\r\n"
        }
        
        // Verisign special formatting
        if server.caseInsensitiveCompare(vnicHost) == .orderedSame {
            return "domain \(cleanQuery)\r\n"
        }
        
        // Default formatting (RFC 3912 compliant)
        return "\(cleanQuery)\r\n"
    }
    
    /// Reads WHOIS response following RFC 3912 and FreeBSD logic
    private func readWhoisResponseFreeBSD(
        connection: NWConnection,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var responseData = Data()
        
        func receiveNext() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
                
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                if let data = data {
                    responseData.append(data)
                }
                
                if isComplete {
                    // RFC 3912: Connection closure indicates end of response
                    // Try character encodings in order (RFC 3912 guidance)
                    let responseString = String(data: responseData, encoding: .ascii) ?? // RFC 3912 original encoding
                                       String(data: responseData, encoding: .utf8) ?? // Common modern encoding
                                       String(data: responseData, encoding: .isoLatin1) ?? // European fallback
                                       ""
                    completion(.success(responseString))
                    connection.cancel()
                } else {
                    receiveNext()
                }
            }
        }
        
        receiveNext()
    }
    
    /// FreeBSD-style referral parsing
    private func parseWhoisReferral(from response: String) -> (host: String, port: String)? {
        let lines = response.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            for (prefix, len) in whoisReferral {
                if trimmedLine.count >= len && 
                   String(trimmedLine.prefix(len)).caseInsensitiveCompare(prefix) == .orderedSame {
                    
                    let remainder = String(trimmedLine.dropFirst(len)).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Parse host and optional port
                    if let host = extractHostFromReferral(remainder) {
                        let port = extractPortFromReferral(remainder) ?? "43"
                        return (host, port)
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Extract host from referral string (FreeBSD SCAN logic)
    private func extractHostFromReferral(_ referral: String) -> String? {
        var host = ""
        for char in referral {
            if char.isLetter || char.isNumber || char == "." || char == "-" {
                host.append(char)
            } else {
                break
            }
        }
        return host.isEmpty ? nil : host
    }
    
    /// Extract port from referral string
    private func extractPortFromReferral(_ referral: String) -> String? {
        if let colonIndex = referral.firstIndex(of: ":") {
            let portString = String(referral[referral.index(after: colonIndex)...])
            let port = portString.prefix { $0.isNumber }
            return port.isEmpty ? nil : String(port)
        }
        return nil
    }
    
    /// Reset RIR tracking (FreeBSD reset_rir function)
    private func resetRir() {
        tryRir = [
            (false, anicHost),
            (false, rnicHost), 
            (false, pnicHost),
            (false, fnicHost),
            (false, lnicHost)
        ]
    }
    
    /// Enhanced WHOIS response parsing (more comprehensive than before)
    private func parseWhoisResponse(_ response: String, for query: String) -> (
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
            
            // Skip comment lines and empty lines (FreeBSD behavior)
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("%") || trimmedLine.hasPrefix("#") {
                continue
            }
            
            // Parse registrar information (comprehensive patterns)
            if registrar == nil {
                let registrarPatterns = [
                    "registrar:",
                    "registrar name:",
                    "organisation:",
                    "org-name:",
                    "sponsoring registrar:",
                    "maintainer:"
                ]
                
                for pattern in registrarPatterns {
                    if lowercaseLine.hasPrefix(pattern) {
                        registrar = String(trimmedLine.dropFirst(pattern.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }
            }
            
            // Parse registration/creation date (comprehensive patterns)
            if registrationDate == nil {
                let creationPatterns = [
                    "creation date:",
                    "created:",
                    "registered:",
                    "registration date:",
                    "domain registration date:",
                    "register date:"
                ]
                
                for pattern in creationPatterns {
                    if lowercaseLine.hasPrefix(pattern) {
                        registrationDate = String(trimmedLine.dropFirst(pattern.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }
            }
            
            // Parse expiration date (comprehensive patterns)
            if expirationDate == nil {
                let expirationPatterns = [
                    "registry expiry date:",
                    "expiry date:",
                    "expires:",
                    "expiration date:",
                    "paid-till:",
                    "renewal date:"
                ]
                
                for pattern in expirationPatterns {
                    if lowercaseLine.hasPrefix(pattern) {
                        expirationDate = String(trimmedLine.dropFirst(pattern.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }
            }
            
            // Parse name servers (comprehensive patterns)
            let nameServerPatterns = [
                "name server:",
                "nserver:",
                "nameserver:",
                "ns:",
                "domain name servers:"
            ]
            
            for pattern in nameServerPatterns {
                if lowercaseLine.hasPrefix(pattern) {
                    let nameServer = String(trimmedLine.dropFirst(pattern.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !nameServer.isEmpty && !nameServers.contains(nameServer) {
                        nameServers.append(nameServer)
                    }
                    break
                }
            }
        }
        
        return (registrar, registrationDate, expirationDate, nameServers)
    }
} 