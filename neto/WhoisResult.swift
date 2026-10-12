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
    /// What the last server's answer says about the queried object
    enum Outcome: Equatable {
        /// The last server answered with a record (summary fields come from that answer)
        case found
        /// The last server said it has no such object (an explicit "no match" line)
        case notFound
        /// The last server returned an empty answer: no record, or the server is limiting queries
        case noData
        /// A referral server did not answer or an answer was cut off; the raw response is partial
        case incomplete
        /// The chain ended at IANA, whose record describes the TLD or address block, not the query
        case ianaOnly
    }
    
    /// Unique identifier for the WHOIS result
    let id: UUID
    
    /// The domain/IP address that was queried
    let domain: String
    
    /// Whether the WHOIS query was successful (at least the first server answered)
    let success: Bool
    
    /// Whether the answer describes the queried object; only meaningful when `success` is true
    let outcome: Outcome
    
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
    
    /// Response time in milliseconds; nil when it was not measured (e.g. the lookup was stopped)
    let responseTime: Double?
    
    /// Whether any summary field was recognized in the last server's answer
    var hasSummaryFields: Bool {
        registrar != nil || registrationDate != nil || expirationDate != nil || !nameServers.isEmpty
    }
    
    init(
        id: UUID = UUID(),
        domain: String,
        success: Bool,
        outcome: Outcome = .found,
        rawResponse: String = "",
        registrar: String? = nil,
        registrationDate: String? = nil,
        expirationDate: String? = nil,
        nameServers: [String] = [],
        whoisServer: String? = nil,
        statusMessage: String,
        responseTime: Double?
    ) {
        self.id = id
        self.domain = domain
        self.success = success
        self.outcome = outcome
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