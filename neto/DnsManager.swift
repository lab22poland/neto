//
//  DnsManager.swift
//  neto
//
//  Created by Sergii Solianyk on 12/10/2026.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Network

/// How a query reaches the server
enum DNSTransport: String, CaseIterable, Identifiable {
    case udp = "UDP"
    case tcp = "TCP"
    case tls = "DoT"
    case https = "DoH"

    var id: String { rawValue }
}

/// A DNS server: an address for UDP/TCP, a TLS host for DoT (RFC 7858) and a URL for DoH (RFC 8484)
struct DNSServer: Hashable, Identifiable {
    let label: String
    let address: String
    let tlsHost: String?
    let dohURL: URL?

    var id: String { label + address }

    func supports(_ transport: DNSTransport) -> Bool {
        switch transport {
        case .udp, .tcp: return true
        case .tls: return tlsHost != nil
        case .https: return dohURL != nil
        }
    }

    static let cloudflare = DNSServer(label: "Cloudflare", address: "1.1.1.1", tlsHost: "one.one.one.one",
                                      dohURL: URL(string: "https://cloudflare-dns.com/dns-query"))
    static let google = DNSServer(label: "Google", address: "8.8.8.8", tlsHost: "dns.google",
                                  dohURL: URL(string: "https://dns.google/dns-query"))
    static let quad9 = DNSServer(label: "Quad9", address: "9.9.9.9", tlsHost: "dns.quad9.net",
                                 dohURL: URL(string: "https://dns.quad9.net/dns-query"))
    static let presets = [cloudflare, google, quad9]

    /// A server given by IP address (UDP, TCP and DoT to that address)
    static func custom(_ address: String) -> DNSServer {
        DNSServer(label: address, address: address, tlsHost: address, dohURL: nil)
    }
}

/// Sends DNS queries like `dig @server`: UDP with EDNS0 (retried over TCP when truncated), TCP, DoT or DoH
final class DnsManager {

    /// Seconds to wait for one exchange
    let timeout: TimeInterval = 5

    /// Performs a lookup and reports the parsed response
    /// - Parameters:
    ///   - name: Domain name to query (absolute or relative to the root)
    ///   - type: Record type
    ///   - server: Server to ask
    ///   - transport: How to reach the server
    ///   - ednsUDPSize: UDP payload size announced in EDNS0 (dig's default since 9.16 is 1232); a smaller one forces truncation
    ///   - onResult: Called on the main actor once, unless the task is cancelled first
    /// - Returns: A Task that can be cancelled
    func performLookup(
        name: String,
        type: DNSRecordType,
        server: DNSServer,
        transport: DNSTransport,
        ednsUDPSize: UInt16 = 1232,
        onResult: @escaping (DnsResult) -> Void
    ) -> Task<Void, Never> {
        Task {
            let result = await lookup(name: name, type: type, server: server, transport: transport, ednsUDPSize: ednsUDPSize)
            await MainActor.run {
                // Checked on the main actor, so a Stop issued before this point always wins
                if !Task.isCancelled { onResult(result) }
            }
        }
    }

    private func lookup(name: String, type: DNSRecordType, server: DNSServer, transport: DNSTransport, ednsUDPSize: UInt16) async -> DnsResult {
        let started = Date()
        var usedTransport = transport
        do {
            // DoH recommends ID 0 so responses are cacheable (RFC 8484 4.1)
            let id = transport == .https ? 0 : UInt16.random(in: 0...UInt16.max)
            guard let wireName = DNSWire.asciiName(name) else { throw DNSMessageError.invalidName(name) }
            let query = try DNSWire.query(name: wireName, type: type.rawValue, id: id, ednsUDPSize: ednsUDPSize)
            var exchange = try await send(query, to: server, over: transport)
            // Truncation is read from the raw header: the rest of a truncated answer may not parse
            if transport == .udp, let header = DNSWire.header(exchange.response), header.flags & 0x0200 != 0 {
                // RFC 7766: a truncated UDP answer is retried over TCP, like dig
                usedTransport = .tcp
                do {
                    exchange = try await send(query, to: server, over: .tcp)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw DNSLookupError.tcpRetryFailed(error.localizedDescription)
                }
            }
            let message = try DNSWire.parse(exchange.response)
            return DnsResult(name: name, type: type, server: server, transport: usedTransport, endpoint: exchange.endpoint,
                             message: message, queryTime: exchange.milliseconds, responseSize: exchange.response.count,
                             timestamp: started)
        } catch {
            return DnsResult(name: name, type: type, server: server, transport: usedTransport, error: error.localizedDescription,
                             timestamp: started)
        }
    }

    /// One query/response exchange; the time is measured from sending to the complete response, like dig's "Query time"
    private func send(_ query: [UInt8], to server: DNSServer, over transport: DNSTransport) async throws -> DNSExchange {
        let accept = { (response: [UInt8]) in DNSWire.isResponse(response, to: query) }
        switch transport {
        case .udp:
            return try await exchange(query, host: server.address, port: 53, parameters: .udp, framed: false, accept: accept)
        case .tcp:
            return try await exchange(query, host: server.address, port: 53, parameters: .tcp, framed: true, accept: accept)
        case .tls:
            guard let host = server.tlsHost else { throw DNSLookupError.unsupportedTransport(transport, server.label) }
            return try await exchange(query, host: host, port: 853, parameters: .tls, framed: true, accept: accept)
        case .https:
            guard let url = server.dohURL else { throw DNSLookupError.unsupportedTransport(transport, server.label) }
            let exchange = try await httpsExchange(query, url: url)
            guard accept(exchange.response) else { throw DNSLookupError.mismatchedResponse }
            return exchange
        }
    }

    /// UDP datagram, or TCP/TLS with the 2-byte length prefix (RFC 1035 4.2.2, RFC 7858).
    /// Over UDP, datagrams that do not answer the query (other ID or question) are ignored like dig does;
    /// over a stream the single answer must match.
    private func exchange(_ query: [UInt8], host: String, port: UInt16, parameters: NWParameters, framed: Bool,
                          accept: @escaping ([UInt8]) -> Bool) async throws -> DNSExchange {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw DNSLookupError.invalidServer(host) }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: parameters)
        let completion = DNSCompletion()
        let timeout = self.timeout

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Already cancelled: the continuation was resumed, don't start the connection
                guard completion.set(continuation, cleanup: { connection.cancel() }) else { return }
                let clock = QueryClock()
                // The address and port the connection actually reached (a DoT host name resolves to one of several)
                func finish(_ response: [UInt8]) {
                    let remote = DNSServerEndpoint.address(of: connection.currentPath?.remoteEndpoint)
                    let endpoint = DNSServerEndpoint(address: remote?.address, port: remote?.port ?? port, host: host,
                                                     url: nil, httpProtocol: nil)
                    completion.finish(.success(DNSExchange(response: response, milliseconds: clock.milliseconds, endpoint: endpoint)))
                }
                func receiveDatagram() {
                    connection.receiveMessage { data, _, _, error in
                        guard let data else { completion.finish(.failure(error ?? DNSLookupError.noResponse)); return }
                        if accept([UInt8](data)) {
                            finish([UInt8](data))
                        } else {
                            receiveDatagram()   // spoofed or stale datagram: keep waiting until the timeout
                        }
                    }
                }

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        let payload = framed ? [UInt8(query.count >> 8), UInt8(query.count & 0xFF)] + query : query
                        clock.start()
                        connection.send(content: Data(payload), completion: .contentProcessed { error in
                            if let error { completion.finish(.failure(error)) }
                        })
                        if framed {
                            connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { header, _, _, error in
                                guard let header, header.count == 2 else {
                                    completion.finish(.failure(error ?? DNSLookupError.noResponse)); return
                                }
                                let length = Int(header[header.startIndex]) << 8 | Int(header[header.startIndex + 1])
                                guard length > 0 else { completion.finish(.failure(DNSLookupError.noResponse)); return }
                                connection.receive(minimumIncompleteLength: length, maximumLength: length) { body, _, _, error in
                                    if let body, body.count == length {
                                        let response = [UInt8](body)
                                        if accept(response) {
                                            finish(response)
                                        } else {
                                            completion.finish(.failure(DNSLookupError.mismatchedResponse))
                                        }
                                    } else {
                                        completion.finish(.failure(error ?? DNSLookupError.noResponse))
                                    }
                                }
                            }
                        } else {
                            receiveDatagram()
                        }
                    case .waiting(let error), .failed(let error):
                        completion.finish(.failure(error))
                    case .cancelled:
                        completion.finish(.failure(CancellationError()))
                    default:
                        break
                    }
                }
                connection.start(queue: .global(qos: .userInitiated))
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    completion.finish(.failure(DNSLookupError.timedOut(host)))
                }
            }
        } onCancel: {
            completion.finish(.failure(CancellationError()))
        }
    }

    /// DoH POST with application/dns-message (RFC 8484 4.1).
    /// The time and the server address come from URLSessionTaskMetrics: from sending the request to the end of the
    /// response, without the host name lookup and the TLS/QUIC handshake (the UDP/TCP/DoT clocks also start on a
    /// ready connection).
    private func httpsExchange(_ query: [UInt8], url: URL) async throws -> DNSExchange {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/dns-message", forHTTPHeaderField: "Content-Type")
        request.setValue("application/dns-message", forHTTPHeaderField: "Accept")
        request.httpBody = Data(query)
        let collector = DoHMetricsCollector()
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let (data, response) = try await URLSession.shared.data(for: request, delegate: collector)
        let wallClock = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DNSLookupError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let mediaType = http.value(forHTTPHeaderField: "Content-Type")?.split(separator: ";").first
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard mediaType == "application/dns-message" else {
            throw DNSLookupError.notDNSMessage(http.value(forHTTPHeaderField: "Content-Type") ?? "none")
        }
        let measurement = Self.dohMeasurement(collector.transactions, url: url, fallbackMilliseconds: wallClock)
        return DNSExchange(response: [UInt8](data), milliseconds: measurement.milliseconds, endpoint: measurement.endpoint)
    }

    /// Query time and server endpoint of a DoH exchange from its transaction metrics. The last network transaction
    /// carries the response (an earlier one may be a cache lookup or a redirect); without metrics the time falls back
    /// to the wall clock around the whole request and the address stays unknown.
    static func dohMeasurement(_ transactions: [DoHTransaction], url: URL,
                               fallbackMilliseconds: Double) -> (milliseconds: Double, endpoint: DNSServerEndpoint) {
        let host = url.host ?? url.absoluteString
        let defaultPort = UInt16(url.port ?? 443)
        guard let last = transactions.last(where: { $0.isNetworkLoad }) else {
            return (fallbackMilliseconds, DNSServerEndpoint(address: nil, port: defaultPort, host: host, url: url, httpProtocol: nil))
        }
        var milliseconds = fallbackMilliseconds
        if let start = last.requestStart, let end = last.responseEnd, end >= start {
            milliseconds = end.timeIntervalSince(start) * 1000
        }
        let port = last.remotePort.flatMap { UInt16(exactly: $0) } ?? defaultPort
        return (milliseconds, DNSServerEndpoint(address: last.remoteAddress, port: port, host: host, url: url,
                                                httpProtocol: last.protocolName))
    }

    // MARK: - System Resolver

    /// DNS servers the system uses (first resolver), read through libresolv like `scutil --dns` shows them.
    /// Falls back to /etc/resolv.conf; both work inside the App Sandbox.
    static func systemServers() -> [String] {
        let fromLibresolv = libresolvServers()
        return fromLibresolv.isEmpty ? resolvConfServers() : fromLibresolv
    }

    /// res_9_ninit + res_9_getservers, loaded at run time because resolv.h is not part of a Swift module
    private static func libresolvServers() -> [String] {
        guard let library = dlopen("/usr/lib/libresolv.9.dylib", RTLD_NOW) else { return [] }
        defer { dlclose(library) }
        guard let initPointer = dlsym(library, "res_9_ninit"),
              let getPointer = dlsym(library, "res_9_getservers"),
              let destroyPointer = dlsym(library, "res_9_ndestroy") else { return [] }
        typealias InitFunction = @convention(c) (UnsafeMutableRawPointer) -> Int32
        typealias GetFunction = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, Int32) -> Int32
        typealias DestroyFunction = @convention(c) (UnsafeMutableRawPointer) -> Void

        // struct __res_9_state is 552 bytes; union res_sockaddr_union is 128 bytes
        let state = UnsafeMutableRawPointer.allocate(byteCount: 8192, alignment: 16)
        state.initializeMemory(as: UInt8.self, repeating: 0, count: 8192)
        defer { state.deallocate() }
        guard unsafeBitCast(initPointer, to: InitFunction.self)(state) == 0 else { return [] }
        defer { unsafeBitCast(destroyPointer, to: DestroyFunction.self)(state) }

        let maxServers = 8, unionSize = 128
        let addresses = UnsafeMutableRawPointer.allocate(byteCount: unionSize * maxServers, alignment: 16)
        addresses.initializeMemory(as: UInt8.self, repeating: 0, count: unionSize * maxServers)
        defer { addresses.deallocate() }
        let count = unsafeBitCast(getPointer, to: GetFunction.self)(state, addresses, Int32(maxServers))

        return (0..<Int(max(count, 0))).compactMap { index in
            let entry = addresses + index * unionSize
            let family = Int32(entry.load(fromByteOffset: 1, as: UInt8.self))
            var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            switch family {
            case AF_INET: return inet_ntop(AF_INET, entry + 4, &text, socklen_t(text.count)).map { _ in String(cString: text) }
            case AF_INET6:
                guard inet_ntop(AF_INET6, entry + 8, &text, socklen_t(text.count)) != nil else { return nil }
                // A link-local server needs its zone (sin6_scope_id at offset 24), e.g. fe80::1%en0
                let scope = entry.load(fromByteOffset: 24, as: UInt32.self)
                var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                if scope != 0, if_indextoname(scope, &name) != nil {
                    return String(cString: text) + "%" + String(cString: name)
                }
                return String(cString: text)
            default: return nil
            }
        }
    }

    private static func resolvConfServers() -> [String] {
        guard let text = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8) else { return [] }
        return parseResolvConf(text)
    }

    /// "nameserver" lines of a resolv.conf
    static func parseResolvConf(_ text: String) -> [String] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            return fields.count >= 2 && fields[0] == "nameserver" ? String(fields[1]) : nil
        }
    }
}

enum DNSLookupError: LocalizedError {
    case timedOut(String)
    case noResponse
    case mismatchedResponse
    case invalidServer(String)
    case unsupportedTransport(DNSTransport, String)
    case httpStatus(Int)
    case notDNSMessage(String)
    case tcpRetryFailed(String)

    var errorDescription: String? {
        switch self {
        case .timedOut(let host): return "No response from \(host) (timed out)"
        case .noResponse: return "The server closed the connection without a response"
        case .mismatchedResponse: return "The response does not match the query"
        case .invalidServer(let host): return "Invalid server: \(host)"
        case .unsupportedTransport(let transport, let server): return "\(server) does not support \(transport.rawValue)"
        case .httpStatus(let status): return "DoH server answered HTTP \(status)"
        case .notDNSMessage(let type): return "DoH server answered with \(type) instead of application/dns-message"
        case .tcpRetryFailed(let reason): return "The UDP answer was truncated and the retry over TCP failed: \(reason)"
        }
    }
}

/// A response with the time it took and the server end of the connection
private struct DNSExchange {
    let response: [UInt8]
    let milliseconds: Double
    let endpoint: DNSServerEndpoint
}

/// The parts of URLSessionTaskTransactionMetrics a DoH result needs (the metrics class cannot be built in tests)
struct DoHTransaction {
    let isNetworkLoad: Bool
    let requestStart: Date?
    let responseEnd: Date?
    let remoteAddress: String?
    let remotePort: Int?
    /// ALPN protocol, e.g. "h2" or "h3"
    let protocolName: String?

    init(isNetworkLoad: Bool, requestStart: Date?, responseEnd: Date?, remoteAddress: String?, remotePort: Int?, protocolName: String?) {
        self.isNetworkLoad = isNetworkLoad
        self.requestStart = requestStart
        self.responseEnd = responseEnd
        self.remoteAddress = remoteAddress
        self.remotePort = remotePort
        self.protocolName = protocolName
    }

    init(_ metrics: URLSessionTaskTransactionMetrics) {
        self.init(isNetworkLoad: metrics.resourceFetchType == .networkLoad, requestStart: metrics.requestStartDate,
                  responseEnd: metrics.responseEndDate, remoteAddress: metrics.remoteAddress, remotePort: metrics.remotePort,
                  protocolName: metrics.networkProtocolName)
    }
}

/// Task delegate that keeps the transaction metrics of one DoH request
private final class DoHMetricsCollector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [DoHTransaction] = []

    var transactions: [DoHTransaction] {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let transactions = metrics.transactionMetrics.map(DoHTransaction.init)
        lock.lock()
        collected = transactions
        lock.unlock()
    }
}

/// Time since the query was sent, shared between the connection callbacks
private final class QueryClock: @unchecked Sendable {
    private let lock = NSLock()
    private var startedAt: UInt64 = 0

    func start() {
        lock.lock()
        startedAt = DispatchTime.now().uptimeNanoseconds
        lock.unlock()
    }

    var milliseconds: Double {
        lock.lock()
        defer { lock.unlock() }
        return Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
    }
}

/// Resumes a continuation exactly once from whichever thread gets there first, then runs the cleanup
private final class DNSCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<DNSExchange, Error>?
    private var cleanup: (() -> Void)?
    private var pending: Result<DNSExchange, Error>?

    /// Returns false if the operation already finished (cancelled early); the continuation is resumed then
    @discardableResult
    func set(_ continuation: CheckedContinuation<DNSExchange, Error>, cleanup: @escaping () -> Void) -> Bool {
        lock.lock()
        if let pending {
            self.pending = nil
            lock.unlock()
            cleanup()
            continuation.resume(with: pending)
            return false
        }
        self.continuation = continuation
        self.cleanup = cleanup
        lock.unlock()
        return true
    }

    func finish(_ result: Result<DNSExchange, Error>) {
        lock.lock()
        guard let continuation else {
            if pending == nil { pending = result }
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

extension DNSServerEndpoint {
    /// IP address and port of a resolved connection endpoint; nil for a name or other endpoint kinds
    static func address(of endpoint: NWEndpoint?) -> (address: String, port: UInt16)? {
        guard case .hostPort(let host, let port)? = endpoint else { return nil }
        switch host {
        case .ipv4(let address): return ("\(address)", port.rawValue)
        case .ipv6(let address): return ("\(address)", port.rawValue)
        default: return nil
        }
    }
}
