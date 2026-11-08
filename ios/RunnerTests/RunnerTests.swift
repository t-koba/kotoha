import Darwin
import Flutter
import UIKit
import XCTest

@testable import Runner

class RunnerTests: XCTestCase {
  @MainActor
  private func waitForPredicate(_ expectation: XCTestExpectation, timeout: TimeInterval, context: String) {
    let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
    XCTAssertEqual(result, .completed, "Timed out waiting for \(context) after \(timeout) seconds")
  }
  @MainActor
  func testPrivacyCoverIsIdempotentAndLeavesContentAttached() throws {
    // Use Runner's connected scene and installed delegate so removing either
    // lifecycle callback's cover operation breaks this regression. These direct
    // callbacks do not change UIApplication state or inspect Dart drafts/focus
    // or an actual app-switcher snapshot.
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .filter { $0.delegate is SceneDelegate }
    XCTAssertEqual(scenes.count, 1, "Runner is configured for a single hosted scene")
    let scene = try XCTUnwrap(scenes.first, "The hosted Runner scene must be connected")
    let delegate = try XCTUnwrap(scene.delegate as? SceneDelegate)
    let window = try XCTUnwrap(delegate.window)
    XCTAssertTrue(window.windowScene === scene)
    let content = try XCTUnwrap(window.rootViewController)
    defer {
      // Restore the active state, including on an unwrap failure.
      delegate.sceneDidBecomeActive(scene)
    }

    // Resume before any cover, then repeat the cycle to catch a stale reference.
    delegate.sceneDidBecomeActive(scene)
    window.layoutIfNeeded()
    let originalSubviews = window.subviews
    XCTAssertTrue(content.view.isDescendant(of: window))
    for _ in 0..<2 {
      delegate.sceneWillResignActive(scene)
      let cover = try XCTUnwrap(window.subviews.last)
      XCTAssertEqual(window.subviews.count, originalSubviews.count + 1)
      XCTAssertFalse(originalSubviews.contains(cover))
      XCTAssertEqual(cover.frame, window.bounds)
      XCTAssertEqual(cover.backgroundColor, UIColor.black)
      XCTAssertTrue(cover.isOpaque)
      XCTAssertEqual(cover.alpha, 1)
      XCTAssertFalse(cover.isHidden)
      XCTAssertFalse(cover.isAccessibilityElement)
      XCTAssertTrue(cover.accessibilityElementsHidden)
      // Check resizing policy without changing scene-managed window geometry.
      XCTAssertEqual(cover.autoresizingMask, [.flexibleWidth, .flexibleHeight])

      delegate.sceneWillResignActive(scene)
      XCTAssertEqual(window.subviews.count, originalSubviews.count + 1)
      XCTAssertTrue(window.subviews.last === cover)

      XCTAssertTrue(window.rootViewController === content)
      XCTAssertTrue(content.view.isDescendant(of: window))

      delegate.sceneDidBecomeActive(scene)
      delegate.sceneDidBecomeActive(scene)
      XCTAssertNil(cover.superview)
      XCTAssertEqual(window.subviews, originalSubviews)
      XCTAssertTrue(window.rootViewController === content)
      XCTAssertTrue(content.view.isDescendant(of: window))
    }
  }

  func testOptInNativeReadMemoryProfile() throws {
    let configured = ProcessInfo.processInfo.environment["KOTOHA_IMPORT_PROFILE_BYTES"] ?? ""
    guard !configured.isEmpty else { throw XCTSkip("Opt-in memory profile") }
    let requested = try XCTUnwrap(Int(configured))
    let validProfileSize = (1024...(16 * 1024 * 1024)).contains(requested)
    XCTAssertTrue(validProfileSize, "Profile fixture is bounded to 16 MiB")
    guard validProfileSize else { return }
    let chunk = Data((String(repeating: "a", count: 1003) + "日本語 مرحبا\n").utf8)
    XCTAssertEqual(chunk.count, 1024, "Multilingual profile chunk must be exactly 1 KiB")
    guard requested % chunk.count == 0 else {
      XCTFail("KOTOHA_IMPORT_PROFILE_BYTES must use complete 1-KiB UTF-8 fixture chunks")
      return
    }
    let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
    defer { try? FileManager.default.removeItem(at: local) }
    XCTAssertTrue(FileManager.default.createFile(atPath: local.path, contents: nil))
    let file = try FileHandle(forWritingTo: local)
    do {
      for _ in 0..<(requested / chunk.count) { try file.write(contentsOf: chunk) }
      try file.close()
    } catch { try? file.close(); throw error }
    var before = rusage()
    XCTAssertEqual(getrusage(RUSAGE_SELF, &before), 0)
    let start = ProcessInfo.processInfo.systemUptime
    let result = try TextDocumentReader().read(local)
    let bytes = try XCTUnwrap(result["bytes"] as? FlutterStandardTypedData)
    XCTAssertEqual(bytes.data.count, requested, "Native profile must return exactly the requested bytes")
    var after = rusage()
    XCTAssertEqual(getrusage(RUSAGE_SELF, &after), 0)
    print("KotohaImportProfile native-read bytes=\(bytes.data.count) seconds=\(ProcessInfo.processInfo.systemUptime - start) peakBeforeBytes=\(before.ru_maxrss) peakAfterBytes=\(after.ru_maxrss) os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
  }

  func testTextImportReaderScopeAndReadFailures() throws {
    let url = URL(fileURLWithPath: "/synthetic/sample.MaRkDoWn")
    let bytes = Data("# 日本語\nمرحبا".utf8)
    for scoped in [false, true] {
      for failure in ["none", "coordinate", "read", "name"] {
        var starts = 0
        var stops = 0
        var loads = 0
        var reader = TextDocumentReader()
        reader.startScope = { _ in starts += 1; return scoped }
        reader.stopScope = { _ in stops += 1 }
        reader.coordinate = { selected, accessor in
          XCTAssertEqual(selected, url)
          if failure == "coordinate" { throw CocoaError(.fileReadUnknown) }
          accessor(selected)
        }
        reader.load = { _ in
          loads += 1
          if failure == "read" { throw CocoaError(.fileReadNoPermission) }
          return bytes
        }
        if failure == "none" {
          let result = try reader.read(url)
          XCTAssertEqual(result["name"] as? String, "sample.MaRkDoWn")
          XCTAssertEqual((result["bytes"] as? FlutterStandardTypedData)?.data, bytes)
        } else {
          let selected = failure == "name" ? url.deletingLastPathComponent() : url
          XCTAssertThrowsError(try reader.read(selected))
        }
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(stops, scoped ? 1 : 0)
        XCTAssertEqual(loads, failure == "none" || failure == "read" ? 1 : 0)
      }
    }
    // Real Foundation coordination/Data on a synthetic local URL; no claim that
    // this fixture exercises an external provider's security-scoped grant.
    let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
    defer { try? FileManager.default.removeItem(at: local) }
    try bytes.write(to: local)
    let result = try TextDocumentReader().read(local)
    XCTAssertEqual((result["bytes"] as? FlutterStandardTypedData)?.data, bytes)
    try FileManager.default.removeItem(at: local)
    XCTAssertThrowsError(try TextDocumentReader().read(local))
  }

  @MainActor
  func testTextImportImplicitRegistrationScenePickerAndDelegates() throws {
    let configured = ProcessInfo.processInfo.environment["KOTOHA_AX_TIMEOUT_SECONDS"] ?? "10"
    let timeout = try XCTUnwrap(Double(configured))
    let active = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      TextImportPlugin.activePresenter() != nil
    }, object: nil)
    waitForPredicate(active, timeout: timeout, context: "active presenter")
    let presenter = try XCTUnwrap(TextImportPlugin.activePresenter())
    let flutter = try XCTUnwrap(presenter as? FlutterViewController)
    let engine = try XCTUnwrap(flutter.engine)
    let plugin = try XCTUnwrap(engine.valuePublished(byPlugin: "TextImportPlugin") as? TextImportPlugin,
                              "Must be registered by the implicit engine callback")
    let originalReader = plugin.reader
    let originalPresentPicker = plugin.presentPicker
    let originalPickerIsPresented = plugin.pickerIsPresented
    let originalDismissPicker = plugin.dismissPicker
    defer {
      plugin.reader = originalReader
      plugin.presentPicker = originalPresentPicker
      plugin.pickerIsPresented = originalPickerIsPresented
      plugin.dismissPicker = originalDismissPicker
    }
    var reader = TextDocumentReader()
    reader.startScope = { _ in false }
    reader.coordinate = { url, accessor in accessor(url) }
    reader.load = { _ in Data([65, 10, 66]) }
    plugin.reader = reader
    var simulatedPresentation: UIDocumentPickerViewController?
    plugin.presentPicker = { selectedPresenter, picker, completion in
      XCTAssertTrue(selectedPresenter === presenter)
      simulatedPresentation = picker
      completion()
    }
    plugin.pickerIsPresented = { $0 === simulatedPresentation }

    // Handler/delegate integration on the implicit engine. Presentation is a
    // narrow seam: picker configuration and active presenter remain real, while
    // no external Files/DocumentManager scene is launched by this unit test.
    // The XCUI regression
    // exercises the real Dart channel and system-picker cancellation as well.
    for outcome in ["cancel", "dismiss", "selection", "read-error", "invalid"] {
      if outcome == "read-error" {
        plugin.reader.load = { _ in throw CocoaError(.fileReadNoPermission) }
      }
      let completed = expectation(description: outcome)
      var completions = 0
      plugin.handle(FlutterMethodCall(methodName: "open", arguments: nil)) { value in
        completions += 1
        if outcome == "cancel" || outcome == "dismiss" { XCTAssertNil(value) }
        else if outcome == "selection" {
          let document = value as? [String: Any]
          XCTAssertEqual(document?["name"] as? String, "sample.md")
          XCTAssertEqual((document?["bytes"] as? FlutterStandardTypedData)?.data, Data([65, 10, 66]))
        } else { XCTAssertNotNil(value as? FlutterError) }
        completed.fulfill()
      }
      let picker = try XCTUnwrap(plugin.picker)
      XCTAssertTrue(simulatedPresentation === picker)
      XCTAssertEqual(picker.documentPickerMode, .open) // asCopy:false, not import/copy mode.
      XCTAssertFalse(picker.allowsMultipleSelection)
      XCTAssertEqual(picker.modalPresentationStyle, .formSheet) // iPad-safe sheet; no unanchored popover.
      XCTAssertTrue(picker.delegate === plugin)
      plugin.handle(FlutterMethodCall(methodName: "open", arguments: nil)) { value in
        XCTAssertEqual((value as? FlutterError)?.code, "busy")
      }
      if outcome == "cancel" { plugin.documentPickerWasCancelled(picker) }
      else if outcome == "dismiss" {
        let presentation = UIPresentationController(presentedViewController: picker,
                                                    presenting: presenter)
        plugin.presentationControllerDidDismiss(presentation)
      } else {
        plugin.documentPicker(picker, didPickDocumentsAt: outcome == "invalid" ? [] : [
          URL(fileURLWithPath: "/synthetic/sample.md")
        ])
      }
      wait(for: [completed], timeout: timeout)
      XCTAssertEqual(completions, 1)
      XCTAssertNil(plugin.picker)
      XCTAssertNil(picker.delegate)
      plugin.documentPickerWasCancelled(picker) // Late delegate callback is ignored.
      XCTAssertEqual(completions, 1)
    }

    // A separate plugin/registrar tests engine detach without breaking the hosted
    // engine's live import handler for later tests.
    let registrar = try XCTUnwrap(engine.registrar(forPlugin: "TextImportDetachTest"))
    let detachedPlugin = TextImportPlugin()
    var detachedPresentation: UIDocumentPickerViewController?
    var detachedDismissals = 0
    detachedPlugin.presentPicker = { _, picker, completion in
      detachedPresentation = picker
      completion()
    }
    detachedPlugin.pickerIsPresented = { $0 === detachedPresentation }
    detachedPlugin.dismissPicker = { _ in detachedDismissals += 1 }
    var detachCompletions = 0
    detachedPlugin.handle(FlutterMethodCall(methodName: "open", arguments: nil)) { value in
      detachCompletions += 1
      XCTAssertEqual((value as? FlutterError)?.code, "detached")
    }
    let detachedPicker = try XCTUnwrap(detachedPlugin.picker)
    XCTAssertTrue(detachedPresentation === detachedPicker)
    detachedPlugin.detachFromEngine(for: registrar)
    XCTAssertEqual(detachedDismissals, 1)
    XCTAssertNil(detachedPicker.delegate)
    XCTAssertNil(detachedPlugin.picker)
    detachedPlugin.documentPickerWasCancelled(detachedPicker)
    XCTAssertEqual(detachCompletions, 1)
  }

}
