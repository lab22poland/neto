//
//  netoTests.swift
//  netoTests
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Testing
import Foundation
@testable import neto

struct netoTests {
    
    // MARK: - NetworkTool Tests
    @Test func networkToolCaseCount() async throws {
        // Test that we have the expected number of tools
        #expect(NetworkTool.allCases.count == 2)
    }
    
    @Test func networkToolIdentifiers() async throws {
        // Test that tool identifiers are correct
        #expect(NetworkTool.ping.id == "ping")
        #expect(NetworkTool.about.id == "about")
    }
    
    @Test func networkToolTitles() async throws {
        // Test that tool titles are correct
        #expect(NetworkTool.ping.title == "Ping")
        #expect(NetworkTool.about.title == "About")
    }
    
    @Test func networkToolIcons() async throws {
        // Test that tool icons are correct
        #expect(NetworkTool.ping.icon == "network")
        #expect(NetworkTool.about.icon == "info.circle")
    }
    
    @Test func networkToolRawValues() async throws {
        // Test that raw values are correct
        #expect(NetworkTool.ping.rawValue == "ping")
        #expect(NetworkTool.about.rawValue == "about")
    }
    
    @Test func networkToolFromRawValue() async throws {
        // Test that tools can be created from raw values
        #expect(NetworkTool(rawValue: "ping") == .ping)
        #expect(NetworkTool(rawValue: "about") == .about)
        #expect(NetworkTool(rawValue: "invalid") == nil)
    }
    
    // MARK: - PingResult Tests
    @Test func pingResultCreation() async throws {
        let id = UUID()
        let result = PingResult(
            id: id,
            sequenceNumber: 1,
            success: true,
            responseTime: 25.5,
            message: "Reply from example.com: time=25.5ms seq=1"
        )
        
        #expect(result.id == id)
        #expect(result.sequenceNumber == 1)
        #expect(result.success == true)
        #expect(result.responseTime == 25.5)
        #expect(result.message == "Reply from example.com: time=25.5ms seq=1")
    }
    
    @Test func pingResultSuccessMessage() async throws {
        let result = PingResult(
            id: UUID(),
            sequenceNumber: 2,
            success: true,
            responseTime: 42.3,
            message: "Reply from 8.8.8.8: time=42.3ms seq=2"
        )
        
        #expect(result.success == true)
        #expect(result.responseTime > 0)
        #expect(result.message.contains("Reply from"))
        #expect(result.message.contains("seq=2"))
    }
    
    @Test func pingResultFailureMessage() async throws {
        let result = PingResult(
            id: UUID(),
            sequenceNumber: 3,
            success: false,
            responseTime: 0,
            message: "Request timeout seq=3"
        )
        
        #expect(result.success == false)
        #expect(result.responseTime == 0)
        #expect(result.message.contains("timeout"))
        #expect(result.message.contains("seq=3"))
    }
    
    @Test func pingResultErrorMessage() async throws {
        let result = PingResult(
            id: UUID(),
            sequenceNumber: 1,
            success: false,
            responseTime: 0,
            message: "Error seq=1: Host not found"
        )
        
        #expect(result.success == false)
        #expect(result.responseTime == 0)
        #expect(result.message.contains("Error"))
        #expect(result.message.contains("Host not found"))
    }
    
    // MARK: - String Validation Tests
    @Test func hostValidation() async throws {
        // Test valid host formats
        let validHosts = [
            "google.com",
            "8.8.8.8",
            "2001:4860:4860::8888",
            "localhost",
            "example.org",
            "192.168.1.1"
        ]
        
        for host in validHosts {
            let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(!trimmed.isEmpty, "Host '\(host)' should be valid")
        }
        
        // Test invalid host formats
        let invalidHosts = [
            "",
            "   ",
            "\n\t",
            "  \n  "
        ]
        
        for host in invalidHosts {
            let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(trimmed.isEmpty, "Host '\(host)' should be invalid")
        }
    }
    
    // MARK: - Performance Tests
    @Test func pingResultCreationPerformance() async throws {
        let startTime = Date()
        
        // Create many ping results to test performance
        var results: [PingResult] = []
        for i in 1...1000 {
            let result = PingResult(
                id: UUID(),
                sequenceNumber: i,
                success: i % 2 == 0,
                responseTime: Double(i) * 0.5,
                message: "Test message \(i)"
            )
            results.append(result)
        }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        #expect(results.count == 1000)
        #expect(duration < 1.0, "Creating 1000 PingResult objects should take less than 1 second")
    }
    
    // MARK: - Network Tool Sequence Tests  
    @Test func networkToolSequence() async throws {
        // Test that NetworkTool conforms to CaseIterable properly
        let allTools = NetworkTool.allCases
        #expect(allTools.contains(.ping))
        #expect(allTools.contains(.about))
        
        // Test that each tool has a unique identifier
        let identifiers = allTools.map { $0.id }
        let uniqueIdentifiers = Set(identifiers)
        #expect(identifiers.count == uniqueIdentifiers.count, "All tools should have unique identifiers")
    }
    
    // MARK: - Ping Result Identifiable Tests
    @Test func pingResultIdentifiable() async throws {
        let result1 = PingResult(
            id: UUID(),
            sequenceNumber: 1,
            success: true,
            responseTime: 25.0,
            message: "Test 1"
        )
        
        let result2 = PingResult(
            id: UUID(),
            sequenceNumber: 2,
            success: false,
            responseTime: 0,
            message: "Test 2"
        )
        
        // Test that each result has a unique ID
        #expect(result1.id != result2.id)
        
        // Test that we can use PingResult in collections that require Identifiable
        let results = [result1, result2]
        let ids = results.map { $0.id }
        #expect(ids.count == 2)
        #expect(Set(ids).count == 2, "All PingResult objects should have unique IDs")
    }
    
    // MARK: - Message Format Tests
    @Test func pingMessageFormats() async throws {
        // Test successful ping message format
        let host = "example.com"
        let responseTime = 42.5
        let sequenceNumber = 3
        
        let expectedMessage = String(format: "Reply from %@: time=%.2fms seq=%d", host, responseTime, sequenceNumber)
        #expect(expectedMessage == "Reply from example.com: time=42.50ms seq=3")
        
        // Test timeout message format
        let timeoutMessage = String(format: "Request timeout seq=%d", sequenceNumber)
        #expect(timeoutMessage == "Request timeout seq=3")
        
        // Test error message format
        let errorMessage = String(format: "Error seq=%d: %@", sequenceNumber, "Network unreachable")
        #expect(errorMessage == "Error seq=3: Network unreachable")
    }
    
    // MARK: - Edge Cases Tests
    @Test func edgeCases() async throws {
        // Test ping result with zero response time
        let zeroTimeResult = PingResult(
            id: UUID(),
            sequenceNumber: 1,
            success: true,
            responseTime: 0.0,
            message: "Instant response"
        )
        #expect(zeroTimeResult.responseTime == 0.0)
        #expect(zeroTimeResult.success == true)
        
        // Test ping result with very high response time
        let highTimeResult = PingResult(
            id: UUID(),
            sequenceNumber: 1,
            success: true,
            responseTime: 5000.0,
            message: "Very slow response"
        )
        #expect(highTimeResult.responseTime == 5000.0)
        #expect(highTimeResult.success == true)
        
        // Test ping result with negative sequence number (edge case)
        let negativeSeqResult = PingResult(
            id: UUID(),
            sequenceNumber: -1,
            success: false,
            responseTime: 0,
            message: "Invalid sequence"
        )
        #expect(negativeSeqResult.sequenceNumber == -1)
        #expect(negativeSeqResult.success == false)
    }
}
