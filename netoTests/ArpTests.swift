//
//  ArpTests.swift
//  netoTests
//
//  Created by Sergii Solianyk on 12/10/2026.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Testing
@testable import neto

/// Grouping and `arp -an`-style output of ARP entries
struct ArpResultTests {

    private func entry(_ ip: String, _ interface: String, status: String = "expires in 2m0s") -> ArpEntry {
        ArpEntry(ipAddress: ip, macAddress: "aa:bb:cc:dd:ee:ff", interface: interface, status: status)
    }

    @Test func entriesAreGroupedBySortedInterface() {
        let result = ArpResult(entries: [entry("10.0.0.1", "en1"), entry("10.0.0.2", "en0"), entry("10.0.0.3", "en1")])
        #expect(result.interfaces == ["en0", "en1"])
        #expect(result.entriesByInterface["en1"]?.count == 2)
    }

    @Test func commandLineFormatMatchesArp() {
        #expect(entry("10.0.0.1", "en0", status: "permanent").commandLineFormat
                == "? (10.0.0.1) at aa:bb:cc:dd:ee:ff on en0 ifscope permanent [ethernet]")
        var bridged = entry("192.168.64.12", "bridge100")
        bridged.linkType = "bridge"
        #expect(bridged.commandLineFormat == "? (192.168.64.12) at aa:bb:cc:dd:ee:ff on bridge100 ifscope [bridge]")
    }

    @Test func outputIsSortedNumerically() {
        let output = ArpResult(entries: [entry("fe80::1", "en0"), entry("10.0.0.10", "en0"), entry("10.0.0.2", "en0")]).commandLineOutput
        #expect(output.components(separatedBy: "\n").map { $0.components(separatedBy: " ")[1] } == ["(10.0.0.2)", "(10.0.0.10)", "(fe80::1)"])
    }
}

#if os(macOS)
/// Parsing of the routing-table dump, using records captured from a real Mac (`sysctl(NET_RT_FLAGS, RTF_LLINFO)`).
/// Expected values were checked against `arp -an` / `ndp -an` on the same machine at the same time.
struct ArpNeighborTableParsingTests {

    private static let now = 1_791_786_736
    private static let interfaces = [1: "lo0", 13: "en0", 28: "bridge100"]

    private func parse(_ hex: [String], neighborInfo: @escaping (String, String) -> ArpManager.NeighborInfo? = { _, _ in nil }) -> [ArpEntry] {
        let joined = hex.joined()
        var bytes: [UInt8] = []
        var index = joined.startIndex
        while index < joined.endIndex {
            let next = joined.index(index, offsetBy: 2)
            bytes.append(UInt8(joined[index..<next], radix: 16)!)
            index = next
        }
        return ArpManager.parseNeighborTable(bytes, now: Self.now, interfaceName: { Self.interfaces[$0] ?? "if\($0)" }, neighborInfo: neighborInfo)
    }

    /// 192.168.64.1 (bridge, permanent), 192.168.64.12 (bridge, dynamic), 224.0.0.251 (en0, multicast)
    private let ipv4Records = [
        "900005040100000005042205230000000000000000000000000000000100000000000000000000000040000000000000",
        "000000000000000000000000000000000000000000000000010000000000000000000000000000000000000010020000",
        "c0a84001000000000000000014121c00d1000600c2c7dbdb7f6400000000000010020000c0a840010000000000000000",
        "900005041c0000000504020523000000000000000000000000000000d42d00000000000000000000dc05000000000000",
        "e582cc6a0000000000000000000000000000000000000000d42d00000000000000000000000000000000000010020000",
        "c0a8400c000000000000000014121c00d10006009abf7cade87f00000000000010020000c0a840010000000000000000",
        "8c0005040d0000000504820123000000000000000000000000000000000000000000000000000000dc05000000000000",
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010020000",
        "e00000fb00000000000000000e120d000600060001005e0000fb000010020000c0a864160000000000000000",
    ]

    /// fe80::101 on en0 (router, with MAC) and fe80::1 on lo0 (incomplete); scope embedded in bytes 2-3
    private let ipv6Records = [
        "a80005040d0000000504020123000000000000000000000000000000434700000000000000000000d405000000000000",
        "00000000000000000000000000000000000000000000000043470000000000000000000000000000000000001c1e0000",
        "00000000fe80000d0000000000000000000001010000000014120d00060006006cb7e29366eb0000000000001c1e0000",
        "00000000fe80000d0000000008bb516f96eb22e700000000a80005040100000005042001230000000000000000000000",
        "00000000d903000000000000000000000040000000000000000000000000000000000000000000000000000000000000",
        "d9030000000000000000000000000000000000001c1e000000000000fe80000100000000000000000000000100000000",
        "14120100180000000000000000000000000000001c1e000000000000fe80000100000000000000000000000100000000",
    ]

    @Test func ipv4EntriesMatchArp() {
        let entries = parse(ipv4Records)
        #expect(entries.map(\.commandLineFormat) == [
            "? (192.168.64.1) at c2:c7:db:db:7f:64 on bridge100 ifscope permanent [bridge]",
            "? (192.168.64.12) at 9a:bf:7c:ad:e8:7f on bridge100 ifscope [bridge]",
            "? (224.0.0.251) at 01:00:5e:00:00:fb on en0 ifscope permanent [ethernet]",
        ])
        #expect(entries[1].status == "expires in 16m53s")
    }

    @Test func ipv6EntriesMatchNdp() {
        let entries = parse(ipv6Records)
        #expect(entries.map(\.ipAddress) == ["fe80::101", "fe80::1"], "the embedded scope must be cleared")
        #expect(entries.map(\.macAddress) == ["6c:b7:e2:93:66:eb", "(incomplete)"])
        #expect(entries.map(\.interface) == ["en0", "lo0"])
    }

    @Test func ipv6StateAndExpiryComeFromNeighborDiscovery() {
        let entries = parse(ipv6Records) { address, interface in
            address == "fe80::101" && interface == "en0"
                ? ArpManager.NeighborInfo(state: 2, expire: Self.now + 86_379)
                : ArpManager.NeighborInfo(state: 1, expire: 0)
        }
        #expect(entries.map(\.status) == ["stale, expires in 23h59m39s", "reachable, permanent"])
    }

    @Test func truncatedDumpIsIgnored() {
        #expect(ArpManager.parseNeighborTable([UInt8](repeating: 0, count: 10), now: Self.now, interfaceName: { _ in "x" }).isEmpty)
        // A header announcing more bytes than the buffer holds must not be read past the end
        var oversized = [UInt8](repeating: 0, count: 100)
        oversized[0] = 0xFF
        oversized[1] = 0x01
        #expect(ArpManager.parseNeighborTable(oversized, now: Self.now, interfaceName: { _ in "x" }).isEmpty)
    }
}
#endif
