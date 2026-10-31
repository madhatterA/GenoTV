import UIKit
import Flutter

@main
class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}

class SceneDelegate: FlutterSceneDelegate {
    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let controller = FlutterViewController(project: nil, nibName: nil, bundle: nil)
        // The engine exists only now (UIScene lifecycle), so plugins register here, not in AppDelegate.
        GeneratedPluginRegistrant.register(with: controller)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        super.scene(scene, willConnectTo: session, options: connectionOptions)
    }
}
