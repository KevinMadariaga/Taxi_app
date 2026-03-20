import Flutter
import UIKit
import GoogleMaps
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Shared engine used by SceneDelegate to keep plugin state stable.
  lazy var flutterEngine = FlutterEngine(name: "io.flutter", project: nil, allowHeadlessExecution: true)

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Provide Google Maps API key for iOS
    GMSServices.provideAPIKey("AIzaSyAUYXdeT3cOtyTSGndd-DEV12OMyAmb-40")
    // Set UNUserNotificationCenter delegate to handle foreground notifications
    UNUserNotificationCenter.current().delegate = self

    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)

    // Register for remote notifications to obtain APNs token (Firebase will use it if configured)
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
