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

    // Set UNUserNotificationCenter delegate BEFORE Flutter starts so foreground
    // notifications are delivered correctly (required by flutter_local_notifications).
    UNUserNotificationCenter.current().delegate = self

    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)

    // Register for remote APNs token AFTER Flutter is ready.
    // The actual user-facing permission dialog is handled from Dart via
    // flutter_local_notifications / permission_handler to avoid race conditions.
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Called when APNs token registration succeeds.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    print("[AppDelegate] APNs token received")
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // Called when APNs token registration fails.
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("[AppDelegate] Failed to register for remote notifications: \(error.localizedDescription)")
  }
}
