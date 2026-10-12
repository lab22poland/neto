//
//  TracerouteManager.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Darwin

/// Traces the route to a host with ICMP echo probes and an increasing TTL (hop limit), like `traceroute -I`.
/// Uses an unprivileged SOCK_DGRAM ICMP socket: routers answer with Time Exceeded, the target with Echo Reply.
/// IPv6 (ICMPv6, hop limit) follows the same scheme but has not been verified on a live IPv6 network.
final class TracerouteManager {

    /// Echo probes sent per hop
    static let probesPerHop = 3

    /// A host name or address resolved to a socket address
    struct ResolvedHost {
        let address: Data
        let family: Int32
        let ipAddress: String
    }

    /// Syntactic kind of the user's input, checked before any DNS lookup
    enum HostKind: Equatable {
        case ipv4, ipv6, name
    }

    // All mutable state is touched only on the main actor
    private var socketFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var family: Int32 = AF_INET
    private var identifier: UInt16 = 0
    private var nextSequenceNumber: UInt16 = 0
    /// Send time per sequence number on the monotonic clock (DispatchTime nanoseconds)
    private var sendTimes: [UInt16: UInt64] = [:]
    private var replies: [UInt16: (time: Double, address: String, reply: ICMPPacket.ProbeReply)] = [:]
    private var runTask: Task<Void, Never>?
    /// Incremented per socket, so replies read from a closed socket cannot reach a newer run
    private var socketGeneration = 0
    /// Serial queue that reads the socket
    private let readQueue = DispatchQueue(label: "pl.lab22.neto.traceroute.read", qos: .userInitiated)
    /// Set when receiving fails hard (e.g. EPERM in the sandbox); ends the run
    private var socketError: Error?

    // MARK: - Public Methods

    /// Traces the route to the specified host
    /// - Parameters:
    ///   - host: The target host (IP address or domain name)
    ///   - maxHops: Maximum TTL / hop limit to probe
    ///   - timeout: Seconds to wait for the replies of one hop
    ///   - onResult: Called on the main actor with one result per hop; called again with the same `id` when the router's name is resolved
    ///   - onComplete: Called exactly once when the run ends, including after cancellation
    /// - Returns: A Task that can be cancelled
    @MainActor
    func performTraceroute(
        to host: String,
        maxHops: Int = 30,
        timeout: TimeInterval = 5.0,
        onResult: @escaping (TracerouteResult) -> Void,
        onComplete: @escaping () -> Void
    ) -> Task<Void, Never> {
        // Runs share the socket state, so a new run waits until the previous (cancelled) one has finished.
        let previousTask = runTask
        previousTask?.cancel()
        let task = Task { @MainActor [weak self] in
            await previousTask?.value
            guard let self else { onComplete(); return }
            await self.trace(host: host, maxHops: maxHops, timeout: timeout) { result in
                if !Task.isCancelled { onResult(result) }
            }
            self.closeSocket()
            onComplete()
        }
        runTask = task
        return task
    }

    /// Classifies the input before any network access; throws for malformed addresses and host names
    func classifyHost(_ host: String) throws -> HostKind {
        guard !host.isEmpty else {
            throw TracerouteError.invalidHost("Host cannot be empty")
        }
        if host.allSatisfy({ $0.isNumber || $0 == "." }) {
            guard isValidIPv4(host) else { throw TracerouteError.invalidHost("Invalid IPv4 address format: \(host)") }
            return .ipv4
        }
        if host.contains(":") {
            var address = in6_addr()
            guard inet_pton(AF_INET6, host, &address) == 1 else { throw TracerouteError.invalidHost("Invalid IPv6 address format: \(host)") }
            return .ipv6
        }
        guard isValidHostname(host) else { throw TracerouteError.invalidHost("Invalid hostname format: \(host)") }
        return .name
    }

    /// Resolves the host to a socket address; IPv4 is preferred when a name has both address families
    func resolveHost(_ host: String) async throws -> ResolvedHost {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = try classifyHost(trimmedHost)
        return try await Self.runBlocking {
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_DGRAM
            if kind != .name { hints.ai_flags = AI_NUMERICHOST }
            var list: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(trimmedHost, nil, &hints, &list)
            defer { if let list { freeaddrinfo(list) } }
            guard status == 0, let list else {
                throw TracerouteError.resolutionFailed(trimmedHost, String(cString: gai_strerror(status)))
            }
            var candidates: [ResolvedHost] = []
            var entry: UnsafeMutablePointer<addrinfo>? = list
            while let current = entry {
                let info = current.pointee
                if info.ai_family == AF_INET || info.ai_family == AF_INET6 {
                    let address = Data(bytes: info.ai_addr, count: Int(info.ai_addrlen))
                    candidates.append(ResolvedHost(address: address, family: info.ai_family, ipAddress: Self.numericHost(address) ?? trimmedHost))
                }
                entry = info.ai_next
            }
            guard let best = candidates.first(where: { $0.family == AF_INET }) ?? candidates.first else {
                throw TracerouteError.resolutionFailed(trimmedHost, "no IPv4 or IPv6 address")
            }
            return best
        }
    }

    /// Validates IPv4 address format strictly
    func isValidIPv4(_ ipString: String) -> Bool {
        let components = ipString.split(separator: ".", omittingEmptySubsequences: false)
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
    func isValidHostname(_ hostname: String) -> Bool {
        let hostnameRegex = "^[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?)*$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", hostnameRegex)
        return predicate.evaluate(with: hostname) && hostname.count <= 253
    }

    /// Formats the hop message for display
    func formatHopMessage(
        ipAddress: String?,
        hostname: String?,
        isDestination: Bool,
        unreachableCode: UInt8? = nil,
        family: Int32 = AF_INET
    ) -> String {
        var components: [String] = []

        if let hostname = hostname, hostname != ipAddress {
            components.append(hostname)
        }

        if let ipAddress = ipAddress {
            components.append("(\(ipAddress))")
        }

        var hostInfo = components.isEmpty ? "* * *" : components.joined(separator: " ")
        if let unreachableCode {
            hostInfo += " " + Self.unreachableAnnotation(code: unreachableCode, family: family)
        }

        if isDestination {
            return "\(hostInfo) [DESTINATION REACHED]"
        } else {
            return hostInfo
        }
    }

    // MARK: - Tracing

    @MainActor
    private func trace(host: String, maxHops: Int, timeout: TimeInterval, deliver: @escaping (TracerouteResult) -> Void) async {
        guard maxHops >= 1 else { return }
        let target: ResolvedHost
        do {
            target = try await resolveHost(host)
        } catch {
            if !Task.isCancelled {
                deliver(TracerouteResult(hopNumber: 1, success: false, responseTime: 0,
                                         message: "Failed to resolve host: \(host) - \(error.localizedDescription)"))
            }
            return
        }
        if Task.isCancelled { return }

        for hop in 1...maxHops {
            if Task.isCancelled { return }
            let sequenceNumbers: [UInt16]
            do {
                if hop == 1 { try openSocket(family: target.family) }
                sequenceNumbers = try sendProbes(to: target, hopLimit: hop)
                await waitForReplies(to: sequenceNumbers, timeout: timeout)
                if let socketError { throw socketError }
            } catch {
                if !Task.isCancelled {
                    deliver(TracerouteResult(hopNumber: hop, success: false, responseTime: 0,
                                             message: "Traceroute failed: \(error.localizedDescription)"))
                }
                return
            }
            if Task.isCancelled { return }

            let answered = sequenceNumbers.compactMap { replies[$0] }
            let routerAddress = answered.first?.address
            let reachedTarget = answered.contains { reply in
                if case .echoReply = reply.reply { return true }
                if case .destinationUnreachable = reply.reply { return reply.address == target.ipAddress }
                return false
            }
            let unreachableCode = answered.lazy.compactMap { reply -> UInt8? in
                if case .destinationUnreachable(_, let code) = reply.reply { return code } else { return nil }
            }.first
            let probeTimes: [Double?] = sequenceNumbers.map { replies[$0]?.time }
            let probeAddresses: [String?] = sequenceNumbers.map { replies[$0]?.address }
            let times = probeTimes.compactMap { $0 }
            let result = TracerouteResult(
                hopNumber: hop,
                success: !answered.isEmpty,
                ipAddress: routerAddress,
                responseTime: times.isEmpty ? 0 : times.reduce(0, +) / Double(times.count),
                message: formatHopMessage(ipAddress: routerAddress, hostname: nil, isDestination: reachedTarget,
                                          unreachableCode: unreachableCode, family: family),
                isDestination: reachedTarget,
                probeTimes: probeTimes,
                unreachableCode: unreachableCode,
                probeAddresses: probeAddresses
            )
            deliver(result)
            if let routerAddress {
                resolveName(of: result, address: routerAddress, deliver: deliver)
            }
            // The path ends at the target, or where a router reports the target unreachable
            if reachedTarget || unreachableCode != nil { return }
        }
    }

    /// Sends the probes of one hop and returns their sequence numbers
    @MainActor
    private func sendProbes(to target: ResolvedHost, hopLimit: Int) throws -> [UInt16] {
        var limit = Int32(hopLimit)
        let status = family == AF_INET6
            ? setsockopt(socketFD, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &limit, socklen_t(MemoryLayout<Int32>.size))
            : setsockopt(socketFD, IPPROTO_IP, IP_TTL, &limit, socklen_t(MemoryLayout<Int32>.size))
        // Without the hop limit the probes would reach the target and hop 1 would look like the destination
        guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var sent: [UInt16] = []
        for _ in 0..<Self.probesPerHop {
            let sequenceNumber = nextSequenceNumber
            nextSequenceNumber &+= 1
            let packet = ICMPPacket.echoRequest(family: family, identifier: identifier, sequenceNumber: sequenceNumber, payload: Data(repeating: 0x4E, count: 24))
            sendTimes[sequenceNumber] = DispatchTime.now().uptimeNanoseconds
            _ = packet.withUnsafeBytes { bytes in
                target.address.withUnsafeBytes { address in
                    sendto(socketFD, bytes.baseAddress, bytes.count, 0,
                           address.bindMemory(to: sockaddr.self).baseAddress, socklen_t(target.address.count))
                }
            }
            // A failed send simply stays unanswered and shows as "*"
            sent.append(sequenceNumber)
        }
        return sent
    }

    @MainActor
    private func waitForReplies(to sequenceNumbers: [UInt16], timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !Task.isCancelled, Date() < deadline, sequenceNumbers.contains(where: { replies[$0] == nil }) {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// Looks up the router's name in the background and re-delivers the row with it (ignored if it arrives too late)
    @MainActor
    private func resolveName(of result: TracerouteResult, address: String, deliver: @escaping (TracerouteResult) -> Void) {
        let family = self.family
        Task { @MainActor in
            let lookedUp = (try? await Self.runBlocking(timeout: 2) { Self.reverseLookup(address) }) ?? nil
            guard let name = lookedUp, name != address else { return }
            deliver(TracerouteResult(
                id: result.id,
                hopNumber: result.hopNumber,
                success: result.success,
                ipAddress: result.ipAddress,
                hostname: name,
                responseTime: result.responseTime,
                message: formatHopMessage(ipAddress: address, hostname: name, isDestination: result.isDestination,
                                          unreachableCode: result.unreachableCode, family: family),
                isDestination: result.isDestination,
                probeTimes: result.probeTimes,
                unreachableCode: result.unreachableCode,
                probeAddresses: result.probeAddresses
            ))
        }
    }

    // MARK: - Socket

    @MainActor
    private func openSocket(family: Int32) throws {
        closeSocket()
        self.family = family
        identifier = UInt16.random(in: 1...UInt16.max)
        sendTimes.removeAll()
        replies.removeAll()
        socketError = nil

        let fd = Darwin.socket(family, SOCK_DGRAM, family == AF_INET6 ? IPPROTO_ICMPV6 : IPPROTO_ICMP)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        socketFD = fd

        // Replies are read and timestamped off the main thread, so main-thread latency does not inflate the RTT;
        // the results are then recorded on the main actor.
        let identifier = self.identifier
        socketGeneration += 1
        let generation = socketGeneration
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: readQueue)
        source.setEventHandler { [weak self] in
            let (received, error) = Self.readReplies(fd: fd, family: family, identifier: identifier)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.record(received, error: error, generation: generation) }
            }
        }
        source.setCancelHandler { close(fd) }
        readSource = source
        source.resume()
    }

    @MainActor
    private func closeSocket() {
        if let readSource {
            // The cancel handler closes the descriptor, so the reader never sees a reused fd.
            readSource.cancel()
            self.readSource = nil
        } else if socketFD >= 0 {
            close(socketFD)
        }
        socketFD = -1
    }

    /// A probe reply as read from the socket, with its receive time on the monotonic clock
    private struct ReceivedReply {
        let reply: ICMPPacket.ProbeReply
        let address: String
        let receivedAt: UInt64
    }

    /// Drains the socket (runs on `readQueue`). Every ICMP socket sees all ICMP traffic of the host,
    /// so only replies to our identifier are kept. Returns a hard error (e.g. sandbox deny) if receiving fails.
    private static func readReplies(fd: Int32, family: Int32, identifier: UInt16) -> ([ReceivedReply], Error?) {
        var received: [ReceivedReply] = []
        var buffer = [UInt8](repeating: 0, count: 2048)
        var from = sockaddr_storage()
        while true {
            var fromLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let count = withUnsafeMutablePointer(to: &from) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buffer, buffer.count, 0, $0, &fromLength) }
            }
            if count < 0 {
                let error = errno
                if error == EAGAIN || error == EWOULDBLOCK || error == EINTR { return (received, nil) }
                return (received, POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO))
            }
            guard count > 0 else { return (received, nil) }
            let now = DispatchTime.now().uptimeNanoseconds
            guard let reply = ICMPPacket.probeReply(in: Data(buffer[0..<count]), family: family, identifier: identifier) else { continue }
            let address = withUnsafeBytes(of: &from) { numericHost(Data($0.prefix(Int(fromLength)))) } ?? "?"
            received.append(ReceivedReply(reply: reply, address: address, receivedAt: now))
        }
    }

    /// Records replies of the current socket; the first reply per sequence number wins
    @MainActor
    private func record(_ received: [ReceivedReply], error: Error?, generation: Int) {
        guard generation == socketGeneration else { return }
        for item in received {
            guard let sent = sendTimes[item.reply.sequenceNumber],
                  replies[item.reply.sequenceNumber] == nil,
                  item.receivedAt >= sent else { continue }
            replies[item.reply.sequenceNumber] = (Double(item.receivedAt - sent) / 1_000_000, item.address, item.reply)
        }
        if let error, socketError == nil {
            // Stop reading instead of spinning on the read source; the trace loop reports the error
            socketError = error
            closeSocket()
        }
    }

    /// traceroute-style annotation of an ICMP Destination Unreachable code
    static func unreachableAnnotation(code: UInt8, family: Int32) -> String {
        if family == AF_INET6 {
            // RFC 4443: 0 no route, 1 administratively prohibited, 3 address unreachable, 4 port unreachable
            switch code {
            case 0: return "!N"
            case 1: return "!X"
            case 3: return "!H"
            case 4: return "!P"
            default: return "!<\(code)>"
            }
        }
        // RFC 792 / RFC 1812: 0 net, 1 host, 2 protocol, 3 port, 9/10/13 administratively prohibited
        switch code {
        case 0: return "!N"
        case 1: return "!H"
        case 2, 3: return "!P"
        case 9, 10, 13: return "!X"
        default: return "!<\(code)>"
        }
    }

    // MARK: - Blocking Calls

    /// Runs a blocking resolver call on a global queue, off the cooperative thread pool.
    /// Cancellation or the optional timeout resumes the caller right away; the call itself finishes in the background.
    static func runBlocking<T>(timeout: TimeInterval? = nil, _ work: @escaping @Sendable () throws -> T) async throws -> T {
        let once = ResumeOnce<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                once.set(continuation)
                DispatchQueue.global(qos: .userInitiated).async {
                    once.resume(with: Result { try work() })
                }
                if let timeout {
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        once.resume(with: .failure(CancellationError()))
                    }
                }
            }
        } onCancel: {
            once.resume(with: .failure(CancellationError()))
        }
    }

    // MARK: - Address Helpers

    /// Numeric host string of a socket address
    static func numericHost(_ address: Data) -> String? {
        address.withUnsafeBytes { raw -> String? in
            guard let sa = raw.bindMemory(to: sockaddr.self).baseAddress else { return nil }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(address.count), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
            return String(cString: host)
        }
    }

    /// Reverse DNS name of a numeric address, or nil
    static func reverseLookup(_ ipAddress: String) -> String? {
        var hints = addrinfo()
        hints.ai_flags = AI_NUMERICHOST
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(ipAddress, nil, &hints, &list) == 0, let list else { return nil }
        defer { freeaddrinfo(list) }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(list.pointee.ai_addr, list.pointee.ai_addrlen, &host, socklen_t(host.count), nil, 0, NI_NAMEREQD) == 0 else { return nil }
        return String(cString: host)
    }
}

// MARK: - Supporting Types

/// Resumes a continuation exactly once from whichever thread gets there first
private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var pending: Result<T, Error>?

    func set(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        if let pending {
            self.pending = nil
            lock.unlock()
            continuation.resume(with: pending)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func resume(with result: Result<T, Error>) {
        lock.lock()
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
            return
        }
        // Not set yet (cancelled before start): remember the first result only
        if pending == nil { pending = result }
        lock.unlock()
    }
}

enum TracerouteError: LocalizedError {
    case invalidHost(String)
    case resolutionFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .invalidHost(let message):
            return message
        case .resolutionFailed(let host, let reason):
            return "Cannot resolve \(host): \(reason)"
        }
    }
}
