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
@MainActor
final class WhoisViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var targetDomain: String = ""
    @Published var whoisResult: WhoisResult?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private let whoisManager = WhoisManager()
    private var whoisTask: Task<Void, Never>?
    
    // MARK: - Public Methods
    
    /// Starts a WHOIS lookup for the target domain
    func startWhoisLookup() {
        let domain = targetDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !domain.isEmpty else {
            errorMessage = "Please enter a valid domain name or IP address"
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
            for: domain,
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
                domain: targetDomain.trimmingCharacters(in: .whitespacesAndNewlines),
                success: false,
                statusMessage: "WHOIS lookup cancelled by user",
                responseTime: 0
            )
            whoisResult = result
        }
    }
    
    /// Sets the target domain for testing purposes
    func setTargetDomain(_ domain: String) {
        targetDomain = domain
    }
    
    /// Checks if the target domain input is valid
    var isTargetDomainValid: Bool {
        let domain = targetDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        return !domain.isEmpty && (isDomainName(domain) || isIPAddress(domain))
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
    
    /// Validates if the input is a valid domain name
    private func isDomainName(_ input: String) -> Bool {
        let domainRegex = "^[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?\\.[a-zA-Z]{2,}$"
        let domainPredicate = NSPredicate(format: "SELF MATCHES %@", domainRegex)
        return domainPredicate.evaluate(with: input)
    }
    
    /// Validates if the input is a valid IP address
    private func isIPAddress(_ input: String) -> Bool {
        return IPv4Address(input) != nil || IPv6Address(input) != nil
    }
    
    // MARK: - Deinitializer
    
    deinit {
        whoisTask?.cancel()
    }
} 