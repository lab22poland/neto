//
//  DNSMessage.swift
//  neto
//
//  Created by Sergii Solianyk on 12/10/2026.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation

/// DNS record types the lookup tool offers (RFC 1035, 3596, 2782, 8659, 4034, 9460)
enum DNSRecordType: UInt16, CaseIterable, Identifiable {
    case a = 1, ns = 2, cname = 5, soa = 6, ptr = 12, mx = 15, txt = 16, aaaa = 28, srv = 33
    case ds = 43, rrsig = 46, dnskey = 48, https = 65, caa = 257, any = 255

    var id: UInt16 { rawValue }

    /// Mnemonic as used by dig ("A", "MX", …)
    var name: String {
        switch self {
        case .a: return "A"
        case .ns: return "NS"
        case .cname: return "CNAME"
        case .soa: return "SOA"
        case .ptr: return "PTR"
        case .mx: return "MX"
        case .txt: return "TXT"
        case .aaaa: return "AAAA"
        case .srv: return "SRV"
        case .ds: return "DS"
        case .rrsig: return "RRSIG"
        case .dnskey: return "DNSKEY"
        case .https: return "HTTPS"
        case .caa: return "CAA"
        case .any: return "ANY"
        }
    }

    /// Mnemonic for any type code; unknown codes as "TYPE<n>" (RFC 3597)
    static func name(of code: UInt16) -> String {
        if code == 41 { return "OPT" }
        return DNSRecordType(rawValue: code)?.name ?? "TYPE\(code)"
    }
}

/// A resource record with dig-style presentation of its data
struct DNSRecord: Equatable {
    let name: String
    let type: UInt16
    let recordClass: UInt16
    let ttl: UInt32
    let data: String

    var typeName: String { DNSRecordType.name(of: type) }

    /// One line like dig: "google.com.  300  IN  A  142.250.120.138"
    var presentation: String {
        "\(name)\t\(ttl)\t\(recordClass == 1 ? "IN" : "CLASS\(recordClass)")\t\(typeName)\t\(data)"
    }
}

/// A parsed DNS response (RFC 1035 section 4.1)
struct DNSMessage: Equatable {
    let id: UInt16
    let flags: UInt16
    let questions: [(name: String, type: UInt16)]
    let answers: [DNSRecord]
    let authority: [DNSRecord]
    /// Additional records without the EDNS OPT pseudo-record
    let additional: [DNSRecord]
    /// EDNS UDP payload size announced by the server, nil without OPT
    let ednsUDPSize: UInt16?

    var isResponse: Bool { flags & 0x8000 != 0 }
    var isTruncated: Bool { flags & 0x0200 != 0 }
    var rcode: UInt16 { flags & 0x000F }

    /// RCODE name like dig ("NOERROR", "NXDOMAIN", …)
    var rcodeName: String {
        let names = ["NOERROR", "FORMERR", "SERVFAIL", "NXDOMAIN", "NOTIMP", "REFUSED", "YXDOMAIN", "YXRRSET", "NXRRSET", "NOTAUTH", "NOTZONE"]
        return Int(rcode) < names.count ? names[Int(rcode)] : "RCODE\(rcode)"
    }

    /// Header flags like dig ("qr rd ra ad")
    var flagNames: [String] {
        [(0x8000, "qr"), (0x0400, "aa"), (0x0200, "tc"), (0x0100, "rd"), (0x0080, "ra"), (0x0020, "ad"), (0x0010, "cd")]
            .filter { flags & UInt16($0.0) != 0 }.map(\.1)
    }

    static func == (lhs: DNSMessage, rhs: DNSMessage) -> Bool {
        lhs.id == rhs.id && lhs.flags == rhs.flags && lhs.answers == rhs.answers && lhs.authority == rhs.authority
            && lhs.additional == rhs.additional && lhs.ednsUDPSize == rhs.ednsUDPSize
            && lhs.questions.map { "\($0.name)/\($0.type)" } == rhs.questions.map { "\($0.name)/\($0.type)" }
    }
}

enum DNSMessageError: LocalizedError, Equatable {
    case invalidName(String)
    case truncatedMessage
    case badCompressionPointer

    var errorDescription: String? {
        switch self {
        case .invalidName(let name): return "Invalid DNS name: \(name)"
        case .truncatedMessage: return "The DNS response is truncated or malformed"
        case .badCompressionPointer: return "The DNS response has an invalid compression pointer"
        }
    }
}

/// RFC 1035 wire format: query building and response parsing (pure, no networking)
enum DNSWire {

    /// Builds a query: RD=1, AD=1 (RFC 6840 5.7: asks for the AD bit in the answer, like dig), one question,
    /// and an EDNS0 OPT record (RFC 6891) announcing `ednsUDPSize`
    static func query(name: String, type: UInt16, id: UInt16, ednsUDPSize: UInt16 = 1232) throws -> [UInt8] {
        var message: [UInt8] = []
        func u16(_ value: UInt16) { message += [UInt8(value >> 8), UInt8(value & 0xFF)] }
        u16(id); u16(0x0120); u16(1); u16(0); u16(0); u16(1)
        message += try encodeName(name)
        u16(type); u16(1)
        message += [0]; u16(41); u16(ednsUDPSize); u16(0); u16(0); u16(0)
        return message
    }

    /// Name as length-prefixed labels; a trailing dot is optional, "." is the root
    static func encodeName(_ name: String) throws -> [UInt8] {
        let trimmed = name.hasSuffix(".") ? String(name.dropLast()) : name
        var bytes: [UInt8] = []
        if !trimmed.isEmpty {
            for label in trimmed.split(separator: ".", omittingEmptySubsequences: false) {
                let utf8 = Array(label.utf8)
                guard !utf8.isEmpty, utf8.count <= 63 else { throw DNSMessageError.invalidName(name) }
                bytes.append(UInt8(utf8.count))
                bytes += utf8
            }
        }
        bytes.append(0)
        guard bytes.count <= 255 else { throw DNSMessageError.invalidName(name) }
        return bytes
    }

    /// Reverse-lookup name for an IPv4 or IPv6 address ("8.8.8.8" → "8.8.8.8.in-addr.arpa."), nil otherwise
    static func reverseName(for address: String) -> String? {
        var v4 = in_addr(), v6 = in6_addr()
        if inet_pton(AF_INET, address, &v4) == 1 {
            let bytes = withUnsafeBytes(of: &v4) { Array($0) }
            return bytes.reversed().map(String.init).joined(separator: ".") + ".in-addr.arpa."
        }
        if inet_pton(AF_INET6, address, &v6) == 1 {
            let bytes = withUnsafeBytes(of: &v6) { Array($0) }
            let nibbles = bytes.flatMap { [$0 >> 4, $0 & 0x0F] }
            return nibbles.reversed().map { String($0, radix: 16) }.joined(separator: ".") + ".ip6.arpa."
        }
        return nil
    }

    /// Parses a response. Names are absolute with a trailing dot, as dig prints them.
    static func parse(_ message: [UInt8]) throws -> DNSMessage {
        var reader = Reader(message: message)
        let id = try reader.u16()
        let flags = try reader.u16()
        let counts = (qd: try reader.u16(), an: try reader.u16(), ns: try reader.u16(), ar: try reader.u16())

        var questions: [(String, UInt16)] = []
        for _ in 0..<counts.qd {
            let name = try reader.name()
            let type = try reader.u16()
            _ = try reader.u16()
            questions.append((name, type))
        }
        func records(_ count: UInt16) throws -> [(record: DNSRecord, udpSize: UInt16?)] {
            try (0..<count).map { _ in try reader.record() }
        }
        let answers = try records(counts.an).map(\.record)
        let authority = try records(counts.ns).map(\.record)
        let additionalRaw = try records(counts.ar)
        return DNSMessage(
            id: id,
            flags: flags,
            questions: questions,
            answers: answers,
            authority: authority,
            additional: additionalRaw.filter { $0.record.type != 41 }.map(\.record),
            ednsUDPSize: additionalRaw.first { $0.record.type == 41 }?.udpSize
        )
    }

    /// Sequential reader over the message; names may point back into the whole message (RFC 1035 4.1.4)
    private struct Reader {
        let message: [UInt8]
        var offset = 0

        mutating func u8() throws -> UInt8 {
            guard offset < message.count else { throw DNSMessageError.truncatedMessage }
            defer { offset += 1 }
            return message[offset]
        }

        mutating func u16() throws -> UInt16 { UInt16(try u8()) << 8 | UInt16(try u8()) }

        mutating func u32() throws -> UInt32 { UInt32(try u16()) << 16 | UInt32(try u16()) }

        mutating func bytes(_ count: Int) throws -> [UInt8] {
            guard count >= 0, offset + count <= message.count else { throw DNSMessageError.truncatedMessage }
            defer { offset += count }
            return Array(message[offset..<(offset + count)])
        }

        mutating func name() throws -> String {
            let (name, next) = try DNSWire.readName(message, at: offset)
            offset = next
            return name
        }

        /// A resource record; OPT records return their UDP payload size (stored in CLASS)
        mutating func record() throws -> (record: DNSRecord, udpSize: UInt16?) {
            let name = try name()
            let type = try u16()
            let recordClass = try u16()
            let ttl = try u32()
            let length = Int(try u16())
            let rdataStart = offset
            let rdata = try bytes(length)
            let data = type == 41 ? "" : try DNSWire.presentation(type: type, rdata: rdata, message: message, rdataOffset: rdataStart)
            return (DNSRecord(name: name, type: type, recordClass: recordClass, ttl: ttl, data: data), type == 41 ? recordClass : nil)
        }
    }

    /// Reads a possibly compressed name; returns it and the offset after it in the original position
    static func readName(_ message: [UInt8], at start: Int) throws -> (String, Int) {
        var labels: [String] = []
        var offset = start
        var next: Int?
        var jumps = 0
        while true {
            guard offset < message.count else { throw DNSMessageError.truncatedMessage }
            let length = Int(message[offset])
            if length & 0xC0 == 0xC0 {
                guard offset + 1 < message.count else { throw DNSMessageError.truncatedMessage }
                let pointer = (length & 0x3F) << 8 | Int(message[offset + 1])
                jumps += 1
                guard pointer < message.count, jumps <= 64 else { throw DNSMessageError.badCompressionPointer }
                if next == nil { next = offset + 2 }
                offset = pointer
                continue
            }
            guard length & 0xC0 == 0 else { throw DNSMessageError.truncatedMessage }
            offset += 1
            if length == 0 { break }
            guard offset + length <= message.count else { throw DNSMessageError.truncatedMessage }
            labels.append(escapeLabel(Array(message[offset..<(offset + length)])))
            offset += length
        }
        return (labels.isEmpty ? "." : labels.joined(separator: ".") + ".", next ?? offset)
    }

    /// Label bytes as dig prints them: "." and "\" escaped, non-printable bytes as \DDD
    private static func escapeLabel(_ bytes: [UInt8]) -> String {
        bytes.map { byte -> String in
            switch byte {
            case 0x2E: return "\\."
            case 0x5C: return "\\\\"
            case 0x21...0x7E: return String(UnicodeScalar(byte))
            default: return String(format: "\\%03d", byte)
            }
        }.joined()
    }

    /// Character-string as dig prints it: quoted, with " and \ escaped and non-printable bytes as \DDD
    private static func quoted(_ bytes: ArraySlice<UInt8>) -> String {
        "\"" + bytes.map { byte -> String in
            switch byte {
            case 0x22: return "\\\""
            case 0x5C: return "\\\\"
            case 0x20...0x7E: return String(UnicodeScalar(byte))
            default: return String(format: "\\%03d", byte)
            }
        }.joined() + "\""
    }

    /// Record data in dig's presentation format; types without a dedicated format use RFC 3597 "\# len hex"
    static func presentation(type: UInt16, rdata: [UInt8], message: [UInt8], rdataOffset: Int) throws -> String {
        func u16(_ at: Int) throws -> UInt16 {
            guard at + 2 <= rdata.count else { throw DNSMessageError.truncatedMessage }
            return UInt16(rdata[at]) << 8 | UInt16(rdata[at + 1])
        }
        func u32(_ at: Int) throws -> UInt32 { UInt32(try u16(at)) << 16 | UInt32(try u16(at + 2)) }
        func name(_ at: Int) throws -> (String, Int) {
            let (name, next) = try readName(message, at: rdataOffset + at)
            return (name, next - rdataOffset)
        }
        let hex = { (bytes: ArraySlice<UInt8>) in bytes.map { String(format: "%02X", $0) }.joined() }

        switch DNSRecordType(rawValue: type) {
        case .a where rdata.count == 4:
            return rdata.map(String.init).joined(separator: ".")
        case .aaaa where rdata.count == 16:
            var address = in6_addr()
            withUnsafeMutableBytes(of: &address) { $0.copyBytes(from: rdata) }
            var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            return inet_ntop(AF_INET6, &address, &text, socklen_t(text.count)) != nil ? String(cString: text) : hex(rdata[...])
        case .ns, .cname, .ptr:
            return try name(0).0
        case .mx:
            return "\(try u16(0)) \(try name(2).0)"
        case .soa:
            let (mname, afterM) = try name(0)
            let (rname, afterR) = try name(afterM)
            let numbers = try (0..<5).map { try u32(afterR + $0 * 4) }
            return ([mname, rname] + numbers.map(String.init)).joined(separator: " ")
        case .txt:
            var parts: [String] = []
            var index = 0
            while index < rdata.count {
                let length = Int(rdata[index])
                guard index + 1 + length <= rdata.count else { throw DNSMessageError.truncatedMessage }
                parts.append(quoted(rdata[(index + 1)..<(index + 1 + length)]))
                index += 1 + length
            }
            return parts.joined(separator: " ")
        case .srv:
            return "\(try u16(0)) \(try u16(2)) \(try u16(4)) \(try name(6).0)"
        case .caa where rdata.count >= 2:
            let tagLength = Int(rdata[1])
            guard 2 + tagLength <= rdata.count else { throw DNSMessageError.truncatedMessage }
            let tag = String(decoding: rdata[2..<(2 + tagLength)], as: UTF8.self)
            return "\(rdata[0]) \(tag) \(quoted(rdata[(2 + tagLength)...]))"
        case .ds where rdata.count >= 4:
            return "\(try u16(0)) \(rdata[2]) \(rdata[3]) \(hex(rdata[4...]))"
        case .dnskey where rdata.count >= 4:
            return "\(try u16(0)) \(rdata[2]) \(rdata[3]) \(Data(rdata[4...]).base64EncodedString())"
        default:
            return "\\# \(rdata.count)" + (rdata.isEmpty ? "" : " " + hex(rdata[...]))
        }
    }
}
