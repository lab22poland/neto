//
//  ICMPPacketTests.swift
//  netoTests
//
//  Created by Sergii Solianyk on 12/10/2026.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Testing
@testable import neto

/// Encoding and decoding of ICMP echo packets, without sockets
struct ICMPPacketTests {

    /// IPv4 header (IHL 5, protocol ICMP) followed by the given ICMP bytes
    private func ipv4Packet(icmp: Data, ihl: UInt8 = 5, protocolNumber: UInt8 = 1) -> Data {
        var header = Data(count: Int(ihl) * 4)
        header[0] = 0x40 | ihl
        header[9] = protocolNumber
        return header + icmp
    }

    /// An echo reply as the peer would send it back for our request
    private func echoReply(identifier: UInt16, sequenceNumber: UInt16, payload: Data = Data([1, 2, 3])) -> Data {
        var reply = ICMPPacket.echoRequest(family: AF_INET, identifier: identifier, sequenceNumber: sequenceNumber, payload: payload)
        reply[0] = ICMPPacket.echoReplyV4
        reply[2] = 0
        reply[3] = 0
        let sum = ICMPPacket.checksum(reply)
        reply[2] = UInt8(sum >> 8)
        reply[3] = UInt8(sum & 0xFF)
        return reply
    }

    @Test func checksumMatchesRFC1071Example() {
        // RFC 1071 section 3 example: words 0001 f203 f4f5 f6f7 sum to 0xddf2, checksum is its complement
        #expect(ICMPPacket.checksum(Data([0x00, 0x01, 0xf2, 0x03, 0xf4, 0xf5, 0xf6, 0xf7])) == ~UInt16(0xddf2))
    }

    @Test func checksumPadsOddLength() {
        #expect(ICMPPacket.checksum(Data([0xab])) == ICMPPacket.checksum(Data([0xab, 0x00])))
    }

    @Test func ipv4EchoRequestLayout() {
        let packet = ICMPPacket.echoRequest(family: AF_INET, identifier: 0x1234, sequenceNumber: 0x0102, payload: Data([9, 9]))
        #expect(packet.count == 10)
        #expect(packet[0] == 8 && packet[1] == 0)
        #expect(Array(packet[4...7]) == [0x12, 0x34, 0x01, 0x02], "identifier and sequence number must be big-endian")
        #expect(ICMPPacket.checksum(packet) == 0, "a correct checksum makes the whole packet sum to zero")
    }

    @Test func ipv6EchoRequestLeavesChecksumToKernel() {
        let packet = ICMPPacket.echoRequest(family: AF_INET6, identifier: 1, sequenceNumber: 2, payload: Data())
        #expect(packet[0] == 128)
        #expect(packet[2] == 0 && packet[3] == 0)
    }

    @Test(arguments: [(UInt8(5), 20), (UInt8(6), 24)])
    func ipv4HeaderIsSkipped(ihl: UInt8, offset: Int) {
        #expect(ICMPPacket.icmpHeaderOffset(in: ipv4Packet(icmp: Data(count: 8), ihl: ihl), family: AF_INET) == offset)
    }

    @Test func malformedIPv4HeaderIsRejected() {
        var notVersion4 = ipv4Packet(icmp: Data(count: 8))
        notVersion4[0] = 0x65
        #expect(ICMPPacket.icmpHeaderOffset(in: notVersion4, family: AF_INET) == nil)
        #expect(ICMPPacket.icmpHeaderOffset(in: ipv4Packet(icmp: Data(count: 8), protocolNumber: 6), family: AF_INET) == nil)
        #expect(ICMPPacket.icmpHeaderOffset(in: Data(count: 19), family: AF_INET) == nil)
        var tooShortIHL = ipv4Packet(icmp: Data(count: 8))
        tooShortIHL[0] = 0x44
        #expect(ICMPPacket.icmpHeaderOffset(in: tooShortIHL, family: AF_INET) == nil)
    }

    @Test func ipv6RepliesHaveNoIPHeader() {
        #expect(ICMPPacket.icmpHeaderOffset(in: Data(count: 8), family: AF_INET6) == 0)
    }

    @Test func matchingReplyYieldsSequenceNumber() {
        let packet = ipv4Packet(icmp: echoReply(identifier: 0xBEEF, sequenceNumber: 7))
        #expect(ICMPPacket.echoReplySequenceNumber(in: packet, family: AF_INET, identifier: 0xBEEF) == 7)
    }

    @Test func foreignOrCorruptRepliesAreIgnored() {
        let reply = echoReply(identifier: 0xBEEF, sequenceNumber: 7)
        #expect(ICMPPacket.echoReplySequenceNumber(in: ipv4Packet(icmp: reply), family: AF_INET, identifier: 0xCAFE) == nil,
                "replies to another pinger's identifier must be ignored")

        var corrupted = reply
        corrupted[corrupted.count - 1] ^= 0xFF
        #expect(ICMPPacket.echoReplySequenceNumber(in: ipv4Packet(icmp: corrupted), family: AF_INET, identifier: 0xBEEF) == nil)

        var request = reply
        request[0] = ICMPPacket.echoRequestV4
        #expect(ICMPPacket.echoReplySequenceNumber(in: ipv4Packet(icmp: request), family: AF_INET, identifier: 0xBEEF) == nil)

        #expect(ICMPPacket.echoReplySequenceNumber(in: ipv4Packet(icmp: reply.prefix(6)), family: AF_INET, identifier: 0xBEEF) == nil)
    }

    @Test func ipv6ReplyIsMatchedWithoutChecksumCheck() {
        var reply = ICMPPacket.echoRequest(family: AF_INET6, identifier: 42, sequenceNumber: 3, payload: Data())
        reply[0] = ICMPPacket.echoReplyV6
        #expect(ICMPPacket.echoReplySequenceNumber(in: reply, family: AF_INET6, identifier: 42) == 3)
    }
}

/// Traceroute replies, using bytes captured from real routers on the path to 8.8.8.8 (probes: identifier 0xBEEF, sequence = TTL)
struct ICMPProbeReplyTests {

    private func bytes(_ hex: String) -> Data {
        Data(hex.split(separator: " ").map { UInt8($0, radix: 16)! })
    }

    /// TTL 1: home router, Time Exceeded quoting our full datagram
    private let timeExceededFull = "45 c0 3c 00 c9 e9 00 00 40 01 66 9b c0 a8 64 01 c0 a8 64 16 0b 00 f4 ff 00 00 00 00 45 00 34 00 c9 f6 00 00 01 01 bb 04 c0 a8 64 16 08 08 08 08 08 00 0d 31 be ef 00 01 54 52 45 58 50 2d 50 41 59 4c 4f 41 44 2d 30 31 32 33 34 35 36 37 38 39"
    /// TTL 5: a router quoting only the minimum (IP header + 8 bytes of ICMP, RFC 792)
    private let timeExceededMinimal = "45 c0 24 00 02 38 00 00 fb 01 2b a0 64 5f 08 0f c0 a8 64 16 0b 00 20 de 00 00 00 00 45 00 34 00 33 40 00 00 01 01 51 bb c0 a8 64 16 08 08 08 08 08 00 0d 2d be ef 00 05"
    /// TTL 4: a router appending RFC 4884 / MPLS extensions after the quote
    private let timeExceededMPLS = "45 00 94 00 a9 bc 00 00 fa 01 a5 47 53 ee f8 a3 c0 a8 64 16 0b 00 f4 ee 00 11 00 00 45 00 34 00 8c a3 00 00 01 01 f8 57 c0 a8 64 16 08 08 08 08 08 00 0d 2e be ef 00 04 54 52 45 58 50 2d 50 41 59 4c 4f 41 44 2d 30 31 32 33 34 35 36 37 38 39 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 20 00 38 14 00 08 01 01 05 e1 a1 01"
    /// TTL 11: Echo Reply from 8.8.8.8
    private let echoReply = "45 00 20 00 00 00 00 00 72 01 13 fb 08 08 08 08 c0 a8 64 16 00 00 15 27 be ef 00 0b 54 52 45 58 50 2d 50 41 59 4c 4f 41 44 2d 30 31 32 33 34 35 36 37 38 39"

    @Test func timeExceededFromRouters() {
        #expect(ICMPPacket.probeReply(in: bytes(timeExceededFull), family: AF_INET, identifier: 0xBEEF) == .timeExceeded(sequenceNumber: 1))
        #expect(ICMPPacket.probeReply(in: bytes(timeExceededMinimal), family: AF_INET, identifier: 0xBEEF) == .timeExceeded(sequenceNumber: 5))
        #expect(ICMPPacket.probeReply(in: bytes(timeExceededMPLS), family: AF_INET, identifier: 0xBEEF) == .timeExceeded(sequenceNumber: 4))
    }

    @Test func echoReplyFromTarget() {
        #expect(ICMPPacket.probeReply(in: bytes(echoReply), family: AF_INET, identifier: 0xBEEF) == .echoReply(sequenceNumber: 11))
    }

    @Test func repliesToOtherProbesAreIgnored() {
        for packet in [timeExceededFull, timeExceededMinimal, timeExceededMPLS, echoReply] {
            #expect(ICMPPacket.probeReply(in: bytes(packet), family: AF_INET, identifier: 0xCAFE) == nil)
        }
    }

    @Test func truncatedQuoteIsIgnored() {
        let minimal = bytes(timeExceededMinimal)
        #expect(ICMPPacket.probeReply(in: minimal.prefix(minimal.count - 1), family: AF_INET, identifier: 0xBEEF) == nil)
    }

    @Test func destinationUnreachableCarriesCode() {
        var packet = bytes(timeExceededFull)
        packet[20] = 3   // Destination Unreachable
        packet[21] = 1   // host unreachable
        #expect(ICMPPacket.probeReply(in: packet, family: AF_INET, identifier: 0xBEEF) == .destinationUnreachable(sequenceNumber: 1, code: 1))
    }

    @Test func ipv6TimeExceededPerRFC4443() {
        // Constructed (not captured): ICMPv6 Time Exceeded, quoted 40-byte IPv6 header (next header 58), quoted echo request
        var packet = Data([3, 0, 0, 0, 0, 0, 0, 0])
        var quotedHeader = Data(count: 40)
        quotedHeader[0] = 0x60
        quotedHeader[6] = 58
        packet += quotedHeader
        packet += ICMPPacket.echoRequest(family: AF_INET6, identifier: 0xBEEF, sequenceNumber: 9, payload: Data())
        #expect(ICMPPacket.probeReply(in: packet, family: AF_INET6, identifier: 0xBEEF) == .timeExceeded(sequenceNumber: 9))
    }
}
