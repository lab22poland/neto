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
    private(set) var currentRunID: UUID?
    /// The run the user stopped: its rows may still receive router names, but it adds no rows
    private var stoppedRunID: UUID?
    /// Parameters of the current or last run, so the export does not pick up later edits of the form
    private(set) var runParameters: (host: String, maxHops: Int, timeout: Double)?
    
    /// The last run was stopped by the user (shown as a status, not as a hop)
    @Published private(set) var stoppedByUser = false
    
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
        stoppedByUser = false
        stoppedRunID = nil
        runParameters = (host, maxHops, timeout)
        let runID = UUID()
        currentRunID = runID
        
        // Start traceroute operation
        tracerouteTask = tracerouteManager.performTraceroute(
            to: host,
            maxHops: maxHops,
            timeout: timeout,
            onResult: { [weak self] result in
                self?.handleResult(result, fromRun: runID)
            },
            onComplete: { [weak self] error in
                guard self?.currentRunID == runID else { return }
                self?.handleTracerouteComplete(error: error)
            }
        )
    }
    
    /// Stops the current traceroute operation; the results so far stay, marked as stopped
    func stopTraceroute() {
        guard isTracing else { return }
        tracerouteTask?.cancel()
        tracerouteTask = nil
        stoppedRunID = currentRunID
        currentRunID = nil
        isTracing = false
        stoppedByUser = true
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
        tracerouteResults.map(\.hopNumber).max() ?? 0
    }
    
    /// Checks if the destination has been reached
    var destinationReached: Bool {
        tracerouteResults.contains { $0.isDestination }
    }
    
    // MARK: - Private Methods
    
    /// Routes a row of a run: rows of the current run are added or updated; a stopped run may only update its
    /// existing rows (late router names); anything from an older run is dropped (internal for tests)
    func handleResult(_ result: TracerouteResult, fromRun runID: UUID) {
        if runID == currentRunID {
            handleTracerouteResult(result)
        } else if runID == stoppedRunID, let index = tracerouteResults.firstIndex(where: { $0.id == result.id }) {
            tracerouteResults[index] = result
        }
    }
    
    /// Appends a hop, or replaces it when the same row comes back with the next probe or the router's name (internal for tests)
    func handleTracerouteResult(_ result: TracerouteResult) {
        if let index = tracerouteResults.firstIndex(where: { $0.id == result.id }) {
            // Same hop again, now with the router's name
            tracerouteResults[index] = result
        } else if result.hostname == nil {
            // A name update for a row that is gone (cleared) is dropped
            tracerouteResults.append(result)
        }
    }
    
    /// Handles the end of the run; an error (resolution, socket or send failure) is shown to the user (internal for tests)
    func handleTracerouteComplete(error: Error?) {
        isTracing = false
        tracerouteTask = nil
        if let error { errorMessage = error.localizedDescription }
    }
    
    /// Clears all results and resets state
    func clearResults() {
        guard !isTracing else { return }
        
        currentRunID = nil
        stoppedRunID = nil
        tracerouteResults.removeAll()
        errorMessage = nil
        stoppedByUser = false
    }
    
    /// Formats the results of the current or last run as text, one traceroute-style line per hop
    func exportResults() -> String {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        let parameters = runParameters ?? (targetHost.trimmingCharacters(in: .whitespacesAndNewlines), maxHops, timeout)
        
        var output = "NETo Traceroute Results\n"
        output += "Target: \(parameters.host)\n"
        output += "Date: \(timestamp)\n"
        output += "Max Hops: \(parameters.maxHops)\n"
        output += "Probe Timeout: \(parameters.timeout)s\n"
        output += String(repeating: "-", count: 50) + "\n\n"
        
        if tracerouteResults.isEmpty {
            output += "No results available.\n"
        } else {
            for result in tracerouteResults {
                output += String(format: "%2d  ", result.hopNumber) + result.line + "\n"
            }
            
            if destinationReached {
                output += "\nTrace complete.\n"
            } else if isTracing {
                output += "\nTrace in progress...\n"
            } else if stoppedByUser {
                output += "\nTrace stopped by user.\n"
            } else {
                output += "\nTrace incomplete.\n"
            }
        }
        if let errorMessage {
            output += "Error: \(errorMessage)\n"
        }
        
        return output
    }
    
    // MARK: - Deinitializer
    
    deinit {
        tracerouteTask?.cancel()
    }
} 