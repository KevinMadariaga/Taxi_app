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

  // Limpia el globo rojo del ícono cada vez que la app pasa a primer plano.
  // Sin esto, el badge que llega en el payload de un push (badge: 1, fijo en
  // cada notificación de functions/index.js) se queda pegado para siempre:
  // iOS solo aplica el valor recibido, nunca lo resetea por su cuenta.
  override func applicationDidBecomeActive(_ application: UIApplication) {
    application.applicationIconBadgeNumber = 0
    super.applicationDidBecomeActive(application)
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
