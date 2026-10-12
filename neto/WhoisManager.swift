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
        var status = "WHOIS lookup successful"
        
        for hop in 0...Self.maxReferrals {
            if Task.isCancelled { throw CancellationError() }
            let response: [UInt8]
            do {
                // whois.c gethostinfo(): an unresolvable host ends the lookup right away
                guard let canonicalName = await Self.canonicalName(of: server) else {
                    throw WhoisError.hostNotFound(server)
                }
                response = try await queryWhoisServerFreeBSD(server: server, query: query, port: port, canonicalName: canonicalName)
            } catch {
                // The first server failing fails the lookup; a later one keeps what was printed so far, like whois.c's err()
                if hop == 0 || error is CancellationError { throw error }
                output += "whois: \(server): \(error.localizedDescription)\n"
                status = "WHOIS lookup incomplete: \(server) failed"
                break
            }
            let processed = processResponse(response, server: server)
            let text = Self.decode(processed.output)
            output += text
            lastServerOutput = text
            
            guard hop < Self.maxReferrals,
                  let next = nextServer(after: server, referral: processed.referral, visitedRIRs: &visitedRIRs),
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
            statusMessage: status,
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
    
    /// RFC 3912 query: send the formatted query, read until the server closes the connection.
    /// Like whois.c's fgetln loop, a read error after some data ends the answer instead of failing it.
    private func queryWhoisServerFreeBSD(server: String, query: String, port: String = "43", canonicalName: String? = nil) async throws -> [UInt8] {
        guard let endpointPort = NWEndpoint.Port(port) else { throw WhoisError.invalidPort(server, port) }
        let formattedQuery = formatQueryForServer(query: query, server: server, canonicalName: canonicalName)
        let connection = NWConnection(host: NWEndpoint.Host(server), port: endpointPort, using: .tcp)
        let completion = CompletionOnce<[UInt8]>()
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion.set(continuation) { connection.cancel() }
                
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        connection.send(content: Data(formattedQuery.utf8), completion: .contentProcessed { error in
                            if let error {
                                completion.finish(.failure(error))
                            } else {
                                Self.readAll(connection: connection, completion: completion)
                            }
                        })
                    case .waiting(let error), .failed(let error):
                        // .waiting = the host cannot be reached now (e.g. no DNS record); whois.c fails right away
                        completion.finish(.failure(error))
                    case .cancelled:
                        completion.finish(.failure(CancellationError()))
                    default:
                        break
                    }
                }
                connection.start(queue: .global())
                DispatchQueue.global().asyncAfter(deadline: .now() + connectionTimeout) {
                    completion.finish(.failure(URLError(.timedOut)))
                }
            }
        } onCancel: {
            completion.finish(.failure(CancellationError()))
        }
    }
    
    /// Reads until the server closes the connection; an error after data counts as the end of the answer
    private static func readAll(connection: NWConnection, completion: CompletionOnce<[UInt8]>, received: [UInt8] = []) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
            var bytes = received
            if let data { bytes.append(contentsOf: data) }
            if let error {
                completion.finish(bytes.isEmpty ? .failure(error) : .success(bytes))
            } else if isComplete {
                completion.finish(.success(bytes))
            } else {
                readAll(connection: connection, completion: completion, received: bytes)
            }
        }
    }
    
    /// Text of a server's answer: UTF-8, or ISO Latin-1 when the bytes are not valid UTF-8 (decoded per server)
    static func decode(_ bytes: [UInt8]) -> String {
        String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1) ?? ""
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
    
    /// What whois.c prints for one server's answer (bytes, unchanged), and the referral it found
    struct ProcessedResponse {
        let output: [UInt8]
        let referral: (host: String, port: String)?
    }
    
    /// whois.c's read loop on bytes (fgetln lines keep their terminator): stops at Nominet's "-- \r\n" line,
    /// skips ARIN/RIPE leading comments and stops at their trailing comments, looks for the first referral,
    /// switches to ARIN on `actually_arin` lines, and cuts Verisign-style legal text after "Last update of WHOIS database".
    func processResponse(_ response: [UInt8], server: String) -> ProcessedResponse {
        var output: [UInt8] = []
        var referral: (host: String, port: String)?
        var comment = (server.caseInsensitiveCompare(anicHost) == .orderedSame ||
                       server.caseInsensitiveCompare(rnicHost) == .orderedSame) ? 2 : 0
        let chop = Array(chopSpam.utf8)
        let arinLines = actuallyArin.map { Array($0.utf8) }
        let prefixes = whoisReferral.map { Array($0.prefix.utf8) }
        
        var start = response.startIndex
        while start < response.endIndex {
            let end = response[start...].firstIndex(of: 0x0A).map { $0 + 1 } ?? response.endIndex
            let line = Array(response[start..<end])
            start = end
            
            if line == Array("-- \r\n".utf8) { break }                                   // Nominet
            if comment == 1 && line.first == UInt8(ascii: "#") { break }                 // RIRs
            if comment == 2 {
                if let first = line.first, [UInt8(ascii: "#"), UInt8(ascii: "%"), 0x0D, 0x0A].contains(first) { continue }
                comment = 1
            }
            output += line
            
            if referral == nil {
                referral = Self.referral(in: line, prefixes: prefixes)
                // strncmp(buf, actually_arin[i], len): the line equals the start of the pattern
                if arinLines.contains(where: { $0.starts(with: line) }) {
                    referral = (anicHost, "43")
                }
            }
            if line.count >= chop.count,
               Self.hasPrefixIgnoringASCIICase(line, chop) || Self.hasPrefixIgnoringASCIICase(line, Array(chop.dropFirst(4))) {
                output.append(0x0A)
                break
            }
        }
        return ProcessedResponse(output: output, referral: referral)
    }
    
    /// Convenience for text input (tests)
    func processResponse(_ response: String, server: String) -> ProcessedResponse {
        processResponse(Array(response.utf8), server: server)
    }
    
    /// strncasecmp: ASCII-only case folding
    static func hasPrefixIgnoringASCIICase(_ bytes: [UInt8], _ prefix: [UInt8]) -> Bool {
        guard bytes.count >= prefix.count else { return false }
        func lower(_ byte: UInt8) -> UInt8 { (0x41...0x5A).contains(byte) ? byte + 0x20 : byte }
        return zip(bytes, prefix).allSatisfy { lower($0) == lower($1) }
    }
    
    /// whois.c referral scan of one line: optional leading spaces, a known prefix (ASCII case-insensitive), spaces,
    /// a host name of [A-Za-z0-9.-], then an optional ":port" of 1-5 digits. A longer or empty port means no referral.
    /// After the first matching prefix no other prefix is tried, even if the host is empty.
    static func referral(in line: [UInt8], prefixes: [[UInt8]]) -> (host: String, port: String)? {
        func isHost(_ byte: UInt8) -> Bool {
            (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) || byte == 0x2E || byte == 0x2D
        }
        var start = 0
        while start < line.count, line[start] == 0x20 { start += 1 }
        for prefix in prefixes {
            guard hasPrefixIgnoringASCIICase(Array(line[start...]), prefix) else { continue }
            var index = start + prefix.count
            while index < line.count, line[index] == 0x20 { index += 1 }
            let hostStart = index
            while index < line.count, isHost(line[index]) { index += 1 }
            guard index > hostStart else { return nil }
            let host = String(decoding: line[hostStart..<index], as: UTF8.self)
            guard index < line.count, line[index] == UInt8(ascii: ":") else { return (host, "43") }
            index += 1
            let portStart = index
            while index < line.count, (0x30...0x39).contains(line[index]) { index += 1 }
            let digits = index - portStart
            return digits > 0 && digits < 6 ? (host, String(decoding: line[portStart..<index], as: UTF8.self)) : nil   // invalid port: don't recurse
        }
        return nil
    }
    
    /// Convenience for text input (tests)
    static func referral(in line: String, prefixes: [String]) -> (host: String, port: String)? {
        referral(in: Array(line.utf8), prefixes: prefixes.map { Array($0.utf8) })
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

// MARK: - Supporting Types

enum WhoisError: LocalizedError {
    case hostNotFound(String)
    case invalidPort(String, String)

    var errorDescription: String? {
        switch self {
        case .hostNotFound(let host): return "\(host): host not found"
        case .invalidPort(let host, let port): return "\(host): invalid port \(port)"
        }
    }
}

/// Resumes a continuation exactly once from whichever thread gets there first, then runs the cleanup
private final class CompletionOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var cleanup: (() -> Void)?
    private var pending: Result<T, Error>?

    func set(_ continuation: CheckedContinuation<T, Error>, cleanup: @escaping () -> Void) {
        lock.lock()
        if let pending {
            self.pending = nil
            lock.unlock()
            cleanup()
            continuation.resume(with: pending)
            return
        }
        self.continuation = continuation
        self.cleanup = cleanup
        lock.unlock()
    }

    func finish(_ result: Result<T, Error>) {
        lock.lock()
        guard let continuation else {
            if pending == nil { pending = result }   // finished before set (cancelled early)
            lock.unlock()
            return
        }
        self.continuation = nil
        let cleanup = self.cleanup
        self.cleanup = nil
        lock.unlock()
        cleanup?()
        continuation.resume(with: result)
    }
}
