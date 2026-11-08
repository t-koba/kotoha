import XCTest

final class NativeExportPanelUITests: XCTestCase {
  private let app = XCUIApplication()
  private var panelTimeout: TimeInterval = 0

  override func setUpWithError() throws {
    continueAfterFailure = false
    guard let raw = ProcessInfo.processInfo.environment["KOTOHA_PANEL_TIMEOUT_SECONDS"],
          let timeout = Double(raw), timeout.isFinite, timeout > 0, timeout <= 30 else {
      throw NSError(domain: "NativeExportPanelUITests", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing bounded panel timeout"])
    }
    panelTimeout = timeout
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
  }

  override func tearDownWithError() throws {
    app.terminate()
  }

  func testNativeSavePanelIsAccessibleAndCancelPreservesDraft() {
    let translation = "macOS panel probe"
    let field = app.descendants(matching: .any).matching(NSPredicate(
      format: "identifier == %@ AND (elementType == %d OR elementType == %d)",
      "translation-text-0",
      XCUIElement.ElementType.textField.rawValue,
      XCUIElement.ElementType.textView.rawValue)).firstMatch
    // The translation editor is below the initial viewport. On macOS the
    // accessibility node may not exist until its ListView region is revealed.
    let deadline = Date().addingTimeInterval(panelTimeout)
    var scrolls = 0
    while Date() < deadline && (!field.exists || !field.isHittable) {
      // Flutter's workspace is not exposed as an XCUI ScrollView on this host.
      // Swipe the application window instead of waiting for a missing semantics node.
      app.swipeUp()
      scrolls += 1
    }
    XCTAssertTrue(
      field.exists,
      "Translation field is unavailable after \(scrolls) scrolls")
    XCTAssertTrue(
      field.isHittable,
      "Translation field is not hittable after \(scrolls) scrolls")
    field.click()
    field.typeText(translation)

    let exportButton = app.buttons["Export translation 1"]
    XCTAssertTrue(
      exportButton.waitForExistence(timeout: panelTimeout),
      "Export action is unavailable")
    exportButton.click()

    let panelExport = app.buttons["Export"]
    let panelCancel = app.buttons["Cancel"]
    XCTAssertTrue(panelExport.waitForExistence(timeout: panelTimeout),
                  "Native save panel Export button was not exposed to XCUI")
    XCTAssertTrue(panelCancel.waitForExistence(timeout: panelTimeout),
                  "Native save panel Cancel button was not exposed to XCUI")
    panelCancel.click()

    XCTAssertTrue(
      field.waitForExistence(timeout: panelTimeout),
      "Translation field disappeared after cancellation")
    XCTAssertTrue((field.value as? String) == translation,
                  "Cancellation did not preserve the translation draft")
  }
}
