//
//  PingManagerV2Tests.swift
//  netoTests
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import XCTest
@testable import neto

/// Unit tests for PingManagerV2 implementation
final class PingManagerV2Tests: XCTestCase {
    
    // MARK: - Test Properties
    
    private var pingManager: PingManagerV2!
    
    // MARK: - Setup and Teardown
    
    override func setUpWithError() throws {
        pingManager = PingManagerV2()
    }
    
    override func tearDownWithError() throws {
        pingManager.stopPing()
        pingManager = nil
    }
    
    // MARK: - Configuration Tests
    
    func testDefaultConfiguration() throws {
        let config = PingManagerV2.PingConfig.default
        
        XCTAssertEqual(config.count, 5)
        XCTAssertEqual(config.interval, 1.0)
        XCTAssertEqual(config.timeout, 5.0)
        XCTAssertEqual(config.payloadSize, 56)
    }
    
    func testCustomConfiguration() throws {
        let config = PingManagerV2.PingConfig(
            count: 10,
            interval: 2.0,
            timeout: 10.0,
            payloadSize: 128
        )
        
        XCTAssertEqual(config.count, 10)
        XCTAssertEqual(config.interval, 2.0)
        XCTAssertEqual(config.timeout, 10.0)
        XCTAssertEqual(config.payloadSize, 128)
    }
    
    // MARK: - Ping Operation Tests
    
    func testPingOperationCreation() throws {
        let expectation = XCTestExpectation(description: "Ping operation created")
        
        let task = pingManager.performPing(
            to: "127.0.0.1",
            onResult: { result in
                XCTAssertNotNil(result)
                expectation.fulfill()
            },
            onComplete: {
                // Completion callback
            }
        )
        
        XCTAssertNotNil(task)
        
        // Cancel the task to clean up
        task.cancel()
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testPingOperationWithCustomConfig() throws {
        let expectation = XCTestExpectation(description: "Ping with custom config")
        
        let config = PingManagerV2.PingConfig(
            count: 3,
            interval: 0.5,
            timeout: 3.0,
            payloadSize: 64
        )
        
        let task = pingManager.performPing(
            to: "127.0.0.1",
            config: config,
            onResult: { result in
                XCTAssertNotNil(result)
                expectation.fulfill()
            },
            onComplete: {
                // Completion callback
            }
        )
        
        XCTAssertNotNil(task)
        
        // Cancel the task to clean up
        task.cancel()
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testPingOperationCancellation() throws {
        let expectation = XCTestExpectation(description: "Ping operation cancelled")
        
        let task = pingManager.performPing(
            to: "127.0.0.1",
            onResult: { result in
                // Should not be called after cancellation
                XCTFail("Result callback should not be called after cancellation")
            },
            onComplete: {
                expectation.fulfill()
            }
        )
        
        // Cancel immediately
        task.cancel()
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testPingStopMethod() throws {
        let expectation = XCTestExpectation(description: "Ping stopped")
        
        let task = pingManager.performPing(
            to: "127.0.0.1",
            onResult: { result in
                // Should not be called after stop
                XCTFail("Result callback should not be called after stop")
            },
            onComplete: {
                expectation.fulfill()
            }
        )
        
        // Stop the ping
        pingManager.stopPing()
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Error Handling Tests
    
    func testPingInvalidHost() throws {
        let expectation = XCTestExpectation(description: "Invalid host error")
        
        let task = pingManager.performPing(
            to: "invalid.host.local",
            onResult: { result in
                XCTAssertFalse(result.success)
                XCTAssertTrue(result.message.contains("Failed to start ping") || result.message.contains("timeout"))
                expectation.fulfill()
            },
            onComplete: {
                // Completion callback
            }
        )
        
        XCTAssertNotNil(task)
        
        wait(for: [expectation], timeout: 15.0)
    }
    
    func testPingEmptyHost() throws {
        let expectation = XCTestExpectation(description: "Empty host error")
        
        let task = pingManager.performPing(
            to: "",
            onResult: { result in
                XCTAssertFalse(result.success)
                expectation.fulfill()
            },
            onComplete: {
                // Completion callback
            }
        )
        
        XCTAssertNotNil(task)
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    // MARK: - Integration Tests
    
    func testPingLocalhost() throws {
        let expectation = XCTestExpectation(description: "Localhost ping")
        expectation.expectedFulfillmentCount = 5 // Expect 5 results
        
        var resultCount = 0
        
        let task = pingManager.performPing(
            to: "127.0.0.1",
            onResult: { result in
                resultCount += 1
                XCTAssertNotNil(result)
                XCTAssertEqual(result.sequenceNumber, resultCount)
                expectation.fulfill()
            },
            onComplete: {
                XCTAssertEqual(resultCount, 5)
            }
        )
        
        XCTAssertNotNil(task)
        
        wait(for: [expectation], timeout: 15.0)
    }
    
    func testPingGoogleDNS() throws {
        let expectation = XCTestExpectation(description: "Google DNS ping")
        expectation.expectedFulfillmentCount = 3 // Expect 3 results
        
        var resultCount = 0
        
        let config = PingManagerV2.PingConfig(
            count: 3,
            interval: 1.0,
            timeout: 5.0,
            payloadSize: 56
        )
        
        let task = pingManager.performPing(
            to: "8.8.8.8",
            config: config,
            onResult: { result in
                resultCount += 1
                XCTAssertNotNil(result)
                XCTAssertEqual(result.sequenceNumber, resultCount)
                expectation.fulfill()
            },
            onComplete: {
                XCTAssertEqual(resultCount, 3)
            }
        )
        
        XCTAssertNotNil(task)
        
        wait(for: [expectation], timeout: 15.0)
    }
    
    // MARK: - Performance Tests
    
    func testPingManagerPerformance() throws {
        measure {
            let manager = PingManagerV2()
            let expectation = XCTestExpectation(description: "Performance test")
            
            let task = manager.performPing(
                to: "127.0.0.1",
                config: PingManagerV2.PingConfig(count: 1, interval: 0.1, timeout: 1.0, payloadSize: 56),
                onResult: { _ in },
                onComplete: { expectation.fulfill() }
            )
            
            wait(for: [expectation], timeout: 2.0)
            task.cancel()
        }
    }
    
    func testMultiplePingManagers() throws {
        measure {
            var managers: [PingManagerV2] = []
            var tasks: [Task<Void, Never>] = []
            
            for _ in 0..<5 {
                let manager = PingManagerV2()
                managers.append(manager)
                
                let task = manager.performPing(
                    to: "127.0.0.1",
                    config: PingManagerV2.PingConfig(count: 1, interval: 0.1, timeout: 1.0, payloadSize: 56),
                    onResult: { _ in },
                    onComplete: { }
                )
                tasks.append(task)
            }
            
            // Clean up
            for task in tasks {
                task.cancel()
            }
            for manager in managers {
                manager.stopPing()
            }
        }
    }
    
    // MARK: - Edge Case Tests
    
    func testPingWithZeroCount() throws {
        let expectation = XCTestExpectation(description: "Zero count ping")
        
        let config = PingManagerV2.PingConfig(
            count: 0,
            interval: 1.0,
            timeout: 5.0,
            payloadSize: 56
        )
        
        let task = pingManager.performPing(
            to: "127.0.0.1",
            config: config,
            onResult: { result in
                XCTFail("Should not receive results with zero count")
            },
            onComplete: {
                expectation.fulfill()
            }
        )
        
        XCTAssertNotNil(task)
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testPingWithVeryShortTimeout() throws {
        let expectation = XCTestExpectation(description: "Short timeout ping")
        
        let config = PingManagerV2.PingConfig(
            count: 1,
            interval: 1.0,
            timeout: 0.1,
            payloadSize: 56
        )
        
        let task = pingManager.performPing(
            to: "8.8.8.8",
            config: config,
            onResult: { result in
                XCTAssertFalse(result.success)
                XCTAssertTrue(result.message.contains("timeout"))
                expectation.fulfill()
            },
            onComplete: {
                // Completion callback
            }
        )
        
        XCTAssertNotNil(task)
        
        wait(for: [expectation], timeout: 5.0)
    }
} 