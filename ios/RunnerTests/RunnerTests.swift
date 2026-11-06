import UIKit
import XCTest

@testable import Runner

class RunnerTests: XCTestCase {
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
}
