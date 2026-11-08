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

  // Keep each locale/field sequence within the existing per-test execution budget.
  func testEnglishSourceLanguageField() {
    selectLocale("English")
    checkField("source-language", label: "Source language", nextID: "source-text",
               nextLabel: "Source text")
  }

  func testEnglishTargetLanguageField() {
    selectLocale("English")
    checkField("target-language-0", label: "Target language", nextID: "translation-text-0",
               nextLabel: "Manual translation")
  }

  func testJapaneseSourceLanguageField() {
    selectLocale("日本語")
    checkField("source-language", label: "原文の言語", nextID: "source-text", nextLabel: "原文")
  }

  func testJapaneseTargetLanguageField() {
    selectLocale("日本語")
    checkField("target-language-0", label: "訳先の言語", nextID: "translation-text-0",
               nextLabel: "手入力した訳文")
  }

  func testImportChannelPresentsSystemPickerAndCancellationKeepsDraft() {
    // Real Dart -> implicit-engine channel -> active-scene UIKit presentation.
    // No fixture is selected here: provider read/scope paths are unit-tested separately.
    let source = reveal("source-text")
    source.tap()
    app.typeText("unsaved source")
    for round in 1...2 {
      let importButton = app.buttons["Import text or Markdown"]
      if !importButton.isHittable { app.swipeDown() }
      XCTAssertTrue(importButton.waitForExistence(timeout: timeout))
      let beforeTap = "enabled=\(importButton.isEnabled), hittable=\(importButton.isHittable)"
      importButton.tap()
      let cancel = app.buttons["Cancel"]
      guard cancel.waitForExistence(timeout: timeout) else {
        // Bounded state only: never log picker contents, UI trees or draft text.
        let importerExists = importButton.exists
        let errorNotice = app.descendants(matching: .any).matching(NSPredicate(
          format: "label == %@",
          "Could not import this document. Choose a UTF-8 .txt, .md, or .markdown file.")).firstMatch.exists
        XCTFail("System document picker must be presented; round=\(round), "
          + "beforeTap=[\(beforeTap)], importerExists=\(importerExists), "
          + "enabled=\(importerExists && importButton.isEnabled), "
          + "hittable=\(importerExists && importButton.isHittable), errorNotice=\(errorNotice), "
          + "alerts=\(app.alerts.count), cancelButtons=\(app.buttons.matching(identifier: "Cancel").count), "
          + "cancelElements=\(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Cancel'")).count)")
        return
      }
      cancel.tap()
      assertField("source-text", label: "Source text", value: "unsaved source")
    }
  }

  private func selectLocale(_ locale: String) {
    let menu = app.buttons["Interface language"]
    XCTAssertTrue(menu.waitForExistence(timeout: timeout))
    menu.tap()
    let choice = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", locale)).firstMatch
    XCTAssertTrue(choice.waitForExistence(timeout: timeout))
    choice.tap()
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
    if current.exists && hasUsableFrame(current.frame) && current.isHittable {
      return current
    }
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
    let state = NSPredicate { [self] _, _ in
      // Resolve the identity on each poll; Flutter can replace its semantics node
      // when the field direction changes from RTL to LTR.
      matchesField(field(id), label: label, expected: value)
    }
    let expectation = XCTNSPredicateExpectation(predicate: state, object: nil)
    let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
    guard result == .completed else {
      // XCTest may stop waiting for reasons other than timeout even after the
      // UI reaches the expected state. Check one fresh snapshot without polling
      // again; the exact label/value remains the acceptance condition.
      let current = field(id)
      if matchesField(current, label: label, expected: value) {
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
      let focusedField = app.descendants(matching: .any).matching(NSPredicate(
        format: "identifier == %@ AND hasKeyboardFocus == 1", id)).firstMatch
      let keyboardVisible = app.keyboards.firstMatch.exists
      XCTFail(
        "Expected native field \(label) value=\(value); wait=\(result). "
          + "Post-wait observation: exists=\(current.exists), enabled=\(current.isEnabled), "
          + "label=\(current.label), valueType=\(valueType), "
          + "scalarPrefix=[\(scalarPrefix)], scalarCount=\(scalarCount), "
          + "fieldKeyboardFocus=\(focusedField.exists), keyboardVisible=\(keyboardVisible)")
      return
    }
  }

  private func matchesField(_ current: XCUIElement, label: String, expected: String) -> Bool {
    guard current.exists, current.isEnabled,
          let actual = current.value as? String else { return false }
    return current.label == label && actual == expected
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
    app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "العربية".count) + "Latin")
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
