//
//  PingTests.swift
//  netoTests
//
//  Created by Sergii Solianyk on 12/10/2026.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import XCTest
@testable import neto

/// Real ICMP over the loopback interface (no internet needed)
@MainActor
final class SimplePingLoopbackTests: XCTestCase {

    private final class Recorder: NSObject, SimplePing.Delegate {
        var onStart: (() -> Void)?
        var onFail: ((Error) -> Void)?
        var onReply: ((UInt16) -> Void)?
        func simplePing(_ pinger: SimplePing, didStartWithAddress address: Data) { onStart?() }
        func simplePing(_ pinger: SimplePing, didFailWithError error: Error) { onFail?(error) }
        func simplePing(_ pinger: SimplePing, didSendPacket packet: Data, sequenceNumber: UInt16) {}
        func simplePing(_ pinger: SimplePing, didFailToSendPacket packet: Data, sequenceNumber: UInt16, error: Error) {}
        func simplePing(_ pinger: SimplePing, didReceivePingResponsePacket packet: Data, sequenceNumber: UInt16) { onReply?(sequenceNumber) }
        func simplePing(_ pinger: SimplePing, didReceiveUnexpectedPacket packet: Data) {}
    }

    /// Sends one echo request and expects the reply with the same sequence number
    private func assertEchoRoundTrip(host: String) {
        let recorder = Recorder()
        let pinger = SimplePing(hostName: host, identifier: UInt16.random(in: 1...UInt16.max), delegate: recorder)
        let replied = expectation(description: "echo reply from \(host)")
        var sentSequence: UInt16?
        recorder.onStart = { sentSequence = pinger.sendPingWithPayload(Data(repeating: 0xA5, count: 32)) }
        recorder.onFail = { XCTFail("\(host): \($0)") }
        recorder.onReply = { sequence in
            XCTAssertEqual(sequence, sentSequence)
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
        XCTAssertTrue(run.results.allSatisfy { $0.message.hasPrefix("Reply from 127.0.0.1") })
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

/// Statistics shown under the ping results
@MainActor
final class PingStatisticsTests: XCTestCase {

    private func result(_ sequence: Int, success: Bool, time: Double = 0, message: String = "") -> PingResult {
        PingResult(id: UUID(), sequenceNumber: sequence, success: success, responseTime: time, message: message)
    }

    func testStatisticsFromReplies() {
        let viewModel = PingViewModel()
        viewModel.pingResults = [result(1, success: true, time: 10), result(2, success: false), result(3, success: true, time: 30)]
        let stats = viewModel.pingStatistics

        XCTAssertEqual(stats.totalPings, 3)
        XCTAssertEqual(stats.successCount, 2)
        XCTAssertEqual(stats.packetLoss, 100.0 / 3, accuracy: 0.001)
        XCTAssertEqual(stats.minResponseTime, 10)
        XCTAssertEqual(stats.maxResponseTime, 30)
        XCTAssertEqual(stats.avgResponseTime, 20)
    }

    func testEmptyHostIsRejected() {
        let viewModel = PingViewModel()
        viewModel.targetHost = "   "
        XCTAssertFalse(viewModel.isTargetHostValid)
        viewModel.startPing()
        XCTAssertFalse(viewModel.isPinging)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testStopMarkerDoesNotCountAsLostPacket() {
        let viewModel = PingViewModel()
        viewModel.pingResults = [result(1, success: true, time: 1), result(2, success: true, time: 1)]
        viewModel.isPinging = true
        viewModel.stopPing()

        XCTExpectFailure("Known issue: the \"Ping stopped by user\" row is counted as a sent and lost packet")
        XCTAssertEqual(viewModel.pingStatistics.totalPings, 2)
        XCTAssertEqual(viewModel.pingStatistics.packetLoss, 0)
    }
}
