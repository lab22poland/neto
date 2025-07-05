//
//  PingViewV2.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import SwiftUI

/// Enhanced Ping View using SimplePing implementation
/// Provides more accurate ping functionality with statistics and configuration options
struct PingViewV2: View {
    @StateObject private var viewModel = PingViewModelV2()
    @State private var showConfiguration = false
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            inputSection
            configurationSection
            errorSection
            resultsSection
            statisticsSection
            Spacer()
        }
        .padding()
        .navigationTitle("Ping")
        .onKeyPress(.escape) {
            if viewModel.isPinging {
                viewModel.stopPing()
                return .handled
            }
            return .ignored
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enhanced Ping Tool")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Send ICMP echo packets to test network connectivity")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Target Host")
                .font(.headline)
            
            TextField("Enter IPv4, IPv6 address or domain name", text: $viewModel.targetHost)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .onSubmit {
                    if viewModel.isTargetHostValid && !viewModel.isPinging {
                        viewModel.startPing()
                    }
                }
            
            HStack(spacing: 12) {
                Button(action: viewModel.startPing) {
                    HStack {
                        if viewModel.isPinging {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 12, height: 12)
                        }
                        Text("Send \(viewModel.pingCount) Ping Packets")
                    }
                    .frame(minWidth: 160, minHeight: 32)
                }
                .disabled(!viewModel.isTargetHostValid || viewModel.isPinging)
                .buttonStyle(.borderedProminent)
                
                if viewModel.isPinging {
                    Button(action: viewModel.stopPing) {
                        Text("Stop")
                            .frame(minWidth: 60, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
                
                Button(action: { showConfiguration.toggle() }) {
                    Image(systemName: "gear")
                        .frame(minWidth: 32, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isPinging)
            }
        }
    }
    
    private var configurationSection: some View {
        Group {
            if showConfiguration {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Configuration")
                        .font(.headline)
                    
                    VStack(spacing: 8) {
                        HStack {
                            Text("Count:")
                            Spacer()
                            Stepper(value: $viewModel.pingCount, in: 1...20) {
                                Text("\(viewModel.pingCount)")
                                    .frame(minWidth: 30)
                            }
                        }
                        
                        HStack {
                            Text("Interval:")
                            Spacer()
                            Stepper(value: $viewModel.pingInterval, in: 0.1...5.0, step: 0.1) {
                                Text(String(format: "%.1fs", viewModel.pingInterval))
                                    .frame(minWidth: 40)
                            }
                        }
                        
                        HStack {
                            Text("Timeout:")
                            Spacer()
                            Stepper(value: $viewModel.pingTimeout, in: 1.0...30.0, step: 0.5) {
                                Text(String(format: "%.1fs", viewModel.pingTimeout))
                                    .frame(minWidth: 40)
                            }
                        }
                        
                        HStack {
                            Text("Payload Size:")
                            Spacer()
                            Stepper(value: $viewModel.payloadSize, in: 32...1024, step: 8) {
                                Text("\(viewModel.payloadSize) bytes")
                                    .frame(minWidth: 80)
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    private var errorSection: some View {
        Group {
            if let errorMessage = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
    
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Results")
                    .font(.headline)
                Spacer()
                if !viewModel.pingResults.isEmpty {
                    Button("Clear") {
                        viewModel.pingResults.removeAll()
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            if viewModel.pingResults.isEmpty {
                Text("No ping results yet")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.pingResults) { result in
                            PingResultRow(result: result)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }
    
    private var statisticsSection: some View {
        Group {
            if !viewModel.pingResults.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Statistics")
                        .font(.headline)
                    
                    let stats = viewModel.pingStatistics
                    VStack(spacing: 4) {
                        HStack {
                            Text("Packets: \(stats.totalPings) sent, \(stats.successCount) received")
                            Spacer()
                            Text("Loss: \(stats.formattedPacketLoss)")
                                .foregroundColor(stats.packetLoss > 0 ? .red : .green)
                        }
                        
                        HStack {
                            Text("Min: \(stats.formattedMinTime)")
                            Spacer()
                            Text("Max: \(stats.formattedMaxTime)")
                        }
                        
                        HStack {
                            Text("Average: \(stats.formattedAvgTime)")
                            Spacer()
                        }
                    }
                    .font(.caption)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
    }
}

// MARK: - Ping Result Row

struct PingResultRow: View {
    let result: PingResult
    
    var body: some View {
        HStack {
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(result.success ? .green : .red)
            
            Text(result.message)
                .font(.system(.body, design: .monospaced))
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationView {
        PingViewV2()
    }
} 