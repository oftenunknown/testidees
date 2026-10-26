import XCTest

/// Launches the app with sample data and screenshots each main screen.
/// CI runs this on iPhone 18 Pro, iPhone 18 Pro Max and iPhone Duo and
/// uploads the screenshots as a build artifact.
final class SnagUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testTourOfScreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        snapshot(app, "01-Today")

        tapTab(app, "Wishlist")
        snapshot(app, "02-Wishlist")
        let firstRow = app.cells.firstMatch
        if firstRow.waitForExistence(timeout: 3) {
            firstRow.tap()
            sleep(1)
            snapshot(app, "03-Product")
        }

        tapTab(app, "Gifts")
        snapshot(app, "04-Gifts")
        let sam = app.staticTexts["Sam"].firstMatch
        if sam.waitForExistence(timeout: 3) {
            if !sam.isHittable { app.swipeUp() }
            sam.tap()
            sleep(2)
            snapshot(app, "05-Recipient")
        }

        tapTab(app, "Perks")
        snapshot(app, "06-Perks")

        tapTab(app, "Scan")
        sleep(1)
        snapshot(app, "07-Scan")
        let sample = app.buttons["Nutella 400g"].firstMatch
        if sample.waitForExistence(timeout: 3) {
            sample.tap()
            sleep(6)
            snapshot(app, "08-Scan-Result")
        }

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        snapshot(app, "09-Landscape")
        XCUIDevice.shared.orientation = .portrait
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
        sleep(1)
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        // The screen (not the app element) captures rotated layouts correctly.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
