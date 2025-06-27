//
//  WhoisResult.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation

/// Represents the result of a WHOIS query
struct WhoisResult: Identifiable {
    /// Unique identifier for the WHOIS result
    let id: UUID
    
    /// The domain/IP address that was queried
    let domain: String
    
    /// Whether the WHOIS query was successful
    let success: Bool
    
    /// Raw WHOIS response data
    let rawResponse: String
    
    /// Parsed registrar information
    let registrar: String?
    
    /// Registration date
    let registrationDate: String?
    
    /// Expiration date
    let expirationDate: String?
    
    /// Name servers
    let nameServers: [String]
    
    /// WHOIS server that was queried
    let whoisServer: String?
    
    /// Human-readable status message
    let statusMessage: String
    
    /// Response time in milliseconds
    let responseTime: Double
    
    init(
        id: UUID = UUID(),
        domain: String,
        success: Bool,
        rawResponse: String = "",
        registrar: String? = nil,
        registrationDate: String? = nil,
        expirationDate: String? = nil,
        nameServers: [String] = [],
        whoisServer: String? = nil,
        statusMessage: String,
        responseTime: Double
    ) {
        self.id = id
        self.domain = domain
        self.success = success
        self.rawResponse = rawResponse
        self.registrar = registrar
        self.registrationDate = registrationDate
        self.expirationDate = expirationDate
        self.nameServers = nameServers
        self.whoisServer = whoisServer
        self.statusMessage = statusMessage
        self.responseTime = responseTime
    }
} 