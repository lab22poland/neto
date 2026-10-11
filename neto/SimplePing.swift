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
        func simplePing(_ pinger: SimplePing, didReceivePingResponsePacket packet: Data, sequenceNumber: UInt16)
        
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
        
        startReceiving()
        delegate?.simplePing(self, didStartWithAddress: hostAddress)
    }
    
    /// Starts receiving ICMP responses using a dispatch read source on the main queue
    private func startReceiving() {
        let fd = socket
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            self?.readData(fd: fd)
        }
        source.setCancelHandler {
            close(fd)
        }
        readSource = source
        source.resume()
    }
    
    private func readData(fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 65535)
        while true {
            let bytesRead = recv(fd, &buffer, buffer.count, 0)
            if bytesRead < 0 {
                let err = errno
                if err == EAGAIN || err == EWOULDBLOCK || err == EINTR { return }
                // Hard error (e.g. sandbox deny): stop reading instead of spinning on the read source.
                readSource?.cancel()
                readSource = nil
                socket = -1
                delegate?.simplePing(self, didFailWithError: POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO))
                return
            }
            guard bytesRead > 0 else { return }
            processReceivedPacket(Data(buffer[0..<bytesRead]))
        }
    }
    
    /// Processes a received ICMP packet (always called on the main queue)
    private func processReceivedPacket(_ packetData: Data) {
        if let sequenceNumber = ICMPPacket.echoReplySequenceNumber(in: packetData, family: addressFamily, identifier: identifier) {
            delegate?.simplePing(self, didReceivePingResponsePacket: packetData, sequenceNumber: sequenceNumber)
        } else {
            delegate?.simplePing(self, didReceiveUnexpectedPacket: packetData)
        }
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
