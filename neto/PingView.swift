//
//  PingView.swift
//  neto
//
//  © 2024 Sergii Solianyk
//  Created by Sergii Solianyk on 21/06/2025.
//

import SwiftUI
import Network

struct PingView: View {
    @State private var targetHost: String = ""
    @State private var pingResults: [PingResult] = []
    @State private var isPinging: Bool = false
    @State private var errorMessage: String?
    @State private var pingTask: Task<Void, Never>?
    
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
            if isPinging {
                stopPing()
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
            
            TextField("Enter IPv4, IPv6 address or domain name", text: $targetHost)
                .textFieldStyle(.roundedBorder)
#if os(iOS)
                .autocapitalization(.none)
#endif
                .disableAutocorrection(true)
#if os(macOS)
                .frame(maxWidth: 400)
#endif
                .onSubmit {
                    if !targetHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPinging {
                        performPing()
                    }
                }
            
            HStack(spacing: 12) {
                Button(action: performPing) {
                    HStack {
                        if isPinging {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 12, height: 12)
                        }
                        Text("Send 5 Ping Packets")
                    }
                    .frame(minWidth: 160, minHeight: 32)
                }
                .disabled(targetHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPinging)
                .buttonStyle(.borderedProminent)
                
                if isPinging {
                    Button(action: stopPing) {
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
        if let errorMessage = errorMessage {
            Text(errorMessage)
                .foregroundColor(.red)
                .font(.caption)
        }
    }
    
    @ViewBuilder
    private var resultsSection: some View {
        if !pingResults.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Results")
                        .font(.headline)
                    Spacer()
                }
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(pingResults) { result in
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
    
    private func performPing() {
        guard !targetHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        isPinging = true
        errorMessage = nil
        pingResults.removeAll()
        
        let host = targetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        
        pingTask = Task {
            await pingHost(host)
        }
    }
    
    private func stopPing() {
        pingTask?.cancel()
        pingTask = nil
        Task { @MainActor in
            isPinging = false
            // Add a final result to show the ping was stopped
            if !pingResults.isEmpty {
                let result = PingResult(
                    id: UUID(),
                    sequenceNumber: pingResults.count + 1,
                    success: false,
                    responseTime: 0,
                    message: "Ping stopped by user"
                )
                pingResults.append(result)
            }
        }
    }
    
    private func pingHost(_ host: String) async {
        let pingCount = 5
        
        for i in 1...pingCount {
            // Check if task was cancelled
            if Task.isCancelled {
                await MainActor.run {
                    isPinging = false
                }
                return
            }
            
            let startTime = Date()
            
            do {
                let isReachable = try await checkHostReachability(host)
                let endTime = Date()
                let responseTime = endTime.timeIntervalSince(startTime) * 1000 // Convert to milliseconds
                
                let result = PingResult(
                    id: UUID(),
                    sequenceNumber: i,
                    success: isReachable,
                    responseTime: responseTime,
                    message: isReachable 
                        ? String(format: "Reply from %@: time=%.2fms seq=%d", host, responseTime, i)
                        : String(format: "Request timeout seq=%d", i)
                )
                
                await MainActor.run {
                    pingResults.append(result)
                }
                
                // Add delay between pings, but check for cancellation
                if i < pingCount {
                    do {
                        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    } catch {
                        // Task was cancelled during sleep
                        await MainActor.run {
                            isPinging = false
                        }
                        return
                    }
                }
                
            } catch {
                // Check if task was cancelled
                if Task.isCancelled {
                    await MainActor.run {
                        isPinging = false
                    }
                    return
                }
                
                let result = PingResult(
                    id: UUID(),
                    sequenceNumber: i,
                    success: false,
                    responseTime: 0,
                    message: String(format: "Error seq=%d: %@", i, error.localizedDescription)
                )
                
                await MainActor.run {
                    pingResults.append(result)
                }
            }
        }
        
        await MainActor.run {
            isPinging = false
            pingTask = nil
        }
    }
    
    private func checkHostReachability(_ host: String) async throws -> Bool {
        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { continuation in
                let queue = DispatchQueue(label: "ping.monitor")
                
                // Create endpoint based on host type
                let endpoint: NWEndpoint
                
                if let ipv4 = IPv4Address(host) {
                    endpoint = .hostPort(host: .ipv4(ipv4), port: 80)
                } else if let ipv6 = IPv6Address(host) {
                    endpoint = .hostPort(host: .ipv6(ipv6), port: 80)
                } else {
                    endpoint = .hostPort(host: .name(host, nil), port: 80)
                }
                
                // Use UDP for a more ping-like experience (lighter weight than TCP)
                let parameters = NWParameters.udp
                parameters.prohibitExpensivePaths = false
                parameters.prohibitConstrainedPaths = false
                
                let connection = NWConnection(to: endpoint, using: parameters)
                var hasCompleted = false
                let lock = NSLock()
                
                connection.stateUpdateHandler = { state in
                    lock.lock()
                    defer { lock.unlock() }
                    
                    guard !hasCompleted else { return }
                    
                    switch state {
                    case .ready:
                        hasCompleted = true
                        connection.cancel()
                        continuation.resume(returning: true)
                    case .failed(let error):
                        hasCompleted = true
                        connection.cancel()
                        // For network unreachable errors, treat as timeout rather than error
                        if let nwError = error as? NWError {
                            switch nwError {
                            case .dns(DNSServiceErrorType(kDNSServiceErr_NoSuchRecord)):
                                continuation.resume(returning: false)
                            case .posix(let posixError) where posixError == .ENETUNREACH:
                                continuation.resume(returning: false)
                            case .posix(let posixError) where posixError == .EHOSTUNREACH:
                                continuation.resume(returning: false)
                            case .posix(let posixError) where posixError == .ETIMEDOUT:
                                continuation.resume(returning: false)
                            default:
                                continuation.resume(throwing: error)
                            }
                        } else {
                            continuation.resume(throwing: error)
                        }
                    case .cancelled:
                        hasCompleted = true
                        continuation.resume(returning: false)
                    default:
                        break
                    }
                }
                
                connection.start(queue: queue)
                
                // Timeout after 5 seconds
                DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
                    lock.lock()
                    defer { lock.unlock() }
                    
                    guard !hasCompleted else { return }
                    hasCompleted = true
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
        } onCancel: {
            // This handler will be called when the task is cancelled
        }
    }
}

struct PingResult: Identifiable {
    let id: UUID
    let sequenceNumber: Int
    let success: Bool
    let responseTime: Double
    let message: String
}

#Preview {
    NavigationStack {
        PingView()
    }
} 