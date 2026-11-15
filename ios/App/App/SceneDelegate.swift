import UIKit
import Capacitor
import LocalAuthentication

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    // Face ID / passcode lock. The app locks whenever it goes to the
    // background, and the cover also hides the numbers in the app switcher.
    private var lockView: UIView?
    private var isUnlocked = false
    private var authInProgress = false
    private var lastAttemptFailed = false

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = CAPBridgeViewController()
        window?.makeKeyAndVisible()
        showLock()

        SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        if !isUnlocked && !authInProgress && !lastAttemptFailed {
            authenticate()
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        isUnlocked = false
        lastAttemptFailed = false
        showLock()
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
    }

    // MARK: - Lock

    private func showLock() {
        guard lockView == nil, let window = window else { return }
        let cover = UIView(frame: window.bounds)
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)

        let title = UILabel()
        title.text = "Lead Gen"
        title.font = .systemFont(ofSize: 28, weight: .bold)
        title.textColor = .white
        title.translatesAutoresizingMaskIntoConstraints = false

        let button = UIButton(type: .system)
        button.setTitle("Unlock", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        button.setTitleColor(.black, for: .normal)
        button.backgroundColor = .white
        button.layer.cornerRadius = 26
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(unlockTapped), for: .touchUpInside)

        cover.addSubview(title)
        cover.addSubview(button)
        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: cover.centerYAnchor, constant: -40),
            button.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            button.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 32),
            button.widthAnchor.constraint(equalToConstant: 200),
            button.heightAnchor.constraint(equalToConstant: 52),
        ])
        window.addSubview(cover)
        lockView = cover
    }

    private func hideLock() {
        UIView.animate(withDuration: 0.2, animations: { self.lockView?.alpha = 0 }) { _ in
            self.lockView?.removeFromSuperview()
            self.lockView = nil
        }
    }

    @objc private func unlockTapped() {
        lastAttemptFailed = false
        authenticate()
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?
        // Face ID or Touch ID, falling back to the device passcode.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode set on the device: nothing to check against.
            isUnlocked = true
            hideLock()
            return
        }
        authInProgress = true
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Lead Gen") { success, _ in
            DispatchQueue.main.async {
                self.authInProgress = false
                if success {
                    self.isUnlocked = true
                    self.hideLock()
                } else {
                    self.lastAttemptFailed = true
                }
            }
        }
    }
}
