//
//  TracerouteView.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import SwiftUI
#if !os(macOS)
import UIKit
#endif

struct TracerouteView: View {
    @StateObject private var viewModel = TracerouteViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            configurationSection
            inputSection
            errorSection
            progressSection
            resultsSection
            Spacer()
        }
        .padding()
        .navigationTitle("Traceroute")
        .onKeyPress(.escape) {
            if viewModel.isTracing {
                viewModel.stopTraceroute()
                return .handled
            }
            return .ignored
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Traceroute Tool")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Discover the network path to a destination by probing intermediate hops")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration")
                .font(.headline)
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Max Hops")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Stepper(value: $viewModel.maxHops, in: 1...50) {
                            Text("\(viewModel.maxHops)")
                                .frame(minWidth: 30)
                        }
                        .disabled(viewModel.isTracing)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Timeout (seconds)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Stepper(value: $viewModel.timeout, in: 1...30, step: 0.5) {
                            Text(String(format: "%.1f", viewModel.timeout))
                                .frame(minWidth: 30)
                        }
                        .disabled(viewModel.isTracing)
                    }
                }
                
                Spacer()
            }
        }
        .padding()
        .background(.quaternary)
        .cornerRadius(8)
    }
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Target Host")
                .font(.headline)
            
            TextField("Enter IPv4, IPv6 address or domain name", text: $viewModel.targetHost)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .onSubmit {
                    if viewModel.canStartTraceroute {
                        viewModel.startTraceroute()
                    }
                }
            
            HStack(spacing: 12) {
                Button(action: viewModel.startTraceroute) {
                    HStack {
                        if viewModel.isTracing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 12, height: 12)
                        }
                        Text("Start Traceroute")
                    }
                    .frame(minWidth: 140, minHeight: 32)
                }
                .disabled(!viewModel.canStartTraceroute)
                .buttonStyle(.borderedProminent)
                
                if viewModel.isTracing {
                    Button(action: viewModel.stopTraceroute) {
                        Text("Stop")
                            .frame(minWidth: 60, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.secondary)
                }
                
                if !viewModel.tracerouteResults.isEmpty && !viewModel.isTracing {
                    Button(action: viewModel.clearResults) {
                        Text("Clear")
                            .frame(minWidth: 60, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: shareResults) {
                        Text("Export")
                            .frame(minWidth: 60, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
    
    private var errorSection: some View {
        Group {
            if let errorMessage = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.secondary)
                    Text(errorMessage)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
                .background(.quaternary)
                .cornerRadius(8)
            }
        }
    }
    
    private var progressSection: some View {
        Group {
            if viewModel.isTracing || !viewModel.tracerouteResults.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Progress")
                            .font(.headline)
                        Spacer()
                        Text("\(viewModel.currentHop)/\(viewModel.maxHops) hops")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    ProgressView(value: viewModel.progress)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    if viewModel.destinationReached {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.primary)
                            Text("Destination reached")
                                .foregroundColor(.primary)
                                .font(.caption)
                        }
                    } else if viewModel.isTracing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 10, height: 10)
                            Text("Tracing route...")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }
    
    private var resultsSection: some View {
        Group {
            if !viewModel.tracerouteResults.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Route Results")
                        .font(.headline)
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(viewModel.tracerouteResults) { result in
                                TracerouteResultRow(result: result)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 300)
                    .background(.quaternary)
                    .cornerRadius(8)
                }
            }
        }
    }
    
    private func shareResults() {
        let results = viewModel.exportResults()
        
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(results, forType: .string)
        #else
        UIPasteboard.general.string = results
        #endif
    }
}

struct TracerouteResultRow: View {
    let result: TracerouteResult
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Hop number
            Text("\(result.hopNumber)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .trailing)
            
            VStack(alignment: .leading, spacing: 2) {
                // Main message
                Text(result.message)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(result.success ? .primary : .secondary)
                
                // Response time (if successful)
                if result.success && result.responseTime > 0 {
                    Text(String(format: "%.2f ms", result.responseTime))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
            
            Spacer()
            
            // Status indicator
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
    
    private var statusIcon: String {
        if result.isDestination {
            return "flag.checkered"
        } else if result.success {
            return "circle.fill"
        } else {
            return "circle"
        }
    }
    
    private var statusColor: Color {
        if result.isDestination {
            return .primary
        } else if result.success {
            return .primary
        } else {
            return .secondary
        }
    }
}

#Preview {
    TracerouteView()
} 