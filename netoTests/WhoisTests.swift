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
        ("AS", "whois.arin.net", "+ a \r\n"),         // same as whois.c (empty AS lookup); the UI rejects "AS" anyway
        ("AS１５", "whois.arin.net", "+ AS１５\r\n"),  // only ASCII digits make an AS lookup, like whois.c strspn("0123456789")
        ("8.8.8.8", "whois.arin.net", "+ 8.8.8.8\r\n"),
        ("google.com", "whois.verisign-grs.com", "domain google.com\r\n"),
        ("AS 15169", "whois.arin.net", "AS 15169\r\n"),        // a query with a space is sent as is, before the ARIN rule
        ("John Smith", "whois.arin.net", "John Smith\r\n"),
        ("example.org", "whois.publicinterestregistry.org", "example.org\r\n"),
    ])
    func queryFormatting(query: String, server: String, sent: String) {
        #expect(WhoisManager().formatQueryForServer(query: query, server: server) == sent)
    }

    @Test(arguments: [
        ("whois:        whois.verisign-grs.com\n", "whois.verisign-grs.com", "43"),
        ("   Registrar WHOIS Server: whois.markmonitor.com\r\n", "whois.markmonitor.com", "43"),
        ("ReferralServer:  whois://whois.ripe.net\n", "whois.ripe.net", "43"),
        ("ReferralServer:  rwhois://rwhois.example.net:4321\n", "rwhois.example.net", "4321"),
        ("refer: whois.verisign-grs.com\n", nil, nil),                          // not a whois.c referral prefix
        ("Registrar WHOIS Server: http://whois.cscglobal.com\n", "http", nil),  // whois.c: host "http", port "//…" is invalid
        ("ReferralServer:  rwhois://rwhois.example.net:123456\n", nil, nil),    // ports of 6+ digits: no recursion
    ] as [(String, String?, String?)])
    func referralInLine(line: String, host: String?, port: String?) {
        let referral = WhoisManager.referral(in: line, prefixes: ["whois:", "Whois Server:", "Registrar WHOIS Server:",
                                                                  "ReferralServer:  whois://", "ReferralServer:  rwhois://"])
        if host == "http" {
            #expect(referral == nil, "a host followed by ':' and no digits is an invalid port")
        } else {
            #expect(referral?.host == host)
            #expect(referral?.port == port)
        }
    }

    /// Raw answers captured with nc from the real servers on 2026-10-12
    private static let ianaCom = "% IANA WHOIS server\n% for more information on IANA, visit http://www.iana.org\n% This query returned 1 object\n\ndomain:       COM\n\norganisation: VeriSign Global Registry Services\naddress:      12061 Bluemont Way\naddress:      Reston VA 20190\naddress:      United States of America (the)\n\ncontact:      administrative\nname:         Registry Customer Service\norganisation: VeriSign Global Registry Services\naddress:      12061 Bluemont Way\naddress:      Reston VA 20190\naddress:      United States of America (the)\nphone:        +1 703 925-6999\nfax-no:       +1 703 948 3978\ne-mail:       info@verisign-grs.com\n\ncontact:      technical\nname:         Registry Customer Service\norganisation: VeriSign Global Registry Services\naddress:      12061 Bluemont Way\naddress:      Reston VA 20190\naddress:      United States of America (the)\nphone:        +1 703 925-6999\nfax-no:       +1 703 948 3978\ne-mail:       info@verisign-grs.com\n\nnserver:      A.GTLD-SERVERS.NET 192.5.6.30 2001:503:a83e:0:0:0:2:30\nnserver:      B.GTLD-SERVERS.NET 192.33.14.30 2001:503:231d:0:0:0:2:30\nnserver:      C.GTLD-SERVERS.NET 192.26.92.30 2001:503:83eb:0:0:0:0:30\nnserver:      D.GTLD-SERVERS.NET 192.31.80.30 2001:500:856e:0:0:0:0:30\nnserver:      E.GTLD-SERVERS.NET 192.12.94.30 2001:502:1ca1:0:0:0:0:30\nnserver:      F.GTLD-SERVERS.NET 192.35.51.30 2001:503:d414:0:0:0:0:30\nnserver:      G.GTLD-SERVERS.NET 192.42.93.30 2001:503:eea3:0:0:0:0:30\nnserver:      H.GTLD-SERVERS.NET 192.54.112.30 2001:502:8cc:0:0:0:0:30\nnserver:      I.GTLD-SERVERS.NET 192.43.172.30 2001:503:39c1:0:0:0:0:30\nnserver:      J.GTLD-SERVERS.NET 192.48.79.30 2001:502:7094:0:0:0:0:30\nnserver:      K.GTLD-SERVERS.NET 192.52.178.30 2001:503:d2d:0:0:0:0:30\nnserver:      L.GTLD-SERVERS.NET 192.41.162.30 2001:500:d937:0:0:0:0:30\nnserver:      M.GTLD-SERVERS.NET 192.55.83.30 2001:501:b1f9:0:0:0:0:30\nds-rdata:     19718 13 2 8acbb0cd28f41250a80a491389424d341522d946b0da0c0291f2d3d771d7805a\n\nwhois:        whois.verisign-grs.com\n\nstatus:       ACTIVE\nremarks:      Registration information: http://www.verisigninc.com\n\ncreated:      1985-01-01\nchanged:      2026-03-10\nsource:       IANA\n\n"
    private static let verisignGoogle = "   Domain Name: GOOGLE.COM\r\n   Registry Domain ID: 2138514_DOMAIN_COM-VRSN\r\n   Registrar WHOIS Server: whois.markmonitor.com\r\n   Registrar URL: http://www.markmonitor.com\r\n   Updated Date: 2019-09-09T15:39:04Z\r\n   Creation Date: 1997-09-15T04:00:00Z\r\n   Registry Expiry Date: 2028-09-14T04:00:00Z\r\n   Registrar: MarkMonitor Inc.\r\n   Registrar IANA ID: 292\r\n   Registrar Abuse Contact Email: abusecomplaints@markmonitor.com\r\n   Registrar Abuse Contact Phone: +1.2086851750\r\n   Domain Status: clientDeleteProhibited https://icann.org/epp#clientDeleteProhibited\r\n   Domain Status: clientTransferProhibited https://icann.org/epp#clientTransferProhibited\r\n   Domain Status: clientUpdateProhibited https://icann.org/epp#clientUpdateProhibited\r\n   Domain Status: serverDeleteProhibited https://icann.org/epp#serverDeleteProhibited\r\n   Domain Status: serverTransferProhibited https://icann.org/epp#serverTransferProhibited\r\n   Domain Status: serverUpdateProhibited https://icann.org/epp#serverUpdateProhibited\r\n   Name Server: NS1.GOOGLE.COM\r\n   Name Server: NS2.GOOGLE.COM\r\n   Name Server: NS3.GOOGLE.COM\r\n   Name Server: NS4.GOOGLE.COM\r\n   DNSSEC: unsigned\r\n   URL of the ICANN Whois Inaccuracy Complaint Form: https://www.icann.org/wicf/\r\n>>> Last update of whois database: 2026-10-12T08:21:09Z <<<\r\n\r\nFor more information on Whois status codes, please visit https://icann.org/epp\r\n\r\nNOTICE: The expiration date displayed in this record is the date the\r\nregistrar's sponsorship of the domain name registration in the registry is\r\ncurrently set to expire. This date does not necessarily reflect the expiration\r\ndate of the domain name registrant's agreement with the sponsoring\r\nregistrar.  Users may consult the sponsoring registrar's Whois database to\r\nview the registrar's reported date of expiration for this registration.\r\n\r\nTERMS OF USE: You are not authorized to access or query our Whois\r\ndatabase through the use of electronic processes that are high-volume and\r\nautomated except as reasonably necessary to register domain names or\r\nmodify existing registrations; the Data in VeriSign Global Registry\r\nServices' (\"VeriSign\") Whois database is provided by VeriSign for\r\ninformation purposes only, and to assist persons in obtaining information\r\nabout or related to a domain name registration record. VeriSign does not\r\nguarantee its accuracy. By submitting a Whois query, you agree to abide\r\nby the following terms of use: You agree that you may use this Data only\r\nfor lawful purposes and that under no circumstances will you use this Data\r\nto: (1) allow, enable, or otherwise support the transmission of mass\r\nunsolicited, commercial advertising or solicitations via e-mail, telephone,\r\nor facsimile; or (2) enable high volume, automated, electronic processes\r\nthat apply to VeriSign (or its computer systems). The compilation,\r\nrepackaging, dissemination or other use of this Data is expressly\r\nprohibited without the prior written consent of VeriSign. You agree not to\r\nuse electronic processes that are automated and high-volume to access or\r\nquery the Whois database except as reasonably necessary to register\r\ndomain names or modify existing registrations. VeriSign reserves the right\r\nto restrict your access to the Whois database in its sole discretion to ensure\r\noperational stability.  VeriSign may restrict or terminate your access to the\r\nWhois database for failure to abide by these terms of use. VeriSign\r\nreserves the right to modify these terms at any time.\r\n\r\nThe Registry database contains ONLY .COM, .NET, .EDU domains and\r\nRegistrars.\r\n"
    private static let arin8888 = "\n#\n# ARIN WHOIS data and services are subject to the Terms of Use\n# available at: https://www.arin.net/resources/registry/whois/tou/\n#\n# If you see inaccuracies in the results, please report at\n# https://www.arin.net/resources/registry/whois/inaccuracy_reporting/\n#\n# Copyright 1997-2026, American Registry for Internet Numbers, Ltd.\n#\n\n\n#\n# Query terms are ambiguous.  The query is assumed to be:\n#     \"n + 8.8.8.8\"\n#\n# Use \"?\" to get help.\n#\n\nNetRange:       8.8.8.0 - 8.8.8.255\nCIDR:           8.8.8.0/24\nNetName:        GOGL\nNetHandle:      NET-8-8-8-0-2\nParent:         NET8 (NET-8-0-0-0-0)\nNetType:        Direct Allocation\nOriginAS:       \nOrganization:   Google LLC (GOGL)\nRegDate:        2023-12-28\nUpdated:        2023-12-28\nRef:            https://rdap.arin.net/registry/ip/8.8.8.0\n\n\n\nOrgName:        Google LLC\nOrgId:          GOGL\nAddress:        1600 Amphitheatre Parkway\nCity:           Mountain View\nStateProv:      CA\nPostalCode:     94043\nCountry:        US\nRegDate:        2000-03-30\nUpdated:        2019-10-31\nComment:        Please note that the recommended way to file abuse complaints are located in the following links. \nComment:        \nComment:        To report abuse and illegal activity: https://www.google.com/contact/\nComment:        \nComment:        For legal requests: http://support.google.com/legal \nComment:        \nComment:        Regards, \nComment:        The Google Team\nRef:            https://rdap.arin.net/registry/entity/GOGL\n\n\nOrgTechHandle: ZG39-ARIN\nOrgTechName:   Google LLC\nOrgTechPhone:  +1-650-253-0000 \nOrgTechEmail:  arin-contact@google.com\nOrgTechRef:    https://rdap.arin.net/registry/entity/ZG39-ARIN\n\nOrgAbuseHandle: ABUSE5250-ARIN\nOrgAbuseName:   Abuse\nOrgAbusePhone:  +1-650-253-0000 \nOrgAbuseEmail:  network-abuse@google.com\nOrgAbuseRef:    https://rdap.arin.net/registry/entity/ABUSE5250-ARIN\n\n\n#\n# ARIN WHOIS data and services are subject to the Terms of Use\n# available at: https://www.arin.net/resources/registry/whois/tou/\n#\n# If you see inaccuracies in the results, please report at\n# https://www.arin.net/resources/registry/whois/inaccuracy_reporting/\n#\n# Copyright 1997-2026, American Registry for Internet Numbers, Ltd.\n#\n\n"

    @Test func ianaReferralIsFound() {
        let processed = WhoisManager().processResponse(Self.ianaCom, server: "whois.iana.org")
        #expect(processed.referral?.host == "whois.verisign-grs.com")
        #expect(processed.output == Self.ianaCom, "IANA output is printed unchanged")
    }

    @Test func verisignLegalTextIsCut() {
        let processed = WhoisManager().processResponse(Self.verisignGoogle, server: "whois.verisign-grs.com")
        #expect(processed.referral?.host == "whois.markmonitor.com")
        #expect(processed.output.hasSuffix("<<<\r\n\n"), "whois.c prints the 'Last update' line, a newline, and stops")
        #expect(!processed.output.contains("TERMS OF USE"))
    }

    @Test func arinCommentsAreStripped() {
        let processed = WhoisManager().processResponse(Self.arin8888, server: "whois.arin.net")
        #expect(processed.output.hasPrefix("NetRange:"), "leading comment block is skipped")
        #expect(!processed.output.contains("# ARIN WHOIS data"), "trailing comment block ends the output")
        #expect(processed.output.contains("OrgName:        Google LLC"))
    }

    @Test func nominetStopsAtSeparator() {
        let processed = WhoisManager().processResponse("Domain name:\r\n    bbc.co.uk\r\n-- \r\nWHOIS lookup made at 10:00\r\n", server: "whois.nic.uk")
        #expect(processed.output == "Domain name:\r\n    bbc.co.uk\r\n")
    }

    @Test func actuallyArinRedirectsToArin() {
        let processed = WhoisManager().processResponse("inetnum:        1.0.0.0\nnetname:        ERX-NETBLOCK\n", server: "whois.apnic.net")
        #expect(processed.referral?.host == "whois.arin.net")
    }

    @Test func rirLoopFallsBackToUnvisitedRIR() {
        let manager = WhoisManager()
        var visited = Set<String>()
        // ARIN refers to RIPE: follow it
        #expect(manager.nextServer(after: "whois.arin.net", referral: ("whois.ripe.net", "43"), visitedRIRs: &visited)?.host == "whois.ripe.net")
        // RIPE refers back to ARIN (visited): whois.c picks the first RIR not asked yet
        #expect(manager.nextServer(after: "whois.ripe.net", referral: ("whois.arin.net", "43"), visitedRIRs: &visited)?.host == "whois.apnic.net")
        // No referral: the chain ends
        #expect(manager.nextServer(after: "whois.apnic.net", referral: nil, visitedRIRs: &visited) == nil)
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
