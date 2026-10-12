//
//  DnsView.swift
//  neto
//
//  Created by Sergii Solianyk on 12/10/2026.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import SwiftUI
#if !os(macOS)
import UIKit
#endif

/// DNS lookup tool: name, record type, server and transport; shows the answer like dig
struct DnsView: View {
    @StateObject private var viewModel = DnsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                querySection
                serverSection
                errorSection
                resultSection
            }
            .padding()
        }
        .navigationTitle("DNS")
        .onKeyPress(.escape) {
            if viewModel.isLoading {
                viewModel.stopLookup()
                return .handled
            }
            return .ignored
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DNS Lookup")
                .font(.largeTitle)
                .fontWeight(.bold)
                .accessibilityIdentifier("dns.header")

            Text("Query any DNS server over UDP, TCP, DNS over TLS or DNS over HTTPS, like dig")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var querySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(.headline)

            TextField("Enter a domain name, or an IP address for a reverse lookup", text: $viewModel.query)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .accessibilityIdentifier("dns.name")
                .onSubmit {
                    if viewModel.canLookup { viewModel.startLookup() }
                }

            HStack(spacing: 12) {
                Picker("Type", selection: $viewModel.recordType) {
                    ForEach(DNSRecordType.allCases) { type in
                        Text(type.name).tag(type)
                    }
                }
                .fixedSize()
                .disabled(viewModel.effectiveQuery.type == .ptr && DNSWire.reverseName(for: viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)) != nil)
                .accessibilityIdentifier("dns.type")

                if viewModel.effectiveQuery.type == .ptr && viewModel.recordType != .ptr {
                    Text("IP address: reverse lookup (PTR)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button(action: viewModel.startLookup) {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 12, height: 12)
                        }
                        Text("Look Up")
                    }
                    .frame(minWidth: 120, minHeight: 32)
                }
                .disabled(!viewModel.canLookup)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("dns.lookup")

                if viewModel.isLoading {
                    Button(action: viewModel.stopLookup) {
                        Text("Stop")
                            .frame(minWidth: 60, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("dns.stop")
                }
            }
        }
    }

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Server")
                .font(.headline)

            Picker("Server", selection: $viewModel.serverChoice) {
                Text(viewModel.systemServers.first.map { "System (\($0))" } ?? "System (not found)")
                    .tag(DnsViewModel.ServerChoice.system)
                ForEach(DNSServer.presets) { server in
                    Text("\(server.label) (\(server.address))").tag(DnsViewModel.ServerChoice.preset(server))
                }
                Text("Custom…").tag(DnsViewModel.ServerChoice.custom)
            }
            .fixedSize()
            .accessibilityIdentifier("dns.server")

            if viewModel.serverChoice == .custom {
                TextField("Server IP address", text: $viewModel.customServer)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    .accessibilityIdentifier("dns.customServer")
            }

            Picker("Transport", selection: $viewModel.transport) {
                ForEach(DNSTransport.allCases) { transport in
                    Text(transport.rawValue).tag(transport)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityIdentifier("dns.transport")

            if let server = viewModel.selectedServer, !server.supports(viewModel.transport) {
                Text("\(server.label) has no \(viewModel.transport.rawValue) endpoint; choose a preset server")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var errorSection: some View {
        Group {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .accessibilityIdentifier("dns.error")
            }
        }
    }

    private var resultSection: some View {
        Group {
            if let result = viewModel.result, let message = result.message {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Result")
                            .font(.headline)
                        Spacer()
                        Button("Copy") { copy(result.digText) }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("dns.copy")
                    }

                    Text(result.status)
                        .font(.system(.body, design: .monospaced))
                        .accessibilityIdentifier("dns.status")

                    recordsSection("Answer", message.answers)
                    recordsSection("Authority", message.authority)
                    recordsSection("Additional", message.additional)

                    Text(String(format: "Query time: %.0f ms · %@ (%@) over %@ · %d bytes",
                                result.queryTime, result.server.label, result.server.address,
                                result.transport.rawValue, result.responseSize))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(.quaternary)
                .cornerRadius(8)
            }
        }
    }

    @ViewBuilder
    private func recordsSection(_ title: String, _ records: [DNSRecord]) -> some View {
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(title) (\(records.count))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                    HStack(alignment: .top, spacing: 8) {
                        Text(record.typeName)
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 56, alignment: .leading)
                        Text(String(record.ttl))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 56, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.data)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Text(record.name)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("dns.record.\(title.lowercased())")
                }
            }
        }
    }

    private func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

#Preview {
    NavigationStack {
        DnsView()
    }
}
