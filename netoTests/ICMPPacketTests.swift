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
