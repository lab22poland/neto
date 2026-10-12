//
//  NetworkDependentTests.swift
//  netoTests
//
//  Created by Sergii Solianyk on 12/10/2026.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Testing
@testable import neto

/// Tests against live internet services. Skipped by default; run with
/// `TEST_RUNNER_NETO_NETWORK_TESTS=1 xcodebuild … test`. Results depend on live registry data.
enum NetworkTests {
    static let enabled = ProcessInfo.processInfo.environment["NETO_NETWORK_TESTS"] == "1"
}

extension Tag {
    @Tag static var network: Self
}

@Suite(.tags(.network), .serialized, .enabled(if: NetworkTests.enabled, "set TEST_RUNNER_NETO_NETWORK_TESTS=1 to run"))
struct LiveNetworkTests {

    private func whois(_ query: String) async -> WhoisResult {
        await withCheckedContinuation { continuation in
            _ = WhoisManager().performWhois(for: query) { continuation.resume(returning: $0) }
        }
    }

    @Test(arguments: [("google.com", "whois.markmonitor.com"),   // IANA → Verisign → MarkMonitor, like whois.c
                      ("wikipedia.org", "whois.markmonitor.com"),   // PIR → MarkMonitor (registrar), like whois.c
                      ("denic.de", "whois.denic.de")])
    func domainReferral(domain: String, server: String) async {
        let result = await whois(domain)
        #expect(result.success, "\(result.statusMessage)")
        #expect(result.whoisServer == server)
    }

    @Test(arguments: [("8.8.8.8", "whois.arin.net"), ("193.0.6.139", "whois.ripe.net")])
    func addressReferral(address: String, server: String) async {
        let result = await whois(address)
        #expect(result.success, "\(result.statusMessage)")
        #expect(result.whoisServer == server)
    }

    @Test @MainActor func tracerouteReachesPublicResolverThroughRouters() async {
        let manager = TracerouteManager()
        var hops: [Int: TracerouteResult] = [:]
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            _ = manager.performTraceroute(to: "8.8.8.8", maxHops: 30, timeout: 2,
                                          onResult: { hops[$0.hopNumber] = $0 },
                                          onComplete: { _ in continuation.resume() })
        }
        let last = hops.keys.max().flatMap { hops[$0] }
        #expect(last?.isDestination == true, "\(hops.values.sorted { $0.hopNumber < $1.hopNumber }.map(\.message))")
        #expect(hops.count > 1, "8.8.8.8 is not on the local network, so routers must appear before it")
        #expect(hops.values.contains { !$0.isDestination && $0.success }, "at least one router must answer Time Exceeded")
    }

    @Test func domainNameResolves() async throws {
        let host = try await TracerouteManager().resolveHost("example.com")
        #expect(host.family == AF_INET || host.family == AF_INET6)
        #expect(!host.ipAddress.isEmpty)
    }

    private func dns(_ name: String, _ type: DNSRecordType, _ server: DNSServer = .cloudflare,
                     _ transport: DNSTransport = .udp, ednsUDPSize: UInt16 = 1232) async -> DnsResult {
        await withCheckedContinuation { continuation in
            _ = DnsManager().performLookup(name: name, type: type, server: server, transport: transport,
                                           ednsUDPSize: ednsUDPSize) { continuation.resume(returning: $0) }
        }
    }

    @Test(arguments: DNSTransport.allCases)
    func dnsReverseLookupOverEveryTransport(_ transport: DNSTransport) async {
        let result = await dns("8.8.8.8.in-addr.arpa.", .ptr, .cloudflare, transport)
        #expect(result.error == nil, "\(result.error ?? "")")
        #expect(result.message?.answers.map(\.data) == ["dns.google."])
        #expect(result.transport == transport)
    }

    @Test func dnsNxdomainCarriesSOA() async {
        let result = await dns("nonexistent-neto-test-12345.com", .a)
        #expect(result.message?.rcodeName == "NXDOMAIN")
        #expect(result.message?.authority.first?.typeName == "SOA")
    }

    @Test func dnsTruncatedUDPIsRetriedOverTCP() async {
        // google.com TXT is ~1.2 kB: with a 512-byte EDNS size the UDP answer is truncated (TC=1)
        let result = await dns("google.com", .txt, ednsUDPSize: 512)
        #expect(result.transport == .tcp)
        #expect((result.message?.answers.count ?? 0) > 5)
    }

    @Test func dnsSystemServer() async throws {
        let address = try #require(DnsManager.systemServers().first, "no system DNS server found")
        let result = await dns("example.com", .a, DNSServer(label: "System", address: address, tlsHost: nil, dohURL: nil))
        #expect(result.error == nil, "\(result.error ?? "")")
        #expect(result.message?.rcodeName == "NOERROR")
    }

    @Test @MainActor func pingPublicResolver() async {
        let manager = PingManager()
        var results: [PingResult] = []
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            _ = manager.performPing(to: "8.8.8.8", config: .init(count: 3, interval: 0.2, timeout: 3, payloadSize: 56),
                                    onResult: { results.append($0) },
                                    onComplete: { continuation.resume() })
        }
        #expect(results.count == 3)
        #expect(!results.filter(\.success).isEmpty, "no reply from 8.8.8.8: \(results.map(\.message))")
    }
}
