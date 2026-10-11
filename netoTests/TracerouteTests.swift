//
//  TracerouteTests.swift
//  netoTests
//
//  Created by Sergii Solianyk on 12/10/2026.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Network
import Testing
@testable import neto

/// Host validation, resolution and hop formatting in TracerouteManager
struct TracerouteManagerLogicTests {

    @Test(arguments: ["8.8.8.8", "0.0.0.0", "255.255.255.255", "192.168.1.10"])
    func validIPv4(_ address: String) {
        #expect(TracerouteManager().isValidIPv4(address))
    }

    @Test(arguments: ["256.1.1.1", "1.2.3", "1.2.3.4.5", "01.2.3.4", "a.b.c.d", "1..2.3"])
    func invalidIPv4(_ address: String) {
        #expect(!TracerouteManager().isValidIPv4(address))
    }

    @Test(arguments: [("google.com", true), ("a-b.example.org", true), ("localhost", true),
                      ("-bad.com", false), ("bad-.com", false), ("spa ce.com", false), ("", false)])
    func hostnameValidation(hostname: String, valid: Bool) {
        #expect(TracerouteManager().isValidHostname(hostname) == valid)
    }

    @Test func resolvesAddressesAndNames() async throws {
        let manager = TracerouteManager()
        let ipv4 = try await manager.resolveHost(" 127.0.0.1 ")
        let ipv6 = try await manager.resolveHost("::1")
        let name = try await manager.resolveHost("localhost")
        #expect(ipv4 == .hostPort(host: .ipv4(.loopback), port: 80))
        #expect(ipv6 == .hostPort(host: .ipv6(.loopback), port: 80))
        #expect(name == .hostPort(host: .name("localhost", nil), port: 80))
    }

    @Test func resolvesDomainNames() async {
        await withKnownIssue("Any host with a dot and no colon is validated as IPv4, so every domain name is rejected") {
            let endpoint = try await TracerouteManager().resolveHost("example.com")
            #expect(endpoint == .hostPort(host: .name("example.com", nil), port: 80))
        }
    }

    @Test(arguments: ["", "999.1.1.1", "bad host"])
    func rejectsInvalidHosts(_ host: String) async {
        await #expect(throws: TracerouteError.self) {
            try await TracerouteManager().resolveHost(host)
        }
    }

    @Test func errorMessageReachesUser() {
        let error: Error = TracerouteError.invalidHost("Invalid IPv4 address format: 999.1.1.1")
        withKnownIssue("TracerouteError is not a LocalizedError, so users see Foundation's generic text") {
            #expect(error.localizedDescription == "Invalid IPv4 address format: 999.1.1.1")
        }
    }

    @Test func hopMessageFormatting() {
        let manager = TracerouteManager()
        #expect(manager.formatHopMessage(ipAddress: "1.1.1.1", hostname: "one.one.one.one", isDestination: false) == "one.one.one.one (1.1.1.1)")
        #expect(manager.formatHopMessage(ipAddress: "1.1.1.1", hostname: "1.1.1.1", isDestination: true) == "(1.1.1.1) [DESTINATION REACHED]")
        #expect(manager.formatHopMessage(ipAddress: nil, hostname: nil, isDestination: false) == "* * *")
    }
}

/// Parameter validation before any network call
@MainActor
struct TracerouteViewModelTests {

    @Test func whitespaceHostCannotStart() {
        let viewModel = TracerouteViewModel()
        viewModel.targetHost = "   "
        #expect(!viewModel.canStartTraceroute)
    }

    @Test(arguments: [(0, 5.0), (51, 5.0), (30, 0.0), (30, 31.0)])
    func outOfRangeParametersAreRejected(maxHops: Int, timeout: Double) {
        let viewModel = TracerouteViewModel()
        viewModel.targetHost = "127.0.0.1"
        viewModel.maxHops = maxHops
        viewModel.timeout = timeout
        #expect(!viewModel.canStartTraceroute)
        viewModel.startTraceroute()
        #expect(!viewModel.isTracing)
        #expect(viewModel.errorMessage != nil)
    }
}
