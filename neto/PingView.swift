//
//  PingView.swift
//  neto
//
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
                
                // Simple reachability check using NWConnection
                let endpoint: NWEndpoint
                
                if let _ = IPv4Address(host) {
                    endpoint = .hostPort(host: .ipv4(IPv4Address(host)!), port: .any)
                } else if let _ = IPv6Address(host) {
                    endpoint = .hostPort(host: .ipv6(IPv6Address(host)!), port: .any)
                } else {
                    endpoint = .hostPort(host: .name(host, nil), port: .any)
                }
                
                let connection = NWConnection(to: endpoint, using: .tcp)
                var hasResumed = false
                let lock = NSLock()
                
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        connection.cancel()
                        lock.lock()
                        if !hasResumed {
                            hasResumed = true
                            lock.unlock()
                            continuation.resume(returning: true)
                        } else {
                            lock.unlock()
                        }
                    case .failed(let error):
                        connection.cancel()
                        lock.lock()
                        if !hasResumed {
                            hasResumed = true
                            lock.unlock()
                            continuation.resume(throwing: error)
                        } else {
                            lock.unlock()
                        }
                    case .cancelled:
                        lock.lock()
                        if !hasResumed {
                            hasResumed = true
                            lock.unlock()
                            continuation.resume(returning: false)
                        } else {
                            lock.unlock()
                        }
                    default:
                        break
                    }
                }
                
                connection.start(queue: queue)
                
                // Timeout after 3 seconds (shorter timeout for better responsiveness)
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                    connection.cancel()
                    lock.lock()
                    if !hasResumed {
                        hasResumed = true
                        lock.unlock()
                        continuation.resume(returning: false)
                    } else {
                        lock.unlock()
                    }
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