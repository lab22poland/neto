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
    /// RIRs tried in turn when one asserts ignorance instead of referring (whois.c try_rir)
    private var rirHosts: [String] { [anicHost, rnicHost, pnicHost, fnicHost, lnicHost] }

    /// Lines with which an RIR says the address is not its own; whois.c then asks ARIN (actually_arin)
    private let actuallyArin = [
        "netname:        ERX-NETBLOCK\n", /* APNIC */
        "netname:        NON-RIPE-NCC-MANAGED-ADDRESS-BLOCK\n"
    ]

    /// whois.c CHOPSPAM: Verisign and others append legal text after this line
    private let chopSpam = ">>> Last update of WHOIS database:"

    /// Safety limit for the referral chain (whois.c has none; registrars could refer to each other in a loop)
    static let maxReferrals = 10
    
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
    
    /// Performs the lookup like whois.c: query the chosen server, print its answer, follow the referral
    /// (with RIR loop avoidance) until there is none, then report the last server's data
    private func performFreeBSDWhoisLookup(query: String, startTime: Date) async throws -> WhoisResult {
        guard var server = chooseServer(for: query) else {
            // whois.c choose_server(): errx(EX_SOFTWARE, "no default whois server")
            throw URLError(.badURL)
        }
        var port = "43"
        var visitedRIRs = Set<String>()
        var output = ""
        var lastServerOutput = ""
        
        for _ in 0...Self.maxReferrals {
            if Task.isCancelled { throw CancellationError() }
            let canonicalName = await Self.canonicalName(of: server)
            let response = try await queryWhoisServerFreeBSD(server: server, query: query, port: port, canonicalName: canonicalName)
            let processed = processResponse(response, server: server)
            output += processed.output
            lastServerOutput = processed.output
            
            guard let next = nextServer(after: server, referral: processed.referral, visitedRIRs: &visitedRIRs),
                  next.host.caseInsensitiveCompare(server) != .orderedSame else { break }   // whois.c ignores self-referrals
            output += "# \(next.host)\n\n"
            server = next.host
            port = next.port
        }
        
        let endTime = Date()
        let responseTime = endTime.timeIntervalSince(startTime) * 1000
        
        // Fields come from the most specific (last) server; the whole chain is shown as the raw response
        let last = parseWhoisResponse(lastServerOutput, for: query)
        let all = parseWhoisResponse(output, for: query)
        
        return WhoisResult(
            domain: query,
            success: true,
            rawResponse: output,
            registrar: last.registrar ?? all.registrar,
            registrationDate: last.registrationDate ?? all.registrationDate,
            expirationDate: last.expirationDate ?? all.expirationDate,
            nameServers: last.nameServers.isEmpty ? all.nameServers : last.nameServers,
            whoisServer: server,
            statusMessage: "WHOIS lookup successful",
            responseTime: responseTime
        )
    }
    
    /// whois.c after reading a server: remember visited RIRs; a referral to an RIR asked before is replaced by
    /// the first RIR not asked yet. Returns the next server, or nil when the chain ends.
    func nextServer(after server: String, referral: (host: String, port: String)?,
                    visitedRIRs: inout Set<String>) -> (host: String, port: String)? {
        var next = referral
        var needAlternative = false
        for rir in rirHosts {
            if !visitedRIRs.contains(rir), rir.caseInsensitiveCompare(server) == .orderedSame {
                visitedRIRs.insert(rir)
            }
            if visitedRIRs.contains(rir), let candidate = next, rir.caseInsensitiveCompare(candidate.host) == .orderedSame {
                next = nil
                needAlternative = true
            }
        }
        if needAlternative, let unvisited = rirHosts.first(where: { !visitedRIRs.contains($0) }) {
            next = (unvisited, "43")
        }
        return next
    }
    
    /// Canonical name of a host (whois.c compares it with the Verisign host); nil if it cannot be resolved
    static func canonicalName(of host: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var hints = addrinfo()
                hints.ai_flags = AI_CANONNAME
                hints.ai_family = AF_UNSPEC
                hints.ai_socktype = SOCK_STREAM
                var list: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(host, "43", &hints, &list) == 0, let list else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { freeaddrinfo(list) }
                continuation.resume(returning: list.pointee.ai_canonname.map { String(cString: $0) })
            }
        }
    }
    
    /// FreeBSD choose_server() function equivalent
    func chooseServer(for query: String) -> String? {
        let domain = query.lowercased()
        
        for (suffix, server) in whoisWhere {
            if domain.count > suffix.count {
                let domainSuffix = String(domain.suffix(suffix.count))
                if domainSuffix.caseInsensitiveCompare(suffix) == .orderedSame {
                    return server
                }
            }
        }
        
        return nil // whois.c: errx "no default whois server"
    }
    
    /// RFC 3912 compliant WHOIS query with FreeBSD server-specific formatting
    private func queryWhoisServerFreeBSD(server: String, query: String, port: String = "43", canonicalName: String? = nil) async throws -> String {
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
                    let formattedQuery = self.formatQueryForServer(query: query, server: server, canonicalName: canonicalName)
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
    
    /// Server-specific query formatting, in whois.c order: DENIC, DK, queries with a space (sent as is), ARIN, Verisign
    /// (recognised by the canonical name of the server, like whois.c's ai_canonname), default
    func formatQueryForServer(query: String, server: String, canonicalName: String? = nil) -> String {
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
        
        // A query with a space is sent unchanged (e.g. "AS 15169", "John Smith")
        if cleanQuery.contains(" ") {
            return "\(cleanQuery)\r\n"
        }
        
        // ARIN special formatting
        if server.caseInsensitiveCompare(anicHost) == .orderedSame {
            // AS number handling
            if cleanQuery.lowercased().hasPrefix("as") {
                let asNumber = String(cleanQuery.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                // whois.c: strspn(query + 2, "0123456789") == strlen(query + 2), so "AS" alone also becomes "+ a "
                if asNumber.allSatisfy({ $0.isASCII && $0.isNumber }) {
                    return "+ a \(asNumber)\r\n"
                }
            }
            return "+ \(cleanQuery)\r\n"
        }
        
        // Verisign special formatting
        if (canonicalName ?? server).caseInsensitiveCompare(vnicHost) == .orderedSame {
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
    
    /// What whois.c prints for one server's answer, and the referral it found
    struct ProcessedResponse {
        let output: String
        let referral: (host: String, port: String)?
    }
    
    /// whois.c's read loop: stops at Nominet's "-- " line, skips ARIN/RIPE leading comments and stops at their
    /// trailing comments, looks for the first referral, switches to ARIN on `actually_arin` lines, and cuts
    /// Verisign-style legal text after the "Last update of WHOIS database" line.
    func processResponse(_ response: String, server: String) -> ProcessedResponse {
        var output = ""
        var referral: (host: String, port: String)?
        var comment = (server.caseInsensitiveCompare(anicHost) == .orderedSame ||
                       server.caseInsensitiveCompare(rnicHost) == .orderedSame) ? 2 : 0
        
        // fgetln: lines keep their terminator
        var lines = response.components(separatedBy: "\n").map { $0 + "\n" }
        if response.hasSuffix("\n") || response.isEmpty { lines.removeLast() } else { lines[lines.count - 1].removeLast() }
        
        for line in lines {
            if line == "-- \r\n" { break }                                  // Nominet
            if comment == 1 && line.hasPrefix("#") { break }                // RIRs
            if comment == 2 {
                // whois.c: strchr("#%\r\n", buf[0]); in Swift "\r\n" is one Character, so check the first scalar
                if let first = line.unicodeScalars.first, "#%\r\n".unicodeScalars.contains(first) { continue }
                comment = 1
            }
            output += line
            
            if referral == nil {
                referral = Self.referral(in: line, prefixes: whoisReferral.map(\.prefix))
                if actuallyArin.contains(where: { $0.utf8.starts(with: line.utf8) }) {
                    referral = (anicHost, "43")
                }
            }
            if line.count >= chopSpam.count,
               line.lowercased().hasPrefix(chopSpam.lowercased()) ||
               line.lowercased().hasPrefix(String(chopSpam.dropFirst(4)).lowercased()) {
                output += "\n"
                break
            }
        }
        return ProcessedResponse(output: output, referral: referral)
    }
    
    /// whois.c referral scan of one line: optional leading spaces, a known prefix (case-insensitive), spaces,
    /// a host name, then an optional ":port" of 1-5 digits. A longer or empty port means no referral.
    static func referral(in line: String, prefixes: [String]) -> (host: String, port: String)? {
        let characters = Array(line)
        var start = 0
        while start < characters.count, characters[start] == " " { start += 1 }
        let rest = String(characters[start...])
        for prefix in prefixes {
            guard rest.count >= prefix.count,
                  String(rest.prefix(prefix.count)).caseInsensitiveCompare(prefix) == .orderedSame else { continue }
            var index = start + prefix.count
            while index < characters.count, characters[index] == " " { index += 1 }
            let hostStart = index
            while index < characters.count, characters[index].isASCII,
                  characters[index].isLetter || characters[index].isNumber || characters[index] == "." || characters[index] == "-" {
                index += 1
            }
            guard index > hostStart else { return nil }
            let host = String(characters[hostStart..<index])
            guard index < characters.count, characters[index] == ":" else { return (host, "43") }
            index += 1
            let portStart = index
            while index < characters.count, characters[index].isASCII, characters[index].isNumber { index += 1 }
            let digits = index - portStart
            return digits > 0 && digits < 6 ? (host, String(characters[portStart..<index])) : nil   // invalid port: don't recurse
        }
        return nil
    }
    
    /// Enhanced WHOIS response parsing (more comprehensive than before)
    func parseWhoisResponse(_ response: String, for query: String) -> (
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