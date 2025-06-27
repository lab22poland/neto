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
                    
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.success ? .green : .red)
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