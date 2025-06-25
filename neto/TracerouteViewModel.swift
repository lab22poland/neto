//
//  TracerouteViewModel.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Combine

/// ViewModel for the Traceroute functionality, coordinating between TracerouteView and TracerouteManager
@MainActor
final class TracerouteViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var targetHost: String = ""
    @Published var tracerouteResults: [TracerouteResult] = []
    @Published var isTracing: Bool = false
    @Published var errorMessage: String?
    @Published var maxHops: Int = 30
    @Published var timeout: Double = 5.0
    
    // MARK: - Private Properties
    
    private let tracerouteManager = TracerouteManager()
    private var tracerouteTask: Task<Void, Never>?
    
    // MARK: - Public Methods
    
    /// Starts a traceroute operation to the target host
    func startTraceroute() {
        let host = targetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !host.isEmpty else {
            errorMessage = "Please enter a valid host address"
            return
        }
        
        guard !isTracing else {
            return
        }
        
        // Validate max hops
        guard maxHops > 0 && maxHops <= 50 else {
            errorMessage = "Max hops must be between 1 and 50"
            return
        }
        
        // Validate timeout
        guard timeout > 0 && timeout <= 30 else {
            errorMessage = "Timeout must be between 1 and 30 seconds"
            return
        }
        
        // Reset state
        isTracing = true
        errorMessage = nil
        tracerouteResults.removeAll()
        
        // Start traceroute operation
        tracerouteTask = tracerouteManager.performTraceroute(
            to: host,
            maxHops: maxHops,
            timeout: timeout,
            onResult: { [weak self] result in
                self?.handleTracerouteResult(result)
            },
            onComplete: { [weak self] in
                self?.handleTracerouteComplete()
            }
        )
    }
    
    /// Stops the current traceroute operation
    func stopTraceroute() {
        tracerouteTask?.cancel()
        tracerouteTask = nil
        isTracing = false
        
        // Add a final result to show the traceroute was stopped
        if !tracerouteResults.isEmpty {
            let lastHop = tracerouteResults.count + 1
            let result = TracerouteResult(
                hopNumber: lastHop,
                success: false,
                responseTime: 0,
                message: "Traceroute stopped by user",
                isDestination: false
            )
            tracerouteResults.append(result)
        }
    }
    
    /// Checks if the target host input is valid
    var isTargetHostValid: Bool {
        !targetHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Checks if all parameters are valid for starting traceroute
    var canStartTraceroute: Bool {
        isTargetHostValid && 
        maxHops > 0 && maxHops <= 50 &&
        timeout > 0 && timeout <= 30 &&
        !isTracing
    }
    
    /// Gets the current progress as a percentage (0.0 to 1.0)
    var progress: Double {
        guard maxHops > 0 else { return 0.0 }
        return min(Double(tracerouteResults.count) / Double(maxHops), 1.0)
    }
    
    /// Gets the current hop count
    var currentHop: Int {
        tracerouteResults.count
    }
    
    /// Checks if the destination has been reached
    var destinationReached: Bool {
        tracerouteResults.contains { $0.isDestination }
    }
    
    // MARK: - Private Methods
    
    /// Handles individual traceroute results
    private func handleTracerouteResult(_ result: TracerouteResult) {
        tracerouteResults.append(result)
        
        // If we reached the destination, we can stop early
        if result.isDestination {
            // Don't stop immediately, let the manager complete naturally
        }
    }
    
    /// Handles completion of all traceroute operations
    private func handleTracerouteComplete() {
        isTracing = false
        tracerouteTask = nil
    }
    
    /// Clears all results and resets state
    func clearResults() {
        guard !isTracing else { return }
        
        tracerouteResults.removeAll()
        errorMessage = nil
    }
    
    /// Exports traceroute results as a formatted string
    func exportResults() -> String {
        let host = targetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        
        var output = "NETo Traceroute Results\n"
        output += "Target: \(host)\n"
        output += "Date: \(timestamp)\n"
        output += "Max Hops: \(maxHops)\n"
        output += "Timeout: \(timeout)s\n"
        output += String(repeating: "-", count: 50) + "\n\n"
        
        if tracerouteResults.isEmpty {
            output += "No results available.\n"
        } else {
            for result in tracerouteResults {
                if result.success {
                    output += String(format: "%2d. %@  %.2fms\n", 
                                   result.hopNumber, 
                                   result.message, 
                                   result.responseTime)
                } else {
                    output += String(format: "%2d. %@\n", 
                                   result.hopNumber, 
                                   result.message)
                }
            }
            
            if destinationReached {
                output += "\nTrace complete.\n"
            } else if isTracing {
                output += "\nTrace in progress...\n"
            } else {
                output += "\nTrace incomplete.\n"
            }
        }
        
        return output
    }
    
    // MARK: - Deinitializer
    
    deinit {
        tracerouteTask?.cancel()
    }
} 