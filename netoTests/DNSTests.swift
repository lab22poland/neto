//
//  DNSTests.swift
//  netoTests
//
//  Created by Sergii Solianyk on 12/10/2026.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Testing
@testable import neto

/// Wire format: responses captured from 1.1.1.1 on 2026-10-12. Expected record data is what `dig @1.1.1.1` printed right
/// after the capture; TTLs come from an independent decoder of the same bytes (a separate dig query sees other cached TTLs).
struct DNSWireParsingTests {

    private static func bytes(_ hex: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return bytes
    }

    /// (query, response hex, dig rows: name, ttl, type, data)
    static let fixtures: [(String, String, [(String, UInt32, String, String)])] = [
        ("google.com A", "49c88180000100060000000106676f6f676c6503636f6d0000010001c00c000100010000011a00048efa7864c00c000100010000011a00048efa7865c00c000100010000011a00048efa7866c00c000100010000011a00048efa788ac00c000100010000011a00048efa7871c00c000100010000011a00048efa788b00002904d0000000000000", [("google.com.", 282, "A", "142.250.120.100"), ("google.com.", 282, "A", "142.250.120.101"), ("google.com.", 282, "A", "142.250.120.102"), ("google.com.", 282, "A", "142.250.120.138"), ("google.com.", 282, "A", "142.250.120.113"), ("google.com.", 282, "A", "142.250.120.139")]),   // addresses rotate between queries: decoded independently
        ("google.com AAAA", "c8dd8180000100040000000106676f6f676c6503636f6d00001c0001c00c001c0001000000c900102a001450402508020000000000000064c00c001c0001000000c900102a001450402508020000000000000065c00c001c0001000000c900102a00145040250802000000000000008ac00c001c0001000000c900102a00145040250802000000000000006600002904d0000000000000", [("google.com.", 201, "AAAA", "2a00:1450:4025:802::64"), ("google.com.", 201, "AAAA", "2a00:1450:4025:802::65"), ("google.com.", 201, "AAAA", "2a00:1450:4025:802::8a"), ("google.com.", 201, "AAAA", "2a00:1450:4025:802::66")]),   // addresses rotate between queries: decoded independently
        ("www.github.com CNAME", "0a3881800001000100000001037777770667697468756203636f6d0000050001c00c0005000100000e100002c01000002904d0000000000000", [("www.github.com.", 3600, "CNAME", "github.com.")]),
        ("gmail.com MX", "35ce8180000100050000000105676d61696c03636f6d00000f0001c00c000f0001000000e70020001404616c74320d676d61696c2d736d74702d696e016c06676f6f676c65c012c00c000f0001000000e70009001e04616c7433c02ec00c000f0001000000e70009002804616c7434c02ec00c000f0001000000e70009000a04616c7431c02ec00c000f0001000000e700040005c02e00002904d0000000000000", [("gmail.com.", 231, "MX", "5 gmail-smtp-in.l.google.com."), ("gmail.com.", 231, "MX", "20 alt2.gmail-smtp-in.l.google.com."), ("gmail.com.", 231, "MX", "30 alt3.gmail-smtp-in.l.google.com."), ("gmail.com.", 231, "MX", "40 alt4.gmail-smtp-in.l.google.com."), ("gmail.com.", 231, "MX", "10 alt1.gmail-smtp-in.l.google.com.")]),
        ("google.com NS", "f4458180000100040000000106676f6f676c6503636f6d0000020001c00c000200010005271c0006036e7331c00cc00c000200010005271c0006036e7332c00cc00c000200010005271c0006036e7333c00cc00c000200010005271c0006036e7334c00c00002904d0000000000000", [("google.com.", 337692, "NS", "ns4.google.com."), ("google.com.", 337692, "NS", "ns3.google.com."), ("google.com.", 337692, "NS", "ns2.google.com."), ("google.com.", 337692, "NS", "ns1.google.com.")]),
        ("google.com TXT", "de1f8180000100110000000106676f6f676c6503636f6d0000100001c00c0010000100000116002e2d646f63757369676e3d31623061363735342d343962312d346462352d383534302d643263313236363462323839c00c0010000100000116005e5d636973636f2d63692d646f6d61696e2d766572696669636174696f6e3d34376333386263386334623734623732333365393035333232306331626265373662636331636433336337616366376163643336636436613533333230303462c00c0010000100000116002b2a6170706c652d646f6d61696e2d766572696669636174696f6e3d33306166494263765375445632504c58c00c00100001000001160021205f723472643170767779727069377377346133687a6d77386535317968397464c00c0010000100000116004544676f6f676c652d736974652d766572696669636174696f6e3d346962465567422d77584c515f5337767358566f6d535456616d754f58426956417a705235495a38374430c00c0010000100000116004140776f726b2d6163636f756e74732d646f6d61696e2d766572696669636174696f6e3d54636a364a6a494d5a4f77324b73534577324e7432724c61653839744e36c00c0010000100000116004544676f6f676c652d736974652d766572696669636174696f6e3d5456392d44426534523830583476304d34555f62645f4a3963704f4a4d306e696b6674306a41676a6d7351c00c00100001000001160009085a3239765a32786cc00c0010000100000116002423763d7370663120696e636c7564653a5f7370662e676f6f676c652e636f6d207e616c6cc00c0010000100000116002e2d646f63757369676e3d30353935383438382d343735322d346566322d393565622d616137626138613362643065c00c0010000100000116003c3b66616365626f6f6b2d646f6d61696e2d766572696669636174696f6e3d3232726d3535316375346b3061623062787377353336746c647334683935c00c0010000100000116004544676f6f676c652d736974652d766572696669636174696f6e3d7744384e3769314a544e546b657a4a34397377765757343866385f39787665524556346f422d304866356fc00c0010000100000116004140676c6f62616c7369676e2d736d696d652d64763d434459582b584648557732776d6c362f4762382b353942734833314b7a55723663316c32425076714b58383dc00c0010000100000116002c2b4d533d45344136384239414232424239363730424345313534313246363239313631363443304232304242c00c0010000100000116003e3d6f6e6574727573742d646f6d61696e2d766572696669636174696f6e3d3664363835663164343161393436393661643765663737316636383939336530c00c0010000100000116003e3d6f6e6574727573742d646f6d61696e2d766572696669636174696f6e3d3064343737666536303830373465366639633132626361373832363033356363c00c0010000100000116004847617263756c65732d646f6d61696e2d766572696669636174696f6e3d325234743547376e49367452436f36316c707878624c6b73505973747868476d745637356370723878394b00002904d0000000000000", [("google.com.", 278, "TXT", "\"docusign=1b0a6754-49b1-4db5-8540-d2c12664b289\""), ("google.com.", 278, "TXT", "\"cisco-ci-domain-verification=47c38bc8c4b74b7233e9053220c1bbe76bcc1cd33c7acf7acd36cd6a5332004b\""), ("google.com.", 278, "TXT", "\"apple-domain-verification=30afIBcvSuDV2PLX\""), ("google.com.", 278, "TXT", "\"_r4rd1pvwyrpi7sw4a3hzmw8e51yh9td\""), ("google.com.", 278, "TXT", "\"google-site-verification=4ibFUgB-wXLQ_S7vsXVomSTVamuOXBiVAzpR5IZ87D0\""), ("google.com.", 278, "TXT", "\"work-accounts-domain-verification=Tcj6JjIMZOw2KsSEw2Nt2rLae89tN6\""), ("google.com.", 278, "TXT", "\"google-site-verification=TV9-DBe4R80X4v0M4U_bd_J9cpOJM0nikft0jAgjmsQ\""), ("google.com.", 278, "TXT", "\"Z29vZ2xl\""), ("google.com.", 278, "TXT", "\"v=spf1 include:_spf.google.com ~all\""), ("google.com.", 278, "TXT", "\"docusign=05958488-4752-4ef2-95eb-aa7ba8a3bd0e\""), ("google.com.", 278, "TXT", "\"facebook-domain-verification=22rm551cu4k0ab0bxsw536tlds4h95\""), ("google.com.", 278, "TXT", "\"google-site-verification=wD8N7i1JTNTkezJ49swvWW48f8_9xveREV4oB-0Hf5o\""), ("google.com.", 278, "TXT", "\"globalsign-smime-dv=CDYX+XFHUw2wml6/Gb8+59BsH31KzUr6c1l2BPvqKX8=\""), ("google.com.", 278, "TXT", "\"MS=E4A68B9AB2BB9670BCE15412F62916164C0B20BB\""), ("google.com.", 278, "TXT", "\"onetrust-domain-verification=6d685f1d41a94696ad7ef771f68993e0\""), ("google.com.", 278, "TXT", "\"onetrust-domain-verification=0d477fe608074e6f9c12bca7826035cc\""), ("google.com.", 278, "TXT", "\"arcules-domain-verification=2R4t5G7nI6tRCo61lpxxbLksPYstxhGmtV75cpr8x9K\"")]),
        ("google.com SOA", "d46e8180000100010000000106676f6f676c6503636f6d0000060001c00c00060001000000270026036e7331c00c09646e732d61646d696ec00c3b730bbc0000038400000384000007080000003c00002904d0000000000000", [("google.com.", 39, "SOA", "ns1.google.com. dns-admin.google.com. 997395388 900 900 1800 60")]),
        ("8.8.8.8.in-addr.arpa PTR", "78a681800001000100000001013801380138013807696e2d61646472046172706100000c0001c00c000c000100013010000c03646e7306676f6f676c650000002904d0000000000000", [("8.8.8.8.in-addr.arpa.", 77840, "PTR", "dns.google.")]),
        ("_imaps._tcp.gmail.com SRV", "091681800001000100000001065f696d617073045f74637005676d61696c03636f6d0000210001c00c002100010001518000160005000003e104696d617005676d61696c03636f6d0000002904d0000000000000", [("_imaps._tcp.gmail.com.", 86400, "SRV", "5 0 993 imap.gmail.com.")]),
        ("google.com CAA", "50e88180000100010000000106676f6f676c6503636f6d0001010001c00c0101000100015180000f00056973737565706b692e676f6f6700002904d0000000000000", [("google.com.", 86400, "CAA", "0 issue \"pki.goog\"")]),
        ("cloudflare.com DS", "d10581a000010001000000010a636c6f7564666c61726503636f6d00002b0001c00c002b000100015180002409430d0232996839a6d808afe3eb4a795a0e6a7a39a76fc52ff228b22b76f6d63826f2b900002904d0000000000000", [("cloudflare.com.", 86400, "DS", "2371 13 2 32996839A6D808AFE3EB4A795A0E6A7A39A76FC52FF228B22B76F6D63826F2B9")]),
        ("cloudflare.com DNSKEY", "42e581a000010002000000010a636c6f7564666c61726503636f6d0000300001c00c0030000100000a3900440100030da09311112cf9138818cd2feae970ebbd4d6a30f6088c25b325a39abbc5cd1197aa098283e5aaf421177c2aa5d714992a9957d1bcc18f98cd71f1f1806b65e148c00c0030000100000a3900440101030d99db2cc14cabdc33d6d77da63a2f15f71112584f234e8d1dc428e39e8a4a97e1aa271a555dc90701e17e2a4c4b6f120b7c32d44f4ac02bd894cf2d4be7778a1900002904d0000000000000", [("cloudflare.com.", 2617, "DNSKEY", "256 3 13 oJMRESz5E4gYzS/q6XDrvU1qMPYIjCWzJaOau8XNEZeqCYKD5ar0IRd8KqXXFJkqmVfRvMGPmM1x8fGAa2XhSA=="), ("cloudflare.com.", 2617, "DNSKEY", "257 3 13 mdsswUyr3DPW132mOi8V9xESWE8jTo0dxCjjnopKl+GqJxpVXckHAeF+KkxLbxILfDLUT0rAK9iUzy1L53eKGQ==")]),
        ("nonexistent-neto-test-12345.com A", "a398818300010000000100011b6e6f6e6578697374656e742d6e65746f2d746573742d313233343503636f6d0000010001c0280006000100000384003d01610c67746c642d73657276657273036e657400056e73746c640c766572697369676e2d677273c0286accd146000007080000038400093a800000038400002904d0000000000000", [("com.", 900, "SOA", "a.gtld-servers.net. nstld.verisign-grs.com. 1791807814 1800 900 604800 900")]),
    ]

    @Test(arguments: fixtures.map { $0.0 })
    func answersMatchDig(query: String) throws {
        let fixture = try #require(Self.fixtures.first { $0.0 == query })
        let message = try DNSWire.parse(Self.bytes(fixture.1))
        // dig +answer +authority: answers, or the SOA in authority for NXDOMAIN / NODATA
        let records = message.answers.isEmpty ? message.authority : message.answers
        // Resolvers rotate the order inside an RRset, so compare sorted
        let parsed: [String] = records.map { "\($0.name) \($0.ttl) \($0.typeName) \($0.data)" }.sorted()
        let expected: [String] = fixture.2.map { "\($0.0) \($0.1) \($0.2) \($0.3)" }.sorted()
        #expect(parsed == expected)
        #expect(message.isResponse)
    }

    @Test func nxdomainStatus() throws {
        let fixture = try #require(Self.fixtures.first { $0.0 == "nonexistent-neto-test-12345.com A" })
        let message = try DNSWire.parse(Self.bytes(fixture.1))
        #expect(message.rcodeName == "NXDOMAIN")
        #expect(message.answers.isEmpty)
        #expect(message.flagNames == ["qr", "rd", "ra"])
    }

    @Test func ednsAndFlags() throws {
        let fixture = try #require(Self.fixtures.first { $0.0 == "cloudflare.com DNSKEY" })
        let message = try DNSWire.parse(Self.bytes(fixture.1))
        #expect(message.ednsUDPSize != nil, "the OPT record is not shown as an additional record")
        #expect(message.flagNames.contains("ad"), "a signed zone is validated by 1.1.1.1 when AD is asked for")
        #expect(message.rcodeName == "NOERROR")
    }

    @Test func unknownTypeUsesRFC3597Format() throws {
        let https = Self.bytes("bcc481a000010001000000010a636c6f7564666c61726503636f6d0000410001c00c0041000100000090003d0001000001000602683302683200040008681084e5681085e500060020260647000000000000000000681084e5260647000000000000000000681085e500002904d0000000000000")
        let message = try DNSWire.parse(https)
        let record = try #require(message.answers.first)
        #expect(record.typeName == "HTTPS")
        // dig 9.10 (no HTTPS support) prints the same bytes as "TYPE65 \\# 61 …", split into groups of 56 hex digits
        #expect(record.data == "\\# 61 0001000001000602683302683200040008681084E5681085E500060020260647000000000000000000681084E5260647000000000000000000681085E5")
    }
}

/// Query building, names and reverse lookups
struct DNSWireEncodingTests {

    @Test func queryLayout() throws {
        // id, flags RD+AD, 1 question, 1 additional (OPT), "google.com" A IN, OPT with UDP size 1232
        let query = try DNSWire.query(name: "google.com", type: 1, id: 0x1000)
        let hex: String = query.map { String(format: "%02x", $0) }.joined()
        let expected: String = "100001200001000000000001" + "06676f6f676c6503636f6d00" + "00010001" + "00002904d0000000000000"
        #expect(hex == expected)
    }

    @Test(arguments: ["google.com", "google.com.", "."])
    func validNames(_ name: String) {
        #expect((try? DNSWire.encodeName(name)) != nil)
    }

    @Test(arguments: ["a..b", String(repeating: "x", count: 64) + ".com", ".com"])
    func invalidNames(_ name: String) {
        #expect(throws: DNSMessageError.self) { try DNSWire.encodeName(name) }
    }

    @Test(arguments: [("8.8.8.8", "8.8.8.8.in-addr.arpa."), ("192.0.2.1", "1.2.0.192.in-addr.arpa."),
                      ("2001:4860:4860::8888", "8.8.8.8.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.6.8.4.0.6.8.4.1.0.0.2.ip6.arpa.")])
    func reverseNames(address: String, name: String) {
        #expect(DNSWire.reverseName(for: address) == name)
    }

    @Test func hostNamesAreNotReversed() {
        #expect(DNSWire.reverseName(for: "google.com") == nil)
    }

    @Test func compressionLoopIsRejected() {
        // header + a question whose name points to itself
        let message: [UInt8] = [0, 1, 0x81, 0x80, 0, 1, 0, 0, 0, 0, 0, 0, 0xC0, 12, 0, 1, 0, 1]
        #expect(throws: DNSMessageError.self) { try DNSWire.parse(message) }
    }

    @Test func truncatedMessageIsRejected() {
        #expect(throws: DNSMessageError.self) { try DNSWire.parse([0, 1, 0x81]) }
    }

    @Test func resolvConfNameservers() {
        #expect(DnsManager.parseResolvConf("# comment\nnameserver 100.100.100.100\nnameserver\tfd7a::53\nsearch example.com\n")
                == ["100.100.100.100", "fd7a::53"])
    }
}

/// Input handling in the view model
@MainActor
struct DnsViewModelTests {

    @Test func ipAddressBecomesReverseLookup() {
        let viewModel = DnsViewModel(systemServers: ["192.0.2.53"])
        viewModel.query = " 8.8.8.8 "
        viewModel.recordType = .mx
        #expect(viewModel.effectiveQuery.name == "8.8.8.8.in-addr.arpa.")
        #expect(viewModel.effectiveQuery.type == .ptr)
    }

    @Test func lookupNeedsNameAndUsableServer() {
        let viewModel = DnsViewModel(systemServers: ["192.0.2.53"])
        #expect(!viewModel.canLookup, "empty name")
        viewModel.query = "example.com"
        #expect(viewModel.canLookup)
        viewModel.transport = .https
        #expect(!viewModel.canLookup, "the system server has no DoH endpoint")
        viewModel.serverChoice = .preset(.cloudflare)
        #expect(viewModel.canLookup)
        viewModel.serverChoice = .custom
        viewModel.customServer = "not-an-ip"
        #expect(!viewModel.canLookup)
        viewModel.customServer = "9.9.9.9"
        viewModel.transport = .udp
        #expect(viewModel.canLookup)
    }

    @Test func noSystemServerMeansNoSystemLookup() {
        let viewModel = DnsViewModel(systemServers: [])
        viewModel.query = "example.com"
        #expect(viewModel.selectedServer == nil)
        #expect(!viewModel.canLookup)
    }
}

/// Hardening and dig-compatibility cases found in review
struct DNSWireReviewTests {

    private static func message(answer: [UInt8], type: UInt16 = 1, rdata: [UInt8], flags: UInt16 = 0x8180, opt: [UInt8] = []) -> [UInt8] {
        // header (1 question, 1 answer, optional OPT), question "a." A IN, answer with the given owner bytes
        var m: [UInt8] = [0, 1, UInt8(flags >> 8), UInt8(flags & 0xFF), 0, 1, 0, 1, 0, 0, 0, opt.isEmpty ? 0 : 1]
        m += [1, 0x61, 0, 0, 1, 0, 1]
        m += answer + [UInt8(type >> 8), UInt8(type & 0xFF), 0, 1, 0, 0, 0, 60, UInt8(rdata.count >> 8), UInt8(rdata.count & 0xFF)] + rdata
        return m + opt
    }

    @Test func rrsigIsPresentedLikeDig() throws {
        let hex = "9f7081a000010003000000010a636c6f7564666c61726503636f6d0000010001c00c000100010000012c0004681084e5c00c000100010000012c0004681085e5c00c002e00010000012c006200010d020000012c6ace363a6acb771a86c90a636c6f7564666c61726503636f6d00ba6046021e1061541a7f76d0e998bcef2d0eaa16c1c59f7941f578a5d866947315f86fe2055aa2dfd245dc370aba84dc1e2344b274dfa4d8063d61fd47e9a56100002904d0000080000000"
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex { let next = hex.index(index, offsetBy: 2); bytes.append(UInt8(hex[index..<next], radix: 16)!); index = next }
        let rrsig = try #require(try DNSWire.parse(bytes).answers.first { $0.typeName == "RRSIG" })
        // Fields decoded independently from the captured bytes; layout as `dig +dnssec` prints it
        #expect(rrsig.data == "A 13 2 300 20261013134634 20261011114634 34505 cloudflare.com. umBGAh4QYVQaf3bQ6Zi87y0OqhbBxZ95QfV4pdhmlHMV+G/iBVqi39JF3DcKuoTcHiNEsnTfpNgGPWH9R+mlYQ==")
    }

    @Test func labelsAreEscapedLikeDig() throws {
        // owner label a"b(c)d;e@f$g h  →  dig: a\"b\(c\)d\;e\@f\$g\032h
        let label = Array("a\"b(c)d;e@f$g h".utf8)
        let owner = [UInt8(label.count)] + label + [0]
        let record = try #require(try DNSWire.parse(Self.message(answer: owner, rdata: [1, 2, 3, 4])).answers.first)
        #expect(record.name == "a\\\"b\\(c\\)d\\;e\\@f\\$g\\032h.")
    }

    @Test func forwardCompressionPointerIsRejected() {
        // the answer owner points forward, past itself
        #expect(throws: DNSMessageError.self) { try DNSWire.parse(Self.message(answer: [0xC0, 40], rdata: [1, 2, 3, 4])) }
    }

    @Test func nameInRdataMustEndInsideTheRecord() {
        // MX: preference 10, then a name whose terminating zero lies beyond RDLENGTH
        let mx: [UInt8] = [0, 10, 3, 0x61, 0x62, 0x63]
        var message = Self.message(answer: [0xC0, 12], type: 15, rdata: mx)
        message += [0]
        #expect(throws: DNSMessageError.self) { try DNSWire.parse(message) }
    }

    @Test func wrongAddressLengthIsMalformed() {
        #expect(throws: DNSMessageError.self) { try DNSWire.parse(Self.message(answer: [0xC0, 12], rdata: [1, 2, 3])) }
    }

    @Test func extendedRCODEFromOPT() throws {
        // OPT with extended RCODE 1 in the TTL's top byte and header RCODE 0 → 16 = BADVERS (RFC 6891)
        let opt: [UInt8] = [0, 0, 41, 0x04, 0xD0, 0x01, 0, 0, 0, 0, 0]
        let parsed = try DNSWire.parse(Self.message(answer: [0xC0, 12], rdata: [1, 2, 3, 4], opt: opt))
        #expect(parsed.rcodeName == "BADVERS")
    }

    @Test(arguments: [(UInt16(1), "IN"), (3, "CH"), (4, "HS"), (254, "NONE"), (255, "ANY"), (7, "CLASS7")])
    func classNamesLikeDig(value: UInt16, name: String) {
        #expect(DNSWire.className(value) == name)
    }

    @Test(arguments: [("ząb.pl", "xn--zb-pla.pl"), ("bücher.de.", "xn--bcher-kva.de."), ("_imaps._tcp.gmail.com", "_imaps._tcp.gmail.com"),
                      ("8.8.8.8.in-addr.arpa.", "8.8.8.8.in-addr.arpa."), (".", ".")])
    func internationalNamesBecomePunycode(name: String, wire: String) {
        #expect(DNSWire.asciiName(name) == wire)
    }

    @Test(arguments: ["a b.com", "https://example.com", ""])
    func nonHostNamesAreRejected(_ name: String) {
        #expect(DNSWire.asciiName(name) == nil)
    }

    @Test func responsesMustMatchTheQuery() throws {
        let query = try DNSWire.query(name: "example.com", type: 1, id: 0x1234)
        var response = query
        response[2] |= 0x80   // QR
        #expect(DNSWire.isResponse(response, to: query))

        var upper = response
        upper[13] = 0x45      // "Example.com": names compare case-insensitively
        #expect(DNSWire.isResponse(upper, to: query))

        var otherID = response
        otherID[1] = 0x35
        #expect(!DNSWire.isResponse(otherID, to: query), "ID mismatch")

        var otherType = response
        otherType[26] = 28    // AAAA instead of A
        #expect(!DNSWire.isResponse(otherType, to: query), "question section mismatch")

        #expect(!DNSWire.isResponse(query, to: query), "a query (QR=0) is not a response")
    }

    @Test func truncationIsReadFromTheHeader() throws {
        // a truncated answer that does not parse still reports TC
        let broken: [UInt8] = [0, 1, 0x83, 0x80, 0, 1, 0, 3, 0, 0, 0, 0, 1, 0x61, 0, 0, 1, 0, 1, 0xC0]
        #expect(throws: DNSMessageError.self) { try DNSWire.parse(broken) }
        #expect(DNSWire.header(broken).map { $0.flags & 0x0200 != 0 } == true)
    }
}
