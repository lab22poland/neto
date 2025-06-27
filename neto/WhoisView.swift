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
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
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
            
            Text("Query domain registration information and IP address details")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Domain or IP Address")
                .font(.headline)
            
            TextField("Enter domain name or IP address", text: $viewModel.targetDomain)
                .textFieldStyle(.roundedBorder)
#if os(iOS)
                .autocapitalization(.none)
#endif
                .disableAutocorrection(true)
#if os(macOS)
                .frame(maxWidth: 400)
#endif
                .onSubmit {
                    if viewModel.isTargetDomainValid && !viewModel.isLoading {
                        viewModel.startWhoisLookup()
                    }
                }
            
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
                .disabled(!viewModel.isTargetDomainValid || viewModel.isLoading)
                .buttonStyle(.borderedProminent)
                
                if viewModel.isLoading {
                    Button(action: viewModel.stopWhoisLookup) {
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
    private var resultSection: some View {
        if let result = viewModel.whoisResult {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("WHOIS Result")
                        .font(.headline)
                    
                    Spacer()
                    
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.success ? .green : .red)
                }
                
                if result.success {
                    summarySection(for: result)
                    rawDataSection(for: result)
                } else {
                    Text(result.statusMessage)
                        .foregroundColor(.red)
                        .font(.body)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func summarySection(for result: WhoisResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                if let registrar = result.registrar {
                    infoRow(label: "Registrar", value: registrar)
                }
                
                if let registrationDate = result.registrationDate {
                    infoRow(label: "Registration Date", value: registrationDate)
                }
                
                if let expirationDate = result.expirationDate {
                    infoRow(label: "Expiration Date", value: expirationDate)
                }
                
                if let whoisServer = result.whoisServer {
                    infoRow(label: "WHOIS Server", value: whoisServer)
                }
                
                if !result.nameServers.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name Servers:")
                            .font(.system(.body, design: .default))
                            .fontWeight(.medium)
                        
                        ForEach(result.nameServers, id: \.self) { nameServer in
                            Text("• \(nameServer)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                infoRow(label: "Response Time", value: String(format: "%.2f ms", result.responseTime))
            }
            .padding()
            .background(Color(red: 0.95, green: 0.95, blue: 0.97))
            .cornerRadius(8)
        }
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text("\(label):")
                .font(.system(.body, design: .default))
                .fontWeight(.medium)
                .frame(width: 120, alignment: .leading)
            
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
            
            Spacer()
        }
    }
    
    private func rawDataSection(for result: WhoisResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Raw WHOIS Data")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            ScrollView {
                Text(result.rawResponse.isEmpty ? "No raw data available" : result.rawResponse)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(maxHeight: 300)
            .background(Color(red: 0.95, green: 0.95, blue: 0.97))
            .cornerRadius(8)
        }
    }
}

#Preview {
    NavigationStack {
        WhoisView()
    }
} 