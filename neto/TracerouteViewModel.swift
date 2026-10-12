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
    /// Identifies the current run, so late callbacks of a stopped run cannot touch a newer one
    private var currentRunID: UUID?
    /// The "stopped by user" row is not a hop and does not count for progress
    private var stopRowID: UUID?
    
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
        guard timeout >= 1 && timeout <= 30 else {
            errorMessage = "Timeout must be between 1 and 30 seconds"
            return
        }
        
        // Reset state
        isTracing = true
        errorMessage = nil
        tracerouteResults.removeAll()
        stopRowID = nil
        let runID = UUID()
        currentRunID = runID
        
        // Start traceroute operation
        tracerouteTask = tracerouteManager.performTraceroute(
            to: host,
            maxHops: maxHops,
            timeout: timeout,
            onResult: { [weak self] result in
                guard self?.currentRunID == runID else { return }
                self?.handleTracerouteResult(result)
            },
            onComplete: { [weak self] in
                guard self?.currentRunID == runID else { return }
                self?.handleTracerouteComplete()
            }
        )
    }
    
    /// Stops the current traceroute operation
    func stopTraceroute() {
        tracerouteTask?.cancel()
        tracerouteTask = nil
        currentRunID = nil
        isTracing = false
        
        // Add a final result to show the traceroute was stopped
        if !tracerouteResults.isEmpty {
            let result = TracerouteResult(
                hopNumber: currentHop + 1,
                success: false,
                responseTime: 0,
                message: "Traceroute stopped by user",
                isDestination: false
            )
            stopRowID = result.id
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
        timeout >= 1 && timeout <= 30 &&
        !isTracing
    }
    
    /// Gets the current progress as a percentage (0.0 to 1.0)
    var progress: Double {
        guard maxHops > 0 else { return 0.0 }
        if destinationReached { return 1.0 }
        return min(Double(currentHop) / Double(maxHops), 1.0)
    }
    
    /// Gets the current hop count
    var currentHop: Int {
        tracerouteResults.filter { $0.id != stopRowID }.map(\.hopNumber).max() ?? 0
    }
    
    /// Checks if the destination has been reached
    var destinationReached: Bool {
        tracerouteResults.contains { $0.isDestination }
    }
    
    // MARK: - Private Methods
    
    /// Appends a hop, or replaces it when the same row comes back with the router's name (internal for tests)
    func handleTracerouteResult(_ result: TracerouteResult) {
        if let index = tracerouteResults.firstIndex(where: { $0.id == result.id }) {
            // Same hop again, now with the router's name
            tracerouteResults[index] = result
        } else if result.hostname == nil {
            // A name update for a row that is gone (cleared) is dropped
            tracerouteResults.append(result)
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
        
        currentRunID = nil
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
                if !result.probeTimes.isEmpty {
                    output += String(format: "%2d. %@  %@\n",
                                   result.hopNumber,
                                   result.message,
                                   result.formattedProbeTimes)
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