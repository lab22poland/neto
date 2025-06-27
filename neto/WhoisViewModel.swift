//
//  WhoisViewModel.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Combine
import Network

/// ViewModel for the WHOIS functionality, coordinating between WhoisView and WhoisManager
/// Supports RFC 3912 compliant WHOIS queries for domains, IP addresses, AS numbers, and person/org records
@MainActor
final class WhoisViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var targetQuery: String = ""
    @Published var whoisResult: WhoisResult?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private let whoisManager = WhoisManager()
    private var whoisTask: Task<Void, Never>?
    
    // MARK: - Public Methods
    
    /// Starts a WHOIS lookup for the target query (domain, IP, AS number, etc.)
    func startWhoisLookup() {
        let query = targetQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !query.isEmpty else {
            errorMessage = "Please enter a valid domain, IP address, AS number, or person/organization name"
            return
        }
        
        guard !isLoading else {
            return
        }
        
        // Reset state
        isLoading = true
        errorMessage = nil
        whoisResult = nil
        
        // Start WHOIS lookup
        whoisTask = whoisManager.performWhois(
            for: query,
            onResult: { [weak self] result in
                self?.handleWhoisResult(result)
            }
        )
    }
    
    /// Stops the current WHOIS lookup
    func stopWhoisLookup() {
        whoisTask?.cancel()
        whoisTask = nil
        isLoading = false
        
        if whoisResult == nil {
            let result = WhoisResult(
                domain: targetQuery.trimmingCharacters(in: .whitespacesAndNewlines),
                success: false,
                statusMessage: "WHOIS lookup cancelled by user",
                responseTime: 0
            )
            whoisResult = result
        }
    }
    
    /// Sets the target query for testing purposes
    func setTargetQuery(_ query: String) {
        targetQuery = query
    }
    
    /// Checks if the target query input is valid
    var isTargetQueryValid: Bool {
        let query = targetQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return !query.isEmpty && isValidWhoisQuery(query)
    }
    
    // MARK: - Private Methods
    
    /// Handles WHOIS lookup results
    private func handleWhoisResult(_ result: WhoisResult) {
        whoisResult = result
        isLoading = false
        whoisTask = nil
        
        if !result.success {
            errorMessage = result.statusMessage
        }
    }
    
    /// Validates if the input is a valid WHOIS query (domain, IP, AS number, person/org)
    private func isValidWhoisQuery(_ input: String) -> Bool {
        let cleanInput = input.lowercased()
        
        // Check for AS number (ASxxxxx or AS xxxxx format)
        if cleanInput.hasPrefix("as") {
            let asNumber = cleanInput.replacingOccurrences(of: "as", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if asNumber.allSatisfy({ $0.isNumber }) {
                return true
            }
        }
        
        // Check for IP addresses
        if isIPAddress(input) {
            return true
        }
        
        // Check for domain names
        if isDomainName(input) {
            return true
        }
        
        // Check for person/organization queries (contains spaces or alphanumeric with limited special chars)
        if input.contains(" ") || (input.count > 2 && input.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })) {
            return true
        }
        
        return false
    }
    
    /// Validates if the input is a valid domain name
    private func isDomainName(_ input: String) -> Bool {
        // More comprehensive domain validation
        let domainRegex = "^[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?\\.[a-zA-Z]{2,}$"
        let domainPredicate = NSPredicate(format: "SELF MATCHES %@", domainRegex)
        return domainPredicate.evaluate(with: input)
    }
    
    /// Validates if the input is a valid IP address (IPv4 or IPv6)
    private func isIPAddress(_ input: String) -> Bool {
        return IPv4Address(input) != nil || IPv6Address(input) != nil
    }
    
    // MARK: - Legacy Support
    
    /// Legacy property for backward compatibility
    var targetDomain: String {
        get { targetQuery }
        set { targetQuery = newValue }
    }
    
    /// Legacy method for backward compatibility
    func setTargetDomain(_ domain: String) {
        setTargetQuery(domain)
    }
    
    /// Legacy property for backward compatibility
    var isTargetDomainValid: Bool {
        return isTargetQueryValid
    }
    
    // MARK: - Deinitializer
    
    deinit {
        whoisTask?.cancel()
    }
} 