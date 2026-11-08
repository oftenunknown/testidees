import XCTest

/// Launches with demo data and screenshots the main screens and every story
/// page. CI runs this on iPhone 18 Pro, iPhone 18 Pro Max, iPhone Duo (outer
/// display) and iPad mini (a stand-in for the Duo's unfolded inner display),
/// and uploads the screenshots as a build artifact.
final class OdysseyUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testTour() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let play = app.buttons["play-recap"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 15), "Recap didn't load")
        sleep(1)
        snapshot("01-Recap")

        // Story: every page, after its entrance animation settles.
        play.tap()
        sleep(3)
        for index in 0..<15 {
            snapshot(String(format: "10-Story-%02d", index))
            guard index < 14 else { break }
            // Tap the right-hand side to advance (left side goes back).
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45)).tap()
            sleep(3)
        }
        // Landscape spread on phones.
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        snapshot("30-Story-Landscape")
        XCUIDevice.shared.orientation = .portrait
        sleep(2)

        let close = app.buttons["story-close"].firstMatch
        if close.waitForExistence(timeout: 3) { close.tap() }
        sleep(1)

        // Range: a quarter.
        let quarter = app.segmentedControls.buttons["Quarter"].firstMatch
        if quarter.waitForExistence(timeout: 3) {
            quarter.tap()
            sleep(2)
            snapshot("02-Recap-Quarter")
            app.segmentedControls.buttons["Year"].firstMatch.tap()
            sleep(2)
        }

        tapTab(app, "Insights")
        sleep(2)
        snapshot("03-Insights")
        app.swipeUp()
        sleep(1)
        snapshot("04-Insights-2")
        app.swipeUp()
        sleep(1)
        snapshot("05-Insights-3")

        tapTab(app, "Crew")
        sleep(2)
        snapshot("06-Crew")

        // Share studio: card preview, then a rendered long image.
        tapTab(app, "Recap")
        let share = app.buttons["home-share"].firstMatch
        if share.waitForExistence(timeout: 3) {
            share.tap()
            sleep(3)
            snapshot("07-Share-Card")
            let create = app.buttons["export-create"].firstMatch
            if create.waitForExistence(timeout: 3) {
                create.tap()
                _ = app.buttons["export-share"].firstMatch.waitForExistence(timeout: 20)
                snapshot("08-Share-Card-Ready")
            }
            let long = app.segmentedControls.buttons.element(boundBy: 1)
            if long.exists {
                long.tap()
                sleep(4)
                snapshot("09-Share-Long")
            }
        }
    }

    @MainActor
    private func tapTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.tabBars.buttons[name].firstMatch
        if tab.waitForExistence(timeout: 2) {
            tab.tap()
        } else {
            // Sidebar or vertical bar layouts expose tabs as plain buttons.
            let button = app.buttons[name].firstMatch
            if button.waitForExistence(timeout: 2) { button.tap() }
        }
    }

    @MainActor
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
