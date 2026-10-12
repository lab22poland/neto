//
//  NetworkToolTests.swift
//  netoTests
//
//  Created by Sergii Solianyk on 12/10/2026.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import Testing
@testable import neto
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct NetworkToolTests {

    @Test(arguments: NetworkTool.allCases)
    func sidebarIconExists(_ tool: NetworkTool) {
        #if os(macOS)
        #expect(NSImage(systemSymbolName: tool.icon, accessibilityDescription: nil) != nil, "unknown SF Symbol \(tool.icon)")
        #else
        #expect(UIImage(systemName: tool.icon) != nil, "unknown SF Symbol \(tool.icon)")
        #endif
    }
}

struct AboutTests {

    @Test func versionComesFromTheBundle() {
        #expect(AboutView.versionText(["CFBundleShortVersionString": "1.2", "CFBundleVersion": "34"]) == "Version 1.2 (34)")
        #expect(AboutView.versionText(["CFBundleShortVersionString": "1.2", "CFBundleVersion": "1.2"]) == "Version 1.2")
        #expect(AboutView.versionText(["CFBundleShortVersionString": "1.2"]) == "Version 1.2")
        #expect(AboutView.versionText(nil) == "Version unknown")
    }
}
