//
//  netoUITests.swift
//  netoUITests
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import XCTest

/// End-to-end user flows. Every test works on macOS, iPad and iPhone (where the split view
/// collapses into a navigation stack) and needs no internet: ping and traceroute use 127.0.0.1.
final class netoUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - Navigation

    @MainActor
    func testNavigationOpensEveryTool() throws {
        if !isCompactLayout {
            XCTAssertTrue(element("detail.placeholder").waitForExistence(timeout: 5))
        }

        let tools = [("ping", "ping.header"),
                     ("traceroute", "traceroute.header"),
                     ("whois", "whois.header"),
                     ("arp", "arp.header"),
                     ("about", "about.header")]
        for (tool, header) in tools {
            openTool(tool, expecting: header)
        }
        // Back to the first tool: selection must still switch after visiting all others
        openTool("ping", expecting: "ping.header")
    }

    // MARK: - Ping

    @MainActor
    func testPingLocalhostReportsReplies() throws {
        openTool("ping", expecting: "ping.header")
        let host = element("ping.host")
        let start = element("ping.start")
        XCTAssertFalse(start.isEnabled, "Start must be disabled for an empty host")

        host.tap()
        host.typeText("   ")
        XCTAssertFalse(start.isEnabled, "Start must be disabled for a whitespace-only host")
        host.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "127.0.0.1")
        XCTAssertTrue(start.isEnabled)

        start.tap()
        XCTAssertTrue(element("ping.stop").waitForExistence(timeout: 2), "Stop must appear while pinging")
        // Statistics prove all replies arrived; the row check below proves the results list is visible
        XCTAssertTrue(wait(for: element("ping.stats"), text: "Packets: 5 sent, 5 received", timeout: 15),
                      "All 5 echo requests to 127.0.0.1 must be answered")
        XCTAssertTrue(waitForDisappearance(of: element("ping.stop"), timeout: 5), "Stop must disappear after the run")
        XCTAssertTrue(start.isEnabled, "Start must be enabled again after the run")
        let replyRow = text(beginningWith: "Reply from 127.0.0.1")
        XCTAssertTrue(replyRow.exists && !replyRow.frame.isEmpty, "Result rows must be visible in the default window")
    }

    @MainActor
    func testPingStartsOnReturnAndClearsResults() throws {
        openTool("ping", expecting: "ping.header")
        let host = element("ping.host")
        host.tap()
        host.typeText("127.0.0.1\n")

        XCTAssertTrue(element("ping.stats").waitForExistence(timeout: 10), "Return in the host field must start a ping")
        XCTAssertTrue(waitForDisappearance(of: element("ping.stop"), timeout: 15))

        element("ping.clear").tap()
        XCTAssertTrue(element("ping.noResults").waitForExistence(timeout: 2))
        XCTAssertFalse(element("ping.stats").exists, "Statistics must be hidden without results")
    }

    // MARK: - Traceroute and WHOIS input validation (nothing is sent)

    @MainActor
    func testTracerouteAndWhoisInputValidation() throws {
        openTool("traceroute", expecting: "traceroute.header")
        let tracerouteHost = element("traceroute.host")
        let tracerouteStart = element("traceroute.start")
        XCTAssertFalse(tracerouteStart.isEnabled)
        tracerouteHost.tap()
        tracerouteHost.typeText("   ")
        XCTAssertFalse(tracerouteStart.isEnabled, "Whitespace-only host must not be accepted")
        tracerouteHost.typeText("127.0.0.1")
        XCTAssertTrue(tracerouteStart.isEnabled)

        openTool("whois", expecting: "whois.header")
        let query = element("whois.query")
        let lookup = element("whois.lookup")
        XCTAssertFalse(lookup.isEnabled)
        query.tap()
        query.typeText("!!")
        XCTAssertFalse(lookup.isEnabled, "Invalid query must not be accepted")

        element("whois.example.ipv4").tap()
        XCTAssertEqual(query.value as? String, "8.8.8.8", "Example button must fill the query")
        XCTAssertTrue(lookup.isEnabled)
    }

    @MainActor
    func testTracerouteToLoopbackReachesDestination() throws {
        openTool("traceroute", expecting: "traceroute.header")
        let host = element("traceroute.host")
        host.tap()
        // Return starts the trace; tapping Start can hit the on-screen keyboard on iPhone in landscape
        host.typeText("127.0.0.1\n")
        XCTAssertTrue(element("traceroute.destination").waitForExistence(timeout: 10), "Loopback must be reached at the first hop")
        XCTAssertTrue(waitForDisappearance(of: element("traceroute.stop"), timeout: 5), "Stop must disappear after the run")
    }

    // MARK: - ARP

    @MainActor
    func testArpTableLoadsWithoutError() throws {
        openTool("arp", expecting: "arp.header")
        let entries = element("arp.entries")
        let empty = element("arp.empty")
        let loaded = NSPredicate { _, _ in entries.exists || empty.exists }
        let expectation = XCTNSPredicateExpectation(predicate: loaded, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed, "ARP table never finished loading")
        XCTAssertFalse(element("arp.error").exists, "ARP refresh must not report an error")
    }

    // MARK: - Helpers

    /// iPhone: the split view is collapsed, so sidebar and detail are never visible together
    private var isCompactLayout: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Opens a tool from the sidebar; on iPhone first navigates back to the sidebar if a tool is shown
    private func openTool(_ tool: String, expecting header: String, file: StaticString = #filePath, line: UInt = #line) {
        // On iOS the Label's identifier lands on both its icon and its text; only the text is hittable
        let row = app.staticTexts.matching(identifier: "sidebar.\(tool)").firstMatch
        if isCompactLayout && !row.waitForExistence(timeout: 1) {
            app.navigationBars.buttons.firstMatch.tap()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Sidebar row \(tool) not reachable", file: file, line: line)
        row.tap()
        XCTAssertTrue(element(header).waitForExistence(timeout: 5), "\(tool) did not open", file: file, line: line)
    }

    /// Static text is exposed as `label` on iOS and as `value` on macOS
    /// First static text starting with the prefix (iOS exposes text as `label`, macOS as `value`)
    private func text(beginningWith prefix: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", prefix, prefix)).firstMatch
    }

    private func wait(for element: XCUIElement, text: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label == %@ OR value == %@", text, text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
