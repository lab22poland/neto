//
//  PingView.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import SwiftUI

struct PingView: View {
    @StateObject private var viewModel = PingViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            inputSection
            errorSection
            resultsSection
            Spacer()
        }
        .padding()
        .navigationTitle("Ping")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
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
            Text("Ping Tool")
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
#if os(iOS)
                .autocapitalization(.none)
#endif
                .disableAutocorrection(true)
#if os(macOS)
                .frame(maxWidth: 400)
#endif
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
                        Text("Send 5 Ping Packets")
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
            }
        }
    }
    
    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .foregroundColor(.red)
                .font(.caption)
        }
    }
    
    @ViewBuilder
    private var resultsSection: some View {
        if !viewModel.pingResults.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Results")
                        .font(.headline)
                    Spacer()
                }
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.pingResults) { result in
                            resultRow(for: result)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    private func resultRow(for result: PingResult) -> some View {
        HStack {
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(result.success ? .green : .red)
            
            Text(result.message)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(result.success ? .primary : .red)
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
    
}

#Preview {
    NavigationStack {
        PingView()
    }
} 