import UIKit
import XCTest

private extension XCUIElement {
  // XCTest exposes keyboard focus as an accessibility attribute rather than a
  // Swift property. Use the same key the failure diagnostics already query.
  var hasKeyboardFocus: Bool {
    (value(forKey: "hasKeyboardFocus") as? Bool) ?? false
  }
}

// Simulator XCUI tree and synthesized input only: no VoiceOver speech/gestures,
// physical devices/keyboards, or OS task-switcher thumbnail validation. Widget tests
// own direction/caret policy and the complete forward/reverse Flutter focus order.
final class LanguageFieldAccessibilityTests: XCTestCase {
  private let app = XCUIApplication()
  // Test policy default, overridable in the Runner scheme/build setting.
  private var timeout: TimeInterval = 10

  // The hosted simulator did not always expose the Files picker's Cancel
  // control as an XCUIButton (CI 46138618554: cancelButtons=0 while
  // cancelElements=1). Match the exact label across element types, then require
  // hittability before tapping; presentation, Cancel and draft assertions stay.
  private var pickerCancel: XCUIElement {
    app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "Cancel")).firstMatch
  }

  override func setUpWithError() throws {
    continueAfterFailure = false
    // A hosted arm64 simulator exceeded XCTest's default two-minute allowance
    // on this suite (CI run 45123648861, vcs-read/6682f4b4); the assertions
    // then passed after the allowance-triggered relaunch. Keep every assertion
    // and the element timeout below unchanged; only give the slow runner room.
    executionTimeAllowance = 300
    let configured = ProcessInfo.processInfo.environment["KOTOHA_AX_TIMEOUT_SECONDS"] ?? ""
    if !configured.isEmpty {
      timeout = try XCTUnwrap(Double(configured), "Invalid accessibility wait budget")
    }
    XCTAssertTrue(timeout > 0 && timeout.isFinite)
    // Keep OS edit-menu labels deterministic. English tests use these launch
    // arguments; the Japanese tests switch the interface language through the UI.
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
  }

  override func tearDownWithError() throws {
    UIPasteboard.general.items = [] // Only synthetic test text was placed here.
    app.terminate()
  }

  // Keep each locale/field sequence within the existing per-test execution budget.
  func testEnglishSourceLanguageField() {
    // Launch arguments already select English. Re-opening the locale menu to
    // choose the active language was the flaky step; checkField asserts the label.
    checkField("source-language", label: "Source language", nextID: "source-text",
               nextLabel: "Source text")
  }

  func testEnglishTargetLanguageField() {
    // Launch arguments already select English. Re-opening the locale menu to
    // choose the active language was the flaky step; checkField asserts the label.
    checkField("target-language-0", label: "Target language 1", nextID: "translation-text-0",
               nextLabel: "Manual translation 1")
  }

  func testJapaneseSourceLanguageField() {
    selectLocale("日本語")
    checkField("source-language", label: "原文の言語", nextID: "source-text", nextLabel: "原文")
  }

  func testJapaneseTargetLanguageField() {
    selectLocale("日本語")
    checkField("target-language-0", label: "1件目の訳先の言語", nextID: "translation-text-0",
               nextLabel: "1件目の手入力した訳文")
  }

  func testImportChannelPresentsSystemPickerAndCancellationKeepsDraft() {
    // Real Dart -> implicit-engine channel -> active-scene UIKit presentation.
    // No fixture is selected here: provider read/scope paths are unit-tested separately.
    let source = reveal("source-text")
    source.tap()
    app.typeText("unsaved source")
    for round in 1...2 {
      // A scroll/locale rebuild can replace the native button node between
      // discovery and tap. Re-resolve it on each bounded attempt; the system
      // picker's Cancel button remains the presentation assertion.
      // A disabled importer can be a pending presentation, not a missed tap.
      // The hosted arm64 runner can need longer than the shared element budget
      // to initialize UIKit's Files picker (CI 45418969661, job 138535780162:
      // an enabled importer was tapped, but no Cancel appeared within 10 s).
      // Give only this OS presentation a bounded 30 s floor; the presentation,
      // Cancel and draft assertions stay unchanged.
      let pickerTimeout = max(timeout, 30)
      var presented = false
      var diagnostics = ""
      for attempt in 1...2 {
        let importButton = app.buttons["Import text or Markdown"]
        if !importButton.isHittable { app.swipeDown() }
        XCTAssertTrue(importButton.waitForExistence(timeout: timeout))
        let enabledBeforeTap = importButton.isEnabled
        let hittableBeforeTap = importButton.isHittable
        let beforeTap = "enabled=\(enabledBeforeTap), hittable=\(hittableBeforeTap)"
        if enabledBeforeTap && hittableBeforeTap { importButton.tap() }
        // Always allow the full wait: a presentation may already be opening.
        let cancel = pickerCancel
        let didPresent = cancel.waitForExistence(timeout: pickerTimeout)
        // Collect bounded state before deciding on a re-tap: a disabled importer
        // means a re-tap would auto-fail and hide why no Cancel was observed.
        // Bounded state only: never log picker contents, UI trees or draft text.
        let importerExists = importButton.exists
        let errorNotice = app.descendants(matching: .any).matching(NSPredicate(
          format: "label == %@",
          "Could not import this document. Choose a UTF-8 .txt, .md, or .markdown file.")).firstMatch.exists
        diagnostics = "tapAttempt=\(attempt), beforeTap=[\(beforeTap)], "
          + "tapped=\(enabledBeforeTap && hittableBeforeTap), "
          + "importerExists=\(importerExists), "
          + "enabled=\(importerExists && importButton.isEnabled), "
          + "hittable=\(importerExists && importButton.isHittable), errorNotice=\(errorNotice), "
          + "alerts=\(app.alerts.count), cancelButtons=\(app.buttons.matching(identifier: "Cancel").count), "
          + "cancelElements=\(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Cancel'")).count), "
          + "cancelHittable=\(cancel.isHittable)"
        if didPresent {
          presented = true
          break
        }
        // Only an enabled, hittable importer is eligible for the bounded re-tap.
        guard importerExists, importButton.isEnabled, importButton.isHittable else { break }
      }
      guard presented else {
        // The two rounds are intentional: the first disabled-importer state can
        // be a pending OS presentation. Keep the full presentation, Cancel and
        // draft assertions; only let the already-bounded second round run.
        if round < 2 { continue }
        XCTFail("System document picker must be presented; round=\(round), \(diagnostics)")
        return
      }
      let cancel = pickerCancel
      XCTAssertTrue(cancel.isHittable, "System document picker Cancel control must be hittable")
      cancel.tap()
      // Keep verification independent of the editor's current scroll position.
      // If XCTest has dropped the offscreen field node, reveal it before the
      // unchanged exact draft-value assertion.
      if !field("source-text").exists { _ = reveal("source-text") }
      assertField("source-text", label: "Source text", value: "unsaved source")
    }
  }

  // Only the Japanese tests switch locale through the UI; English tests use the
  // launch arguments. A locale rebuild can replace the popup nodes between tap
  // and lookup, so allow one re-tap and then fail with bounded diagnostics.
  private func selectLocale(_ locale: String) {
    XCTAssertTrue(app.buttons["Interface language"].waitForExistence(timeout: timeout))
    for _ in 1...2 {
      // Resolve menu and choice afresh each time: either node may be recycled.
      app.buttons["Interface language"].tap()
      let choice = app.descendants(matching: .any).matching(
        NSPredicate(format: "label == %@", locale)).firstMatch
      guard choice.waitForExistence(timeout: timeout) else { continue }
      choice.tap()
      // Let the locale rebuild dismiss the popup before the next field lookup.
      // The dismissal wait is short and bounded; assertions keep their full budget.
      let dismissed = NSPredicate { [self] _, _ in
        !app.descendants(matching: .any).matching(
          NSPredicate(format: "label == %@", locale)).firstMatch.exists
      }
      _ = XCTWaiter.wait(
        for: [XCTNSPredicateExpectation(predicate: dismissed, object: nil)],
        timeout: min(3, timeout))
      return
    }
    // One re-tap only: more attempts would inflate the per-test budget without
    // new signal. Fail explicitly; never proceed in the wrong locale.
    let menu = app.buttons["Interface language"]
    let choices = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", locale)).count
    XCTFail("Locale choice unavailable; locale=\(locale), taps=2, "
      + "menuExists=\(menu.exists), menuHittable=\(menu.isHittable), choices=\(choices)")
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
      // A usable frame tells us which way to scroll. A collapsed node reports
      // (0, 0, 0, 0) both above and below the viewport, so its origin cannot
      // choose a direction: alternate two-swipe blocks instead of repeatedly
      // pushing farther past the field in one direction.
      let swipeUp = hasUsableFrame(targetFrame)
        ? targetFrame.midY >= midpoint
        : (swipes / 2).isMultiple(of: 2)
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

  // Acceptance is keyboard focus on the target field. Software-keyboard visibility
  // is not a reliable proxy in hosted simulators: the field can hold focus and accept
  // typed text while no keyboard element appears in the XCUI tree.
  private func focusWaitResult(_ id: String, timeout: TimeInterval) -> XCTWaiter.Result {
    let focused = NSPredicate { [self] _, _ in
      // Re-resolve on each poll; Flutter can replace the semantics node when the
      // field direction changes from RTL to LTR.
      let current = field(id)
      return current.exists && current.hasKeyboardFocus
    }
    let expectation = XCTNSPredicateExpectation(predicate: focused, object: nil)
    return XCTWaiter.wait(for: [expectation], timeout: timeout)
  }

  private func assertKeyboardFocus(_ id: String) {
    let result = focusWaitResult(id, timeout: timeout)
    guard result == .completed else {
      // XCTest can stop waiting before a late focus change. Check one fresh
      // snapshot without polling again; focus on the target is the acceptance
      // condition, so an interrupted wait may still be a pass.
      let current = field(id)
      if current.exists && current.hasKeyboardFocus {
        return
      }
      // Scalar-only diagnostics: no UI tree, draft text or picker contents.
      let targetExists = current.exists
      let keyboard = app.keyboards.firstMatch
      let focused = app.descendants(matching: .any).matching(
        NSPredicate(format: "hasKeyboardFocus == 1")).count
      XCTFail("Expected keyboard focus on native field \(id); wait=\(result). "
        + "exists=\(targetExists), hittable=\(targetExists && current.isHittable), "
        + "frame=\(targetExists ? String(describing: current.frame) : "<absent>"), "
        + "keyboard=\(keyboard.exists), focusedElements=\(focused), "
        + "hasKeyboardFocus=\(targetExists && current.hasKeyboardFocus)")
      return
    }
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

  // Locale/scroll rebuilds can replace a target field's native node between
  // `reveal` and `tap`, leaving the first synthesized tap on a stale frame.
  // Resolve again immediately before each tap and retry once only: bounded taps
  // keep the per-test budget, and the full-budget focus assertion is unchanged.
  private func focusField(_ id: String) -> XCUIElement {
    _ = reveal(id)
    field(id).tap()
    if focusWaitResult(id, timeout: min(3, timeout)) != .completed {
      _ = reveal(id)
      field(id).tap()
    }
    assertKeyboardFocus(id)
    return field(id)
  }

  private func checkField(_ id: String, label: String, nextID: String, nextLabel: String) {
    let element = focusField(id)
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
    let destination = focusField(nextID)
    app.typeText("z")
    assertField(nextID, label: nextLabel, value: "z")
    assertField(id, label: label, value: "Latin")
  }
}
