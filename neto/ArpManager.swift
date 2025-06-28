//
//  ArpManager.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation

/// Manager class responsible for ARP table operations
final class ArpManager {
    
    /// Retrieves the current ARP table from the system
    /// - Returns: ArpResult containing all ARP entries grouped by interface
    /// - Throws: ArpError if the operation fails
    func getArpTable() async throws -> ArpResult {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let errorPipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
            process.arguments = ["-a"]
            process.standardOutput = pipe
            process.standardError = errorPipe
            
            do {
                try process.run()
                
                DispatchQueue.global(qos: .userInitiated).async {
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    if process.terminationStatus != 0 {
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: ArpError.commandFailed(errorMessage))
                        return
                    }
                    
                    guard let output = String(data: data, encoding: .utf8) else {
                        continuation.resume(throwing: ArpError.invalidOutput)
                        return
                    }
                    
                    do {
                        let arpResult = try self.parseArpOutput(output)
                        continuation.resume(returning: arpResult)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: ArpError.processError(error))
            }
        }
    }
    
    /// Parses the output of the 'arp -a' command
    /// - Parameter output: Raw output from the arp command
    /// - Returns: ArpResult with parsed entries
    /// - Throws: ArpError if parsing fails
    private func parseArpOutput(_ output: String) throws -> ArpResult {
        let lines = output.components(separatedBy: .newlines)
        var entries: [ArpEntry] = []
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty else { continue }
            
            if let entry = parseArpLine(trimmedLine) {
                entries.append(entry)
            }
        }
        
        return ArpResult(entries: entries)
    }
    
    /// Parses a single line of ARP output
    /// - Parameter line: A single line from arp -a output
    /// - Returns: ArpEntry if parsing succeeds, nil otherwise
    private func parseArpLine(_ line: String) -> ArpEntry? {
        // Expected formats:
        // hostname (192.168.1.1) at aa:bb:cc:dd:ee:ff on en0 ifscope [ethernet]
        // ? (192.168.1.1) at aa:bb:cc:dd:ee:ff on en0 ifscope [ethernet]
        // ? (192.168.1.1) at (incomplete) on en0 ifscope [ethernet]
        // gateway.local (192.168.1.1) at aa:bb:cc:dd:ee:ff on en0 permanent [ethernet]
        
        // Use regex to extract components
        let pattern = #"^.*\(([^)]+)\)\s+at\s+([^\s]+)\s+on\s+([^\s]+)(?:\s+([^[]+))?"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        
        let nsString = line as NSString
        let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: nsString.length))
        
        guard let match = matches.first, match.numberOfRanges >= 4 else {
            return nil
        }
        
        let ipAddress = nsString.substring(with: match.range(at: 1))
        let macAddress = nsString.substring(with: match.range(at: 2))
        let interface = nsString.substring(with: match.range(at: 3))
        
        // Extract status information
        var status = "active"
        if match.numberOfRanges > 4 && match.range(at: 4).location != NSNotFound {
            let statusString = nsString.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces)
            if !statusString.isEmpty {
                status = statusString
            }
        }
        
        // Check for special cases in the MAC address field
        if macAddress == "(incomplete)" {
            status = "incomplete"
        } else if line.contains("permanent") {
            status = "permanent"
        }
        
        // Validate MAC address format (unless incomplete)
        if macAddress != "(incomplete)" && !isValidMacAddress(macAddress) {
            return nil
        }
        
        return ArpEntry(
            ipAddress: ipAddress,
            macAddress: macAddress,
            interface: interface,
            status: status
        )
    }
    
    /// Validates MAC address format
    /// - Parameter macAddress: MAC address string to validate
    /// - Returns: True if the MAC address format is valid
    private func isValidMacAddress(_ macAddress: String) -> Bool {
        let macPattern = #"^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$"#
        return macAddress.range(of: macPattern, options: .regularExpression) != nil
    }
}

/// Errors that can occur during ARP operations
enum ArpError: LocalizedError {
    case commandFailed(String)
    case processError(Error)
    case invalidOutput
    case parsingFailed
    
    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return "ARP command failed: \(message)"
        case .processError(let error):
            return "Process error: \(error.localizedDescription)"
        case .invalidOutput:
            return "Invalid command output"
        case .parsingFailed:
            return "Failed to parse ARP output"
        }
    }
} 