//
//  TracerouteTests.swift
//  netoTests
//
//  Created by Sergii Solianyk on 12/10/2026.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Testing
import XCTest
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

    @Test(arguments: [("8.8.8.8", TracerouteManager.HostKind.ipv4), ("::1", .ipv6), ("2001:db8::1", .ipv6),
                      ("example.com", .name), ("sub.example.co.uk", .name), ("localhost", .name)])
    func hostKind(host: String, kind: TracerouteManager.HostKind) throws {
        #expect(try TracerouteManager().classifyHost(host) == kind)
    }

    @Test(arguments: ["", "999.1.1.1", "1.2.3", "bad host", "2001:db8::zz"])
    func rejectsInvalidHosts(_ host: String) async {
        await #expect(throws: TracerouteError.self) {
            try await TracerouteManager().resolveHost(host)
        }
    }

    @Test func resolvesLocalAddresses() async throws {
        let manager = TracerouteManager()
        let ipv4 = try await manager.resolveHost(" 127.0.0.1 ")
        let ipv6 = try await manager.resolveHost("::1")
        let name = try await manager.resolveHost("localhost")
        #expect(ipv4.family == AF_INET && ipv4.ipAddress == "127.0.0.1")
        #expect(ipv6.family == AF_INET6 && ipv6.ipAddress == "::1")
        #expect(name.family == AF_INET && name.ipAddress == "127.0.0.1", "IPv4 is preferred for names")
    }

    @Test func errorMessageReachesUser() {
        let error: Error = TracerouteError.invalidHost("Invalid IPv4 address format: 999.1.1.1")
        #expect(error.localizedDescription == "Invalid IPv4 address format: 999.1.1.1")
    }

    @Test func hopMessageFormatting() {
        let manager = TracerouteManager()
        #expect(manager.formatHopMessage(ipAddress: "1.1.1.1", hostname: "one.one.one.one", isDestination: false) == "one.one.one.one (1.1.1.1)")
        #expect(manager.formatHopMessage(ipAddress: "1.1.1.1", hostname: "1.1.1.1", isDestination: true) == "(1.1.1.1) [DESTINATION REACHED]")
        #expect(manager.formatHopMessage(ipAddress: nil, hostname: nil, isDestination: false) == "* * *")
    }

    @Test(arguments: [(UInt8(0), Int32(AF_INET), "!N"), (1, AF_INET, "!H"), (13, AF_INET, "!X"), (7, AF_INET, "!<7>"),
                      (1, AF_INET6, "!X"), (3, AF_INET6, "!H")])
    func unreachableAnnotation(code: UInt8, family: Int32, annotation: String) {
        #expect(TracerouteManager.unreachableAnnotation(code: code, family: family) == annotation)
        #expect(TracerouteManager().formatHopMessage(ipAddress: "10.0.0.1", hostname: nil, isDestination: false,
                                                     unreachableCode: code, family: family) == "(10.0.0.1) \(annotation)")
    }

    @Test func loadBalancedProbesShowTheirAddress() {
        let result = TracerouteResult(hopNumber: 4, success: true, ipAddress: "10.0.0.1", responseTime: 2, message: "",
                                      probeTimes: [1, 2, nil, 3], probeAddresses: ["10.0.0.1", "10.0.0.2", nil, "10.0.0.2"])
        #expect(result.formattedProbeTimes == "1.00 ms  (10.0.0.2) 2.00 ms  *  3.00 ms")
    }

    @Test func probeTimesFormatting() {
        let result = TracerouteResult(hopNumber: 1, success: true, responseTime: 2, message: "", probeTimes: [1.234, nil, 3])
        #expect(result.formattedProbeTimes == "1.23 ms  *  3.00 ms")
    }
}

/// A real traceroute over loopback: the target answers at hop 1 (no internet needed)
@MainActor
final class TracerouteLoopbackTests: XCTestCase {

    private func run(_ host: String, maxHops: Int = 5, cancelAfterStart: Bool = false) -> (results: [TracerouteResult], completions: Int) {
        let manager = TracerouteManager()
        var results: [TracerouteResult] = []
        var completions = 0
        let completed = expectation(description: "completed")
        let task = manager.performTraceroute(to: host, maxHops: maxHops, timeout: 2,
                                             onResult: { result in
                                                 // A second call with the same id carries the router's name
                                                 if let index = results.firstIndex(where: { $0.id == result.id }) {
                                                     results[index] = result
                                                 } else {
                                                     results.append(result)
                                                 }
                                             },
                                             onComplete: { completions += 1; completed.fulfill() })
        if cancelAfterStart { task.cancel() }
        wait(for: [completed], timeout: 10)
        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { settle.fulfill() }
        wait(for: [settle], timeout: 2)
        return (results, completions)
    }

    func testLoopbackIsReachedAtFirstHop() {
        let (results, completions) = run("127.0.0.1")
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(results.count, 1, results.map(\.message).joined(separator: "; "))
        XCTAssertEqual(results.first?.hopNumber, 1)
        XCTAssertEqual(results.first?.isDestination, true)
        XCTAssertEqual(results.first?.ipAddress, "127.0.0.1")
        XCTAssertEqual(results.first?.probeTimes.count, TracerouteManager.probesPerHop)
        XCTAssertTrue(results.first?.probeTimes.allSatisfy { $0 != nil } == true)
    }

    func testInvalidHostReportsErrorAndCompletesOnce() {
        let (results, completions) = run("999.1.1.1")
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.success, false)
        XCTAssertTrue(results.first?.message.contains("Invalid IPv4 address format: 999.1.1.1") == true)
    }

    func testCancelCompletesOnceWithoutResults() {
        let (results, completions) = run("127.0.0.1", cancelAfterStart: true)
        XCTAssertEqual(completions, 1)
        XCTAssertTrue(results.isEmpty)
    }
}

/// Parameter validation, progress and row updates in the view model
@MainActor
struct TracerouteViewModelTests {

    @Test func whitespaceHostCannotStart() {
        let viewModel = TracerouteViewModel()
        viewModel.targetHost = "   "
        #expect(!viewModel.canStartTraceroute)
    }

    @Test(arguments: [(0, 5.0), (51, 5.0), (30, 0.5), (30, 31.0)])
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

    @Test func progressAndStopRow() {
        let viewModel = TracerouteViewModel()
        viewModel.maxHops = 10
        viewModel.tracerouteResults = [
            TracerouteResult(hopNumber: 1, success: true, responseTime: 1, message: "(10.0.0.1)"),
            TracerouteResult(hopNumber: 2, success: false, responseTime: 0, message: "* * *"),
        ]
        #expect(viewModel.currentHop == 2)
        #expect(viewModel.progress == 0.2)

        viewModel.isTracing = true
        viewModel.stopTraceroute()
        #expect(viewModel.tracerouteResults.last?.message == "Traceroute stopped by user")
        #expect(viewModel.currentHop == 2, "the stop row is not a hop")
    }

    @Test func nameUpdateReplacesRow() {
        let viewModel = TracerouteViewModel()
        let hop = TracerouteResult(hopNumber: 1, success: true, ipAddress: "10.0.0.1", responseTime: 1, message: "(10.0.0.1)")
        viewModel.handleTracerouteResult(hop)
        viewModel.handleTracerouteResult(TracerouteResult(id: hop.id, hopNumber: 1, success: true, ipAddress: "10.0.0.1",
                                                          hostname: "gw.local", responseTime: 1, message: "gw.local (10.0.0.1)"))
        #expect(viewModel.tracerouteResults.count == 1)
        #expect(viewModel.tracerouteResults.first?.hostname == "gw.local")
    }

    @Test func nameUpdateForRemovedRowIsDropped() {
        let viewModel = TracerouteViewModel()
        viewModel.handleTracerouteResult(TracerouteResult(hopNumber: 1, success: true, ipAddress: "10.0.0.1",
                                                          hostname: "gw.local", responseTime: 1, message: "gw.local (10.0.0.1)"))
        #expect(viewModel.tracerouteResults.isEmpty, "a late name for a cleared row must not resurrect it")
    }

    @Test func destinationCompletesProgress() {
        let viewModel = TracerouteViewModel()
        viewModel.maxHops = 30
        viewModel.tracerouteResults = [TracerouteResult(hopNumber: 3, success: true, responseTime: 1, message: "", isDestination: true)]
        #expect(viewModel.progress == 1.0)
    }
}
