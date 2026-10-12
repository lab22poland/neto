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
    /// Server end of the connection that produced the response (nil for errors)
    let endpoint: DNSServerEndpoint?
    let message: DNSMessage?
    let error: String?
    /// Milliseconds from sending the query to the complete response
    let queryTime: Double
    let responseSize: Int
    let timestamp: Date

    init(name: String, type: DNSRecordType, server: DNSServer, transport: DNSTransport, endpoint: DNSServerEndpoint,
         message: DNSMessage, queryTime: Double, responseSize: Int, timestamp: Date) {
        self.name = name
        self.type = type
        self.server = server
        self.transport = transport
        self.endpoint = endpoint
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
        self.endpoint = nil
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

    /// Line under the records: "Query time: 13 ms · Cloudflare · 1.0.0.1#853 (one.one.one.one) over DoT · 72 bytes"
    var summary: String {
        // Results with a response always carry the endpoint; error results show only the error
        guard message != nil, let endpoint else { return error ?? "" }
        let connection = endpoint.summary(transport)
        return String(format: "Query time: %.0f ms · %@ · %@ · %d bytes", queryTime, server.label, connection, responseSize)
    }

    /// Whole answer in dig's text layout (sections, query time, server), for copying
    var digText: String {
        // Results with a response always carry the endpoint (both come from the same initializer)
        guard let message, let endpoint else { return ";; \(error ?? "")" }
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
                  endpoint.digServerLine(transport),
                  ";; MSG SIZE  rcvd: \(responseSize)"]
        return lines.joined(separator: "\n")
    }
}

/// The server end of the connection that answered: the address the connection actually reached and the name the
/// query was addressed to (a DoT host or DoH URL resolves to one of several addresses, not the preset's address)
struct DNSServerEndpoint: Equatable {
    /// Remote IP address of the connection; nil if the system did not report it
    let address: String?
    let port: UInt16
    /// Server as addressed: IP address for UDP/TCP, TLS host for DoT, URL host for DoH (dig's "@server" argument)
    let host: String
    /// DoH URL
    let url: URL?
    /// Negotiated HTTP version for DoH ("h2", "h3", "http/1.1")
    let httpProtocol: String?

    /// Address and port like dig's isc_sockaddr_format ("1.1.1.1#853"); the host name stands in for an unknown address
    var addressAndPort: String { "\(address ?? host)#\(port)" }

    /// dig 9.18's server line, e.g. ";; SERVER: 1.0.0.1#853(one.one.one.one) (TLS)"
    func digServerLine(_ transport: DNSTransport) -> String {
        let proto: String
        switch transport {
        case .udp: proto = "UDP"
        case .tcp: proto = "TCP"
        case .tls: proto = "TLS"
        case .https: proto = "HTTPS"
        }
        return ";; SERVER: \(addressAndPort)(\(host)) (\(proto))"
    }

    /// Short form for the UI, e.g. "104.16.248.249#443 (https://cloudflare-dns.com/dns-query) over DoH, h3"
    func summary(_ transport: DNSTransport) -> String {
        let name = url?.absoluteString ?? host
        var text = addressAndPort
        if name != address { text += " (\(name))" }
        text += " over \(transport.rawValue)"
        if let httpProtocol { text += ", \(httpProtocol)" }
        return text
    }
}
