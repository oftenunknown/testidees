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
        sleep(2)
        for index in 0..<15 {
            snapshot(String(format: "10-Story-%02d", index))
            guard index < 14 else { break }
            // Tap right of centre to advance (the left quarter goes back). Not the far
            // right: on iPhone Duo's outer display that's the system's vertical bar.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).tap()
            sleep(1)
        }
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
            let long = app.segmentedControls["export-format"].buttons.element(boundBy: 1)
            if long.exists {
                long.tap()
                sleep(4)
                snapshot("09-Share-Long")
            }
            app.buttons["Close"].firstMatch.tap()
            sleep(1)
        }

        // Last, because rotating can unsettle some layouts (the Duo's outer display
        // doesn't rotate at all): the story as a two-page spread in landscape.
        if play.waitForExistence(timeout: 3) {
            play.tap()
            sleep(2)
            XCUIDevice.shared.orientation = .landscapeLeft
            sleep(3)
            snapshot("30-Story-Landscape")
            XCUIDevice.shared.orientation = .portrait
        }
    }

    @MainActor
    private func tapTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.tabBars.buttons[name].firstMatch
        if tab.waitForExistence(timeout: 2), tab.isHittable {
            tab.tap()
            return
        }
        // Sidebar, top tab bar and the Duo's vertical bar expose tabs as plain buttons.
        let button = app.buttons[name].firstMatch
        if button.waitForExistence(timeout: 2), button.isHittable {
            button.tap()
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
