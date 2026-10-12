//
//  WhoisTests.swift
//  netoTests
//
//  Created by Sergii Solianyk on 12/10/2026.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Foundation
import Testing
@testable import neto

/// FreeBSD whois.c logic ported to WhoisManager: server choice, query formatting, referrals, parsing
struct WhoisManagerLogicTests {

    @Test(arguments: [
        ("google.com", "whois.iana.org"),
        ("8.8.8.8", "whois.iana.org"),
        ("JD123-ARIN", "whois.arin.net"),
        ("jd123-arin", "whois.arin.net"),
        ("XY1-RIPE", "whois.ripe.net"),
        ("FOO-NICAT", "at.whois-servers.net"),
        ("example.ac.uk", "ac.uk.whois-servers.net"),
        ("example.gov.uk", "ac.uk.whois-servers.net"),
        ("ac.uk", "whois.iana.org"),   // whois.c needs the query to be longer than the suffix
    ])
    func chooseServer(query: String, server: String) {
        #expect(WhoisManager().chooseServer(for: query) == server)
    }

    @Test func emptyQueryHasNoServer() {
        #expect(WhoisManager().chooseServer(for: "") == nil)
    }

    @Test(arguments: [
        ("example.de", "whois.denic.de", "-T dn,ace example.de\r\n"),
        ("müller.de", "whois.denic.de", "-T dn müller.de\r\n"),
        ("example.dk", "whois.dk-hostmaster.dk", "--show-handles example.dk\r\n"),
        ("AS15169", "whois.arin.net", "+ a 15169\r\n"),
        ("AS", "whois.arin.net", "+ AS\r\n"),
        ("8.8.8.8", "whois.arin.net", "+ 8.8.8.8\r\n"),
        ("google.com", "whois.verisign-grs.com", "domain google.com\r\n"),
        ("example.org", "whois.publicinterestregistry.org", "example.org\r\n"),
    ])
    func queryFormatting(query: String, server: String, sent: String) {
        #expect(WhoisManager().formatQueryForServer(query: query, server: server) == sent)
    }

    @Test(arguments: [
        ("refer:        whois.verisign-grs.com\nwhois:        whois.verisign-grs.com\n", "whois.verisign-grs.com", "43"),
        ("   Registrar WHOIS Server: whois.markmonitor.com\n", "whois.markmonitor.com", "43"),
        ("ReferralServer:  whois://whois.ripe.net\n", "whois.ripe.net", "43"),
        ("ReferralServer:  rwhois://rwhois.example.net:4321\n", "rwhois.example.net", "4321"),
    ])
    func referralIsFollowed(response: String, host: String, port: String) throws {
        let referral = try #require(WhoisManager().parseWhoisReferral(from: response))
        #expect(referral.host == host)
        #expect(referral.port == port)
    }

    @Test func responseWithoutReferral() {
        #expect(WhoisManager().parseWhoisReferral(from: "Domain Name: EXAMPLE.ORG\nRegistrar: Foo\n") == nil)
    }

    @Test func responseFieldsAreParsed() {
        let response = """
        % comment line with Registrar: Ignored
        Domain Name: GOOGLE.COM
        Registrar: MarkMonitor Inc.
        Creation Date: 1997-09-15T04:00:00Z
        Registry Expiry Date: 2028-09-14T04:00:00Z
        Name Server: NS1.GOOGLE.COM
        Name Server: NS2.GOOGLE.COM
        Name Server: NS1.GOOGLE.COM
        """
        let parsed = WhoisManager().parseWhoisResponse(response, for: "google.com")
        #expect(parsed.registrar == "MarkMonitor Inc.")
        #expect(parsed.registrationDate == "1997-09-15T04:00:00Z")
        #expect(parsed.expirationDate == "2028-09-14T04:00:00Z")
        #expect(parsed.nameServers == ["NS1.GOOGLE.COM", "NS2.GOOGLE.COM"])
    }

    @Test func emptyQueryFailsWithoutNetwork() async {
        let result = await withCheckedContinuation { continuation in
            _ = WhoisManager().performWhois(for: "") { continuation.resume(returning: $0) }
        }
        #expect(result.success == false)
        #expect(result.whoisServer == nil)
    }
}

/// Input validation that enables the lookup button
@MainActor
struct WhoisQueryValidationTests {

    @Test(arguments: ["google.com", "site.co.uk", "sub.example.com", "8.8.8.8", "2001:4860:4860::8888",
                      "AS15169", "as15169", "AS 15169", "John Smith", "JD123-ARIN", "invalid_domain",
                      "as1as2"])   // not an AS number, but a valid alphanumeric handle
    func validQuery(_ query: String) {
        let viewModel = WhoisViewModel()
        viewModel.targetQuery = query
        #expect(viewModel.isTargetQueryValid)
    }

    @Test(arguments: ["", "   ", "!!", "a", "foo.bar!"])
    func invalidQuery(_ query: String) {
        let viewModel = WhoisViewModel()
        viewModel.targetQuery = query
        #expect(!viewModel.isTargetQueryValid)
    }

    @Test(arguments: ["as", "AS", "as "])
    func malformedASNumber(_ query: String) {
        let viewModel = WhoisViewModel()
        viewModel.targetQuery = query
        #expect(!viewModel.isTargetQueryValid, "\"as\" alone is neither an AS number nor a handle (too short)")
    }

    @Test func emptyQueryShowsError() {
        let viewModel = WhoisViewModel()
        viewModel.startWhoisLookup()
        #expect(viewModel.errorMessage != nil)
        #expect(!viewModel.isLoading)
    }
}
