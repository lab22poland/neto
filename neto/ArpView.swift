//
//  ArpView.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import SwiftUI
import Foundation
#if !os(macOS)
import UIKit
#endif

struct ArpView: View {
    @StateObject private var viewModel = ArpViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            controlSection
            errorSection
            tabSection
            Spacer()
        }
        .padding()
        .navigationTitle("ARP")
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.stopRefresh()
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ARP Browser")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Browse the system's Address Resolution Protocol (ARP) table")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if viewModel.totalEntries > 0 {
                HStack {
                    Text("Total entries: \(viewModel.totalEntries)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("Last updated: \(viewModel.lastUpdated)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var controlSection: some View {
        HStack {
            Button(action: viewModel.refreshArpTable) {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Refresh ARP Table")
                }
                .frame(minWidth: 160, minHeight: 32)
            }
            .disabled(viewModel.isLoading)
            .buttonStyle(.borderedProminent)
            
            if !viewModel.currentEntries.isEmpty {
                Button(action: copyTableContent) {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        Text("Copy Table")
                    }
                    .frame(minWidth: 120, minHeight: 32)
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                    .foregroundColor(.secondary)
                    .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    @ViewBuilder
    private var tabSection: some View {
        if !viewModel.currentEntries.isEmpty || viewModel.isLoading {
            VStack(spacing: 16) {
                interfaceTabsSection
                arpTableSection
            }
        }
    }
    
    private var interfaceTabsSection: some View {
        // Always use segmented picker - it's the most native approach
        Picker("Interface", selection: Binding(
            get: { viewModel.selectedInterface },
            set: { viewModel.selectInterface($0) }
        )) {
            ForEach(viewModel.availableTabs, id: \.self) { interface in
                Text(interface != "All" || viewModel.totalEntries > 0 ? 
                     "\(interface) (\(viewModel.entryCountForInterface(interface)))" : 
                     interface)
                .tag(interface)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
    

    
    private func copyTableContent() {
        var content = "ARP Entries (\(viewModel.selectedInterface))\n\n"
        
        // Add header
        if viewModel.selectedInterface == "All" {
            content += "IP Address\t\tMAC Address\t\tInterface\t\tStatus\n"
        } else {
            content += "IP Address\t\tMAC Address\t\tStatus\n"
        }
        content += String(repeating: "=", count: 60) + "\n"
        
        // Add entries
        for entry in viewModel.currentEntries {
            if viewModel.selectedInterface == "All" {
                content += "\(entry.ipAddress)\t\t\(entry.macAddress)\t\t\(entry.interface)\t\t\(entry.status)\n"
            } else {
                content += "\(entry.ipAddress)\t\t\(entry.macAddress)\t\t\(entry.status)\n"
            }
        }
        
        // Copy to clipboard using platform-appropriate method
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        #else
        UIPasteboard.general.string = content
        #endif
    }
    
    @ViewBuilder
    private var arpTableSection: some View {
        if viewModel.isLoading {
            ProgressView("Loading ARP table...")
                .frame(maxWidth: .infinity, minHeight: 200)
        } else if viewModel.currentEntries.isEmpty {
            VStack {
                Image(systemName: "network.slash")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No ARP entries found")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("for interface \(viewModel.selectedInterface)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("ARP Entries (\(viewModel.selectedInterface))")
                    .font(.headline)
                
                tableOutputView
            }
        }
    }
    

    
    @ViewBuilder
    private var tableOutputView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Header row
                arpTableHeader
                
                // Data rows
                ForEach(viewModel.currentEntries) { entry in
                    arpEntryRow(for: entry)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxHeight: 400)
    }
    
    private var arpTableHeader: some View {
        HStack {
            Group {
                Text("IP Address")
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("MAC Address")
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if viewModel.selectedInterface == "All" {
                    Text("Interface")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Text("Status")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(.caption, design: .monospaced))
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary)
    }
    
    private func arpEntryRow(for entry: ArpEntry) -> some View {
        HStack {
            Group {
                Text(entry.ipAddress)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(entry.macAddress)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(entry.macAddress == "(incomplete)" ? .secondary : .primary)
                
                if viewModel.selectedInterface == "All" {
                    Text(entry.interface)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    statusIcon(for: entry)
                    Text(entry.status)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.system(.caption, design: .monospaced))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.clear)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(.tertiary),
            alignment: .bottom
        )
    }
    
    @ViewBuilder
    private func statusIcon(for entry: ArpEntry) -> some View {
        if entry.isPermanent {
            Image(systemName: "lock.fill")
                .foregroundColor(.primary)
                .font(.system(size: 10))
        } else if entry.status.contains("incomplete") {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.secondary)
                .font(.system(size: 10))
        } else {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.primary)
                .font(.system(size: 10))
        }
    }
}

#Preview {
    NavigationStack {
        ArpView()
    }
} 