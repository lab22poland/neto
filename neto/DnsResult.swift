//
//  DnsResult.swift
//  neto
//
//  Created by Sergii Solianyk on 12/10/2026.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation

/// Outcome of one DNS lookup: the parsed response, or the error that prevented it
struct DnsResult: Identifiable {
    let id = UUID()
    let name: String
    let type: DNSRecordType
    let server: DNSServer
    /// Transport that produced the response (UDP may have been retried over TCP)
    let transport: DNSTransport
    let message: DNSMessage?
    let error: String?
    /// Milliseconds from sending the query to the complete response
    let queryTime: Double
    let responseSize: Int
    let timestamp: Date

    init(name: String, type: DNSRecordType, server: DNSServer, transport: DNSTransport, message: DNSMessage,
         queryTime: Double, responseSize: Int, timestamp: Date) {
        self.name = name
        self.type = type
        self.server = server
        self.transport = transport
        self.message = message
        self.error = nil
        self.queryTime = queryTime
        self.responseSize = responseSize
        self.timestamp = timestamp
    }

    init(name: String, type: DNSRecordType, server: DNSServer, transport: DNSTransport, error: String, timestamp: Date) {
        self.name = name
        self.type = type
        self.server = server
        self.transport = transport
        self.message = nil
        self.error = error
        self.queryTime = 0
        self.responseSize = 0
        self.timestamp = timestamp
    }

    /// Status line like dig's header: "NOERROR · qr rd ra ad"
    var status: String {
        guard let message else { return error ?? "" }
        return ([message.rcodeName] + [message.flagNames.joined(separator: " ")]).joined(separator: " · ")
    }

    /// Whole answer in dig's text layout (sections, query time, server), for copying
    var digText: String {
        guard let message else { return ";; \(error ?? "")" }
        // dig counts the EDNS OPT pseudo-record in ADDITIONAL
        let additionalCount = message.additional.count + (message.ednsUDPSize == nil ? 0 : 1)
        var lines = [";; ->>HEADER<<- opcode: \(message.opcodeName), status: \(message.rcodeName), id: \(message.id)",
                     ";; flags: \(message.flagNames.joined(separator: " ")); QUERY: \(message.questions.count), ANSWER: \(message.answers.count), AUTHORITY: \(message.authority.count), ADDITIONAL: \(additionalCount)",
                     "",
                     ";; QUESTION SECTION:"]
        lines += message.questions.map { ";\($0.name)\t\tIN\t\(DNSRecordType.name(of: $0.type))" }
        for (title, records) in [("ANSWER", message.answers), ("AUTHORITY", message.authority), ("ADDITIONAL", message.additional)] where !records.isEmpty {
            lines += ["", ";; \(title) SECTION:"] + records.map(\.presentation)
        }
        lines += ["", String(format: ";; Query time: %.0f msec", queryTime),
                  ";; SERVER: \(server.label) (\(server.address)) over \(transport.rawValue)",
                  ";; MSG SIZE  rcvd: \(responseSize)"]
        return lines.joined(separator: "\n")
    }
}
