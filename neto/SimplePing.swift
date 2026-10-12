//
//  SimplePing.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Network
import Darwin

/// A modern Swift implementation of Apple's SimplePing sample code
/// Provides ICMP echo request/response functionality for network connectivity testing
final class SimplePing: NSObject {
    
    // MARK: - Types
    
    /// Delegate protocol for ping operations
    protocol Delegate: AnyObject {
        /// Called when the ping operation starts
        func simplePing(_ pinger: SimplePing, didStartWithAddress address: Data)
        
        /// Called when the ping operation fails to start
        func simplePing(_ pinger: SimplePing, didFailWithError error: Error)
        
        /// Called when an echo request is sent
        func simplePing(_ pinger: SimplePing, didSendPacket packet: Data, sequenceNumber: UInt16)
        
        /// Called when an echo request fails to send
        func simplePing(_ pinger: SimplePing, didFailToSendPacket packet: Data, sequenceNumber: UInt16, error: Error)
        
        /// Called when an echo response is received
        /// - Parameters:
        ///   - address: The sender's socket address (sockaddr_in / sockaddr_in6) as returned by recvmsg
        ///   - receivedAt: Receive time on the `SimplePing.now()` clock (kernel timestamp when available)
        func simplePing(_ pinger: SimplePing, didReceivePingResponsePacket packet: Data, sequenceNumber: UInt16, from address: Data, receivedAt: UInt64)
        
        /// Called when an unexpected packet is received
        func simplePing(_ pinger: SimplePing, didReceiveUnexpectedPacket packet: Data)
    }
    
    // MARK: - Properties
    
    private let hostName: String
    private let identifier: UInt16
    private weak var delegate: Delegate?
    
    private var hostAddress: Data?
    private var socketAddress: Data?
    private var socket: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var addressFamily: Int32 = AF_INET
    private var nextSequenceNumber: UInt16 = 0
    /// Serial queue that reads the socket and timestamps replies, so main-queue latency does not add to the RTT
    private let readQueue = DispatchQueue(label: "pl.lab22.neto.ping.read", qos: .userInitiated)
    
    // MARK: - Initialization
    
    /// Creates a new SimplePing instance
    /// - Parameters:
    ///   - hostName: The target host name or IP address
    ///   - identifier: A unique identifier for this ping session
    ///   - delegate: The delegate to receive ping callbacks
    init(hostName: String, identifier: UInt16, delegate: Delegate) {
        self.hostName = hostName
        self.identifier = identifier
        self.delegate = delegate
        super.init()
    }
    
    /// The host name being pinged
    var targetHostName: String { return self.hostName }
    
    /// Monotonic time in nanoseconds (mach_absolute_time, the clock of SO_TIMESTAMP_MONOTONIC); use it for send times
    static func now() -> UInt64 {
        nanoseconds(fromMachTime: mach_absolute_time())
    }
    
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()
    
    /// Converts mach_absolute_time ticks to nanoseconds
    static func nanoseconds(fromMachTime ticks: UInt64) -> UInt64 {
        let numer = UInt64(timebase.numer), denom = UInt64(timebase.denom)
        return ticks / denom * numer + ticks % denom * numer / denom
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Public Methods
    
    /// Starts the ping operation
    func start() {
        // Resolve the host name to an address
        resolveHostName()
    }
    
    /// Stops the ping operation
    func stop() {
        if let readSource = readSource {
            // The cancel handler closes the descriptor, so the reader never sees a reused fd.
            readSource.cancel()
            self.readSource = nil
        } else if socket != -1 {
            close(socket)
        }
        socket = -1
        hostAddress = nil
        socketAddress = nil
    }
    
    /// Sends an echo request
    /// - Parameter payload: Optional payload data to include in the echo request
    /// - Returns: The sequence number of the sent packet, or nil if failed
    @discardableResult
    func sendPingWithPayload(_ payload: Data? = nil) -> UInt16? {
        guard hostAddress != nil,
              let socketAddress = socketAddress,
              socket != -1 else {
            return nil
        }
        
        let sequenceNumber = nextSequenceNumber
        nextSequenceNumber += 1
        
        // Create the ICMP packet
        guard let packet = createICMPPacket(sequenceNumber: sequenceNumber, payload: payload) else {
            return nil
        }
        
        // Send the packet
        let bytesSent = packet.withUnsafeBytes { packetBytes in
            sendto(socket, packetBytes.baseAddress, packetBytes.count, 0, socketAddress.withUnsafeBytes { $0.bindMemory(to: sockaddr.self).baseAddress }, socklen_t(socketAddress.count))
        }
        
        let sendErrno = errno
        if bytesSent == packet.count {
            delegate?.simplePing(self, didSendPacket: packet, sequenceNumber: sequenceNumber)
            return sequenceNumber
        } else {
            let error = POSIXError(POSIXErrorCode(rawValue: bytesSent < 0 ? sendErrno : EMSGSIZE) ?? .EIO)
            delegate?.simplePing(self, didFailToSendPacket: packet, sequenceNumber: sequenceNumber, error: error)
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    /// Resolves the host name to an IP address
    private func resolveHostName() {
        let queue = DispatchQueue.global(qos: .userInitiated)
        queue.async { [weak self] in
            guard let self = self else { return }
            
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_DGRAM
            
            var result: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(self.hostName, nil, &hints, &result)
            
            defer {
                if let result = result {
                    freeaddrinfo(result)
                }
            }
            
            guard status == 0, let addrInfo = result else {
                let message = String(cString: gai_strerror(status))
                let error = NSError(domain: "SimplePing.getaddrinfo", code: Int(status), userInfo: [NSLocalizedDescriptionKey: message])
                DispatchQueue.main.async {
                    self.delegate?.simplePing(self, didFailWithError: error)
                }
                return
            }
            
            // Convert the address to Data
            let addressData = Data(bytes: addrInfo.pointee.ai_addr, count: Int(addrInfo.pointee.ai_addrlen))
            
            DispatchQueue.main.async {
                self.hostAddress = addressData
                self.socketAddress = addressData
                self.setupSocket()
            }
        }
    }
    
    /// Sets up the socket for ICMP communication
    private func setupSocket() {
        guard let hostAddress = hostAddress else { return }
        
        addressFamily = hostAddress.withUnsafeBytes { Int32($0.load(fromByteOffset: 1, as: UInt8.self)) } // sa_family
        let proto = addressFamily == AF_INET6 ? IPPROTO_ICMPV6 : IPPROTO_ICMP
        
        socket = Darwin.socket(addressFamily, SOCK_DGRAM, proto)
        guard socket != -1 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            delegate?.simplePing(self, didFailWithError: error)
            return
        }
        
        let flags = fcntl(socket, F_GETFL)
        _ = fcntl(socket, F_SETFL, flags | O_NONBLOCK)
        // Kernel receive timestamps on the monotonic clock (verified on macOS for SOCK_DGRAM ICMP);
        // if the option is refused, readReplies falls back to the time the packet is read.
        var on: Int32 = 1
        _ = setsockopt(socket, SOL_SOCKET, SO_TIMESTAMP_MONOTONIC, &on, socklen_t(MemoryLayout<Int32>.size))
        
        startReceiving()
        delegate?.simplePing(self, didStartWithAddress: hostAddress)
    }
    
    /// Starts receiving ICMP responses using a dispatch read source on a background queue;
    /// delegate callbacks are still delivered on the main queue
    private func startReceiving() {
        let fd = socket
        let family = addressFamily
        let identifier = identifier
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: readQueue)
        var failed = false   // touched only on readQueue
        source.setEventHandler { [weak self] in
            guard !failed else { return }
            let (replies, error) = Self.readReplies(fd: fd, family: family, identifier: identifier)
            if error != nil { failed = true }
            guard !replies.isEmpty || error != nil else { return }
            DispatchQueue.main.async {
                // Nothing is delivered once the pinger has been stopped
                guard let self, self.readSource === source else { return }
                for reply in replies {
                    guard self.readSource === source else { return }
                    if let sequenceNumber = reply.sequenceNumber {
                        self.delegate?.simplePing(self, didReceivePingResponsePacket: reply.packet, sequenceNumber: sequenceNumber,
                                                  from: reply.address, receivedAt: reply.receivedAt)
                    } else {
                        self.delegate?.simplePing(self, didReceiveUnexpectedPacket: reply.packet)
                    }
                }
                // Hard error (e.g. sandbox deny): stop reading instead of spinning on the read source.
                // ping(8) only warns about a recvmsg error and keeps reading; this divergence is deliberate.
                if let error {
                    source.cancel()
                    self.readSource = nil
                    self.socket = -1
                    self.delegate?.simplePing(self, didFailWithError: error)
                }
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        readSource = source
        source.resume()
    }
    
    /// A packet read from the socket with its sender and receive time
    private struct ReceivedPacket {
        let packet: Data
        let address: Data
        let receivedAt: UInt64
        /// Set if the packet is an echo reply to our identifier
        let sequenceNumber: UInt16?
    }
    
    /// Drains the socket with recvmsg (runs on `readQueue`). Returns the packets read so far and a hard error, if any.
    private static func readReplies(fd: Int32, family: Int32, identifier: UInt16) -> ([ReceivedPacket], Error?) {
        var packets: [ReceivedPacket] = []
        var buffer = [UInt8](repeating: 0, count: 65535)
        var control = [UInt8](repeating: 0, count: 128)
        var from = sockaddr_storage()
        while true {
            var kernelTime: UInt64?
            var fromLength = socklen_t(0)
            let bytesRead: Int = buffer.withUnsafeMutableBytes { bufferBytes in
                control.withUnsafeMutableBytes { controlBytes in
                    withUnsafeMutablePointer(to: &from) { fromPointer in
                        var iov = iovec(iov_base: bufferBytes.baseAddress, iov_len: bufferBytes.count)
                        return withUnsafeMutablePointer(to: &iov) { iovPointer in
                            var message = msghdr()
                            message.msg_name = UnsafeMutableRawPointer(fromPointer)
                            message.msg_namelen = socklen_t(MemoryLayout<sockaddr_storage>.size)
                            message.msg_iov = iovPointer
                            message.msg_iovlen = 1
                            message.msg_control = controlBytes.baseAddress
                            message.msg_controllen = socklen_t(controlBytes.count)
                            let count = recvmsg(fd, &message, 0)
                            guard count >= 0 else { return count }
                            fromLength = message.msg_namelen
                            kernelTime = monotonicTimestamp(in: UnsafeRawBufferPointer(rebasing: controlBytes[..<Int(message.msg_controllen)]))
                            return count
                        }
                    }
                }
            }
            if bytesRead < 0 {
                let err = errno
                if err == EAGAIN || err == EWOULDBLOCK || err == EINTR { return (packets, nil) }
                return (packets, POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO))
            }
            guard bytesRead > 0 else { return (packets, nil) }
            let receivedAt = kernelTime.map { nanoseconds(fromMachTime: $0) } ?? now()
            let packet = Data(buffer[0..<bytesRead])
            let address = withUnsafeBytes(of: &from) { Data($0.prefix(Int(fromLength))) }
            packets.append(ReceivedPacket(packet: packet, address: address, receivedAt: receivedAt,
                                          sequenceNumber: ICMPPacket.echoReplySequenceNumber(in: packet, family: family, identifier: identifier)))
        }
    }
    
    /// The SCM_TIMESTAMP_MONOTONIC value (mach_absolute_time ticks) from a recvmsg control buffer, or nil
    private static func monotonicTimestamp(in control: UnsafeRawBufferPointer) -> UInt64? {
        let headerSize = MemoryLayout<cmsghdr>.size
        let align = { (length: Int) in (length + 3) & ~3 }   // __DARWIN_ALIGN32
        var offset = 0
        while offset + headerSize <= control.count {
            let header = control.loadUnaligned(fromByteOffset: offset, as: cmsghdr.self)
            guard header.cmsg_len >= headerSize, offset + Int(header.cmsg_len) <= control.count else { return nil }
            let dataOffset = offset + align(headerSize)
            if header.cmsg_level == SOL_SOCKET, header.cmsg_type == SCM_TIMESTAMP_MONOTONIC,
               dataOffset + MemoryLayout<UInt64>.size <= control.count {
                return control.loadUnaligned(fromByteOffset: dataOffset, as: UInt64.self)
            }
            offset += align(Int(header.cmsg_len))
        }
        return nil
    }
    
    /// Creates an ICMP echo request packet
    private func createICMPPacket(sequenceNumber: UInt16, payload: Data?) -> Data? {
        ICMPPacket.echoRequest(family: addressFamily, identifier: identifier, sequenceNumber: sequenceNumber, payload: payload ?? Data())
    }
}

// MARK: - ICMP Packet Encoding

/// Pure ICMP echo encoding/decoding used by SimplePing (no sockets, testable)
enum ICMPPacket {
    static let headerSize = 8
    static let echoRequestV4: UInt8 = 8
    static let echoReplyV4: UInt8 = 0
    static let echoRequestV6: UInt8 = 128
    static let echoReplyV6: UInt8 = 129
    
    /// Builds an echo request: type, code 0, checksum, identifier and sequence number in network byte order, payload.
    /// For ICMPv6 the checksum stays 0 because the kernel computes it (it covers a pseudo-header).
    static func echoRequest(family: Int32, identifier: UInt16, sequenceNumber: UInt16, payload: Data) -> Data {
        var packet = Data([family == AF_INET6 ? echoRequestV6 : echoRequestV4, 0, 0, 0,
                           UInt8(identifier >> 8), UInt8(identifier & 0xFF),
                           UInt8(sequenceNumber >> 8), UInt8(sequenceNumber & 0xFF)])
        packet.append(payload)
        if family != AF_INET6 {
            let sum = checksum(packet)
            packet[2] = UInt8(sum >> 8)
            packet[3] = UInt8(sum & 0xFF)
        }
        return packet
    }
    
    /// Returns the offset of the ICMP header. IPv4 SOCK_DGRAM ICMP sockets on Darwin
    /// deliver the IP header too; IPv6 ones do not.
    static func icmpHeaderOffset(in packet: Data, family: Int32) -> Int? {
        guard family == AF_INET else { return 0 }
        guard packet.count >= 20 else { return nil }
        let versionAndIHL = packet[packet.startIndex]
        guard versionAndIHL >> 4 == 4 else { return nil }
        let ipHeaderLength = Int(versionAndIHL & 0x0F) * 4
        guard ipHeaderLength >= 20, packet[packet.startIndex + 9] == UInt8(IPPROTO_ICMP) else { return nil }
        return ipHeaderLength
    }
    
    /// Returns the sequence number if the packet is an echo reply to our identifier (valid checksum on IPv4), otherwise nil
    static func echoReplySequenceNumber(in packet: Data, family: Int32, identifier: UInt16) -> UInt16? {
        guard let offset = icmpHeaderOffset(in: packet, family: family),
              packet.count >= offset + headerSize else { return nil }
        let icmp = Data(packet[(packet.startIndex + offset)...])
        let type = icmp[0], code = icmp[1]
        let replyIdentifier = UInt16(icmp[4]) << 8 | UInt16(icmp[5])
        guard type == (family == AF_INET6 ? echoReplyV6 : echoReplyV4),
              code == 0,
              replyIdentifier == identifier,
              family == AF_INET6 || checksum(icmp) == 0 else { return nil }
        return UInt16(icmp[6]) << 8 | UInt16(icmp[7])
    }
    
    /// What came back for a traceroute probe (an echo request sent with a limited TTL / hop limit)
    enum ProbeReply: Equatable {
        /// A router on the path dropped the probe (ICMP Time Exceeded)
        case timeExceeded(sequenceNumber: UInt16)
        /// The probe could not be delivered (ICMP Destination Unreachable); `code` as in the ICMP header
        case destinationUnreachable(sequenceNumber: UInt16, code: UInt8)
        /// The target answered (ICMP Echo Reply)
        case echoReply(sequenceNumber: UInt16)
        /// ICMPv6 Parameter Problem, unrecognized Next Header (code 1): the target got the probe (traceroute6 "!H")
        case parameterProblem(sequenceNumber: UInt16)
        
        var sequenceNumber: UInt16 {
            switch self {
            case .timeExceeded(let sequenceNumber), .destinationUnreachable(let sequenceNumber, _), .echoReply(let sequenceNumber),
                 .parameterProblem(let sequenceNumber):
                return sequenceNumber
            }
        }
    }
    
    /// Classifies a received packet as a reply to one of our probes (matched by identifier), or nil.
    /// Error messages quote our original datagram: its IP header plus at least 8 bytes of our ICMP header (RFC 792),
    /// which carry the identifier and sequence number. Like traceroute, only Time Exceeded in transit (code 0) counts,
    /// not fragment reassembly time exceeded (code 1). IPv6 support follows RFC 4443 and traceroute6 and is not verified
    /// on a live network.
    static func probeReply(in packet: Data, family: Int32, identifier: UInt16) -> ProbeReply? {
        if let sequenceNumber = echoReplySequenceNumber(in: packet, family: family, identifier: identifier) {
            return .echoReply(sequenceNumber: sequenceNumber)
        }
        guard let offset = icmpHeaderOffset(in: packet, family: family),
              packet.count >= offset + headerSize else { return nil }
        let bytes = [UInt8](packet)
        let type = bytes[offset], code = bytes[offset + 1]
        let quoted = offset + headerSize
        
        let quotedICMP: Int
        if family == AF_INET6 {
            // ICMPv6 Time Exceeded in transit / Destination Unreachable / Parameter Problem "unrecognized Next Header"
            guard (type == 3 && code == 0) || type == 1 || (type == 4 && code == 1) else { return nil }
            // Fixed 40-byte IPv6 header with Next Header = ICMPv6
            guard bytes.count >= quoted + 40, bytes[quoted] >> 4 == 6, bytes[quoted + 6] == UInt8(IPPROTO_ICMPV6) else { return nil }
            quotedICMP = quoted + 40
        } else {
            guard (type == 11 && code == 0) || type == 3 else { return nil }  // ICMP Time Exceeded in transit / Destination Unreachable
            guard bytes.count >= quoted + 20, bytes[quoted] >> 4 == 4, bytes[quoted + 9] == UInt8(IPPROTO_ICMP) else { return nil }
            let quotedHeaderLength = Int(bytes[quoted] & 0x0F) * 4
            guard quotedHeaderLength >= 20 else { return nil }
            quotedICMP = quoted + quotedHeaderLength
        }
        guard bytes.count >= quotedICMP + headerSize,
              bytes[quotedICMP] == (family == AF_INET6 ? echoRequestV6 : echoRequestV4),
              UInt16(bytes[quotedICMP + 4]) << 8 | UInt16(bytes[quotedICMP + 5]) == identifier else { return nil }
        let sequenceNumber = UInt16(bytes[quotedICMP + 6]) << 8 | UInt16(bytes[quotedICMP + 7])
        if type == (family == AF_INET6 ? 3 : 11) { return .timeExceeded(sequenceNumber: sequenceNumber) }
        if family == AF_INET6 && type == 4 { return .parameterProblem(sequenceNumber: sequenceNumber) }
        return .destinationUnreachable(sequenceNumber: sequenceNumber, code: code)
    }
    
    /// TTL of a received IPv4 packet (Darwin hands the IP header to SOCK_DGRAM ICMP sockets); nil for IPv6,
    /// whose hop limit would need IPV6_RECVHOPLIMIT ancillary data
    static func receivedTTL(in packet: Data, family: Int32) -> UInt8? {
        guard family == AF_INET, let offset = icmpHeaderOffset(in: packet, family: family), offset >= 20 else { return nil }
        return packet[packet.startIndex + 8]
    }
    
    /// Internet checksum (RFC 1071); returns the value in host order, to be written big-endian
    static func checksum(_ data: Data) -> UInt16 {
        var sum: UInt32 = 0
        var index = data.startIndex
        while index + 1 < data.endIndex {
            sum += UInt32(data[index]) << 8 | UInt32(data[index + 1])
            index += 2
        }
        if index < data.endIndex {
            sum += UInt32(data[index]) << 8
        }
        while sum > 0xFFFF {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return ~UInt16(sum)
    }
}
