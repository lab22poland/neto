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
                .accessibilityIdentifier("whois.header")
            
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
                .accessibilityIdentifier("whois.query")
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
                            .foregroundColor(.primary)
                        
                        Button("8.8.8.8") { viewModel.targetQuery = "8.8.8.8" }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundColor(.primary)
                            .accessibilityIdentifier("whois.example.ipv4")
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Button("AS15169") { viewModel.targetQuery = "AS15169" }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundColor(.primary)
                        
                        Button("2001:4860:4860::8888") { viewModel.targetQuery = "2001:4860:4860::8888" }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundColor(.primary)
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
                .accessibilityIdentifier("whois.lookup")
                
                if viewModel.isLoading {
                    Button(action: viewModel.stopWhoisLookup) {
                        Text("Stop")
                            .frame(minWidth: 60, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.secondary)
                }
                
                if let responseTime = viewModel.whoisResult?.responseTime {
                    Text(String(format: "Response Time: %.2f ms", responseTime))
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
                .foregroundColor(.secondary)
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
                    
                    Image(systemName: statusSymbol(for: result))
                        .foregroundColor(result.success && result.outcome == .found ? .primary : .secondary)
                }
                
                // Not found, no data, incomplete, IANA-only or no recognized fields: say so; the raw response is still shown
                if result.success && (result.outcome != .found || !result.hasSummaryFields) {
                    Text(result.statusMessage)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .accessibilityIdentifier("whois.status")
                }
                
                // Quick info section: fields from the last server's answer only (none when not found or empty)
                if result.success && result.hasSummaryFields {
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
                        .foregroundColor(result.success ? .primary : .secondary)
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
    
    /// Checkmark only when the last server answered with the object
    private func statusSymbol(for result: WhoisResult) -> String {
        guard result.success else { return "xmark.circle.fill" }
        switch result.outcome {
        case .found: return "checkmark.circle.fill"
        case .notFound: return "questionmark.circle.fill"
        case .noData: return "minus.circle.fill"
        case .incomplete: return "exclamationmark.triangle.fill"
        case .ianaOnly: return "info.circle.fill"
        }
    }
}

#Preview {
    NavigationStack {
        WhoisView()
    }
} 