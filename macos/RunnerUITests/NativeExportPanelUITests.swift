import AppKit
import ApplicationServices
import CoreGraphics
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

  private func attemptVoiceOverFocus() {
    app.activate()
    // Request the standard VoiceOver focus/interact chords through XCUITest.
    // Synthesized key delivery does not prove VoiceOver handled either chord.
    app.typeKey(.F4, modifierFlags: [.control, .option, .shift, .function])
    app.typeKey(.downArrow, modifierFlags: [.control, .option, .shift])
  }

  private func appAccessibilityDiagnostic() -> String {
    let trusted = AXIsProcessTrusted()
    let processes = NSRunningApplication.runningApplications(
      withBundleIdentifier: "org.kotoha.app")
    guard processes.count == 1, let process = processes.first else {
      return "axClientTrusted=\(trusted) appProcessCount=\(processes.count) "
        + "appEnhancedUIStatus=notQueried appEnhancedUI=unavailable "
        + "axTimeoutStatus=notQueried"
    }
    let application = AXUIElementCreateApplication(process.processIdentifier)
    let timeoutStatus = AXUIElementSetMessagingTimeout(application, 1.0)
    var enhancedUI: CFTypeRef?
    let queryStatus = AXUIElementCopyAttributeValue(
      application, "AXEnhancedUserInterface" as CFString, &enhancedUI)
    let value: String
    if queryStatus == .success, let enabled = enhancedUI as? Bool {
      value = enabled ? "true" : "false"
    } else if queryStatus == .success {
      value = "nonBoolean"
    } else {
      value = "unavailable"
    }
    return "axClientTrusted=\(trusted) appEnhancedUIStatus=\(queryStatus.rawValue) "
      + "appEnhancedUI=\(value) axTimeoutStatus=\(timeoutStatus.rawValue)"
  }

  private func logAccessibilityDiagnostics(target: XCUIElement) {
    func describe(_ identifier: String, element: XCUIElement) -> String {
      guard element.exists else { return "\(identifier){exists=false}" }
      return "\(identifier){exists=true,hittable=\(element.isHittable)," +
        "frame=\(element.frame)}"
    }

    let window = app.windows.firstMatch
    let windowFrame = window.exists ? "\(window.frame)" : "unavailable"
    let visibleFields = ["source-language", "source-text"].map { identifier in
      let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
      return describe(identifier, element: element)
    }
    // Deliberately omit element values: these diagnostics report only geometry
    // and accessibility availability, never draft contents.
    print("KotohaAccessibilityDiagnostic voiceOverEnabled=\(NSWorkspace.shared.isVoiceOverEnabled) " +
          appAccessibilityDiagnostic() + " windowFrame=\(windowFrame) " +
          "scrollViews=\(app.scrollViews.count) " +
          describe("target", element: target) + " " +
          visibleFields.joined(separator: " "))
  }

  func testNativeSavePanelIsAccessibleAndCancelPreservesDraft() {
    let translation = "macOS panel probe"
    let field = app.descendants(matching: .any).matching(NSPredicate(
      format: "identifier == %@ AND (elementType == %d OR elementType == %d)",
      "translation-text-0",
      XCUIElement.ElementType.textField.rawValue,
      XCUIElement.ElementType.textView.rawValue)).firstMatch
    // The Flutter ListView is not exposed as an XCUI ScrollView on macOS.
    // Target one measured drag at the native application window: XCTest's
    // app.swipeUp() requires an application hit point that this host does not expose.
    if !field.exists || !field.isHittable {
      let window = app.windows.firstMatch
      guard window.waitForExistence(timeout: panelTimeout) else {
        XCTFail("Main application window was not exposed to XCUI")
        return
      }
      let frame = window.frame
      guard !frame.isNull && frame.origin.x.isFinite && frame.origin.y.isFinite
          && frame.width.isFinite && frame.height.isFinite
          && frame.width > 0 && frame.height > 48 else {
        XCTFail("Main application window has no usable frame: \(frame)")
        return
      }
      let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
      let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20))
      start.press(forDuration: 0.05, thenDragTo: end)
      attemptVoiceOverFocus()
    }
    let fieldExists = field.waitForExistence(timeout: panelTimeout)
    if !fieldExists || !field.isHittable {
      logAccessibilityDiagnostics(target: field)
    }
    XCTAssertTrue(
      fieldExists,
      "Translation field is unavailable after one window-coordinate scroll")
    XCTAssertTrue(
      field.isHittable,
      "Translation field is not hittable after the window-coordinate scroll")
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
