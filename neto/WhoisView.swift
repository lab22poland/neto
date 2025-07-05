//
//  WhoisView.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import SwiftUI

struct WhoisView: View {
    @StateObject private var viewModel = WhoisViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            inputSection
            errorSection
            resultSection
            Spacer()
        }
        .padding()
        .navigationTitle("WHOIS")
        .onKeyPress(.escape) {
            if viewModel.isLoading {
                viewModel.stopWhoisLookup()
                return .handled
            }
            return .ignored
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHOIS Lookup")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("RFC 3912 compliant WHOIS queries for domains, IP addresses, AS numbers, and person/organization records")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Query Target")
                .font(.headline)
            
            TextField("Enter domain, IP address, AS number, or person/organization", text: $viewModel.targetQuery)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .onSubmit {
                    if viewModel.isTargetQueryValid && !viewModel.isLoading {
                        viewModel.startWhoisLookup()
                    }
                }
            
            // Examples section
            VStack(alignment: .leading, spacing: 4) {
                Text("Examples:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Button("google.com") { viewModel.targetQuery = "google.com" }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                        
                        Button("8.8.8.8") { viewModel.targetQuery = "8.8.8.8" }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Button("AS15169") { viewModel.targetQuery = "AS15169" }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                        
                        Button("2001:4860:4860::8888") { viewModel.targetQuery = "2001:4860:4860::8888" }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.top, 4)
            
            HStack(spacing: 12) {
                Button(action: viewModel.startWhoisLookup) {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 12, height: 12)
                        }
                        Text("Perform WHOIS Lookup")
                    }
                    .frame(minWidth: 160, minHeight: 32)
                }
                .disabled(!viewModel.isTargetQueryValid || viewModel.isLoading)
                .buttonStyle(.borderedProminent)
                
                if viewModel.isLoading {
                    Button(action: viewModel.stopWhoisLookup) {
                        Text("Stop")
                            .frame(minWidth: 60, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
                
                if let result = viewModel.whoisResult {
                    Text(String(format: "Response Time: %.2f ms", result.responseTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
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
    private var resultSection: some View {
        if let result = viewModel.whoisResult {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("WHOIS Result")
                        .font(.headline)
                    
                    Spacer()
                    
                    if let server = result.whoisServer {
                        Text("Server: \(server)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.success ? .green : .red)
                }
                
                // Quick info section for successful results
                if result.success {
                    VStack(alignment: .leading, spacing: 4) {
                        if let registrar = result.registrar {
                            HStack {
                                Text("Registrar/Organization:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(registrar)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                        
                        if let created = result.registrationDate {
                            HStack {
                                Text("Created/Registered:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(created)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                        
                        if let expires = result.expirationDate {
                            HStack {
                                Text("Expires:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(expires)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                        
                        if !result.nameServers.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Name Servers:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                ForEach(result.nameServers.prefix(3), id: \.self) { server in
                                    Text("• \(server)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                if result.nameServers.count > 3 {
                                    Text("• ... and \(result.nameServers.count - 3) more")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                
                ScrollView {
                    Text(result.success ? result.rawResponse : result.statusMessage)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(result.success ? .primary : .red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(maxHeight: 400)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    NavigationStack {
        WhoisView()
    }
} 