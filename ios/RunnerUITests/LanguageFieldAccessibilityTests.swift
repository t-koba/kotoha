import UIKit
import XCTest

// Simulator XCUI tree and synthesized input only: no VoiceOver speech/gestures,
// physical devices/keyboards, or OS task-switcher thumbnail validation. Widget tests
// own direction/caret policy and the complete forward/reverse Flutter focus order.
final class LanguageFieldAccessibilityTests: XCTestCase {
  private let app = XCUIApplication()
  private static let bidiFormattingControls: Set<UInt32> = [
    0x061C, 0x200E, 0x200F,
    0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
    0x2066, 0x2067, 0x2068, 0x2069,
  ]
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

  func testImportChannelPresentsSystemPickerAndCancellationKeepsDraft() {
    // Real Dart -> implicit-engine channel -> active-scene UIKit presentation.
    // No fixture is selected here: provider read/scope paths are unit-tested separately.
    let source = reveal("source-text")
    source.tap()
    app.typeText("unsaved source")
    for _ in 0..<2 {
      let importButton = app.buttons["Import text or Markdown"]
      if !importButton.isHittable { app.swipeDown() }
      XCTAssertTrue(importButton.waitForExistence(timeout: timeout))
      importButton.tap()
      let cancel = app.buttons["Cancel"]
      XCTAssertTrue(cancel.waitForExistence(timeout: timeout), "System document picker must be presented")
      cancel.tap()
      assertField("source-text", label: "Source text", value: "unsaved source")
    }
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
    checkField("source-language", label: source, nextID: "source-text", nextLabel: sourceText)
    checkField("target-language-0", label: target, nextID: "translation-text-0",
               nextLabel: translation)
  }

  // A focused empty field can include its example hint in the label. Locate by
  // identity instead; assert the localized label separately after entering text.
  private func field(_ id: String) -> XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(
      format: "identifier == %@ AND (elementType == %d OR elementType == %d)", id,
      XCUIElement.ElementType.textField.rawValue,
      XCUIElement.ElementType.textView.rawValue)).firstMatch
  }

  private func hasUsableFrame(_ frame: CGRect) -> Bool {
    return frame.origin.x.isFinite && frame.origin.y.isFinite
      && frame.width.isFinite && frame.height.isFinite
      && frame.width > 0 && frame.height > 0
  }

  private func reveal(_ id: String) -> XCUIElement {
    let deadline = Date().addingTimeInterval(timeout)
    var swipes = 0
    while Date() < deadline {
      // Re-resolve the field after every scroll; direction changes can replace its
      // native semantics node. Do not retain a recycled ScrollView or target.
      let element = field(id)
      let targetFrame = element.exists ? element.frame : .null
      if hasUsableFrame(targetFrame) && element.isHittable { return element }

      let appFrame = app.frame
      guard hasUsableFrame(appFrame) else { break }
      let keyboard = app.keyboards.firstMatch
      let keyboardExists = keyboard.exists
      let keyboardFrame = keyboardExists ? keyboard.frame : .null
      // Never fall back to a full-window gesture over a keyboard with unknown bounds.
      guard !keyboardExists || hasUsableFrame(keyboardFrame) else { break }
      let top = appFrame.minY + 8
      // The app-level coordinates are clipped above the software keyboard. The
      // editor ListView dismisses the keyboard on drag, then scrolls its content.
      let bottom = min(
        appFrame.maxY - 8,
        keyboardFrame.isNull ? appFrame.maxY - 8 : keyboardFrame.minY - 8)
      let height = bottom - top
      guard height > 48 else { break }

      let midpoint = (top + bottom) / 2
      let swipeUp = !hasUsableFrame(targetFrame) || targetFrame.midY >= midpoint
      let distance = min(240, height * 0.6)
      // Start inside the available region, away from the status bar/window edges.
      let startY = top + height * (swipeUp ? 0.8 : 0.2)
      let endY = swipeUp ? max(top, startY - distance) : min(bottom, startY + distance)
      let start = app.coordinate(withNormalizedOffset: CGVector(
        dx: 0.5, dy: (startY - appFrame.minY) / appFrame.height))
      let end = app.coordinate(withNormalizedOffset: CGVector(
        dx: 0.5, dy: (endY - appFrame.minY) / appFrame.height))
      start.press(forDuration: 0.05, thenDragTo: end)
      swipes += 1
    }

    let current = field(id)
    let keyboard = app.keyboards.firstMatch
    let targetExists = current.exists
    XCTFail(
      "Native editable field unavailable after targeted scrolling: \(id); "
        + "swipes=\(swipes), app=\(String(describing: app.frame)), "
        + "keyboard=\(keyboard.exists ? String(describing: keyboard.frame) : "<absent>"), "
        + "targetExists=\(targetExists), "
        + "target=\(targetExists ? String(describing: current.frame) : "<absent>"), "
        + "hittable=\(targetExists && current.isHittable)")
    return current
  }

  private func assertField(_ id: String, label: String, value: String) {
    let expected = Self.withoutBidiFormattingControls(value)
    let state = NSPredicate { [self] _, _ in
      // Resolve the identity on each poll; Flutter can replace its semantics node
      // when the field direction changes from RTL to LTR.
      matchesField(field(id), label: label, expected: expected)
    }
    let expectation = XCTNSPredicateExpectation(predicate: state, object: nil)
    let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
    guard result == .completed else {
      // XCTest may stop waiting for reasons other than timeout even after the
      // UI reaches the expected state. Check one fresh snapshot without polling
      // again; the exact label/value remains the acceptance condition.
      let current = field(id)
      if matchesField(current, label: label, expected: expected) {
        return
      }
      // Keep failure details bounded while preserving scalar-level clues.
      let actual = current.value as? String
      let scalarPrefix = actual.map { text in
        text.unicodeScalars.prefix(32)
          .map { String($0.value, radix: 16) }
          .joined(separator: " ")
      } ?? "<non-string>"
      let scalarCount = actual?.unicodeScalars.count ?? 0
      let valueType = current.value.map { String(describing: type(of: $0)) } ?? "nil"
      XCTFail(
        "Expected native field \(label) value=\(value); wait=\(result). "
          + "Post-wait observation: exists=\(current.exists), enabled=\(current.isEnabled), "
          + "label=\(current.label), valueType=\(valueType), "
          + "scalarPrefix=[\(scalarPrefix)], scalarCount=\(scalarCount)")
      return
    }
  }

  private func matchesField(_ current: XCUIElement, label: String, expected: String) -> Bool {
    guard current.exists, current.isEnabled,
          let actual = current.value as? String else { return false }
    // Some native accessibility bridges include bidi formatting controls in the
    // exposed value. They change presentation, not the underlying editor text; the
    // Flutter tests independently assert exact controller contents.
    return current.label == label
      && Self.withoutBidiFormattingControls(actual) == expected
  }

  private static func withoutBidiFormattingControls(_ text: String) -> String {
    let scalars = text.unicodeScalars.filter {
      !bidiFormattingControls.contains($0.value)
    }
    return String(String.UnicodeScalarView(scalars))
  }

  private func checkField(_ id: String, label: String, nextID: String, nextLabel: String) {
    let element = reveal(id)
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
    assertField(id, label: label, value: "العربية")

    // No re-tap through the RTL-to-LTR edit: delete the known RTL value, then type
    // Latin. The exact final value checks input focus survived both direction rebuilds.
    // This is input-focus evidence, not VoiceOver/accessibility focus.
    app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "العربية".count))
    app.typeText("Latin")
    assertField(id, label: label, value: "Latin")
    // Tap the next native field and verify it receives keyboard input. Flutter widget
    // tests separately cover keyboard traversal order; iPhone XCUI has no Tab key API.
    let destination = reveal(nextID)
    destination.tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: timeout))
    app.typeText("z")
    assertField(nextID, label: nextLabel, value: "z")
    assertField(id, label: label, value: "Latin")
  }
}
