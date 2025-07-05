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
    
    /// ICMP header structure
    private struct ICMPHeader {
        var type: UInt8
        var code: UInt8
        var checksum: UInt16
        var identifier: UInt16
        var sequenceNumber: UInt16
        
        init(type: UInt8, code: UInt8, identifier: UInt16, sequenceNumber: UInt16) {
            self.type = type
            self.code = code
            self.checksum = 0
            self.identifier = identifier
            self.sequenceNumber = sequenceNumber
        }
    }
    
    // MARK: - Constants
    
    private let ICMP_ECHO_REQUEST: UInt8 = 8
    private let ICMP_ECHO_REPLY: UInt8 = 0
    private let ICMP_TIMEOUT: UInt8 = 11
    
    // MARK: - Properties
    
    private let hostName: String
    private let identifier: UInt16
    private weak var delegate: Delegate?
    
    private var hostAddress: Data?
    private var socketAddress: Data?
    private var socket: Int32 = -1
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
        if socket != -1 {
            close(socket)
            socket = -1
        }
        hostAddress = nil
        socketAddress = nil
    }
    
    /// Sends an echo request
    /// - Parameter payload: Optional payload data to include in the echo request
    /// - Returns: The sequence number of the sent packet, or nil if failed
    @discardableResult
    func sendPingWithPayload(_ payload: Data? = nil) -> UInt16? {
        guard let hostAddress = hostAddress,
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
        
        if bytesSent == packet.count {
            delegate?.simplePing(self, didSendPacket: packet, sequenceNumber: sequenceNumber)
            return sequenceNumber
        } else {
            let error = POSIXError(.init(rawValue: errno)!)
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
            hints.ai_protocol = IPPROTO_ICMP
            
            var result: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(self.hostName, nil, &hints, &result)
            
            defer {
                if let result = result {
                    freeaddrinfo(result)
                }
            }
            
            guard status == 0, let addrInfo = result else {
                let error = POSIXError(.init(rawValue: status)!)
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
        
        // Determine the address family
        let addressFamily: Int32
        if hostAddress.count >= MemoryLayout<sockaddr_in>.size {
            let sockaddr = hostAddress.withUnsafeBytes { rawBuffer in
                let ptr = UnsafeRawPointer(rawBuffer.baseAddress!).assumingMemoryBound(to: Darwin.sockaddr.self)
                return ptr.pointee
            }
            addressFamily = Int32(sockaddr.sa_family)
        } else {
            addressFamily = AF_INET // Default to IPv4
        }
        
        // Create the socket
        socket = Darwin.socket(addressFamily, SOCK_DGRAM, IPPROTO_ICMP)
        
        guard socket != -1 else {
            let error = POSIXError(.init(rawValue: errno)!)
            delegate?.simplePing(self, didFailWithError: error)
            return
        }
        
        // Set socket options for non-blocking operation
        var value: Int32 = 1
        setsockopt(socket, SOL_SOCKET, O_NONBLOCK, &value, socklen_t(MemoryLayout<Int32>.size))
        
        // Start receiving responses
        startReceiving()
        
        // Notify delegate that we've started
        delegate?.simplePing(self, didStartWithAddress: hostAddress)
    }
    
    /// Starts receiving ICMP responses
    private func startReceiving() {
        let queue = DispatchQueue.global(qos: .userInitiated)
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let bufferSize = 65535
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            
            while self.socket != -1 {
                let bytesRead = recv(self.socket, buffer, bufferSize, 0)
                
                if bytesRead > 0 {
                    let packetData = Data(bytes: buffer, count: bytesRead)
                    self.processReceivedPacket(packetData)
                } else if bytesRead == -1 {
                    let errorCode = errno
                    if errorCode == EAGAIN || errorCode == EWOULDBLOCK {
                        // No data available, continue
                        usleep(10000) // 10ms
                        continue
                    } else {
                        // Error occurred
                        break
                    }
                } else {
                    // Connection closed
                    break
                }
            }
        }
    }
    
    /// Processes a received ICMP packet
    private func processReceivedPacket(_ packetData: Data) {
        guard packetData.count >= MemoryLayout<ICMPHeader>.size else { return }
        
        let header = packetData.withUnsafeBytes { $0.bindMemory(to: ICMPHeader.self).baseAddress!.pointee }
        
        switch header.type {
        case ICMP_ECHO_REPLY:
            if header.identifier == identifier {
                DispatchQueue.main.async {
                    self.delegate?.simplePing(self, didReceivePingResponsePacket: packetData, sequenceNumber: header.sequenceNumber)
                }
            } else {
                DispatchQueue.main.async {
                    self.delegate?.simplePing(self, didReceiveUnexpectedPacket: packetData)
                }
            }
            
        case ICMP_TIMEOUT:
            // TTL exceeded, could be used for traceroute
            DispatchQueue.main.async {
                self.delegate?.simplePing(self, didReceiveUnexpectedPacket: packetData)
            }
            
        default:
            // Other ICMP message types
            DispatchQueue.main.async {
                self.delegate?.simplePing(self, didReceiveUnexpectedPacket: packetData)
            }
        }
    }
    
    /// Creates an ICMP echo request packet
    private func createICMPPacket(sequenceNumber: UInt16, payload: Data?) -> Data? {
        var header = ICMPHeader(
            type: ICMP_ECHO_REQUEST,
            code: 0,
            identifier: identifier,
            sequenceNumber: sequenceNumber
        )
        
        // Calculate checksum
        header.checksum = calculateChecksum(header: header, payload: payload)
        
        // Create the packet
        var packet = Data()
        packet.append(Data(bytes: &header, count: MemoryLayout<ICMPHeader>.size))
        
        if let payload = payload {
            packet.append(payload)
        }
        
        return packet
    }
    
    /// Calculates the ICMP checksum
    private func calculateChecksum(header: ICMPHeader, payload: Data?) -> UInt16 {
        var headerCopy = header
        headerCopy.checksum = 0
        
        var data = Data()
        data.append(Data(bytes: &headerCopy, count: MemoryLayout<ICMPHeader>.size))
        
        if let payload = payload {
            data.append(payload)
        }
        
        // Ensure even length for checksum calculation
        if data.count % 2 != 0 {
            data.append(0)
        }
        
        var sum: UInt32 = 0
        data.withUnsafeBytes { bytes in
            let words = bytes.bindMemory(to: UInt16.self)
            for word in words {
                sum += UInt32(word.bigEndian)
            }
        }
        
        while sum > 0xFFFF {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        
        return UInt16(truncatingIfNeeded: ~sum).bigEndian
    }
} 