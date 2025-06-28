//
//  ArpView.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import SwiftUI

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
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
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
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .foregroundColor(.red)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.availableTabs, id: \.self) { interface in
                    interfaceTabButton(for: interface)
                }
            }
            .padding(.horizontal, 8)
        }
    }
    
    private func interfaceTabButton(for interface: String) -> some View {
        Button(action: {
            viewModel.selectInterface(interface)
        }) {
            HStack(spacing: 4) {
                Text(interface)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(viewModel.selectedInterface == interface ? .semibold : .regular)
                
                if interface != "All" || viewModel.totalEntries > 0 {
                    Text("(\(viewModel.entryCountForInterface(interface)))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(viewModel.selectedInterface == interface ? Color.accentColor : Color.clear)
            )
            .foregroundColor(viewModel.selectedInterface == interface ? .white : .primary)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
                
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Header row
                        arpTableHeader
                        
                        // Data rows
                        ForEach(viewModel.currentEntries) { entry in
                            arpEntryRow(for: entry)
                        }
                    }
                    .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                    .cornerRadius(8)
                }
                .frame(maxHeight: 400)
            }
        }
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
        .background(Color.gray.opacity(0.2))
    }
    
    private func arpEntryRow(for entry: ArpEntry) -> some View {
        HStack {
            Group {
                Text(entry.ipAddress)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(entry.macAddress)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(entry.macAddress == "(incomplete)" ? .orange : .primary)
                
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
                .foregroundColor(Color.gray.opacity(0.3)),
            alignment: .bottom
        )
    }
    
    @ViewBuilder
    private func statusIcon(for entry: ArpEntry) -> some View {
        if entry.isPermanent {
            Image(systemName: "lock.fill")
                .foregroundColor(.blue)
                .font(.system(size: 10))
        } else if entry.status.contains("incomplete") {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 10))
        } else {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 10))
        }
    }
}

#Preview {
    NavigationStack {
        ArpView()
    }
} 