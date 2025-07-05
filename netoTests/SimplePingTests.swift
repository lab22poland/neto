//
//  SimplePingTests.swift
//  netoTests
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import XCTest
@testable import neto

/// Unit tests for SimplePing implementation
final class SimplePingTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private var simplePing: SimplePing!
    private var mockDelegate: MockSimplePingDelegate!
    
    // MARK: - Setup and Teardown
    
    override func setUpWithError() throws {
        mockDelegate = MockSimplePingDelegate()
        simplePing = SimplePing(hostName: "127.0.0.1", identifier: 12345, delegate: mockDelegate)
    }
    
    override func tearDownWithError() throws {
        simplePing.stop()
        simplePing = nil
        mockDelegate = nil
    }
    
    // MARK: - Initialization Tests
    
    func testSimplePingInitialization() throws {
        let ping = SimplePing(hostName: "example.com", identifier: 54321, delegate: mockDelegate)
        
        XCTAssertEqual(ping.targetHostName, "example.com")
        XCTAssertNotNil(ping)
    }
    
    func testSimplePingInitializationWithIPv4() throws {
        let ping = SimplePing(hostName: "192.168.1.1", identifier: 12345, delegate: mockDelegate)
        
        XCTAssertEqual(ping.targetHostName, "192.168.1.1")
        XCTAssertNotNil(ping)
    }
    
    func testSimplePingInitializationWithIPv6() throws {
        let ping = SimplePing(hostName: "::1", identifier: 12345, delegate: mockDelegate)
        
        XCTAssertEqual(ping.targetHostName, "::1")
        XCTAssertNotNil(ping)
    }
    
    // MARK: - Lifecycle Tests
    
    func testSimplePingStartAndStop() throws {
        // Test that start and stop don't crash
        simplePing.start()
        
        // Give some time for the async operations
        let expectation = XCTestExpectation(description: "Ping operations complete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.simplePing.stop()
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testSimplePingStopWhenNotStarted() throws {
        // Test that stopping when not started doesn't crash
        simplePing.stop()
        XCTAssertTrue(true) // If we get here, no crash occurred
    }
    
    // MARK: - Delegate Tests
    
    func testDelegateCallbacks() throws {
        let expectation = XCTestExpectation(description: "Delegate callbacks")
        expectation.expectedFulfillmentCount = 1 // At least one callback
        
        mockDelegate.onStartWithAddress = { address in
            XCTAssertFalse(address.isEmpty)
            expectation.fulfill()
        }
        
        simplePing.start()
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testDelegateErrorHandling() throws {
        let expectation = XCTestExpectation(description: "Error callback")
        
        mockDelegate.onFailWithError = { error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }
        
        // Try to ping an invalid host
        let invalidPing = SimplePing(hostName: "invalid.host.local", identifier: 12345, delegate: mockDelegate)
        invalidPing.start()
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    // MARK: - Integration Tests
    
    func testPingLocalhost() throws {
        let expectation = XCTestExpectation(description: "Localhost ping")
        
        mockDelegate.onStartWithAddress = { address in
            XCTAssertFalse(address.isEmpty)
            expectation.fulfill()
        }
        
        let localhostPing = SimplePing(hostName: "localhost", identifier: 12345, delegate: mockDelegate)
        localhostPing.start()
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testPingGoogleDNS() throws {
        let expectation = XCTestExpectation(description: "Google DNS ping")
        
        mockDelegate.onStartWithAddress = { address in
            XCTAssertFalse(address.isEmpty)
            expectation.fulfill()
        }
        
        let googlePing = SimplePing(hostName: "8.8.8.8", identifier: 12345, delegate: mockDelegate)
        googlePing.start()
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Performance Tests
    
    func testPingPerformance() throws {
        measure {
            let ping = SimplePing(hostName: "127.0.0.1", identifier: 12345, delegate: mockDelegate)
            ping.start()
            ping.stop()
        }
    }
    
    func testMultiplePingInstances() throws {
        measure {
            var pings: [SimplePing] = []
            
            for i in 0..<10 {
                let ping = SimplePing(hostName: "127.0.0.1", identifier: UInt16(i), delegate: mockDelegate)
                pings.append(ping)
                ping.start()
            }
            
            for ping in pings {
                ping.stop()
            }
        }
    }
}

// MARK: - Mock Delegate

/// Mock delegate for testing SimplePing
class MockSimplePingDelegate: NSObject, SimplePing.Delegate {
    
    var onStartWithAddress: ((Data) -> Void)?
    var onFailWithError: ((Error) -> Void)?
    var onSendPacket: ((Data, UInt16) -> Void)?
    var onFailToSendPacket: ((Data, UInt16, Error) -> Void)?
    var onReceivePingResponse: ((Data, UInt16) -> Void)?
    var onReceiveUnexpectedPacket: ((Data) -> Void)?
    
    func simplePing(_ pinger: SimplePing, didStartWithAddress address: Data) {
        onStartWithAddress?(address)
    }
    
    func simplePing(_ pinger: SimplePing, didFailWithError error: Error) {
        onFailWithError?(error)
    }
    
    func simplePing(_ pinger: SimplePing, didSendPacket packet: Data, sequenceNumber: UInt16) {
        onSendPacket?(packet, sequenceNumber)
    }
    
    func simplePing(_ pinger: SimplePing, didFailToSendPacket packet: Data, sequenceNumber: UInt16, error: Error) {
        onFailToSendPacket?(packet, sequenceNumber, error)
    }
    
    func simplePing(_ pinger: SimplePing, didReceivePingResponsePacket packet: Data, sequenceNumber: UInt16) {
        onReceivePingResponse?(packet, sequenceNumber)
    }
    
    func simplePing(_ pinger: SimplePing, didReceiveUnexpectedPacket packet: Data) {
        onReceiveUnexpectedPacket?(packet)
    }
} 