//
//  DnsViewModel.swift
//  neto
//
//  Created by Sergii Solianyk on 12/10/2026.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Combine

/// ViewModel for the DNS lookup tool, coordinating between DnsView and DnsManager
@MainActor
final class DnsViewModel: ObservableObject {

    /// Where the query goes
    enum ServerChoice: Hashable {
        case system
        case preset(DNSServer)
        case custom
    }

    @Published var query: String = ""
    @Published var recordType: DNSRecordType = .a
    @Published var serverChoice: ServerChoice = .system
    @Published var customServer: String = ""
    @Published var transport: DNSTransport = .udp
    @Published var result: DnsResult?
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// System DNS servers, read once
    let systemServers: [String]

    private let dnsManager = DnsManager()
    private var lookupTask: Task<Void, Never>?

    init(systemServers: [String] = DnsManager.systemServers()) {
        self.systemServers = systemServers
    }

    /// Name and type actually queried: an IP address becomes its reverse name with type PTR, like `dig -x`
    var effectiveQuery: (name: String, type: DNSRecordType) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let reverse = DNSWire.reverseName(for: trimmed) { return (reverse, .ptr) }
        return (trimmed, recordType)
    }

    /// The server for the current choice, nil if it is not usable yet
    var selectedServer: DNSServer? {
        switch serverChoice {
        case .system:
            return systemServers.first.map { DNSServer(label: "System", address: $0, tlsHost: nil, dohURL: nil) }
        case .preset(let server):
            return server
        case .custom:
            let address = customServer.trimmingCharacters(in: .whitespacesAndNewlines)
            var v4 = in_addr(), v6 = in6_addr()
            guard inet_pton(AF_INET, address, &v4) == 1 || inet_pton(AF_INET6, address, &v6) == 1 else { return nil }
            return .custom(address)
        }
    }

    /// Whether the name can be encoded: labels of 1-63 bytes, at most 253 characters
    var isQueryValid: Bool {
        let name = effectiveQuery.name
        guard !name.isEmpty, (try? DNSWire.encodeName(name)) != nil else { return false }
        return name.count <= 254
    }

    var canLookup: Bool {
        guard isQueryValid, !isLoading, let server = selectedServer else { return false }
        return server.supports(transport)
    }

    /// Starts the lookup with the current settings
    func startLookup() {
        guard canLookup, let server = selectedServer else {
            errorMessage = isQueryValid ? "Choose a server that supports \(transport.rawValue)" : "Please enter a valid domain name or IP address"
            return
        }
        let (name, type) = effectiveQuery
        isLoading = true
        errorMessage = nil
        result = nil
        lookupTask = dnsManager.performLookup(name: name, type: type, server: server, transport: transport) { [weak self] result in
            self?.result = result
            self?.isLoading = false
            self?.lookupTask = nil
            if let error = result.error { self?.errorMessage = error }
        }
    }

    /// Cancels a running lookup
    func stopLookup() {
        lookupTask?.cancel()
        lookupTask = nil
        isLoading = false
    }

    deinit {
        lookupTask?.cancel()
    }
}
