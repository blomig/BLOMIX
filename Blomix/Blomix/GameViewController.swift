//
//  GameViewController.swift
//  Blomix
//

import GameKit
import SpriteKit
import UIKit

/// Wrapper Sendable pour GKMatch traversant les frontières d'acteur dans GameViewController.
private struct GKMatchInviteBox: @unchecked Sendable {
    let match: GKMatch
}

/// Contrôleur racine : le storyboard fournit une `UIView` ; on y intègre un `SKView` en code
/// (évite l’erreur Interface Builder « Unknown class … SKView » liée au chargement SpriteKit).
final class GameViewController: UIViewController, @preconcurrency GKLocalPlayerListener, @preconcurrency GKMatchmakerViewControllerDelegate {

    private var spriteKitView: SKView?
    private weak var tutorialOverlay: GameTutorialOverlayView?
    private var didRegisterGameCenterInviteListener = false
    private var pendingPvPMatch: GKMatch?
    /// Vrai quand une invitation sortante (vers un joueur récent) est en cours.
    /// Permet d'ignorer le callback parasite `player(_:didAccept:)` déclenché côté émetteur par GameKit.
    private var outgoingInviteActive = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let skView = BlomixSKView()
        skView.translatesAutoresizingMaskIntoConstraints = false
        skView.ignoresSiblingOrder = true
        #if DEBUG
        skView.showsFPS = true
        skView.showsNodeCount = true
        #endif
        view.addSubview(skView)
        NSLayoutConstraint.activate([
            skView.topAnchor.constraint(equalTo: view.topAnchor),
            skView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            skView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            skView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        spriteKitView = skView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMatchStartedForTutorial(_:)),
            name: .blomixDidBeginGameplayMatch,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGameCenterAuthDidChange(_:)),
            name: .blomixGameCenterAuthDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOutgoingInviteStateChanged(_:)),
            name: .blomixPvPOutgoingInviteStateChanged,
            object: nil
        )
        registerGameCenterInviteListenerIfNeeded()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleMatchStartedForTutorial(_ notification: Notification) {
        let anchors = (notification.object as? GameScene)?.makeTutorialLayoutAnchorsForOverlay()
        presentTutorialOverlayIfNeeded(anchors: anchors)
    }

    @objc private func handleGameCenterAuthDidChange(_ notification: Notification) {
        _ = notification
        registerGameCenterInviteListenerIfNeeded()
    }

    @objc private func handleOutgoingInviteStateChanged(_ notification: Notification) {
        outgoingInviteActive = (notification.userInfo?["active"] as? Bool) ?? false
    }

    /// Tutoriel plein écran au démarrage d'une partie si `hasSeenGameTutorial` est `false`.
    private func presentTutorialOverlayIfNeeded(anchors: TutorialLayoutAnchors?) {
        guard !UserDefaults.standard.hasSeenGameTutorial else { return }
        showTutorialOverlay(anchors: anchors)
    }

    /// Affiche le tutoriel paginé — toujours accessible (ex. bouton "Règles" du menu).
    func showTutorialOverlay(anchors: TutorialLayoutAnchors?) {
        guard tutorialOverlay == nil else { return }

        let overlay = GameTutorialOverlayView(anchors: anchors)
        overlay.onDismiss = { [weak self] in self?.tutorialOverlay = nil }
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        tutorialOverlay = overlay
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        registerGameCenterInviteListenerIfNeeded()
        (spriteKitView as? BlomixSKView)?.becomeFirstResponder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let skView = spriteKitView else { return }
        let bounds = skView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        if skView.scene == nil {
            let scene = GameScene(size: bounds.size)
            scene.scaleMode = .resizeFill
            skView.presentScene(scene)
        } else if let scene = skView.scene as? GameScene {
            scene.size = bounds.size
        }
        beginPendingPvPMatchIfPossible()
    }

    private func registerGameCenterInviteListenerIfNeeded() {
        guard !didRegisterGameCenterInviteListener else { return }
        guard GKLocalPlayer.local.isAuthenticated else { return }
        GKLocalPlayer.local.register(self)
        didRegisterGameCenterInviteListener = true
    }

    private func topPresentedViewController() -> UIViewController {
        var top: UIViewController = self
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    private func beginPvPMatchOrQueueIfNeeded(_ match: GKMatch) {
        // Annule toute recherche en cours (cas : lobby ouvert en auto-search au moment de l'acceptation).
        GKMatchmaker.shared().cancel()
        // Ferme automatiquement tout modal ouvert (lobby, classement, réglages…)
        // avant de basculer en partie PvP.
        if presentedViewController != nil {
            dismiss(animated: true) { [weak self] in
                self?.launchPvPMatch(match)
            }
        } else {
            launchPvPMatch(match)
        }
    }

    private func launchPvPMatch(_ match: GKMatch) {
        guard let scene = spriteKitView?.scene as? GameScene else {
            pendingPvPMatch = match
            return
        }
        scene.beginPvPWithMatch(match)
    }

    private func beginPendingPvPMatchIfPossible() {
        guard let pendingPvPMatch else { return }
        guard let scene = spriteKitView?.scene as? GameScene else { return }
        self.pendingPvPMatch = nil
        scene.beginPvPWithMatch(pendingPvPMatch)
    }

    // MARK: - GKLocalPlayerListener — invitation reçue

    /// Reçu quand un autre joueur BLOMIX nous invite directement (via "Adversaire récent").
    /// On crée le match sans UI native et on affiche une bannière BLOMIX.
    func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        _ = player  // local player — l'envoyeur est invite.sender
        // Ignore le callback parasite déclenché par GameKit côté émetteur lors d'une invitation sortante.
        guard !outgoingInviteActive else {
            print("[PvP] didAccept ignoré — invitation sortante en cours")
            return
        }
        let inviterName = invite.sender.displayName
        GKMatchmaker.shared().match(for: invite) { [weak self] match, error in
            let box = match.map { GKMatchInviteBox(match: $0) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let box {
                    GKMatchmaker.shared().finishMatchmaking(for: box.match)
                    self.showInviteBanner(inviterName: inviterName, match: box.match)
                } else {
                    print("[PvP] Création du match depuis invitation échouée : \(error?.localizedDescription ?? "inconnu")")
                }
            }
        }
    }

    private func showInviteBanner(inviterName: String, match: GKMatch) {
        let banner = BlomixPvPInviteBannerView()
        banner.configure(inviterName: inviterName)
        banner.onAccept = { [weak self] in
            self?.beginPvPMatchOrQueueIfNeeded(match)
        }
        banner.onDecline = {
            match.disconnect()
        }
        // Affiche dans la fenêtre pour passer au-dessus de tous les modaux éventuels.
        let targetView: UIView = view.window ?? view
        let safeTop = targetView.safeAreaInsets.top
        banner.show(in: targetView, safeAreaTop: safeTop)
    }

    // MARK: - GKMatchmakerViewControllerDelegate (conservé pour fallback)

    func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        viewController.dismiss(animated: true)
    }

    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        print("[PvP] Matchmaker error: \(error.localizedDescription)")
        viewController.dismiss(animated: true)
    }

    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        GKMatchmaker.shared().finishMatchmaking(for: match)
        viewController.dismiss(animated: true) { [weak self] in
            self?.beginPvPMatchOrQueueIfNeeded(match)
        }
    }
}
