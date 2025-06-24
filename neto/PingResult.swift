//
//  PingResult.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation

/// Represents the result of a single ping operation
struct PingResult: Identifiable {
    /// Unique identifier for the ping result
    let id: UUID
    
    /// Sequence number of the ping in the series
    let sequenceNumber: Int
    
    /// Whether the ping was successful
    let success: Bool
    
    /// Response time in milliseconds
    let responseTime: Double
    
    /// Human-readable message describing the result
    let message: String
} 