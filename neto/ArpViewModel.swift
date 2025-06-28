//
//  ArpViewModel.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Combine

/// ViewModel for the ARP functionality, coordinating between ArpView and ArpManager
@MainActor
final class ArpViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var arpResult: ArpResult?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var selectedInterface: String = "All"
    
    // MARK: - Private Properties
    
    private let arpManager = ArpManager()
    private var refreshTask: Task<Void, Never>?
    
    // MARK: - Computed Properties
    
    /// Available tabs for the interface selection (All + specific interfaces)
    var availableTabs: [String] {
        guard let arpResult = arpResult else { return ["All"] }
        return ["All"] + arpResult.interfaces
    }
    
    /// ARP entries for the currently selected interface
    var currentEntries: [ArpEntry] {
        guard let arpResult = arpResult else { return [] }
        
        if selectedInterface == "All" {
            return arpResult.allEntries
        } else {
            return arpResult.entriesByInterface[selectedInterface] ?? []
        }
    }
    
    /// Formatted timestamp of the last ARP table refresh
    var lastUpdated: String {
        guard let arpResult = arpResult else { return "Never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: arpResult.timestamp)
    }
    
    /// Total number of ARP entries
    var totalEntries: Int {
        arpResult?.allEntries.count ?? 0
    }
    
    // MARK: - Public Methods
    
    /// Refreshes the ARP table from the system
    func refreshArpTable() {
        // Cancel any existing refresh task
        refreshTask?.cancel()
        
        isLoading = true
        errorMessage = nil
        
        refreshTask = Task {
            do {
                let result = try await arpManager.getArpTable()
                
                // Check if task was cancelled
                if Task.isCancelled {
                    return
                }
                
                self.arpResult = result
                
                // Reset selected interface if it no longer exists
                if selectedInterface != "All" && !result.interfaces.contains(selectedInterface) {
                    selectedInterface = "All"
                }
                
            } catch {
                // Check if task was cancelled
                if Task.isCancelled {
                    return
                }
                
                self.errorMessage = error.localizedDescription
            }
            
            self.isLoading = false
        }
    }
    
    /// Stops any ongoing refresh operation
    func stopRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        isLoading = false
    }
    
    /// Selects a specific interface tab
    /// - Parameter interface: The interface name to select, or "All" for all interfaces
    func selectInterface(_ interface: String) {
        selectedInterface = interface
    }
    
    /// Gets entries for a specific interface
    /// - Parameter interface: The interface name
    /// - Returns: Array of ARP entries for the specified interface
    func entriesForInterface(_ interface: String) -> [ArpEntry] {
        guard let arpResult = arpResult else { return [] }
        
        if interface == "All" {
            return arpResult.allEntries
        } else {
            return arpResult.entriesByInterface[interface] ?? []
        }
    }
    
    /// Gets the number of entries for a specific interface
    /// - Parameter interface: The interface name
    /// - Returns: Number of entries for the specified interface
    func entryCountForInterface(_ interface: String) -> Int {
        entriesForInterface(interface).count
    }
    
    // MARK: - Lifecycle
    
    /// Called when the view appears - automatically refresh ARP table
    func onAppear() {
        if arpResult == nil {
            refreshArpTable()
        }
    }
    
    // MARK: - Deinitializer
    
    deinit {
        refreshTask?.cancel()
    }
} 