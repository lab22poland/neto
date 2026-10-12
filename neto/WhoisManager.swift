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
            // A result that completes after Stop must not reach a newer lookup
            if Task.isCancelled { return }
            
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
        var incompleteReason: String?
        var answeredServer = server
        
        for hop in 0...Self.maxReferrals {
            if Task.isCancelled { throw CancellationError() }
            let response: ServerAnswer
            do {
                // whois.c gethostinfo(): an unresolvable host ends the lookup right away
                guard let canonicalName = await Self.resolveCanonicalName(of: server) else {
                    throw WhoisError.hostNotFound(server)
                }
                response = try await queryWhoisServerFreeBSD(server: server, query: query, port: port, canonicalName: canonicalName)
            } catch {
                // The first server failing fails the lookup; a later one keeps what was printed so far, like whois.c's err()
                if hop == 0 || Task.isCancelled || error is CancellationError { throw error }
                output += "whois: \(server): \(error.localizedDescription)\n"
                incompleteReason = "Incomplete: \(server) did not answer (\(error.localizedDescription))"
                break
            }
            answeredServer = server
            if let cutOff = response.cutOff, incompleteReason == nil {
                incompleteReason = "Incomplete: \(server) \(cutOff)"
            }
            let processed = processResponse(response.bytes, server: server)
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
        
        // Fields come only from the most specific (last) server; the whole chain is shown as the raw response
        let summary = summarize(lastAnswer: lastServerOutput, server: answeredServer, query: query,
                                incompleteReason: incompleteReason)
        
        return WhoisResult(
            domain: query,
            success: true,
            outcome: summary.outcome,
            rawResponse: output,
            registrar: summary.fields.registrar,
            registrationDate: summary.fields.registrationDate,
            expirationDate: summary.fields.expirationDate,
            nameServers: summary.fields.nameServers,
            whoisServer: answeredServer,   // the last server that answered (a failed referral is reported in the raw response)
            statusMessage: summary.status,
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
    
    /// Resolves a host like whois.c's gethostinfo(): `nil` if it cannot be resolved, otherwise its canonical name
    /// (compared with the Verisign host; `.some(nil)` for numeric hosts, which have none)
    static func resolveCanonicalName(of host: String) async -> String?? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var hints = addrinfo()
                hints.ai_flags = AI_CANONNAME
                hints.ai_family = AF_UNSPEC
                hints.ai_socktype = SOCK_STREAM
                var list: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(host, "43", &hints, &list) == 0, let list else {
                    continuation.resume(returning: .none)
                    return
                }
                defer { freeaddrinfo(list) }
                continuation.resume(returning: .some(list.pointee.ai_canonname.map { String(cString: $0) }))
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
    /// Only a failed connect fails the query (whois.c: err "connect()"). Once connected, an error ends the answer
    /// like EOF, even with no data yet: whois.c's fgetln loop stops on a read error and never checks ferror()
    /// (seen live: whois.markmonitor.com resets throttled connections without sending anything).
    private func queryWhoisServerFreeBSD(server: String, query: String, port: String = "43", canonicalName: String? = nil) async throws -> ServerAnswer {
        guard let endpointPort = NWEndpoint.Port(port) else { throw WhoisError.invalidPort(server, port) }
        let formattedQuery = formatQueryForServer(query: query, server: server, canonicalName: canonicalName)
        let connection = NWConnection(host: NWEndpoint.Host(server), port: endpointPort, using: .tcp)
        let completion = CompletionOnce<ServerAnswer>()
        let buffer = ResponseBuffer()
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion.set(continuation) { connection.cancel() }
                
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        buffer.markConnected()
                        connection.send(content: Data(formattedQuery.utf8), completion: .contentProcessed { error in
                            if let error {
                                Self.endAnswer(after: error, buffer: buffer, completion: completion)   // whois.c ignores fprintf errors
                            } else {
                                Self.readAll(connection: connection, into: buffer, completion: completion)
                            }
                        })
                    case .waiting(let error), .failed(let error):
                        if buffer.isConnected {
                            Self.endAnswer(after: error, buffer: buffer, completion: completion)
                        } else {
                            // connect() failed; .waiting = the host cannot be reached now (e.g. no DNS record), whois.c fails right away
                            completion.finish(.failure(error))
                        }
                    case .cancelled:
                        completion.finish(.failure(CancellationError()))
                    default:
                        break
                    }
                }
                connection.start(queue: .global())
                let timeout = connectionTimeout
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    // Like a read error: what arrived so far is the answer, marked as cut off
                    let received = buffer.bytes
                    completion.finish(received.isEmpty
                                      ? .failure(URLError(.timedOut))
                                      : .success(ServerAnswer(bytes: received, cutOff: "answer cut off after \(Int(timeout)) s")))
                }
            }
        } onCancel: {
            completion.finish(.failure(CancellationError()))
        }
    }
    
    /// Reads until the server closes the connection; an error ends the answer (see `endAnswer`)
    private static func readAll(connection: NWConnection, into buffer: ResponseBuffer, completion: CompletionOnce<ServerAnswer>) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
            if let data { buffer.append(data) }
            if let error {
                endAnswer(after: error, buffer: buffer, completion: completion)
            } else if isComplete {
                completion.finish(.success(ServerAnswer(bytes: buffer.bytes, cutOff: nil)))
            } else {
                readAll(connection: connection, into: buffer, completion: completion)
            }
        }
    }
    
    /// An error on a connected socket ends the answer with what arrived so far (possibly nothing), marked as incomplete
    private static func endAnswer(after error: Error, buffer: ResponseBuffer, completion: CompletionOnce<ServerAnswer>) {
        let received = buffer.bytes
        let reason = received.isEmpty
            ? "closed the connection without an answer (\(error.localizedDescription))"
            : "answer cut off by a connection error (\(error.localizedDescription))"
        completion.finish(.success(ServerAnswer(bytes: received, cutOff: reason)))
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
                if let first = line.first, [UInt8(ascii: "#"), UInt8(ascii: "%"), 0x0D, 0x0A, 0x00].contains(first) { continue }
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
    
    /// Summary fields shown above the raw response
    typealias WhoisFields = (registrar: String?, registrationDate: String?, expirationDate: String?, nameServers: [String])
    
    /// Keys in order of preference: the first key present wins, and within a key the first line wins
    /// (ARIN `OrgName:` before its `Organization: Name (HANDLE)`, RIPE `org-name:` before the `organisation:` handle)
    static let registrarKeys = ["registrar:", "registrar name:", "sponsoring registrar:", "orgname:", "org-name:",
                                "organization:", "organisation:", "maintainer:"]
    /// `Registered on:` (Nominet), `RegDate:` (ARIN), `created:` (RIPE, NASK, IANA)
    static let creationKeys = ["creation date:", "created:", "registered on:", "registered:", "registration date:",
                               "domain registration date:", "register date:", "regdate:"]
    /// `Registrar Registration Expiration Date:` (registrars such as MarkMonitor), `Expiry date:` (Nominet), `renewal date:` (NASK)
    static let expirationKeys = ["registry expiry date:", "registrar registration expiration date:", "expiry date:",
                                 "expiration date:", "expires:", "paid-till:", "renewal date:"]
    /// `Name servers:` (Nominet) and `nameservers:` (NASK) start an indented block
    static let nameServerKeys = ["name server:", "name servers:", "nameserver:", "nameservers:", "nserver:", "ns:",
                                 "domain name servers:"]
    
    /// Line starts (case-insensitive, after leading spaces) with which the servers say the object does not exist,
    /// as returned live: Verisign .com/.net and Nominet ("No match for"), ARIN ("No match found for"),
    /// PIR .org and Identity Digital .io ("Domain not found."), NASK .pl, DENIC ("Status: free")
    static let notFoundMarkers = ["no match for ", "no match found for ", "domain not found.",
                                  "no information available about domain name ", "status: free"]
    
    /// Parses the summary fields of ONE server's answer (callers pass only the last server's text).
    /// A key with an empty value takes the next line as its value when that line is not another "Key: value"
    /// (NASK `REGISTRAR:`, Nominet `Registrar:`); a name server key also takes the following, more indented lines.
    /// Name servers are reduced to the host name (no addresses, no trailing dot). Empty values are nil, never "".
    func parseWhoisResponse(_ response: String, for query: String) -> WhoisFields {
        let lines = response.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
        let valueKeys = Self.registrarKeys + Self.creationKeys + Self.expirationKeys
        var values: [String: String] = [:]
        var nameServers: [String] = []
        
        func trim<S: StringProtocol>(_ text: S) -> String { text.trimmingCharacters(in: .whitespaces) }
        func indent(_ line: String) -> Int { line.prefix(while: { $0 == " " || $0 == "\t" }).count }
        func isComment(_ trimmed: String) -> Bool { trimmed.hasPrefix("%") || trimmed.hasPrefix("#") }
        
        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            let trimmed = trim(line)
            if trimmed.isEmpty || isComment(trimmed) { continue }
            let lower = trimmed.lowercased()
            
            if let key = Self.nameServerKeys.first(where: { lower.hasPrefix($0) }) {
                var entries = [trim(trimmed.dropFirst(key.count))]
                while index < lines.count, !trim(lines[index]).isEmpty, indent(lines[index]) > indent(line) {
                    entries.append(trim(lines[index]))
                    index += 1
                }
                for entry in entries {
                    guard let token = entry.split(whereSeparator: { $0 == " " || $0 == "\t" }).first else { continue }
                    let host = token.hasSuffix(".") ? String(token.dropLast()) : String(token)
                    if !host.isEmpty, !nameServers.contains(where: { $0.caseInsensitiveCompare(host) == .orderedSame }) {
                        nameServers.append(host)
                    }
                }
            } else if let key = valueKeys.first(where: { lower.hasPrefix($0) }), values[key] == nil {
                var value = trim(trimmed.dropFirst(key.count))
                if value.isEmpty, index < lines.count {
                    let next = trim(lines[index])
                    if !next.isEmpty, !isComment(next), !next.hasSuffix(":"), !next.contains(": ") {
                        value = next
                    }
                }
                if !value.isEmpty { values[key] = value }
            }
        }
        
        func first(_ keys: [String]) -> String? { keys.lazy.compactMap { values[$0] }.first }
        return (first(Self.registrarKeys), first(Self.creationKeys), first(Self.expirationKeys), nameServers)
    }
    
    /// Whether the answer says the object does not exist (see `notFoundMarkers`)
    func isNotFound(_ answer: String) -> Bool {
        answer.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n").contains { line in
            let lower = line.trimmingCharacters(in: .whitespaces).lowercased()
            return Self.notFoundMarkers.contains { lower.hasPrefix($0) }
        }
    }
    
    /// Decides what the summary may show, from the LAST server's answer only. IANA's answer describes the TLD or
    /// address block (registry operator, TLD creation date, TLD name servers), so it yields fields only when its
    /// `domain:` is the query itself (e.g. "uk"). Not found or an empty answer shows no fields; an incomplete chain says so.
    func summarize(lastAnswer: String, server: String, query: String, incompleteReason: String?) -> (
        outcome: WhoisResult.Outcome, status: String, fields: WhoisFields
    ) {
        let none: WhoisFields = (nil, nil, nil, [])
        if isNotFound(lastAnswer) {
            return (.notFound, "Not found: \(server) has no record for \(query)", none)
        }
        let onlyIANABlock = server.caseInsensitiveCompare(ianaHost) == .orderedSame && !ianaRecordIsQuery(lastAnswer, query: query)
        let fields = onlyIANABlock ? none : parseWhoisResponse(lastAnswer, for: query)
        if let incompleteReason {
            return (.incomplete, incompleteReason, fields)
        }
        if lastAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // No record (RIPE's "no entries found" is a stripped comment) or a throttling server: it cannot be told apart
            return (.notFound, "No data: \(server) returned an empty answer for \(query)", none)
        }
        if onlyIANABlock {
            return (.ianaOnly, "No registry record: IANA refers to no other WHOIS server; its answer describes the TLD or address block, not \(query)", none)
        }
        return (.found, "WHOIS lookup successful", fields)
    }
    
    /// Whether IANA's answer is the record of the query itself (a TLD such as "uk"), not of the TLD above it
    private func ianaRecordIsQuery(_ answer: String, query: String) -> Bool {
        let wanted = query.hasSuffix(".") ? String(query.dropLast()) : query
        return answer.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n").contains { line in
            guard line.lowercased().hasPrefix("domain:") else { return false }
            return line.dropFirst("domain:".count).trimmingCharacters(in: .whitespaces)
                .caseInsensitiveCompare(wanted) == .orderedSame
        }
    }
}

// MARK: - Supporting Types

/// One server's answer; `cutOff` says why it may be partial (timeout or read error after some data)
struct ServerAnswer {
    let bytes: [UInt8]
    let cutOff: String?
}

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

/// Bytes received so far and whether the connection was established, shared between the callbacks and the timeout
private final class ResponseBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UInt8] = []
    private var connected = false

    func markConnected() {
        lock.lock()
        connected = true
        lock.unlock()
    }

    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return connected
    }

    func append(_ data: Data) {
        lock.lock()
        storage.append(contentsOf: data)
        lock.unlock()
    }

    var bytes: [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        return storage
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
