import Flutter
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private var fallbackEngine: FlutterEngine?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else {
      return
    }

    let appDelegate = UIApplication.shared.delegate as? AppDelegate
    let flutterViewController: FlutterViewController

    if let engine = appDelegate?.flutterEngine {
      flutterViewController = FlutterViewController(
        engine: engine,
        nibName: nil,
        bundle: nil
      )
    } else {
      // Safety fallback if the shared engine is unavailable.
      let engine = FlutterEngine(name: "io.flutter.fallback", project: nil, allowHeadlessExecution: true)
      engine.run()
      GeneratedPluginRegistrant.register(with: engine)
      fallbackEngine = engine
      flutterViewController = FlutterViewController(
        engine: engine,
        nibName: nil,
        bundle: nil
      )
    }

    let window = UIWindow(windowScene: windowScene)
    window.rootViewController = flutterViewController
    self.window = window
    window.makeKeyAndVisible()
  }

  func sceneDidDisconnect(_ scene: UIScene) {}

  func sceneDidBecomeActive(_ scene: UIScene) {}

  func sceneWillResignActive(_ scene: UIScene) {}

  func sceneWillEnterForeground(_ scene: UIScene) {}

  func sceneDidEnterBackground(_ scene: UIScene) {}
}
