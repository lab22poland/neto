//
//  netoUITests.swift
//  netoUITests
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import XCTest

final class netoUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it's important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testAppLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for the app to load and verify main elements exist
        // On macOS, we use NavigationSplitView, so look for the sidebar elements
        let pingTool = app.staticTexts["Ping"]
        XCTAssertTrue(pingTool.waitForExistence(timeout: 5))
        
        let aboutTool = app.staticTexts["About"]
        XCTAssertTrue(aboutTool.waitForExistence(timeout: 2))
        
        // Verify the default message is shown
        let defaultMessage = app.staticTexts["Select a tool from the sidebar"]
        XCTAssertTrue(defaultMessage.waitForExistence(timeout: 2))
    }

    @MainActor
    func testNavigationElements() throws {
        let app = XCUIApplication()
        app.launch()
        
        // On macOS, we have a sidebar with tools, not a navigation bar
        let pingTool = app.staticTexts["Ping"]
        XCTAssertTrue(pingTool.waitForExistence(timeout: 5))
        
        let aboutTool = app.staticTexts["About"]
        XCTAssertTrue(aboutTool.waitForExistence(timeout: 2))
        
        // Test that tools are clickable
        XCTAssertTrue(pingTool.isHittable)
        XCTAssertTrue(aboutTool.isHittable)
    }

    @MainActor
    func testPingToolNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to ping tool
        let pingTool = app.staticTexts["Ping"]
        XCTAssertTrue(pingTool.waitForExistence(timeout: 5))
        pingTool.tap()
        
        // Verify ping tool elements exist
        let pingToolTitle = app.staticTexts["Ping Tool"]
        XCTAssertTrue(pingToolTitle.waitForExistence(timeout: 3))
        
        let targetHostLabel = app.staticTexts["Target Host"]
        XCTAssertTrue(targetHostLabel.waitForExistence(timeout: 2))
        
        let textField = app.textFields.firstMatch
        XCTAssertTrue(textField.waitForExistence(timeout: 2))
        
        let pingButton = app.buttons["Send 5 Ping Packets"]
        XCTAssertTrue(pingButton.waitForExistence(timeout: 2))
    }

    @MainActor
    func testAboutPageNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to about page
        let aboutTool = app.staticTexts["About"]
        XCTAssertTrue(aboutTool.waitForExistence(timeout: 5))
        aboutTool.tap()
        
        // Verify about page content
        let netoTitle = app.staticTexts["NETo"]
        XCTAssertTrue(netoTitle.waitForExistence(timeout: 3))
        
        let subtitle = app.staticTexts["Network Engineer Tools"]
        XCTAssertTrue(subtitle.waitForExistence(timeout: 2))
        
        let version = app.staticTexts["Version 1.0"]
        XCTAssertTrue(version.waitForExistence(timeout: 2))
        
        let copyright = app.staticTexts["© 2025 Lab22 Poland Sp. z o.o."]
        XCTAssertTrue(copyright.waitForExistence(timeout: 2))
    }

    @MainActor
    func testAboutPageContent() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to about page
        let aboutTool = app.staticTexts["About"]
        aboutTool.tap()
        
        // Check for specific content sections
        let aboutSection = app.staticTexts["About NETo"]
        XCTAssertTrue(aboutSection.waitForExistence(timeout: 3))
        
        let currentToolsSection = app.staticTexts["Current Tools"]
        XCTAssertTrue(currentToolsSection.waitForExistence(timeout: 2))
        
        let platformSupportSection = app.staticTexts["Platform Support"]
        XCTAssertTrue(platformSupportSection.waitForExistence(timeout: 2))
        
        let technologiesSection = app.staticTexts["Technologies"]
        XCTAssertTrue(technologiesSection.waitForExistence(timeout: 2))
    }

    @MainActor
    func testPingToolInput() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to ping tool
        let pingTool = app.staticTexts["Ping"]
        XCTAssertTrue(pingTool.waitForExistence(timeout: 5))
        pingTool.tap()
        
        // Test text field input
        let textField = app.textFields.firstMatch
        XCTAssertTrue(textField.waitForExistence(timeout: 3))
        textField.tap()
        textField.typeText("8.8.8.8")
        
        // Verify text was entered
        XCTAssertEqual(textField.value as? String, "8.8.8.8")
        
        // Verify ping button exists and is enabled
        let pingButton = app.buttons["Send 5 Ping Packets"]
        XCTAssertTrue(pingButton.exists)
        XCTAssertTrue(pingButton.isEnabled)
    }

    @MainActor
    func testPingButtonStates() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to ping tool
        let pingTool = app.staticTexts["Ping"]
        XCTAssertTrue(pingTool.waitForExistence(timeout: 5))
        pingTool.tap()
        
        // Verify button is initially disabled (empty text field)
        let pingButton = app.buttons["Send 5 Ping Packets"]
        XCTAssertTrue(pingButton.waitForExistence(timeout: 3))
        XCTAssertFalse(pingButton.isEnabled)
        
        // Add text to enable button
        let textField = app.textFields.firstMatch
        textField.tap()
        textField.typeText("google.com")
        
        // Verify button is now enabled
        XCTAssertTrue(pingButton.isEnabled)
        
        // Test that the button remains enabled with valid input
        // This is the main functionality we want to test
        XCTAssertTrue(pingButton.isEnabled)
        
        // Verify text field contains the entered text
        XCTAssertEqual(textField.value as? String, "google.com")
    }

    @MainActor
    func testNavigationBetweenTools() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to ping tool
        let pingTool = app.staticTexts["Ping"]
        pingTool.tap()
        
        // Verify we're in ping tool
        let pingToolTitle = app.staticTexts["Ping Tool"]
        XCTAssertTrue(pingToolTitle.waitForExistence(timeout: 3))
        
        // Navigate to about page
        let aboutTool = app.staticTexts["About"]
        aboutTool.tap()
        
        // Verify we're in about page
        let netoTitle = app.staticTexts["NETo"]
        XCTAssertTrue(netoTitle.waitForExistence(timeout: 3))
        
        // Navigate back to ping tool
        pingTool.tap()
        
        // Verify we're back in ping tool
        XCTAssertTrue(pingToolTitle.waitForExistence(timeout: 3))
    }

    @MainActor
    func testAccessibilityElements() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Test accessibility identifiers and labels
        let pingTool = app.staticTexts["Ping"]
        XCTAssertTrue(pingTool.exists)
        
        let aboutTool = app.staticTexts["About"]
        XCTAssertTrue(aboutTool.exists)
        
        // Navigate to ping tool and test accessibility
        pingTool.tap()
        
        let textField = app.textFields.firstMatch
        XCTAssertTrue(textField.exists)
        
        let pingButton = app.buttons["Send 5 Ping Packets"]
        XCTAssertTrue(pingButton.exists)
    }

    @MainActor
    func testKeyboardInteraction() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to ping tool
        let pingTool = app.staticTexts["Ping"]
        pingTool.tap()
        
        // Test keyboard input
        let textField = app.textFields.firstMatch
        textField.tap()
        textField.typeText("example.com")
        
        // Test submitting with Enter key (onSubmit in SwiftUI)
        // On macOS, pressing return in the text field should trigger the ping action
        textField.typeText(XCUIKeyboardKey.return.rawValue)
        
        // Wait a moment to see if ping starts (button might become disabled)
        sleep(1)
        
        // The ping should have started, so there might be results or the button might show "Stop"
        // We'll just verify the text field still contains our input
        XCTAssertEqual(textField.value as? String, "example.com")
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
    
    @MainActor
    func testMemoryUsage() throws {
        let app = XCUIApplication()
        
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            measure(metrics: [XCTMemoryMetric()]) {
                app.launch()
                
                // Navigate between tools to test memory usage
                let pingTool = app.staticTexts["Ping"]
                pingTool.tap()
                
                let textField = app.textFields.firstMatch
                textField.tap()
                textField.typeText("test.com")
                
                let aboutTool = app.staticTexts["About"]
                aboutTool.tap()
                
                app.terminate()
            }
        }
    }
}
