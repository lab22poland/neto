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
        #expect(NetworkTool.allCases.count == 3)
    }
    
    @Test func networkToolIdentifiers() async throws {
        // Test that tool identifiers are correct
        #expect(NetworkTool.ping.id == "ping")
        #expect(NetworkTool.traceroute.id == "traceroute")
        #expect(NetworkTool.about.id == "about")
    }
    
    @Test func networkToolTitles() async throws {
        // Test that tool titles are correct
        #expect(NetworkTool.ping.title == "Ping")
        #expect(NetworkTool.traceroute.title == "Traceroute")
        #expect(NetworkTool.about.title == "About")
    }
    
    @Test func networkToolIcons() async throws {
        // Test that tool icons are correct
        #expect(NetworkTool.ping.icon == "network")
        #expect(NetworkTool.traceroute.icon == "point.topleft.down.curvedto.point.bottomright.up")
        #expect(NetworkTool.about.icon == "info.circle")
    }
    
    @Test func networkToolRawValues() async throws {
        // Test that raw values are correct
        #expect(NetworkTool.ping.rawValue == "ping")
        #expect(NetworkTool.traceroute.rawValue == "traceroute")
        #expect(NetworkTool.about.rawValue == "about")
    }
    
    @Test func networkToolFromRawValue() async throws {
        // Test that tools can be created from raw values
        #expect(NetworkTool(rawValue: "ping") == .ping)
        #expect(NetworkTool(rawValue: "traceroute") == .traceroute)
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
    
    // MARK: - TracerouteResult Tests
    @Test func tracerouteResultCreation() async throws {
        let id = UUID()
        let result = TracerouteResult(
            id: id,
            hopNumber: 3,
            success: true,
            ipAddress: "192.168.1.1",
            hostname: "gateway.local",
            responseTime: 15.2,
            message: "Hop 3: gateway.local (192.168.1.1)",
            isDestination: false
        )
        
        #expect(result.id == id)
        #expect(result.hopNumber == 3)
        #expect(result.success == true)
        #expect(result.ipAddress == "192.168.1.1")
        #expect(result.hostname == "gateway.local")
        #expect(result.responseTime == 15.2)
        #expect(result.message == "Hop 3: gateway.local (192.168.1.1)")
        #expect(result.isDestination == false)
    }
    
    @Test func tracerouteResultDestination() async throws {
        let result = TracerouteResult(
            hopNumber: 10,
            success: true,
            ipAddress: "8.8.8.8",
            hostname: "dns.google",
            responseTime: 50.1,
            message: "Hop 10: dns.google (8.8.8.8) [DESTINATION REACHED]",
            isDestination: true
        )
        
        #expect(result.success == true)
        #expect(result.isDestination == true)
        #expect(result.message.contains("DESTINATION REACHED"))
        #expect(result.responseTime > 0)
    }
    
    @Test func tracerouteResultTimeout() async throws {
        let result = TracerouteResult(
            hopNumber: 5,
            success: false,
            responseTime: 0,
            message: "Hop 5: * * * Request timed out",
            isDestination: false
        )
        
        #expect(result.success == false)
        #expect(result.isDestination == false)
        #expect(result.responseTime == 0)
        #expect(result.message.contains("* * *"))
        #expect(result.message.contains("timed out"))
    }
    
    @Test func tracerouteResultWithDefaults() async throws {
        let result = TracerouteResult(
            hopNumber: 1,
            success: true,
            responseTime: 5.0,
            message: "Test hop"
        )
        
        // Test default values
        #expect(result.ipAddress == nil)
        #expect(result.hostname == nil)
        #expect(result.isDestination == false)
        #expect(result.id != UUID())  // Should have a valid UUID
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
    
    @Test func tracerouteResultCreationPerformance() async throws {
        let startTime = Date()
        
        // Create many traceroute results to test performance
        var results: [TracerouteResult] = []
        for i in 1...1000 {
            let result = TracerouteResult(
                hopNumber: i,
                success: i % 3 != 0,
                ipAddress: i % 2 == 0 ? "192.168.1.\(i % 255)" : nil,
                hostname: i % 4 == 0 ? "host\(i).local" : nil,
                responseTime: Double(i) * 0.3,
                message: "Test hop \(i)",
                isDestination: i == 1000
            )
            results.append(result)
        }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        #expect(results.count == 1000)
        #expect(duration < 1.0, "Creating 1000 TracerouteResult objects should take less than 1 second")
    }
    
    // MARK: - Network Tool Sequence Tests  
    @Test func networkToolSequence() async throws {
        // Test that NetworkTool conforms to CaseIterable properly
        let allTools = NetworkTool.allCases
        #expect(allTools.contains(.ping))
        #expect(allTools.contains(.traceroute))
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
    
    // MARK: - Traceroute Result Identifiable Tests
    @Test func tracerouteResultIdentifiable() async throws {
        let result1 = TracerouteResult(
            hopNumber: 1,
            success: true,
            responseTime: 10.0,
            message: "Test hop 1"
        )
        
        let result2 = TracerouteResult(
            hopNumber: 2,
            success: false,
            responseTime: 0,
            message: "Test hop 2"
        )
        
        // Test that each result has a unique ID
        #expect(result1.id != result2.id)
        
        // Test that we can use TracerouteResult in collections that require Identifiable
        let results = [result1, result2]
        let ids = results.map { $0.id }
        #expect(ids.count == 2)
        #expect(Set(ids).count == 2, "All TracerouteResult objects should have unique IDs")
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
    
    @Test func tracerouteMessageFormats() async throws {
        // Test successful hop message format
        let hopNumber = 5
        let ipAddress = "192.168.1.1"
        let hostname = "gateway.local"
        
        let hopMessage = String(format: "Hop %d: %@ (%@)", hopNumber, hostname, ipAddress)
        #expect(hopMessage == "Hop 5: gateway.local (192.168.1.1)")
        
        // Test timeout message format
        let timeoutMessage = String(format: "Hop %d: * * * Request timed out", hopNumber)
        #expect(timeoutMessage == "Hop 5: * * * Request timed out")
        
        // Test destination reached message format
        let destinationMessage = String(format: "Hop %d: %@ [DESTINATION REACHED]", hopNumber, ipAddress)
        #expect(destinationMessage == "Hop 5: 192.168.1.1 [DESTINATION REACHED]")
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
        
        // Test traceroute result with very high hop number
        let highHopResult = TracerouteResult(
            hopNumber: 100,
            success: false,
            responseTime: 0,
            message: "Hop 100: Too many hops"
        )
        #expect(highHopResult.hopNumber == 100)
        #expect(highHopResult.success == false)
        
        // Test traceroute result with negative hop number (edge case)
        let negativeHopResult = TracerouteResult(
            hopNumber: -1,
            success: false,
            responseTime: 0,
            message: "Invalid hop"
        )
        #expect(negativeHopResult.hopNumber == -1)
        #expect(negativeHopResult.success == false)
    }
    
    // MARK: - Data Consistency Tests
    @Test func tracerouteResultConsistency() async throws {
        // Test that failed results have zero response time
        let failedResult = TracerouteResult(
            hopNumber: 1,
            success: false,
            responseTime: 0,
            message: "Failed hop"
        )
        #expect(failedResult.success == false)
        #expect(failedResult.responseTime == 0)
        
        // Test that successful results have positive response time
        let successResult = TracerouteResult(
            hopNumber: 1,
            success: true,
            responseTime: 25.5,
            message: "Successful hop"
        )
        #expect(successResult.success == true)
        #expect(successResult.responseTime > 0)
        
        // Test destination flag consistency
        let destinationResult = TracerouteResult(
            hopNumber: 1,
            success: true,
            responseTime: 30.0,
            message: "Destination reached",
            isDestination: true
        )
        #expect(destinationResult.isDestination == true)
        #expect(destinationResult.success == true)  // Destination should typically be successful
    }
}
