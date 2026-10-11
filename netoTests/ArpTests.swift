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

    private func entry(_ ip: String, _ interface: String, status: String = "120s") -> ArpEntry {
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
        #expect(entry("10.0.0.1", "en0").commandLineFormat
                == "? (10.0.0.1) at aa:bb:cc:dd:ee:ff on en0 ifscope [ethernet]")
    }

    @Test func outputIsSortedNumerically() {
        let output = ArpResult(entries: [entry("10.0.0.10", "en0"), entry("10.0.0.2", "en0")]).commandLineOutput
        withKnownIssue("IP addresses are sorted as strings, so 10.0.0.10 comes before 10.0.0.2") {
            #expect(output.hasPrefix("? (10.0.0.2)"))
        }
    }
}

#if os(macOS)
import Darwin

/// Parsing of link-layer addresses from routing messages (macOS only)
struct ArpLinkLayerParsingTests {

    @Test func macAddressIsReadAtLLADDR() {
        // sockaddr_dl as the kernel lays it out: 8-byte header, interface name, then the address (LLADDR = sdl_data + sdl_nlen)
        let name = Array("en0".utf8)
        let mac: [UInt8] = [0x00, 0x11, 0x22, 0x33, 0x44, 0x55]
        var bytes: [UInt8] = [0, UInt8(AF_LINK), 4, 0, 6 /* IFT_ETHER */, UInt8(name.count), UInt8(mac.count), 0]
        bytes += name + mac
        bytes += [UInt8](repeating: 0xEE, count: 32)   // whatever follows in the message buffer
        bytes[0] = UInt8(8 + name.count + mac.count)

        let parsed = bytes.withUnsafeMutableBytes { raw in
            ArpManager().parseLinkLayerAddress(raw.baseAddress!.assumingMemoryBound(to: sockaddr.self))
        }
        withKnownIssue("The MAC is read at sizeof(sockaddr_dl) + nlen instead of LLADDR (offsetof(sdl_data) + nlen)") {
            #expect(parsed == "00:11:22:33:44:55")
        }
    }
}
#endif
