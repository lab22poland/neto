//
//  PingTests.swift
//  netoTests
//
//  Created by Sergii Solianyk on 12/10/2026.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import XCTest
import Testing
@testable import neto

/// Real ICMP over the loopback interface (no internet needed)
@MainActor
final class SimplePingLoopbackTests: XCTestCase {

    private final class Recorder: NSObject, SimplePing.Delegate {
        var onStart: (() -> Void)?
        var onFail: ((Error) -> Void)?
        var onReply: ((UInt16, String?) -> Void)?
        func simplePing(_ pinger: SimplePing, didStartWithAddress address: Data) { onStart?() }
        func simplePing(_ pinger: SimplePing, didFailWithError error: Error) { onFail?(error) }
        func simplePing(_ pinger: SimplePing, didSendPacket packet: Data, sequenceNumber: UInt16) {}
        func simplePing(_ pinger: SimplePing, didFailToSendPacket packet: Data, sequenceNumber: UInt16, error: Error) {}
        func simplePing(_ pinger: SimplePing, didReceivePingResponsePacket packet: Data, sequenceNumber: UInt16,
                        from address: Data, receivedAt: UInt64) {
            onReply?(sequenceNumber, TracerouteManager.numericHost(address))
        }
        func simplePing(_ pinger: SimplePing, didReceiveUnexpectedPacket packet: Data) {}
    }

    /// Sends one echo request and expects the reply with the same sequence number from the target address
    private func assertEchoRoundTrip(host: String) {
        let recorder = Recorder()
        let pinger = SimplePing(hostName: host, identifier: UInt16.random(in: 1...UInt16.max), delegate: recorder)
        let replied = expectation(description: "echo reply from \(host)")
        var sentSequence: UInt16?
        recorder.onStart = { sentSequence = pinger.sendPingWithPayload(Data(repeating: 0xA5, count: 32)) }
        recorder.onFail = { XCTFail("\(host): \($0)") }
        recorder.onReply = { sequence, sender in
            XCTAssertEqual(sequence, sentSequence)
            XCTAssertEqual(sender, host, "the sender address comes from recvmsg")
            replied.fulfill()
        }
        pinger.start()
        wait(for: [replied], timeout: 5)
        pinger.stop()
    }

    func testIPv4LoopbackEchoRoundTrip() {
        assertEchoRoundTrip(host: "127.0.0.1")
    }

    func testIPv6LoopbackEchoRoundTrip() {
        assertEchoRoundTrip(host: "::1")
    }

    func testUnresolvableHostReportsFailure() {
        let recorder = Recorder()
        let pinger = SimplePing(hostName: "", identifier: 1, delegate: recorder)
        let failed = expectation(description: "resolve failure")
        recorder.onStart = { XCTFail("an empty host must not start") }
        recorder.onFail = { _ in failed.fulfill() }
        pinger.start()
        wait(for: [failed], timeout: 5)
    }
}

/// PingManager contract: results, ordering, cancellation and exactly-once completion
@MainActor
final class PingManagerTests: XCTestCase {

    private struct Run {
        var results: [PingResult] = []
        var completions = 0
    }

    private let fast = PingManager.PingConfig(count: 3, interval: 0.2, timeout: 2, payloadSize: 56)

    /// Waits for the first completion, then a little longer to catch a second (forbidden) one
    private func waitForCompletion(_ completed: XCTestExpectation, timeout: TimeInterval = 10) {
        wait(for: [completed], timeout: timeout)
        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { settle.fulfill() }
        wait(for: [settle], timeout: 2)
    }

    func testLocalhostRunDeliversOrderedReplies() {
        var run = Run()
        let completed = expectation(description: "completed")
        let manager = PingManager()
        _ = manager.performPing(to: "127.0.0.1", config: fast,
                                      onResult: { run.results.append($0) },
                                      onComplete: { run.completions += 1; completed.fulfill() })
        waitForCompletion(completed)

        XCTAssertEqual(run.completions, 1)
        XCTAssertEqual(run.results.map(\.sequenceNumber), [1, 2, 3])
        XCTAssertTrue(run.results.allSatisfy(\.success), run.results.map(\.message).joined(separator: "; "))
        XCTAssertTrue(run.results.allSatisfy { $0.message.hasPrefix("Reply from 127.0.0.1:") })
    }

    func testStatisticsCountTransmittedAndReceived() {
        var statistics: [PingStatistics] = []
        let completed = expectation(description: "completed")
        let manager = PingManager()
        _ = manager.performPing(to: "localhost", config: fast,
                                      onResult: { _ in },
                                      onStatistics: { statistics.append($0) },
                                      onComplete: { completed.fulfill() })
        waitForCompletion(completed)

        let first = statistics.first
        XCTAssertEqual(first?.transmitted, 0, "the first update comes with the resolved address, before any send")
        XCTAssertTrue(["127.0.0.1", "::1"].contains(first?.address ?? ""), "resolved address: \(first?.address ?? "nil")")
        XCTAssertEqual(first?.host, "localhost")
        XCTAssertEqual(statistics.last?.transmitted, 3)
        XCTAssertEqual(statistics.last?.received, 3)
        XCTAssertEqual(statistics.last?.late, 0)
    }

    /// With interval > timeout the timeout row must not wait for the next send
    func testTimeoutRowIsDeliveredWithoutWaitingForNextSend() {
        let manager = PingManager()
        var firstTimeoutAfter: TimeInterval?
        let start = Date()
        let timedOut = expectation(description: "timeout row")
        _ = manager.performPing(to: "192.0.2.1", config: .init(count: 2, interval: 3, timeout: 0.3, payloadSize: 56),
                                onResult: { result in
                                    guard firstTimeoutAfter == nil else { return }
                                    firstTimeoutAfter = Date().timeIntervalSince(start)
                                    timedOut.fulfill()
                                },
                                onComplete: {})
        wait(for: [timedOut], timeout: 5)
        manager.stopPing()
        // Either a timeout (TEST-NET never answers) or a send error without a route; both well before the 3 s interval
        XCTAssertLessThan(firstTimeoutAfter ?? 99, 1.5)
    }

    /// Every loopback reply takes longer than 1 µs: whether the expiry or the reply is processed first,
    /// the rows are timeouts and the replies still count as received (like `ping -W`)
    func testLateRepliesAreTimeoutRowsButCountAsReceived() {
        var run = Run()
        var statistics: PingStatistics?
        let completed = expectation(description: "completed")
        let manager = PingManager()
        _ = manager.performPing(to: "127.0.0.1", config: .init(count: 3, interval: 0.2, timeout: 0.000_001, payloadSize: 56),
                                      onResult: { run.results.append($0) },
                                      onStatistics: { statistics = $0 },
                                      onComplete: { completed.fulfill() })
        waitForCompletion(completed)

        XCTAssertEqual(run.results.map(\.kind), [.timeout, .timeout, .timeout], run.results.map(\.message).joined(separator: "; "))
        XCTAssertEqual(statistics?.transmitted, 3)
        // A reply still in flight when the run ends is lost, as in ping; on loopback all three arrive in time
        XCTAssertEqual(statistics?.received, 3)
        XCTAssertEqual(statistics?.late, 3)
        XCTAssertEqual(statistics?.packetLoss, 0)
    }

    func testStopEndsRunOnceWithoutFurtherResults() {
        var run = Run()
        let manager = PingManager()
        let firstResult = expectation(description: "first result")
        let completed = expectation(description: "completed")
        var resultsAtStop = 0
        _ = manager.performPing(to: "127.0.0.1", config: .init(count: 5, interval: 1, timeout: 2, payloadSize: 56),
                                onResult: { result in
                                    run.results.append(result)
                                    if run.results.count == 1 { firstResult.fulfill() }
                                },
                                onComplete: { run.completions += 1; completed.fulfill() })
        wait(for: [firstResult], timeout: 5)
        resultsAtStop = run.results.count
        manager.stopPing()
        waitForCompletion(completed, timeout: 3)

        XCTAssertEqual(run.completions, 1)
        XCTAssertEqual(run.results.count, resultsAtStop, "no result may arrive after stop")
    }

    func testCancelBeforeStartStillCompletesOnce() {
        var run = Run()
        let completed = expectation(description: "completed")
        let manager = PingManager()
        let task = manager.performPing(to: "127.0.0.1", config: fast,
                                             onResult: { run.results.append($0) },
                                             onComplete: { run.completions += 1; completed.fulfill() })
        task.cancel()
        waitForCompletion(completed, timeout: 3)

        XCTAssertEqual(run.completions, 1)
        XCTAssertTrue(run.results.isEmpty)
    }

    func testZeroCountCompletesWithoutResults() {
        var run = Run()
        let completed = expectation(description: "completed")
        let manager = PingManager()
        _ = manager.performPing(to: "127.0.0.1", config: .init(count: 0, interval: 1, timeout: 1, payloadSize: 56),
                                      onResult: { run.results.append($0) },
                                      onComplete: { run.completions += 1; completed.fulfill() })
        waitForCompletion(completed, timeout: 3)

        XCTAssertEqual(run.completions, 1)
        XCTAssertTrue(run.results.isEmpty)
    }

    func testStartFailureIsReportedAsSingleResult() {
        var run = Run()
        let completed = expectation(description: "completed")
        let manager = PingManager()
        _ = manager.performPing(to: "", config: fast,
                                      onResult: { run.results.append($0) },
                                      onComplete: { run.completions += 1; completed.fulfill() })
        waitForCompletion(completed, timeout: 5)

        XCTAssertEqual(run.completions, 1)
        XCTAssertEqual(run.results.count, 1)
        XCTAssertEqual(run.results.first?.sequenceNumber, 1)
        XCTAssertEqual(run.results.first?.success, false)
        XCTAssertTrue(run.results.first?.message.hasPrefix("Failed to start ping") == true)
    }

    func testNewRunWaitsForPreviousRunOnSameManager() {
        let manager = PingManager()
        var first = Run(), second = Run()
        let firstCompleted = expectation(description: "first completed")
        let secondCompleted = expectation(description: "second completed")
        _ = manager.performPing(to: "127.0.0.1", config: fast,
                                onResult: { first.results.append($0) },
                                onComplete: { first.completions += 1; firstCompleted.fulfill() })
        _ = manager.performPing(to: "127.0.0.1", config: fast,
                                onResult: { second.results.append($0) },
                                onComplete: { second.completions += 1; secondCompleted.fulfill() })
        wait(for: [firstCompleted, secondCompleted], timeout: 10, enforceOrder: true)

        XCTAssertEqual(first.completions, 1)
        XCTAssertEqual(second.completions, 1)
        XCTAssertEqual(second.results.map(\.sequenceNumber), [1, 2, 3], "the cancelled first run must not disturb the second")
        XCTAssertTrue(second.results.allSatisfy(\.success))
    }
}

/// Statistics with ping's semantics: transmitted = send attempts, loss = (transmitted - received) / transmitted
struct PingStatisticsTests {

    @Test func lossAndTimesFromRepliesIncludingLateOnes() {
        var statistics = PingStatistics(host: "example.com", address: "192.0.2.1")
        for _ in 0..<4 { statistics.recordTransmitted() }
        statistics.recordReply(roundTripTime: 10, late: false)
        statistics.recordReply(roundTripTime: 50, late: true)
        statistics.recordReply(roundTripTime: 30, late: false)

        #expect(statistics.received == 3)
        #expect(statistics.late == 1)
        #expect(statistics.packetLoss == 25)
        #expect(statistics.formattedPacketLoss == "25.0%")
        #expect(statistics.minResponseTime == 10)
        #expect(statistics.maxResponseTime == 50)
        #expect(statistics.avgResponseTime == 30)
    }

    /// ping.c: 2 * tmax truncated to whole seconds, at least 1 s, if anything was received; else the wait time
    @Test(arguments: [
        (0, 0.0, 5.0, 5.0),
        (0, 0.0, 0.3, 0.3),
        (3, 35.0, 5.0, 1.0),
        (3, 499.0, 5.0, 1.0),
        (3, 600.0, 5.0, 1.0),     // 1.2 s truncated
        (3, 1000.0, 5.0, 2.0),
        (1, 2600.0, 2.0, 5.0),    // a late reply raises tmax too
    ])
    func finalWaitLikePing(received: Int, maxRoundTripTime: Double, timeout: Double, wait: Double) {
        #expect(PingManager.finalWait(received: received, maxRoundTripTime: maxRoundTripTime, timeout: timeout) == wait)
    }

    @Test func nothingTransmittedIsNoLoss() {
        let statistics = PingStatistics(host: "localhost", address: "127.0.0.1")
        #expect(statistics.packetLoss == 0)
        #expect(statistics.avgResponseTime == 0)
    }

    @Test(arguments: [
        (0.004, 0.005, false),
        (0.005, 0.005, false),   // ping: late only if triptime > waittime
        (0.0051, 0.005, true),
        (0.012, 0.005, true),
        (2.5, 5.0, false),
    ])
    func lateRule(roundTripTime: Double, timeout: Double, late: Bool) {
        #expect(PingManager.isLate(roundTripTime: roundTripTime, timeout: timeout) == late)
    }
}

/// View model accounting: failed start, stop, clear
@MainActor
final class PingViewModelTests: XCTestCase {

    private func waitUntilIdle(_ viewModel: PingViewModel, timeout: TimeInterval) {
        let done = expectation(for: NSPredicate { _, _ in !viewModel.isPinging }, evaluatedWith: nil)
        wait(for: [done], timeout: timeout)
    }

    func testEmptyHostIsRejected() {
        let viewModel = PingViewModel()
        viewModel.targetHost = "   "
        XCTAssertFalse(viewModel.isTargetHostValid)
        viewModel.startPing()
        XCTAssertFalse(viewModel.isPinging)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    /// A host that does not resolve is an error, not a run with "1 sent, 100% loss"
    func testFailedStartShowsErrorWithoutStatistics() {
        let viewModel = PingViewModel()
        viewModel.targetHost = "a..b"   // an invalid name fails in getaddrinfo without a DNS query
        viewModel.startPing()
        waitUntilIdle(viewModel, timeout: 10)

        XCTAssertTrue(viewModel.errorMessage?.hasPrefix("Failed to start ping") == true, viewModel.errorMessage ?? "nil")
        XCTAssertTrue(viewModel.pingResults.isEmpty)
        XCTAssertNil(viewModel.statistics)
    }

    /// Packets in flight at Stop count as transmitted and lost, like ping's Ctrl-C summary
    func testStopKeepsUnansweredPacketsAsLost() {
        let viewModel = PingViewModel()
        viewModel.targetHost = "192.0.2.1"   // TEST-NET-1: never answers (or sendto fails without a route; both count as sent)
        viewModel.pingCount = 10
        viewModel.pingInterval = 0.2
        viewModel.pingTimeout = 5
        viewModel.startPing()
        let sent = expectation(for: NSPredicate { _, _ in (viewModel.statistics?.transmitted ?? 0) >= 2 }, evaluatedWith: nil)
        wait(for: [sent], timeout: 10)
        viewModel.stopPing()
        let transmitted = viewModel.statistics?.transmitted ?? 0
        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { settle.fulfill() }
        wait(for: [settle], timeout: 2)

        XCTAssertFalse(viewModel.isPinging)
        XCTAssertGreaterThanOrEqual(transmitted, 2)
        XCTAssertEqual(viewModel.statistics?.transmitted, transmitted, "nothing changes after stop")
        XCTAssertEqual(viewModel.statistics?.received, 0)
        XCTAssertEqual(viewModel.statistics?.packetLoss, 100)
        XCTAssertEqual(viewModel.pingResults.last?.kind, .stopped)
        XCTAssertEqual(viewModel.pingResults.filter { $0.kind == .stopped }.count, 1)
    }

    func testStopAfterRepliesKeepsStatisticsAndClearRemovesThem() {
        let viewModel = PingViewModel()
        viewModel.targetHost = "127.0.0.1"
        viewModel.pingCount = 20
        viewModel.pingInterval = 0.2
        viewModel.startPing()
        let replied = expectation(for: NSPredicate { _, _ in (viewModel.statistics?.received ?? 0) >= 2 }, evaluatedWith: nil)
        wait(for: [replied], timeout: 10)
        viewModel.stopPing()

        let statistics = viewModel.statistics
        XCTAssertEqual(statistics?.address, "127.0.0.1")
        XCTAssertEqual(viewModel.pingResults.filter(\.success).count, statistics?.received)
        XCTAssertLessThanOrEqual(statistics?.received ?? 0, statistics?.transmitted ?? 0)
        viewModel.clearResults()
        XCTAssertTrue(viewModel.pingResults.isEmpty)
        XCTAssertNil(viewModel.statistics)
    }
}
