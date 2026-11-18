import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// The Gemini bridge must be registered exactly once: Flutter throws
  /// "Duplicate plugin key" (and the app aborts at launch) when the same plugin
  /// key is registered twice on one engine.
  private var hybridAiRegistered = false

  private func registerHybridAi(with registry: FlutterPluginRegistry) {
    guard !hybridAiRegistered else { return }
    if let registrar = registry.registrar(forPlugin: "HybridAiPlugin") {
      HybridAiPlugin.register(with: registrar)
      hybridAiRegistered = true
    }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerHybridAi(with: engineBridge.pluginRegistry)
  }
}
