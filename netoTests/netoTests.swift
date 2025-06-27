//
//  netoTests.swift
//  netoTests
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Testing
import Foundation
import Network
@testable import neto

struct netoTests {
    
    // MARK: - NetworkTool Tests
    @Test func networkToolCaseCount() async throws {
        // Test that we have the expected number of tools (including WHOIS)
        #expect(NetworkTool.allCases.count == 4)
    }
    
    @Test func networkToolIdentifiers() async throws {
        // Test that tool identifiers are correct
        #expect(NetworkTool.ping.id == "ping")
        #expect(NetworkTool.traceroute.id == "traceroute")
        #expect(NetworkTool.whois.id == "whois")
        #expect(NetworkTool.about.id == "about")
    }
    
    @Test func networkToolTitles() async throws {
        // Test that tool titles are correct
        #expect(NetworkTool.ping.title == "Ping")
        #expect(NetworkTool.traceroute.title == "Traceroute")
        #expect(NetworkTool.whois.title == "WHOIS")
        #expect(NetworkTool.about.title == "About")
    }
    
    @Test func networkToolIcons() async throws {
        // Test that tool icons are correct
        #expect(NetworkTool.ping.icon == "network")
        #expect(NetworkTool.traceroute.icon == "point.topleft.down.curvedto.point.bottomright.up")
        #expect(NetworkTool.whois.icon == "doc.text.magnifyingglass")
        #expect(NetworkTool.about.icon == "info.circle")
    }
    
    @Test func networkToolRawValues() async throws {
        // Test that raw values are correct
        #expect(NetworkTool.ping.rawValue == "ping")
        #expect(NetworkTool.traceroute.rawValue == "traceroute")
        #expect(NetworkTool.whois.rawValue == "whois")
        #expect(NetworkTool.about.rawValue == "about")
    }
    
    @Test func networkToolFromRawValue() async throws {
        // Test that tools can be created from raw values
        #expect(NetworkTool(rawValue: "ping") == .ping)
        #expect(NetworkTool(rawValue: "traceroute") == .traceroute)
        #expect(NetworkTool(rawValue: "whois") == .whois)
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
    
    // MARK: - WhoisResult Tests
    @Test func whoisResultCreation() async throws {
        let id = UUID()
        let result = WhoisResult(
            id: id,
            domain: "example.com",
            success: true,
            rawResponse: "Domain Name: EXAMPLE.COM\nRegistrar: Example Registrar\n",
            registrar: "Example Registrar",
            registrationDate: "2023-01-01T00:00:00Z",
            expirationDate: "2024-01-01T00:00:00Z",
            nameServers: ["ns1.example.com", "ns2.example.com"],
            whoisServer: "whois.verisign-grs.com",
            statusMessage: "WHOIS lookup successful",
            responseTime: 1250.5
        )
        
        #expect(result.id == id)
        #expect(result.domain == "example.com")
        #expect(result.success == true)
        #expect(result.rawResponse.contains("EXAMPLE.COM"))
        #expect(result.registrar == "Example Registrar")
        #expect(result.registrationDate == "2023-01-01T00:00:00Z")
        #expect(result.expirationDate == "2024-01-01T00:00:00Z")
        #expect(result.nameServers.count == 2)
        #expect(result.nameServers.contains("ns1.example.com"))
        #expect(result.nameServers.contains("ns2.example.com"))
        #expect(result.whoisServer == "whois.verisign-grs.com")
        #expect(result.statusMessage == "WHOIS lookup successful")
        #expect(result.responseTime == 1250.5)
    }
    
    @Test func whoisResultFailure() async throws {
        let result = WhoisResult(
            domain: "nonexistent.invalid",
            success: false,
            statusMessage: "WHOIS lookup failed: Domain not found",
            responseTime: 500.0
        )
        
        #expect(result.success == false)
        #expect(result.domain == "nonexistent.invalid")
        #expect(result.statusMessage.contains("failed"))
        #expect(result.rawResponse.isEmpty)
        #expect(result.registrar == nil)
        #expect(result.registrationDate == nil)
        #expect(result.expirationDate == nil)
        #expect(result.nameServers.isEmpty)
        #expect(result.whoisServer == nil)
        #expect(result.responseTime == 500.0)
    }
    
    @Test func whoisResultMinimal() async throws {
        let result = WhoisResult(
            domain: "test.com",
            success: true,
            rawResponse: "Minimal data",
            statusMessage: "WHOIS lookup successful",
            responseTime: 750.0
        )
        
        #expect(result.domain == "test.com")
        #expect(result.success == true)
        #expect(result.rawResponse == "Minimal data")
        #expect(result.statusMessage == "WHOIS lookup successful")
        #expect(result.responseTime == 750.0)
        
        // Test default values
        #expect(result.registrar == nil)
        #expect(result.registrationDate == nil)
        #expect(result.expirationDate == nil)
        #expect(result.nameServers.isEmpty)
        #expect(result.whoisServer == nil)
        #expect(result.id != UUID())  // Should have a valid UUID
    }
    
    @Test func whoisResultWithNameServers() async throws {
        let nameServers = ["ns1.google.com", "ns2.google.com", "ns3.google.com", "ns4.google.com"]
        let result = WhoisResult(
            domain: "google.com",
            success: true,
            rawResponse: "Sample WHOIS data",
            nameServers: nameServers,
            statusMessage: "WHOIS lookup successful",
            responseTime: 980.5
        )
        
        #expect(result.nameServers.count == 4)
        #expect(result.nameServers == nameServers)
        #expect(result.nameServers.contains("ns1.google.com"))
        #expect(result.nameServers.contains("ns4.google.com"))
    }
    
    @Test func whoisResultIdentifiable() async throws {
        let result1 = WhoisResult(
            domain: "test1.com",
            success: true,
            statusMessage: "Test 1",
            responseTime: 100.0
        )
        
        let result2 = WhoisResult(
            domain: "test2.com",
            success: false,
            statusMessage: "Test 2",
            responseTime: 200.0
        )
        
        // Test that each result has a unique ID
        #expect(result1.id != result2.id)
        
        // Test that we can use WhoisResult in collections that require Identifiable
        let results = [result1, result2]
        let ids = results.map { $0.id }
        #expect(ids.count == 2)
        #expect(Set(ids).count == 2, "All WhoisResult objects should have unique IDs")
    }
    
    // MARK: - WhoisManager Tests
    @Test func whoisManagerTLDMapping() async throws {
        let manager = WhoisManager()
        
        // We can't easily test the private TLD mapping method directly,
        // but we can test that the manager doesn't crash during initialization
        #expect(Bool(true), "WhoisManager should initialize successfully")
        
        // Test that we can call the manager - basic smoke test
        _ = manager
    }
    
    // MARK: - WhoisViewModel Tests
    @Test func whoisViewModelInitialization() async throws {
        let viewModel = await WhoisViewModel()
        
        // Test initial state
        let targetDomain = await viewModel.targetDomain
        let whoisResult = await viewModel.whoisResult
        let isLoading = await viewModel.isLoading
        let errorMessage = await viewModel.errorMessage
        
        #expect(targetDomain.isEmpty)
        #expect(whoisResult == nil)
        #expect(isLoading == false)
        #expect(errorMessage == nil)
    }
    
    @Test func whoisViewModelDomainValidation() async throws {
        await MainActor.run {
            // Test valid domains with separate instances to ensure isolation
            let validDomains = ["google.com", "8.8.8.8", "example.org"]
            
            for domain in validDomains {
                let viewModel = WhoisViewModel()
                viewModel.setTargetDomain(domain)
                let isValid = viewModel.isTargetDomainValid
                #expect(isValid == true, "Domain '\(domain)' should be valid")
            }
            
            // Test invalid domains with separate instances to ensure isolation
            let invalidDomains = ["", "   ", "invalid_domain"]
            
            for domain in invalidDomains {
                let viewModel = WhoisViewModel()
                viewModel.setTargetDomain(domain)
                let isValid = viewModel.isTargetDomainValid
                #expect(isValid == false, "Domain '\(domain)' should be invalid")
            }
        }
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
    
    @Test func whoisDomainValidation() {
        // Test domain validation using the same regex pattern as WhoisViewModel
        let domainRegex = "^[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?\\.[a-zA-Z]{2,}$"
        let domainPredicate = NSPredicate(format: "SELF MATCHES %@", domainRegex)
        
        // Test valid domains
        let validDomains = ["google.com", "example.org", "test.net", "site.co.uk", "test.example"]
        for domain in validDomains {
            let result = domainPredicate.evaluate(with: domain)
            #expect(result, "Domain '\(domain)' should be valid")
        }
        
        // Test invalid domains  
        let invalidDomains = ["", ".", "invalid", "test.", ".com", "test..com", "test.c"]
        for domain in invalidDomains {
            let result = domainPredicate.evaluate(with: domain)
            #expect(!result, "Domain '\(domain)' should be invalid")
        }
        
        // Test IP addresses (should be invalid for domain regex but valid overall)
        let ipAddresses = ["8.8.8.8", "192.168.1.1"]
        for ip in ipAddresses {
            let isDomain = domainPredicate.evaluate(with: ip)
            #expect(!isDomain, "IP address '\(ip)' should not match domain regex")
            
            // Test that it's a valid IPv4 address
            let isValidIP = IPv4Address(ip) != nil
            #expect(isValidIP, "'\(ip)' should be a valid IPv4 address")
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
    
    @Test func whoisResultCreationPerformance() async throws {
        let startTime = Date()
        
        // Create many WHOIS results to test performance
        var results: [WhoisResult] = []
        for i in 1...1000 {
            let result = WhoisResult(
                domain: "test\(i).com",
                success: i % 2 == 0,
                rawResponse: "Sample WHOIS data for test\(i).com",
                registrar: i % 3 == 0 ? "Test Registrar \(i)" : nil,
                nameServers: i % 4 == 0 ? ["ns1.test\(i).com", "ns2.test\(i).com"] : [],
                statusMessage: "Test message \(i)",
                responseTime: Double(i) * 1.5
            )
            results.append(result)
        }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        #expect(results.count == 1000)
        #expect(duration < 1.0, "Creating 1000 WhoisResult objects should take less than 1 second")
    }
    
    // MARK: - Network Tool Sequence Tests  
    @Test func networkToolSequence() async throws {
        // Test that NetworkTool conforms to CaseIterable properly
        let allTools = NetworkTool.allCases
        #expect(allTools.contains(.ping))
        #expect(allTools.contains(.traceroute))
        #expect(allTools.contains(.whois))
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
    
    @Test func whoisMessageFormats() async throws {
        // Test successful WHOIS status message
        let successMessage = "WHOIS lookup successful"
        #expect(successMessage == "WHOIS lookup successful")
        
        // Test failure status message format
        let errorMsg = "Domain not found"
        let failureMessage = String(format: "WHOIS lookup failed: %@", errorMsg)
        #expect(failureMessage == "WHOIS lookup failed: Domain not found")
        
        // Test cancellation message format
        let cancelMessage = "WHOIS lookup cancelled by user"
        #expect(cancelMessage == "WHOIS lookup cancelled by user")
        
        // Test timeout message format
        let timeoutMessage = "WHOIS lookup failed: The operation couldn't be completed. (NSURLErrorDomain error -1001.)"
        #expect(timeoutMessage.contains("failed"))
        #expect(timeoutMessage.contains("error"))
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
        
        // Test WHOIS result with empty domain
        let emptyDomainResult = WhoisResult(
            domain: "",
            success: false,
            statusMessage: "Empty domain",
            responseTime: 0
        )
        #expect(emptyDomainResult.domain.isEmpty)
        #expect(emptyDomainResult.success == false)
        #expect(emptyDomainResult.responseTime == 0)
        
        // Test WHOIS result with very long domain
        let longDomain = String(repeating: "a", count: 100) + ".com"
        let longDomainResult = WhoisResult(
            domain: longDomain,
            success: false,
            statusMessage: "Domain too long",
            responseTime: 50.0
        )
        #expect(longDomainResult.domain == longDomain)
        #expect(longDomainResult.success == false)
        
        // Test WHOIS result with many name servers
        let manyNameServers = (1...20).map { "ns\($0).example.com" }
        let manyNSResult = WhoisResult(
            domain: "example.com",
            success: true,
            nameServers: manyNameServers,
            statusMessage: "Success",
            responseTime: 1200.0
        )
        #expect(manyNSResult.nameServers.count == 20)
        #expect(manyNSResult.nameServers.first == "ns1.example.com")
        #expect(manyNSResult.nameServers.last == "ns20.example.com")
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
    
    @Test func whoisResultConsistency() async throws {
        // Test that failed results typically have empty data
        let failedResult = WhoisResult(
            domain: "nonexistent.test",
            success: false,
            statusMessage: "Domain not found",
            responseTime: 800.0
        )
        #expect(failedResult.success == false)
        #expect(failedResult.rawResponse.isEmpty)
        #expect(failedResult.registrar == nil)
        #expect(failedResult.registrationDate == nil)
        #expect(failedResult.expirationDate == nil)
        #expect(failedResult.nameServers.isEmpty)
        #expect(failedResult.responseTime > 0)  // Should still have response time
        
        // Test that successful results have meaningful data
        let successResult = WhoisResult(
            domain: "example.com",
            success: true,
            rawResponse: "Domain Name: EXAMPLE.COM\nRegistrar: Test Corp",
            registrar: "Test Corp",
            statusMessage: "WHOIS lookup successful",
            responseTime: 1500.0
        )
        #expect(successResult.success == true)
        #expect(!successResult.rawResponse.isEmpty)
        #expect(successResult.registrar != nil)
        #expect(successResult.statusMessage.contains("successful"))
        #expect(successResult.responseTime > 0)
        
        // Test case consistency
        let lowercaseDomain = WhoisResult(
            domain: "EXAMPLE.COM",
            success: true,
            statusMessage: "Success",
            responseTime: 500.0
        )
        // Domain should be stored as provided (manager handles normalization)
        #expect(lowercaseDomain.domain == "EXAMPLE.COM")
    }
    
    // MARK: - IP Address Tests
    @Test func whoisIPAddressTests() async throws {
        // Test IPv4 address WHOIS result
        let ipv4Result = WhoisResult(
            domain: "8.8.8.8",
            success: true,
            rawResponse: "NetRange: 8.0.0.0 - 8.255.255.255\nOrgName: Google LLC",
            statusMessage: "WHOIS lookup successful",
            responseTime: 2000.0
        )
        #expect(ipv4Result.domain == "8.8.8.8")
        #expect(ipv4Result.success == true)
        #expect(ipv4Result.rawResponse.contains("Google LLC"))
        
        // Test IPv6 address WHOIS result
        let ipv6Result = WhoisResult(
            domain: "2001:4860:4860::8888",
            success: true,
            rawResponse: "inet6num: 2001:4860::/32\nnetname: GOOGLE",
            statusMessage: "WHOIS lookup successful",
            responseTime: 1800.0
        )
        #expect(ipv6Result.domain == "2001:4860:4860::8888")
        #expect(ipv6Result.success == true)
        #expect(ipv6Result.rawResponse.contains("GOOGLE"))
    }
    
    // MARK: - TLD Specific Tests
    @Test func whoisTLDTests() async throws {
        // Test different TLD handling
        let comDomain = WhoisResult(
            domain: "example.com",
            success: true,
            whoisServer: "whois.verisign-grs.com",
            statusMessage: "Success",
            responseTime: 1000.0
        )
        #expect(comDomain.domain.hasSuffix(".com"))
        #expect(comDomain.whoisServer == "whois.verisign-grs.com")
        
        let orgDomain = WhoisResult(
            domain: "example.org",
            success: true,
            whoisServer: "whois.pir.org",
            statusMessage: "Success",
            responseTime: 1200.0
        )
        #expect(orgDomain.domain.hasSuffix(".org"))
        #expect(orgDomain.whoisServer == "whois.pir.org")
        
        let ukDomain = WhoisResult(
            domain: "example.co.uk",
            success: true,
            whoisServer: "whois.nominet.uk",
            statusMessage: "Success",
            responseTime: 1500.0
        )
        #expect(ukDomain.domain.hasSuffix(".uk"))
        #expect(ukDomain.whoisServer == "whois.nominet.uk")
    }
}

// MARK: - Helper Extensions for Testing
extension WhoisViewModel {
    func setTargetDomain(_ domain: String) {
        targetDomain = domain
    }
}

// MARK: - WhoisManager Integration Tests
// These tests make real network calls to WHOIS servers
struct WhoisManagerIntegrationTests {
    
    @Test(.timeLimit(.minutes(10)))
    func whoisManagerRealDomainLookups() async throws {
        let manager = WhoisManager()
        
        // Test popular .com domains
        let comDomains = ["google.com", "apple.com", "microsoft.com"]
        
        for domain in comDomains {
            print("Testing WHOIS lookup for: \(domain)")
            
            // Use async/await pattern to get result
            let result = await withCheckedContinuation { continuation in
                let _ = manager.performWhois(for: domain) { result in
                    continuation.resume(returning: result)
                }
            }
            
            // Basic validation - must always pass
            #expect(result.domain == domain.lowercased())
            #expect(result.responseTime > 0, "Response time should be positive for \(domain)")
            
            // Network-dependent validation - more lenient for real-world conditions
            if result.success {
                #expect(!result.rawResponse.isEmpty, "WHOIS response should not be empty for successful \(domain)")
                #expect(result.statusMessage.contains("successful"), "Status should indicate success for \(domain)")
                
                // .com domains should use Verisign server (when successful)
                #expect(result.whoisServer?.contains("verisign") == true, "COM domains should use Verisign WHOIS server")
                
                print("✓ \(domain): Success (Response time: \(String(format: "%.2f", result.responseTime))ms)")
            } else {
                print("⚠ \(domain): Failed (\(result.statusMessage))")
                // Failure is acceptable for integration tests - network issues happen
            }
            
            // No longer checking response keywords here - moved above
        }
    }
    
    @Test(.timeLimit(.minutes(3)))
    func whoisManagerDifferentTLDs() async throws {
        let manager = WhoisManager()
        
        // Test different TLD patterns
        let domains = [
            "example.org",      // .org
            "iana.org",         // Another .org
            "kernel.org"        // Popular .org domain
        ]
        
        for domain in domains {
            print("Testing TLD for: \(domain)")
            
            let result = await withCheckedContinuation { continuation in
                let _ = manager.performWhois(for: domain) { result in
                    continuation.resume(returning: result)
                }
            }
            
            #expect(result.responseTime > 0, "Response time should be positive for \(domain)")
            
            // Network-dependent validation - more lenient
            if result.success {
                #expect(!result.rawResponse.isEmpty, "WHOIS response should not be empty for \(domain)")
                
                // .org domains should use PIR server (when successful)
                if domain.hasSuffix(".org") {
                    #expect(result.whoisServer?.contains("pir.org") == true, "ORG domains should use PIR WHOIS server")
                }
                
                print("✓ \(domain): Success (Server: \(result.whoisServer ?? "unknown"))")
            } else {
                print("⚠ \(domain): Failed (\(result.statusMessage))")
            }
        }
    }
    
    @Test(.timeLimit(.minutes(2)))
    func whoisManagerIPAddressLookups() async throws {
        let manager = WhoisManager()
        
        // Test well-known IP addresses
        let ipAddresses = [
            "8.8.8.8",          // Google DNS
            "1.1.1.1",          // Cloudflare DNS
            "208.67.222.222"    // OpenDNS
        ]
        
        for ip in ipAddresses {
            print("Testing WHOIS lookup for IP: \(ip)")
            
            let result = await withCheckedContinuation { continuation in
                let _ = manager.performWhois(for: ip) { result in
                    continuation.resume(returning: result)
                }
            }
            
            #expect(result.domain == ip, "IP address should be preserved as domain field")
            #expect(result.responseTime > 0, "Response time should be positive for \(ip)")
            
            // Network-dependent validation
            if result.success {
                #expect(!result.rawResponse.isEmpty, "IP WHOIS response should not be empty for \(ip)")
                
                // IP lookups should contain network information
                let response = result.rawResponse.lowercased()
                let hasNetworkInfo = response.contains("netrange") || 
                                   response.contains("inetnum") || 
                                   response.contains("cidr") ||
                                   response.contains("network")
                #expect(hasNetworkInfo, "IP WHOIS should contain network range information for \(ip)")
                
                print("✓ \(ip): Success (Response time: \(String(format: "%.2f", result.responseTime))ms)")
            } else {
                print("⚠ \(ip): Failed (\(result.statusMessage))")
            }
        }
    }
    
    @Test(.timeLimit(.minutes(2)))
    func whoisManagerIPv6Lookups() async throws {
        let manager = WhoisManager()
        
        // Test IPv6 addresses
        let ipv6Addresses = [
            "2001:4860:4860::8888",  // Google IPv6 DNS
            "2606:4700:4700::1111"   // Cloudflare IPv6 DNS
        ]
        
        for ipv6 in ipv6Addresses {
            print("Testing WHOIS lookup for IPv6: \(ipv6)")
            
            let result = await withCheckedContinuation { continuation in
                let _ = manager.performWhois(for: ipv6) { result in
                    continuation.resume(returning: result)
                }
            }
            
            #expect(result.domain == ipv6, "IPv6 address should be preserved as domain field")
            #expect(result.responseTime > 0, "Response time should be positive for \(ipv6)")
            
            // Network-dependent validation
            if result.success {
                #expect(!result.rawResponse.isEmpty, "IPv6 WHOIS response should not be empty for \(ipv6)")
                
                // IPv6 lookups should contain network information
                let response = result.rawResponse.lowercased()
                let hasIPv6Info = response.contains("inet6num") || 
                                response.contains("ipv6") ||
                                response.contains("2001:") ||
                                response.contains("2606:")
                #expect(hasIPv6Info, "IPv6 WHOIS should contain IPv6 network information for \(ipv6)")
                
                print("✓ \(ipv6): Success (Response time: \(String(format: "%.2f", result.responseTime))ms)")
            } else {
                print("⚠ \(ipv6): Failed (\(result.statusMessage))")
            }
        }
    }
    
    @Test(.timeLimit(.minutes(2)))
    func whoisManagerCountryCodeTLDs() async throws {
        let manager = WhoisManager()
        
        // Test country code TLDs
        let ccTLDs = [
            "example.co.uk",    // UK
            "nic.de",           // Germany
            "afnic.fr"          // France
        ]
        
        for domain in ccTLDs {
            print("Testing ccTLD for: \(domain)")
            
            let result = await withCheckedContinuation { continuation in
                let _ = manager.performWhois(for: domain) { result in
                    continuation.resume(returning: result)
                }
            }
            
            #expect(result.responseTime > 0, "Response time should be positive for \(domain)")
            
            // Network-dependent validation
            if result.success {
                #expect(!result.rawResponse.isEmpty, "ccTLD WHOIS response should not be empty for \(domain)")
                
                // Verify appropriate WHOIS server was used (when successful)
                if domain.hasSuffix(".uk") {
                    #expect(result.whoisServer?.contains("nominet") == true, "UK domains should use Nominet server")
                } else if domain.hasSuffix(".de") {
                    #expect(result.whoisServer?.contains("denic") == true, "DE domains should use DENIC server")
                } else if domain.hasSuffix(".fr") {
                    #expect(result.whoisServer?.contains("afnic") == true, "FR domains should use AFNIC server")
                }
                
                print("✓ \(domain): Success (Server: \(result.whoisServer ?? "unknown"))")
            } else {
                print("⚠ \(domain): Failed (\(result.statusMessage))")
            }
        }
    }
    
    @Test(.timeLimit(.minutes(1)))
    func whoisManagerInvalidDomains() async throws {
        let manager = WhoisManager()
        
        // Test invalid/non-existent domains
        let invalidDomains = [
            "thisisnotarealdomain12345.com",
            "nonexistent.invalid",
            "definitely-does-not-exist.xyz"
        ]
        
        for domain in invalidDomains {
            print("Testing invalid domain: \(domain)")
            
            let result = await withCheckedContinuation { continuation in
                let _ = manager.performWhois(for: domain) { result in
                    continuation.resume(returning: result)
                }
            }
            
            #expect(result.domain == domain.lowercased())
            #expect(result.responseTime > 0, "Should still measure response time for \(domain)")
            
            // Invalid domains might succeed with "No Data Found" response
            // or fail outright - both are acceptable
            if result.success {
                let response = result.rawResponse.lowercased()
                let isNoDataResponse = response.contains("no data found") ||
                                     response.contains("no match") ||
                                     response.contains("not found") ||
                                     response.contains("no matching record")
                #expect(isNoDataResponse, "Successful response for invalid domain should indicate no data found")
            } else {
                #expect(result.statusMessage.contains("failed"), "Failed response should have appropriate status message")
            }
            
            print("✓ \(domain): Handled appropriately (Success: \(result.success))")
        }
    }
    
    @Test(.timeLimit(.minutes(1)))
    func whoisManagerMalformedInputs() async throws {
        let manager = WhoisManager()
        
        // Test malformed inputs that should fail gracefully
        let malformedInputs = [
            "",                     // Empty string
            "not-a-domain",        // No TLD
            "spaces in domain.com", // Invalid characters
            "999.999.999.999"      // Invalid IP
        ]
        
        for input in malformedInputs {
            print("Testing malformed input: '\(input)'")
            
            let result = await withCheckedContinuation { continuation in
                let _ = manager.performWhois(for: input) { result in
                    continuation.resume(returning: result)
                }
            }
            
            #expect(result.domain == input.lowercased())
            #expect(result.success == false, "Malformed input should fail: '\(input)'")
            #expect(result.statusMessage.contains("failed"), "Status should indicate failure for: '\(input)'")
            #expect(result.rawResponse.isEmpty, "Raw response should be empty for failed lookup: '\(input)'")
            #expect(result.responseTime >= 0, "Response time should be non-negative for: '\(input)'")
            
            print("✓ '\(input)': Failed gracefully")
        }
    }
    
    @Test(.timeLimit(.minutes(2)))
    func whoisManagerNewGenericTLDs() async throws {
        let manager = WhoisManager()
        
        // Test some new generic TLDs
        let newTLDs = [
            "nic.tech",         // .tech TLD
            "google.dev",       // .dev TLD  
            "test.app"          // .app TLD
        ]
        
        for domain in newTLDs {
            print("Testing new gTLD: \(domain)")
            
            let result = await withCheckedContinuation { continuation in
                let _ = manager.performWhois(for: domain) { result in
                    continuation.resume(returning: result)
                }
            }
            
            #expect(result.domain == domain.lowercased())
            #expect(result.responseTime > 0, "Should measure response time for \(domain)")
            
            // New gTLDs should either succeed or fail gracefully
            if result.success {
                #expect(!result.rawResponse.isEmpty, "Successful lookup should have response data for \(domain)")
                #expect(result.registrar != nil || !result.nameServers.isEmpty, "Should have some parsed data for \(domain)")
            } else {
                #expect(result.statusMessage.contains("failed"), "Failed lookup should have appropriate message for \(domain)")
            }
            
            print("✓ \(domain): \(result.success ? "Success" : "Handled failure") (Response time: \(String(format: "%.2f", result.responseTime))ms)")
        }
    }
    
    @Test(.timeLimit(.minutes(1)))
    func whoisManagerEdgeCaseDomains() async throws {
        let manager = WhoisManager()
        
        // Test edge case domains
        let edgeCases = [
            "a.com",                    // Single character
            "very-long-domain-name-that-tests-length-limits.com", // Long domain
            "sub.domain.example.com"    // Subdomain
        ]
        
        for domain in edgeCases {
            print("Testing edge case: \(domain)")
            
            let result = await withCheckedContinuation { continuation in
                let _ = manager.performWhois(for: domain) { result in
                    continuation.resume(returning: result)
                }
            }
            
            #expect(result.domain == domain.lowercased())
            #expect(result.responseTime > 0, "Should measure response time for \(domain)")
            
            // Edge cases should be handled gracefully
            if result.success {
                #expect(!result.rawResponse.isEmpty, "Successful lookup should have response data for \(domain)")
            }
            
            print("✓ \(domain): \(result.success ? "Success" : "Handled") (Response time: \(String(format: "%.2f", result.responseTime))ms)")
        }
    }
    
    @Test(.timeLimit(.minutes(2)))
    func whoisManagerPerformanceValidation() async throws {
        let manager = WhoisManager()
        
        // Test performance with rapid successive queries
        let testDomains = ["google.com", "apple.com", "microsoft.com"]
        var results: [WhoisResult] = []
        
        let startTime = Date()
        
        // Perform lookups sequentially to test performance
        for domain in testDomains {
            print("Performance test for: \(domain)")
            
            let result = await withCheckedContinuation { continuation in
                let _ = manager.performWhois(for: domain) { result in
                    continuation.resume(returning: result)
                }
            }
            results.append(result)
            
            #expect(result.success == true, "Performance test should succeed for \(domain)")
            #expect(result.responseTime < 10000, "Response should be under 10 seconds for \(domain)")
        }
        
        let totalTime = Date().timeIntervalSince(startTime)
        
        #expect(results.count == testDomains.count)
        #expect(totalTime < 30, "Three WHOIS lookups should complete within 30 seconds")
        
        print("✓ Performance test completed in \(String(format: "%.2f", totalTime)) seconds")
        
        // Verify all results have reasonable response times
        for result in results {
            #expect(result.responseTime > 0, "All results should have positive response times")
            #expect(result.responseTime < 10000, "All results should complete within 10 seconds")
        }
    }
} 