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
        #expect(manager.formatHopMessage(ipAddress: nil, hostname: nil, isDestination: false) == "", "the probe columns show the stars")
    }

    @Test(arguments: [(UInt8(0), "!N"), (1, "!H"), (2, "!P"), (4, "!F"), (9, "!A"), (10, "!Z"), (13, "!X"), (15, "!C"), (16, "!<16>")])
    func unreachableAnnotation(code: UInt8, annotation: String) {
        #expect(TracerouteManager.unreachableAnnotation(code: code) == annotation)
    }

    @Test func verdictsFollowTraceroute() {
        typealias Verdict = TracerouteManager.ProbeVerdict
        let v4 = { TracerouteManager.verdict(for: $0, family: AF_INET) }
        let v6 = { TracerouteManager.verdict(for: $0, family: AF_INET6) }
        #expect(v4(.timeExceeded(sequenceNumber: 1)) == Verdict(annotation: nil, reachedTarget: false, unreachable: false))
        #expect(v4(.echoReply(sequenceNumber: 1)) == Verdict(annotation: nil, reachedTarget: true, unreachable: false))
        // Port unreachable means the target was reached, protocol unreachable too (with "!P"); others count as unreachable
        #expect(v4(.destinationUnreachable(sequenceNumber: 1, code: 3)) == Verdict(annotation: nil, reachedTarget: true, unreachable: false))
        #expect(v4(.destinationUnreachable(sequenceNumber: 1, code: 2)) == Verdict(annotation: "!P", reachedTarget: true, unreachable: false))
        #expect(v4(.destinationUnreachable(sequenceNumber: 1, code: 1)) == Verdict(annotation: "!H", reachedTarget: false, unreachable: true))
        #expect(v6(.destinationUnreachable(sequenceNumber: 1, code: 4)) == Verdict(annotation: nil, reachedTarget: true, unreachable: false))
        #expect(v6(.destinationUnreachable(sequenceNumber: 1, code: 1)) == Verdict(annotation: "!P", reachedTarget: false, unreachable: true))
        #expect(v6(.destinationUnreachable(sequenceNumber: 1, code: 3)) == Verdict(annotation: "!A", reachedTarget: false, unreachable: true))
        #expect(v6(.destinationUnreachable(sequenceNumber: 1, code: 6)) == Verdict(annotation: nil, reachedTarget: false, unreachable: false))
    }

    @Test(arguments: [Int32(AF_INET), Int32(AF_INET6)])
    func traceEndsAtTargetOrMostlyUnreachableHop(family: Int32) {
        let router = TracerouteManager.ProbeVerdict(annotation: nil, reachedTarget: false, unreachable: false)
        let target = TracerouteManager.ProbeVerdict(annotation: nil, reachedTarget: true, unreachable: false)
        let unreachable = TracerouteManager.ProbeVerdict(annotation: "!H", reachedTarget: false, unreachable: true)
        #expect(!TracerouteManager.endsTrace([router, router, router], family: family))
        #expect(!TracerouteManager.endsTrace([], family: family), "a hop without replies goes on")
        #expect(TracerouteManager.endsTrace([router, target], family: family))
        #expect(!TracerouteManager.endsTrace([unreachable, router, router], family: family), "one unreachable of three is not enough")
        #expect(TracerouteManager.endsTrace([unreachable, unreachable], family: family), "two of three probes unreachable")
    }

    @Test func loadBalancedProbesShowTheirAddress() {
        let result = TracerouteResult(hopNumber: 4, success: true, ipAddress: "10.0.0.1", responseTime: 2, message: "",
                                      probeTimes: [1, 2, nil, 3], probeAddresses: ["10.0.0.1", "10.0.0.2", nil, "10.0.0.2"])
        #expect(result.formattedProbeTimes == "1.000 ms  (10.0.0.2) 2.000 ms *  3.000 ms")
        let back = TracerouteResult(hopNumber: 4, success: true, ipAddress: "10.0.0.1", responseTime: 2, message: "",
                                    probeTimes: [1, 2, 3], probeAddresses: ["10.0.0.1", "10.0.0.2", "10.0.0.1"])
        #expect(back.formattedProbeTimes == "1.000 ms  (10.0.0.2) 2.000 ms  (10.0.0.1) 3.000 ms")
    }

    @Test func probeColumnsKeepTheirPosition() {
        let partial = TracerouteResult(hopNumber: 9, success: true, ipAddress: "172.68.1.1", responseTime: 28, message: "(172.68.1.1)",
                                       probeTimes: [nil, 43.7, 12.7], probeAddresses: [nil, "172.68.1.1", "172.68.1.1"])
        #expect(partial.formattedProbeTimes == "*  43.700 ms  12.700 ms")
        #expect(partial.line == "(172.68.1.1)  *  43.700 ms  12.700 ms")
        let middle = TracerouteResult(hopNumber: 1, success: true, responseTime: 2, message: "", probeTimes: [1.2344, nil, 3])
        #expect(middle.formattedProbeTimes == "1.234 ms *  3.000 ms")
    }

    @Test func hopWithoutRepliesShowsThreeStars() {
        let result = TracerouteResult(hopNumber: 1, success: false, responseTime: 0,
                                      message: TracerouteManager().formatHopMessage(ipAddress: nil, hostname: nil, isDestination: false),
                                      probeTimes: [nil, nil, nil], probeAddresses: [nil, nil, nil])
        #expect(result.line == "* * *")
    }

    @Test func annotationFollowsItsProbe() {
        let result = TracerouteResult(hopNumber: 5, success: true, ipAddress: "10.0.0.1", responseTime: 1, message: "(10.0.0.1)",
                                      probeTimes: [1, nil, 2], probeAnnotations: ["!H", nil, "!H"],
                                      probeAddresses: ["10.0.0.1", nil, "10.0.0.1"])
        #expect(result.formattedProbeTimes == "1.000 ms !H *  2.000 ms !H")
    }
}

/// A real traceroute over loopback: the target answers at hop 1 (no internet needed)
@MainActor
final class TracerouteLoopbackTests: XCTestCase {

    private func run(_ host: String, maxHops: Int = 5, timeout: TimeInterval = 2,
                     cancelAfterStart: Bool = false) -> (results: [TracerouteResult], completions: Int, error: Error?, seconds: Double) {
        let manager = TracerouteManager()
        var results: [TracerouteResult] = []
        var completions = 0
        var completionError: Error?
        let started = Date()
        var seconds = 0.0
        let completed = expectation(description: "completed")
        let task = manager.performTraceroute(to: host, maxHops: maxHops, timeout: timeout,
                                             onResult: { result in
                                                 // The same id comes again after each probe and with the router's name
                                                 if let index = results.firstIndex(where: { $0.id == result.id }) {
                                                     results[index] = result
                                                 } else {
                                                     results.append(result)
                                                 }
                                             },
                                             onComplete: { error in
                                                 completions += 1
                                                 completionError = error
                                                 seconds = Date().timeIntervalSince(started)
                                                 completed.fulfill()
                                             })
        if cancelAfterStart { task.cancel() }
        wait(for: [completed], timeout: 10)
        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { settle.fulfill() }
        wait(for: [settle], timeout: 2)
        return (results, completions, completionError, seconds)
    }

    func testLoopbackIsReachedAtFirstHop() {
        let (results, completions, error, _) = run("127.0.0.1")
        XCTAssertEqual(completions, 1)
        XCTAssertNil(error)
        XCTAssertEqual(results.count, 1, results.map(\.line).joined(separator: "; "))
        XCTAssertEqual(results.first?.hopNumber, 1)
        XCTAssertEqual(results.first?.isDestination, true)
        XCTAssertEqual(results.first?.ipAddress, "127.0.0.1")
        XCTAssertEqual(results.first?.probeTimes.count, TracerouteManager.probesPerHop)
        XCTAssertTrue(results.first?.probeTimes.allSatisfy { $0 != nil } == true)
        XCTAssertEqual(results.first?.probeAddresses, ["127.0.0.1", "127.0.0.1", "127.0.0.1"])
        XCTAssertFalse(results.first?.formattedProbeTimes.contains("(") ?? true, "one address per hop needs no annotation")
    }

    func testInvalidHostReportsErrorWithoutHopsAndCompletesOnce() {
        let (results, completions, error, _) = run("999.1.1.1")
        XCTAssertEqual(completions, 1)
        XCTAssertTrue(results.isEmpty, "an input error is not a hop")
        XCTAssertEqual(error?.localizedDescription, "Invalid IPv4 address format: 999.1.1.1")
    }

    /// 0.0.0.0 cannot be sent to ("Socket is not connected"): the run stops at once instead of waiting out every probe
    func testSendFailureEndsTheRunWithTheError() {
        let (results, completions, error, seconds) = run("0.0.0.0", maxHops: 30, timeout: 2)
        XCTAssertEqual(completions, 1)
        XCTAssertTrue(results.isEmpty, results.map(\.line).joined(separator: "; "))
        XCTAssertTrue(error?.localizedDescription.contains("sendto: ") == true, error?.localizedDescription ?? "no error")
        XCTAssertLessThan(seconds, 2, "the run must not wait for probes that were never sent")
    }

    func testCancelCompletesOnceWithoutResults() {
        let (results, completions, error, _) = run("127.0.0.1", cancelAfterStart: true)
        XCTAssertEqual(completions, 1)
        XCTAssertNil(error)
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

    @Test func progressAndStop() {
        let viewModel = TracerouteViewModel()
        viewModel.maxHops = 10
        viewModel.tracerouteResults = [
            TracerouteResult(hopNumber: 1, success: true, responseTime: 1, message: "(10.0.0.1)"),
            TracerouteResult(hopNumber: 2, success: false, responseTime: 0, message: "", probeTimes: [nil, nil, nil]),
        ]
        #expect(viewModel.currentHop == 2)
        #expect(viewModel.progress == 0.2)

        viewModel.isTracing = true
        viewModel.stopTraceroute()
        #expect(viewModel.stoppedByUser)
        #expect(viewModel.tracerouteResults.count == 2, "stopping adds no row")
        #expect(viewModel.currentHop == 2)
        #expect(viewModel.exportResults().contains("Trace stopped by user."))
    }

    @Test func runErrorIsShownWithoutHops() async throws {
        let viewModel = TracerouteViewModel()
        viewModel.targetHost = "999.1.1.1"
        viewModel.startTraceroute()
        for _ in 0..<200 where viewModel.isTracing {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(!viewModel.isTracing)
        #expect(viewModel.errorMessage == "Invalid IPv4 address format: 999.1.1.1")
        #expect(viewModel.tracerouteResults.isEmpty)
        #expect(viewModel.currentHop == 0)
    }

    @Test func exportUsesTheRunParametersAndTracerouteLines() async throws {
        let viewModel = TracerouteViewModel()
        viewModel.targetHost = "999.1.1.1"
        viewModel.maxHops = 7
        viewModel.timeout = 2
        viewModel.startTraceroute()
        for _ in 0..<200 where viewModel.isTracing {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        // The form changes after the run; the export still describes the run
        viewModel.targetHost = "example.com"
        viewModel.maxHops = 30
        viewModel.timeout = 5
        viewModel.tracerouteResults = [
            TracerouteResult(hopNumber: 1, success: false, responseTime: 0, message: "", probeTimes: [nil, nil, nil]),
            TracerouteResult(hopNumber: 2, success: true, ipAddress: "10.0.0.2", responseTime: 2, message: "(10.0.0.2)",
                             probeTimes: [nil, 2, nil], probeAddresses: [nil, "10.0.0.2", nil]),
        ]
        let export = viewModel.exportResults()
        #expect(export.contains("Target: 999.1.1.1\n"))
        #expect(export.contains("Max Hops: 7\n"))
        #expect(export.contains("Probe Timeout: 2.0s\n"))
        #expect(export.contains("\n 1  * * *\n"))
        #expect(export.contains("\n 2  (10.0.0.2)  *  2.000 ms *\n"))
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
