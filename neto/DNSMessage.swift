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
    case a = 1, ns = 2, cname = 5, soa = 6, ptr = 12, hinfo = 13, mx = 15, txt = 16, aaaa = 28, srv = 33
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
        case .hinfo: return "HINFO"
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
        "\(name)\t\(ttl)\t\(DNSWire.className(recordClass))\t\(typeName)\t\(data)"
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
    /// Upper 8 bits of the 12-bit RCODE, carried in the OPT record's TTL (RFC 6891 6.1.3)
    var ednsExtendedRCODE: UInt8 = 0

    var isResponse: Bool { flags & 0x8000 != 0 }
    var isTruncated: Bool { flags & 0x0200 != 0 }
    /// Full RCODE: header bits plus the EDNS extension
    var rcode: UInt16 { UInt16(ednsExtendedRCODE) << 4 | flags & 0x000F }

    /// RCODE name like dig ("NOERROR", "NXDOMAIN", "BADVERS", …)
    var rcodeName: String {
        let names = ["NOERROR", "FORMERR", "SERVFAIL", "NXDOMAIN", "NOTIMP", "REFUSED", "YXDOMAIN", "YXRRSET", "NXRRSET", "NOTAUTH", "NOTZONE"]
        if Int(rcode) < names.count { return names[Int(rcode)] }
        if rcode == 16 { return "BADVERS" }
        return rcode < 16 ? "RESERVED\(rcode)" : "RCODE\(rcode)"
    }

    /// OPCODE name like dig ("QUERY", "NOTIFY", …)
    var opcodeName: String {
        let opcode = Int(flags >> 11 & 0xF)
        let names = [0: "QUERY", 1: "IQUERY", 2: "STATUS", 4: "NOTIFY", 5: "UPDATE"]
        return names[opcode] ?? "RESERVED\(opcode)"
    }

    /// Header flags like dig ("qr rd ra ad")
    var flagNames: [String] {
        [(0x8000, "qr"), (0x0400, "aa"), (0x0200, "tc"), (0x0100, "rd"), (0x0080, "ra"), (0x0020, "ad"), (0x0010, "cd")]
            .filter { flags & UInt16($0.0) != 0 }.map(\.1)
    }

    static func == (lhs: DNSMessage, rhs: DNSMessage) -> Bool {
        lhs.id == rhs.id && lhs.flags == rhs.flags && lhs.answers == rhs.answers && lhs.authority == rhs.authority
            && lhs.additional == rhs.additional && lhs.ednsUDPSize == rhs.ednsUDPSize && lhs.ednsExtendedRCODE == rhs.ednsExtendedRCODE
            && lhs.questions.map { "\($0.name)/\($0.type)" } == rhs.questions.map { "\($0.name)/\($0.type)" }
    }
}

enum DNSMessageError: LocalizedError, Equatable {
    case invalidName(String)
    case truncatedMessage
    case badCompressionPointer
    case malformedRecord(String)

    var errorDescription: String? {
        switch self {
        case .invalidName(let name): return "Invalid DNS name: \(name)"
        case .truncatedMessage: return "The DNS response is truncated or malformed"
        case .badCompressionPointer: return "The DNS response has an invalid compression pointer"
        case .malformedRecord(let type): return "The DNS response has a malformed \(type) record"
        }
    }
}

/// RFC 1035 wire format: query building and response parsing (pure, no networking)
enum DNSWire {

    /// Builds a query: RD=1, AD=1 (RFC 6840 5.7: asks for the AD bit in the answer, like dig), one question,
    /// and an EDNS0 OPT record (RFC 6891) announcing `ednsUDPSize` (1232 is dig's default since 9.16)
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

    /// Name as sent on the wire: internationalised labels in punycode (IDNA), nil for names with spaces or
    /// characters a host name cannot carry. Underscore labels (_sip._tcp) and reverse names stay unchanged.
    static func asciiName(_ name: String) -> String? {
        guard !name.isEmpty, !name.contains(where: \.isWhitespace) else { return nil }
        if name == "." { return name }
        var components = URLComponents()
        components.host = name
        guard let host = components.encodedHost, !host.contains("%") else { return nil }
        return host
    }

    /// Class mnemonic like dig
    static func className(_ value: UInt16) -> String {
        switch value {
        case 1: return "IN"
        case 3: return "CH"
        case 4: return "HS"
        case 254: return "NONE"
        case 255: return "ANY"
        default: return "CLASS\(value)"
        }
    }

    /// ID and flags straight from the header, before parsing the rest (a truncated answer may not parse)
    static func header(_ message: [UInt8]) -> (id: UInt16, flags: UInt16)? {
        guard message.count >= 12 else { return nil }
        return (UInt16(message[0]) << 8 | UInt16(message[1]), UInt16(message[2]) << 8 | UInt16(message[3]))
    }

    /// Whether a response answers this query: same ID, QR set, and the same question (name compared
    /// case-insensitively, type, class IN) – dig ignores anything else ("ID mismatch", "Question section mismatch").
    /// Like dig, a response without a question section (e.g. a bare FORMERR or NOTIMP) is accepted on the ID alone.
    /// Stricter than dig on QR: dig only warns when it is missing, this ignores such a datagram.
    static func isResponse(_ response: [UInt8], to query: [UInt8]) -> Bool {
        guard let header = header(response), let queryHeader = self.header(query),
              header.id == queryHeader.id, header.flags & 0x8000 != 0 else { return false }
        let questionCount = UInt16(response[4]) << 8 | UInt16(response[5])
        if questionCount == 0 { return true }
        guard questionCount == 1,
              let (responseName, afterResponse) = try? readName(response, at: 12),
              let (queryName, afterQuery) = try? readName(query, at: 12),
              afterResponse + 4 <= response.count, afterQuery + 4 <= query.count else { return false }
        return responseName.lowercased() == queryName.lowercased()
            && response[afterResponse..<(afterResponse + 4)] == query[afterQuery..<(afterQuery + 4)]
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
        var message = DNSMessage(
            id: id,
            flags: flags,
            questions: questions,
            answers: answers,
            authority: authority,
            additional: additionalRaw.filter { $0.record.type != 41 }.map(\.record),
            ednsUDPSize: additionalRaw.first { $0.record.type == 41 }?.udpSize
        )
        if let opt = additionalRaw.first(where: { $0.record.type == 41 }) {
            message.ednsExtendedRCODE = UInt8(opt.record.ttl >> 24)
        }
        return message
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
        var pointerLimit = start
        var wireLength = 1
        while true {
            guard offset < message.count else { throw DNSMessageError.truncatedMessage }
            let length = Int(message[offset])
            if length & 0xC0 == 0xC0 {
                guard offset + 1 < message.count else { throw DNSMessageError.truncatedMessage }
                let pointer = (length & 0x3F) << 8 | Int(message[offset + 1])
                jumps += 1
                // Like BIND, every jump must land before the previous one (and before the name's start),
                // which rules out loops
                guard pointer < pointerLimit, jumps <= 64 else { throw DNSMessageError.badCompressionPointer }
                if next == nil { next = offset + 2 }
                offset = pointer
                pointerLimit = pointer
                continue
            }
            guard length & 0xC0 == 0 else { throw DNSMessageError.malformedRecord("label type") }
            offset += 1
            if length == 0 { break }
            guard offset + length <= message.count else { throw DNSMessageError.truncatedMessage }
            labels.append(escapeLabel(Array(message[offset..<(offset + length)])))
            offset += length
            wireLength += length + 1
            guard wireLength <= 255 else { throw DNSMessageError.malformedRecord("name (longer than 255 bytes)") }
        }
        return (labels.isEmpty ? "." : labels.joined(separator: ".") + ".", next ?? offset)
    }

    /// Label bytes as dig prints them: "." and "\" escaped, non-printable bytes as \DDD
    private static func escapeLabel(_ bytes: [UInt8]) -> String {
        bytes.map { byte -> String in
            switch byte {
            case 0x2E, 0x5C, 0x22, 0x28, 0x29, 0x3B, 0x40, 0x24: return "\\" + String(UnicodeScalar(byte))   // . \ " ( ) ; @ $
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

    /// Record data in dig's presentation format; types without a dedicated format use RFC 3597 "\\# len hex".
    /// Names inside the data may be compressed but must end within the record (dig rejects them otherwise).
    static func presentation(type: UInt16, rdata: [UInt8], message: [UInt8], rdataOffset: Int) throws -> String {
        let typeName = DNSRecordType.name(of: type)
        func malformed() -> DNSMessageError { .malformedRecord(typeName) }
        func u16(_ at: Int) throws -> UInt16 {
            guard at >= 0, at + 2 <= rdata.count else { throw malformed() }
            return UInt16(rdata[at]) << 8 | UInt16(rdata[at + 1])
        }
        func u32(_ at: Int) throws -> UInt32 { UInt32(try u16(at)) << 16 | UInt32(try u16(at + 2)) }
        func name(_ at: Int) throws -> (String, Int) {
            guard at < rdata.count else { throw malformed() }
            let (name, next) = try readName(message, at: rdataOffset + at)
            guard next - rdataOffset <= rdata.count else { throw malformed() }
            return (name, next - rdataOffset)
        }
        func lastName(_ at: Int) throws -> String {
            let (value, end) = try name(at)
            guard end == rdata.count else { throw malformed() }
            return value
        }
        func characterStrings(from start: Int) throws -> [String] {
            var parts: [String] = []
            var index = start
            while index < rdata.count {
                let length = Int(rdata[index])
                guard index + 1 + length <= rdata.count else { throw malformed() }
                parts.append(quoted(rdata[(index + 1)..<(index + 1 + length)]))
                index += 1 + length
            }
            return parts
        }
        let hex = { (bytes: ArraySlice<UInt8>) in bytes.map { String(format: "%02X", $0) }.joined() }
        /// RRSIG times as YYYYMMDDHHmmSS in UTC (RFC 4034 3.2)
        func time(_ seconds: UInt32) -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMddHHmmss"
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
        }

        switch DNSRecordType(rawValue: type) {
        case .a:
            guard rdata.count == 4 else { throw malformed() }
            return rdata.map(String.init).joined(separator: ".")
        case .aaaa:
            guard rdata.count == 16 else { throw malformed() }
            var address = in6_addr()
            withUnsafeMutableBytes(of: &address) { $0.copyBytes(from: rdata) }
            var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &address, &text, socklen_t(text.count)) != nil else { throw malformed() }
            return String(cString: text)
        case .ns, .cname, .ptr:
            return try lastName(0)
        case .mx:
            return "\(try u16(0)) \(try lastName(2))"
        case .soa:
            let (mname, afterM) = try name(0)
            let (rname, afterR) = try name(afterM)
            guard afterR + 20 == rdata.count else { throw malformed() }
            let numbers = try (0..<5).map { try u32(afterR + $0 * 4) }
            return ([mname, rname] + numbers.map(String.init)).joined(separator: " ")
        case .txt:
            guard !rdata.isEmpty else { throw malformed() }
            return try characterStrings(from: 0).joined(separator: " ")
        case .hinfo:
            let parts = try characterStrings(from: 0)
            guard parts.count == 2 else { throw malformed() }
            return parts.joined(separator: " ")
        case .srv:
            return "\(try u16(0)) \(try u16(2)) \(try u16(4)) \(try lastName(6))"
        case .caa:
            guard rdata.count >= 2, 2 + Int(rdata[1]) <= rdata.count else { throw malformed() }
            let tagLength = Int(rdata[1])
            let tag = String(decoding: rdata[2..<(2 + tagLength)], as: UTF8.self)
            return "\(rdata[0]) \(tag) \(quoted(rdata[(2 + tagLength)...]))"
        case .ds:
            guard rdata.count > 4 else { throw malformed() }
            return "\(try u16(0)) \(rdata[2]) \(rdata[3]) \(hex(rdata[4...]))"
        case .dnskey:
            guard rdata.count > 4 else { throw malformed() }
            return "\(try u16(0)) \(rdata[2]) \(rdata[3]) \(Data(rdata[4...]).base64EncodedString())"
        case .rrsig:
            // type covered, algorithm, labels, original TTL, expiration, inception, key tag, signer (uncompressed), signature
            guard rdata.count > 18 else { throw malformed() }
            let covered = DNSRecordType.name(of: try u16(0))
            let (signer, afterSigner) = try name(18)
            guard afterSigner < rdata.count else { throw malformed() }
            let fields = [covered, String(rdata[2]), String(rdata[3]), String(try u32(4)),
                          time(try u32(8)), time(try u32(12)), String(try u16(16)), signer]
            return (fields + [Data(rdata[afterSigner...]).base64EncodedString()]).joined(separator: " ")
        default:
            return "\\# \(rdata.count)" + (rdata.isEmpty ? "" : " " + hex(rdata[...]))
        }
    }
}
