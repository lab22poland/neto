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
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Verify the app launches successfully
        XCTAssertTrue(app.exists)
        
        // Check that the main navigation title exists
        let navigationTitle = app.navigationBars["NETo"]
        XCTAssertTrue(navigationTitle.waitForExistence(timeout: 5.0))
    }

    @MainActor
    func testNavigationElements() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Test that main navigation elements exist
        let navigationBar = app.navigationBars["NETo"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 5.0))
        
        // Check for tool list items
        let pingTool = app.staticTexts["Ping"]
        let aboutTool = app.staticTexts["About"]
        
        XCTAssertTrue(pingTool.waitForExistence(timeout: 3.0))
        XCTAssertTrue(aboutTool.waitForExistence(timeout: 3.0))
    }

    @MainActor
    func testPingToolNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to Ping tool
        let pingTool = app.staticTexts["Ping"]
        XCTAssertTrue(pingTool.waitForExistence(timeout: 5.0))
        pingTool.tap()
        
        // Check that ping view elements exist
        let pingTitle = app.staticTexts["Ping Tool"]
        XCTAssertTrue(pingTitle.waitForExistence(timeout: 3.0))
        
        let targetHostLabel = app.staticTexts["Target Host"]
        XCTAssertTrue(targetHostLabel.waitForExistence(timeout: 2.0))
        
        // Check for input field
        let textField = app.textFields.firstMatch
        XCTAssertTrue(textField.waitForExistence(timeout: 2.0))
        
        // Check for ping button
        let pingButton = app.buttons["Send 5 Ping Packets"]
        XCTAssertTrue(pingButton.waitForExistence(timeout: 2.0))
    }

    @MainActor
    func testPingToolInput() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to Ping tool
        let pingTool = app.staticTexts["Ping"]
        XCTAssertTrue(pingTool.waitForExistence(timeout: 5.0))
        pingTool.tap()
        
        // Find and interact with the text field
        let textField = app.textFields.firstMatch
        XCTAssertTrue(textField.waitForExistence(timeout: 3.0))
        
        // Test input
        textField.tap()
        textField.typeText("8.8.8.8")
        
        // Verify the text was entered
        XCTAssertEqual(textField.value as? String, "8.8.8.8")
        
        // Check that ping button is now enabled (not disabled)
        let pingButton = app.buttons["Send 5 Ping Packets"]
        XCTAssertTrue(pingButton.isEnabled)
    }

    @MainActor
    func testPingButtonStates() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to Ping tool
        let pingTool = app.staticTexts["Ping"]
        XCTAssertTrue(pingTool.waitForExistence(timeout: 5.0))
        pingTool.tap()
        
        // Initially, ping button should be disabled (empty input)
        let pingButton = app.buttons["Send 5 Ping Packets"]
        XCTAssertTrue(pingButton.waitForExistence(timeout: 3.0))
        XCTAssertFalse(pingButton.isEnabled)
        
        // Enter text to enable button
        let textField = app.textFields.firstMatch
        textField.tap()
        textField.typeText("google.com")
        
        // Button should now be enabled
        XCTAssertTrue(pingButton.isEnabled)
        
        // Clear text field
        textField.tap()
        textField.buttons["Clear text"].tap()
        
        // Button should be disabled again
        XCTAssertFalse(pingButton.isEnabled)
    }

    @MainActor
    func testAboutPageNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to About page
        let aboutTool = app.staticTexts["About"]
        XCTAssertTrue(aboutTool.waitForExistence(timeout: 5.0))
        aboutTool.tap()
        
        // Check that about page content exists
        let aboutTitle = app.staticTexts["NETo"]
        XCTAssertTrue(aboutTitle.waitForExistence(timeout: 3.0))
        
        let subtitle = app.staticTexts["Network Engineer Tools"]
        XCTAssertTrue(subtitle.waitForExistence(timeout: 2.0))
        
        let version = app.staticTexts["Version 1.0"]
        XCTAssertTrue(version.waitForExistence(timeout: 2.0))
        
        let copyright = app.staticTexts["© 2025 Lab22 Poland Sp. z o.o."]
        XCTAssertTrue(copyright.waitForExistence(timeout: 2.0))
    }

    @MainActor
    func testAboutPageContent() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to About page
        let aboutTool = app.staticTexts["About"]
        aboutTool.tap()
        
        // Check for specific content sections
        let aboutSection = app.staticTexts["About NETo"]
        XCTAssertTrue(aboutSection.waitForExistence(timeout: 3.0))
        
        let currentToolsSection = app.staticTexts["Current Tools"]
        XCTAssertTrue(currentToolsSection.waitForExistence(timeout: 2.0))
        
        let platformSupportSection = app.staticTexts["Platform Support"]
        XCTAssertTrue(platformSupportSection.waitForExistence(timeout: 2.0))
        
        let technologiesSection = app.staticTexts["Technologies"]
        XCTAssertTrue(technologiesSection.waitForExistence(timeout: 2.0))
    }

    @MainActor
    func testNavigationBetweenTools() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Start with Ping tool
        let pingTool = app.staticTexts["Ping"]
        pingTool.tap()
        
        let pingTitle = app.staticTexts["Ping Tool"]
        XCTAssertTrue(pingTitle.waitForExistence(timeout: 3.0))
        
        // Navigate to About
        let aboutTool = app.staticTexts["About"]
        aboutTool.tap()
        
        let aboutTitle = app.staticTexts["NETo"]
        XCTAssertTrue(aboutTitle.waitForExistence(timeout: 3.0))
        
        // Navigate back to Ping
        pingTool.tap()
        XCTAssertTrue(pingTitle.waitForExistence(timeout: 3.0))
    }

    @MainActor
    func testKeyboardInteraction() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to Ping tool
        let pingTool = app.staticTexts["Ping"]
        pingTool.tap()
        
        // Interact with text field
        let textField = app.textFields.firstMatch
        textField.tap()
        
        // Type and verify
        textField.typeText("example.com")
        XCTAssertEqual(textField.value as? String, "example.com")
        
        // Test return key behavior
        app.keyboards.buttons["return"].tap()
        
        // The ping button should still be enabled
        let pingButton = app.buttons["Send 5 Ping Packets"]
        XCTAssertTrue(pingButton.isEnabled)
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
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testMemoryUsage() throws {
        let app = XCUIApplication()
        
        measure(metrics: [XCTMemoryMetric()]) {
            app.launch()
            
            // Navigate through different views
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
