//
//  SceneDelegate.swift
//  Blomix
//
//  Déclaré dans `Info.plist` (`UIApplicationSceneManifest`) pour adopter le cycle de vie UIScene
//  et supprimer l’avertissement « UIScene lifecycle will soon be required ».
//

import UIKit

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    /// Obligatoire avec `UISceneStoryboardFile` : UIKit rattache ici la fenêtre créée depuis `Main.storyboard`.
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        _ = session
        _ = connectionOptions
        guard let windowScene = scene as? UIWindowScene else { return }
        window = windowScene.windows.first { $0.isKeyWindow } ?? windowScene.windows.first

        // Fenêtre + `GameViewController` : storyboard ; le `rootViewController` peut arriver un tick plus tard.
        Task { @MainActor in
            guard let root = windowScene.windows.first?.rootViewController else { return }
            ScoreManager.shared.authenticateOnLaunch(from: root)
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Secours si `willConnect` n’avait pas encore de `rootViewController` (ordre de callbacks / storyboard).
        guard let windowScene = scene as? UIWindowScene,
              let root = windowScene.windows.first?.rootViewController else { return }
        ScoreManager.shared.authenticateOnLaunch(from: root)
    }
}
