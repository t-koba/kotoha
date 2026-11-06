import UIKit
import XCTest

// Simulator XCUI tree and synthesized input only: no VoiceOver speech/gestures,
// physical devices/keyboards, or OS task-switcher thumbnail validation. Widget tests
// own direction/caret policy and the complete forward/reverse Flutter focus order.
final class LanguageFieldAccessibilityTests: XCTestCase {
  private let app = XCUIApplication()
  // Test policy default, overridable in the Runner scheme/build setting.
  private var timeout: TimeInterval = 10

  override func setUpWithError() throws {
    continueAfterFailure = false
    let configured = ProcessInfo.processInfo.environment["KOTOHA_AX_TIMEOUT_SECONDS"] ?? ""
    if !configured.isEmpty {
      timeout = try XCTUnwrap(Double(configured), "Invalid accessibility wait budget")
    }
    XCTAssertTrue(timeout > 0 && timeout.isFinite)
    // Keep OS edit-menu labels deterministic; change the app locale through its UI.
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
  }

  override func tearDownWithError() throws {
    UIPasteboard.general.items = [] // Only synthetic test text was placed here.
    app.terminate()
  }

  func testEnglishLanguageFields() {
    checkLocale("English", source: "Source language", sourceText: "Source text",
                target: "Target language", translation: "Manual translation")
  }

  func testJapaneseLanguageFields() {
    checkLocale("日本語", source: "原文の言語", sourceText: "原文",
                target: "訳先の言語", translation: "手入力した訳文")
  }

  private func checkLocale(_ locale: String, source: String, sourceText: String,
                           target: String, translation: String) {
    let menu = app.buttons["Interface language"]
    XCTAssertTrue(menu.waitForExistence(timeout: timeout))
    menu.tap()
    let choice = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", locale)).firstMatch
    XCTAssertTrue(choice.waitForExistence(timeout: timeout))
    choice.tap()
    checkField(source, nextField: sourceText)
    checkField(target, nextField: translation)
  }

  private func field(_ label: String) -> XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(
      format: "label == %@ AND (elementType == %d OR elementType == %d)", label,
      XCUIElement.ElementType.textField.rawValue,
      XCUIElement.ElementType.textView.rawValue)).firstMatch
  }

  private func reveal(_ label: String) -> XCUIElement {
    let element = field(label)
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if element.exists && element.isHittable { return element }
      // Ordinary UI scrolling, not a VoiceOver gesture. Drag in the content viewport,
      // above the software keyboard if present.
      let bottom = app.keyboards.firstMatch.exists
        ? app.keyboards.firstMatch.frame.minY : app.frame.maxY
      let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
        .withOffset(CGVector(dx: 0, dy: bottom - app.frame.minY - 20))
      let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
      start.press(forDuration: 0.15, thenDragTo: end)
    }
    XCTFail("Native editable field unavailable after scrolling: \(label)")
    return element
  }

  private func assertField(_ label: String, value: String) {
    let element = field(label) // Re-query XCUI after every dynamic rebuild.
    let state = NSPredicate(format: "exists == true AND enabled == true AND value == %@", value)
    let expectation = XCTNSPredicateExpectation(predicate: state, object: element)
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                   "Expected native field \(label) value=\(value); tree: \(app.debugDescription)")
    XCTAssertEqual(element.label, label)
  }

  private func checkField(_ label: String, nextField: String) {
    let element = reveal(label)
    element.tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: timeout))
    // Use the public Paste UI for Arabic: typeText cannot synthesize every Unicode
    // character on an English software keyboard. Only synthetic text; no app test hook.
    UIPasteboard.general.string = "العربية"
    element.press(forDuration: 1)
    let paste = app.descendants(matching: .any).matching(NSPredicate(
      format: "label == 'Paste' AND (elementType == %d OR elementType == %d)",
      XCUIElement.ElementType.menuItem.rawValue,
      XCUIElement.ElementType.button.rawValue)).firstMatch
    XCTAssertTrue(paste.waitForExistence(timeout: timeout))
    paste.tap()
    assertField(label, value: "العربية")

    // No re-tap throughout the direction change: typing, deleting the known RTL
    // value at its insertion point, and typing Latin must keep the same input focus.
    // This is input-focus evidence, not VoiceOver/accessibility focus.
    app.typeText("x")
    assertField(label, value: "العربيةx")
    app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "العربيةx".count))
    app.typeText("Latin")
    assertField(label, value: "Latin")
    app.typeText("x")
    assertField(label, value: "Latinx")
    // Tap the next native field and verify it receives keyboard input. Flutter widget
    // tests separately cover keyboard traversal order; iPhone XCUI has no Tab key API.
    let destination = reveal(nextField)
    destination.tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: timeout))
    app.typeText("z")
    assertField(nextField, value: "z")
    assertField(label, value: "Latinx")
  }
}
