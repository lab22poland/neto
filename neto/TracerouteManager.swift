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
    /// The probe in flight and its send time on the monotonic clock (DispatchTime nanoseconds). Like traceroute,
    /// only a reply to this probe counts; a late reply to an earlier probe is ignored.
    private var awaitedProbe: (sequenceNumber: UInt16, sentAt: UInt64)?
    private var awaitedReply: ProbeAnswer?
    /// Answers per hop row of the current run, so a router name that arrives later can re-deliver the latest row
    private var hops: [UUID: (hopNumber: Int, probes: [ProbeAnswer?])] = [:]
    private var hostnames: [UUID: String] = [:]
    private var runTask: Task<Void, Never>?
    /// Incremented per socket, so replies read from a closed socket cannot reach a newer run
    private var socketGeneration = 0
    /// Serial queue that reads the socket
    private let readQueue = DispatchQueue(label: "pl.lab22.neto.traceroute.read", qos: .userInitiated)
    /// Set when receiving fails hard (e.g. EPERM in the sandbox); ends the run
    private var socketError: Error?

    /// The reply to one probe
    struct ProbeAnswer: Equatable {
        /// Round-trip time in milliseconds
        let time: Double
        /// Address that answered
        let address: String
        let reply: ICMPPacket.ProbeReply
    }

    /// What one reply means for its hop, as decided by traceroute.c (IPv4) and traceroute6.c (IPv6)
    struct ProbeVerdict: Equatable {
        /// Printed after the probe's time, e.g. "!H"
        let annotation: String?
        /// The probe got to the target ("got_there")
        let reachedTarget: Bool
        /// Counts towards giving up on an unreachable path
        let unreachable: Bool
    }

    deinit {
        // Close the socket if the manager goes away during a run
        readSource?.cancel()
    }

    // MARK: - Public Methods

    /// Traces the route to the specified host
    /// - Parameters:
    ///   - host: The target host (IP address or domain name)
    ///   - maxHops: Maximum TTL / hop limit to probe
    ///   - timeout: Seconds to wait for the reply to each probe (traceroute `-w`, default 5); probes go out one after another
    ///   - onResult: Called on the main actor after every probe with the hop's row so far; the same row (same `id`)
    ///     comes again with the next probe and when the router's name is resolved, even after the run has ended
    ///   - onComplete: Called exactly once when the run ends, including after cancellation; carries the error that
    ///     ended the run (resolution, socket or send failure), nil when it finished or was cancelled
    /// - Returns: A Task that can be cancelled
    @MainActor
    func performTraceroute(
        to host: String,
        maxHops: Int = 30,
        timeout: TimeInterval = 5.0,
        onResult: @escaping (TracerouteResult) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) -> Task<Void, Never> {
        // Runs share the socket state, so a new run waits until the previous (cancelled) one has finished.
        let previousTask = runTask
        previousTask?.cancel()
        let task = Task { @MainActor [weak self] in
            await previousTask?.value
            guard let self else { onComplete(nil); return }
            let error = await self.trace(host: host, maxHops: maxHops, timeout: timeout) { result in
                if !Task.isCancelled { onResult(result) }
            }
            self.closeSocket()
            onComplete(Task.isCancelled ? nil : error)
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

    /// Formats the router part of a hop row; empty when no probe was answered (the probe columns show "*")
    func formatHopMessage(ipAddress: String?, hostname: String?, isDestination: Bool) -> String {
        var components: [String] = []

        if let hostname = hostname, hostname != ipAddress {
            components.append(hostname)
        }

        if let ipAddress = ipAddress {
            components.append("(\(ipAddress))")
        }

        let hostInfo = components.joined(separator: " ")
        if isDestination {
            return "\(hostInfo) [DESTINATION REACHED]"
        } else {
            return hostInfo
        }
    }

    // MARK: - Tracing

    /// Runs the trace like traceroute's main loop: per hop, probes go out one after another and each waits for its
    /// own reply or the timeout. Returns the error that ended the run, nil when it finished or was cancelled.
    @MainActor
    private func trace(host: String, maxHops: Int, timeout: TimeInterval, deliver: @escaping (TracerouteResult) -> Void) async -> Error? {
        guard maxHops >= 1 else { return nil }
        let target: ResolvedHost
        do {
            target = try await resolveHost(host)
        } catch {
            return Task.isCancelled ? nil : error
        }
        if Task.isCancelled { return nil }

        do {
            try openSocket(family: target.family)
            for hop in 1...maxHops {
                try setHopLimit(hop)
                let id = UUID()
                var probes: [ProbeAnswer?] = []
                for _ in 0..<Self.probesPerHop {
                    if Task.isCancelled { return nil }
                    let sequenceNumber = try sendProbe(to: target, hop: hop)
                    await waitForReply(to: sequenceNumber, timeout: timeout)
                    if let socketError { throw socketError }
                    if Task.isCancelled { return nil }
                    let answer = awaitedReply
                    awaitedProbe = nil
                    probes.append(answer)
                    hops[id] = (hop, probes)
                    // Like traceroute, the router's name is looked up for the first address that answers
                    if let answer, probes.compactMap({ $0 }).count == 1 {
                        resolveName(of: id, address: answer.address, deliver: deliver)
                    }
                    deliver(makeResult(id: id))
                }
                let verdicts = probes.compactMap { $0.map { Self.verdict(for: $0.reply, family: family) } }
                if Self.endsTrace(verdicts, family: family) { return nil }
            }
            return nil
        } catch {
            return Task.isCancelled ? nil : error
        }
    }

    /// Builds the row of a hop from its answers so far and the router's name, if already known
    @MainActor
    private func makeResult(id: UUID) -> TracerouteResult {
        let (hopNumber, probes) = hops[id] ?? (0, [])
        let answered = probes.compactMap { $0 }
        let verdicts = probes.map { $0.map { Self.verdict(for: $0.reply, family: family) } }
        let routerAddress = answered.first?.address
        let reachedTarget = verdicts.contains { $0?.reachedTarget == true }
        let hostname = hostnames[id]
        let times = answered.map(\.time)
        return TracerouteResult(
            id: id,
            hopNumber: hopNumber,
            success: !answered.isEmpty,
            ipAddress: routerAddress,
            hostname: hostname,
            responseTime: times.isEmpty ? 0 : times.reduce(0, +) / Double(times.count),
            message: formatHopMessage(ipAddress: routerAddress, hostname: hostname, isDestination: reachedTarget),
            isDestination: reachedTarget,
            probeTimes: probes.map { $0?.time },
            probeAnnotations: verdicts.map { $0?.annotation },
            probeAddresses: probes.map { $0?.address }
        )
    }

    /// Classifies a probe reply like traceroute's `packet_ok` switch (IPv4) or traceroute6 (IPv6)
    static func verdict(for reply: ICMPPacket.ProbeReply, family: Int32) -> ProbeVerdict {
        switch reply {
        case .timeExceeded:
            return ProbeVerdict(annotation: nil, reachedTarget: false, unreachable: false)
        case .echoReply:
            return ProbeVerdict(annotation: nil, reachedTarget: true, unreachable: false)
        case .destinationUnreachable(_, let code):
            if family == AF_INET6 {
                // RFC 4443 codes as printed by traceroute6; port unreachable means the target was reached,
                // other codes are neither printed nor counted
                switch code {
                case 0: return ProbeVerdict(annotation: "!N", reachedTarget: false, unreachable: true)
                case 1: return ProbeVerdict(annotation: "!P", reachedTarget: false, unreachable: true)
                case 2: return ProbeVerdict(annotation: "!S", reachedTarget: false, unreachable: true)
                case 3: return ProbeVerdict(annotation: "!A", reachedTarget: false, unreachable: true)
                case 4: return ProbeVerdict(annotation: nil, reachedTarget: true, unreachable: false)
                default: return ProbeVerdict(annotation: nil, reachedTarget: false, unreachable: false)
                }
            }
            switch code {
            case 3: return ProbeVerdict(annotation: nil, reachedTarget: true, unreachable: false)
            case 2: return ProbeVerdict(annotation: "!P", reachedTarget: true, unreachable: false)
            default: return ProbeVerdict(annotation: unreachableAnnotation(code: code), reachedTarget: false, unreachable: true)
            }
        }
    }

    /// traceroute stops after the hop that got to the target, or when most probes of the hop came back unreachable:
    /// at least nprobes - 1 (traceroute.c) or (nprobes + 1) / 2 (traceroute6.c), which is 2 of 3 for both
    static func endsTrace(_ verdicts: [ProbeVerdict], family: Int32) -> Bool {
        if verdicts.contains(where: \.reachedTarget) { return true }
        let unreachable = verdicts.filter(\.unreachable).count
        let limit = family == AF_INET6 ? (probesPerHop + 1) / 2 : probesPerHop - 1
        return unreachable > 0 && unreachable >= limit
    }

    /// Sets the TTL / hop limit of the following probes
    @MainActor
    private func setHopLimit(_ hop: Int) throws {
        var limit = Int32(hop)
        let status = family == AF_INET6
            ? setsockopt(socketFD, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &limit, socklen_t(MemoryLayout<Int32>.size))
            : setsockopt(socketFD, IPPROTO_IP, IP_TTL, &limit, socklen_t(MemoryLayout<Int32>.size))
        // Without the hop limit the probes would reach the target and hop 1 would look like the destination
        guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    /// Sends one echo probe and returns its sequence number. A failed send (e.g. "Socket is not connected" for
    /// 0.0.0.0) throws: traceroute prints the error and keeps waiting out every probe, the app reports it and stops.
    @MainActor
    private func sendProbe(to target: ResolvedHost, hop: Int) throws -> UInt16 {
        let sequenceNumber = nextSequenceNumber
        nextSequenceNumber &+= 1
        let packet = ICMPPacket.echoRequest(family: family, identifier: identifier, sequenceNumber: sequenceNumber, payload: Data(repeating: 0x4E, count: 24))
        awaitedReply = nil
        awaitedProbe = (sequenceNumber, DispatchTime.now().uptimeNanoseconds)
        let sent = packet.withUnsafeBytes { bytes in
            target.address.withUnsafeBytes { address in
                sendto(socketFD, bytes.baseAddress, bytes.count, 0,
                       address.bindMemory(to: sockaddr.self).baseAddress, socklen_t(target.address.count))
            }
        }
        guard sent == packet.count else {
            let reason = sent < 0 ? String(cString: strerror(errno)) : "wrote \(sent) of \(packet.count) bytes"
            awaitedProbe = nil
            throw TracerouteError.sendFailed(hop: hop, reason: reason)
        }
        return sequenceNumber
    }

    /// Waits until the probe is answered or `timeout` seconds after it was sent (traceroute's `wait_for_reply`)
    @MainActor
    private func waitForReply(to sequenceNumber: UInt16, timeout: TimeInterval) async {
        guard let sentAt = awaitedProbe?.sentAt else { return }
        let deadline = sentAt + UInt64(timeout * 1_000_000_000)
        while !Task.isCancelled, socketError == nil, awaitedReply == nil, DispatchTime.now().uptimeNanoseconds < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// Looks up the router's name in the background and re-delivers the hop's latest row with it. There is no
    /// time limit (traceroute resolves synchronously); a name that arrives after the run is still delivered.
    @MainActor
    private func resolveName(of id: UUID, address: String, deliver: @escaping (TracerouteResult) -> Void) {
        let generation = socketGeneration
        Task { @MainActor in
            let lookedUp = (try? await Self.runBlocking { Self.reverseLookup(address) }) ?? nil
            guard let name = lookedUp, name != address,
                  generation == self.socketGeneration, self.hops[id] != nil else { return }
            self.hostnames[id] = name
            deliver(self.makeResult(id: id))
        }
    }

    // MARK: - Socket

    @MainActor
    private func openSocket(family: Int32) throws {
        closeSocket()
        self.family = family
        identifier = UInt16.random(in: 1...UInt16.max)
        awaitedProbe = nil
        awaitedReply = nil
        hops.removeAll()
        hostnames.removeAll()
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
        source.setEventHandler { [weak self, weak source] in
            let (received, error) = Self.readReplies(fd: fd, family: family, identifier: identifier)
            // Cancel right here on a hard error: the read source is level-triggered and would fire again immediately
            if error != nil { source?.cancel() }
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

    /// Records the first reply to the probe in flight; replies to earlier probes are ignored like in traceroute
    @MainActor
    private func record(_ received: [ReceivedReply], error: Error?, generation: Int) {
        guard generation == socketGeneration else { return }
        for item in received {
            guard let awaitedProbe, awaitedReply == nil,
                  item.reply.sequenceNumber == awaitedProbe.sequenceNumber,
                  item.receivedAt >= awaitedProbe.sentAt else { continue }
            awaitedReply = ProbeAnswer(time: Double(item.receivedAt - awaitedProbe.sentAt) / 1_000_000, address: item.address, reply: item.reply)
        }
        if let error, socketError == nil {
            // Stop reading instead of spinning on the read source; the trace loop reports the error
            socketError = error
            closeSocket()
        }
    }

    /// Annotation of an IPv4 Destination Unreachable code as printed by traceroute.c (RFC 792 / RFC 1812 codes;
    /// traceroute adds the next-hop MTU to "!F", which the app does not read)
    static func unreachableAnnotation(code: UInt8) -> String {
        switch code {
        case 0: return "!N"
        case 1: return "!H"
        case 2: return "!P"
        case 4: return "!F"
        case 5: return "!S"
        case 6: return "!U"
        case 7: return "!W"
        case 8: return "!I"
        case 9: return "!A"
        case 10: return "!Z"
        case 11: return "!Q"
        case 12: return "!T"
        case 13: return "!X"
        case 14: return "!V"
        case 15: return "!C"
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
    case sendFailed(hop: Int, reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidHost(let message):
            return message
        case .resolutionFailed(let host, let reason):
            return "Cannot resolve \(host): \(reason)"
        case .sendFailed(let hop, let reason):
            return "Cannot send the probe for hop \(hop): sendto: \(reason)"
        }
    }
}
