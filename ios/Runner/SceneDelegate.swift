import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var privacyCover: UIView?

  override func sceneWillResignActive(_ scene: UIScene) {
    showPrivacyCover()
    super.sceneWillResignActive(scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }

  private func showPrivacyCover() {
    guard privacyCover == nil, let window = self.window else { return }

    let cover = UIView(frame: window.bounds)
    cover.backgroundColor = .black
    cover.isOpaque = true
    cover.isAccessibilityElement = false
    cover.accessibilityElementsHidden = true
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(cover)
    privacyCover = cover
  }
}
