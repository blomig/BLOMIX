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

/// Délégué GKMatch dédié au côté « challengé » du défi CloudKit.
/// Attend que la connexion P2P soit complète (expectedPlayerCount == 0) avant d'entrer en partie,
/// symétrique du comportement du côté « challenger » dans BlomixPvPAvailablePlayersViewController.
private final class ChallengeMatchDelegate: NSObject, @preconcurrency GKMatchDelegate, @unchecked Sendable {
    var onConnected: (() -> Void)?
    var onFailed:    (() -> Void)?

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        guard state == .connected, match.expectedPlayerCount == 0 else { return }
        Task { @MainActor [weak self] in self?.onConnected?() }
    }

    nonisolated func match(_ match: GKMatch, didFailWithError error: (any Error)?) {
        Task { @MainActor [weak self] in self?.onFailed?() }
    }
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
    /// ID GameKit du joueur qu'on invite actuellement (nil si aucune invitation sortante).
    private var outgoingInviteTargetPlayerID: String?
    /// Timer de sécurité : remet outgoingInviteActive à false si un chemin d'erreur l'a oublié.
    private var outgoingInviteSafetyTimer: Timer?
    /// Timer d'annulation pour le matchmaking d'un défi CloudKit accepté.
    private var challengeMatchCancelTimer: Timer?
    /// Match CloudKit en attente de connexion P2P complète (même pattern que le côté challenger).
    private var pendingChallengeMatch: GKMatch?
    /// Délégué retenu pour le match en attente.
    private var challengeMatchDelegate: ChallengeMatchDelegate?
    /// Vrai pendant le splash studio (fond noir forcé, hors thème Clair/Sombre).
    private var isStudioSplashChromeActive = false

    override func viewDidLoad() {
        super.viewDidLoad()

        // Enregistrement manuel de ChangaOne-Regular : UIAppFonts ne charge pas ce fichier
        // automatiquement (PostScript name "ChangaOne" sans suffixe de style, comportement iOS).
        if let url = Bundle.main.url(forResource: "ChangaOne-Regular", withExtension: "ttf"),
           let data = try? Data(contentsOf: url),
           let provider = CGDataProvider(data: data as CFData),
           let cgFont = CGFont(provider) {
            CTFontManagerRegisterGraphicsFont(cgFont, nil)
        }

        // Démarrage noir : le splash logo est toujours sur fond noir ; le thème
        // Clair/Sombre est appliqué ensuite par GameScene après le splash.
        applyForcedBlackChromeForStudioSplash()

        let skView = BlomixSKView()
        skView.translatesAutoresizingMaskIntoConstraints = false
        skView.ignoresSiblingOrder = true
        skView.allowsTransparency = false
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleIncomingChallengeDetected(_:)),
            name: .blomixIncomingChallengeDetected,
            object: nil
        )
        registerGameCenterInviteListenerIfNeeded()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Fond + status bar selon le thème chrome (Sombre / Clair).
    func applyBlomixAppearanceChrome() {
        isStudioSplashChromeActive = false
        let bg = BlomixAppearance.sceneBackground
        view.backgroundColor = bg
        spriteKitView?.backgroundColor = bg
        setNeedsStatusBarAppearanceUpdate()
    }

    /// Splash studio : forcer le noir (indépendant du thème Clair).
    func applyForcedBlackChromeForStudioSplash() {
        isStudioSplashChromeActive = true
        view.backgroundColor = .black
        spriteKitView?.backgroundColor = .black
        setNeedsStatusBarAppearanceUpdate()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        if isStudioSplashChromeActive { return .lightContent }
        return BlomixAppearance.statusBarStyle
    }

    @objc private func handleMatchStartedForTutorial(_ notification: Notification) {
        // L'overlay statique est remplacé par le tutoriel interactif intégré dans GameScene.
        // Cette notification reste observée pour compatibilité mais ne fait plus rien ici.
    }

    @objc private func handleGameCenterAuthDidChange(_ notification: Notification) {
        _ = notification
        registerGameCenterInviteListenerIfNeeded()
    }

    @objc private func handleOutgoingInviteStateChanged(_ notification: Notification) {
        let active = (notification.userInfo?["active"] as? Bool) ?? false
        outgoingInviteActive = active
        outgoingInviteTargetPlayerID = notification.userInfo?["targetPlayerID"] as? String
        outgoingInviteSafetyTimer?.invalidate()
        outgoingInviteSafetyTimer = nil
        if active {
            // Timer de sécurité : 90 s (timeout invite 60 s + marge) pour éviter un état bloqué.
            outgoingInviteSafetyTimer = Timer.scheduledTimer(withTimeInterval: 90, repeats: false) { [weak self] _ in
                guard let self, self.outgoingInviteActive else { return }
                print("[PvP] Safety timer — réinitialisation outgoingInviteActive")
                self.outgoingInviteActive = false
                self.outgoingInviteTargetPlayerID = nil
            }
        }
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
            // La scène n'est pas encore prête : on met le match en attente.
            // Si un ancien pendingPvPMatch traîne, on le raccroche pour éviter
            // qu'un GKMatch orphelin tente d'envoyer des données en arrière-plan.
            if let old = pendingPvPMatch, old !== match { old.disconnect() }
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

    // MARK: - Défi CloudKit entrant (overlay global)

    @objc private func handleIncomingChallengeDetected(_ notification: Notification) {
        guard
            let challengerID   = notification.userInfo?["challengerGamePlayerID"] as? String,
            let challengerName = notification.userInfo?["challengerDisplayName"]  as? String,
            var matchGroup     = notification.userInfo?["matchPlayerGroup"]        as? Int
        else { return }
        // Secours si matchPlayerGroup invalide (ex. lecture CloudKit Int64 manquée).
        if matchGroup == 0, GKLocalPlayer.local.isAuthenticated, !challengerID.isEmpty {
            matchGroup = BlomixAvailablePlayersManager.matchPlayerGroup(
                id1: GKLocalPlayer.local.gamePlayerID, id2: challengerID)
        }
        guard matchGroup != 0 else {
            print("[PvP] Défi entrant ignoré — matchPlayerGroup invalide")
            return
        }
        // Pas de bannière pendant une partie PvP active.
        guard !BlomixAvailablePlayersManager.shared.isInActiveMatch else { return }
        // Ne pas afficher une deuxième bannière si l'une est déjà visible.
        let alreadyShowing = (view.window ?? view).subviews
            .contains(where: { $0 is BlomixChallengeBannerView })
        guard !alreadyShowing else { return }

        let challenge = BlomixIncomingChallenge(
            challengerGamePlayerID: challengerID,
            challengerDisplayName:  challengerName,
            matchPlayerGroup:       matchGroup
        )
        showChallengeBanner(challenge)
    }

    private func showChallengeBanner(_ challenge: BlomixIncomingChallenge) {
        let banner = BlomixChallengeBannerView()
        banner.configure(challengerName: challenge.challengerDisplayName)
        banner.onAccept = { [weak self] in self?.acceptIncomingChallenge(challenge) }
        banner.onDecline = { [weak self] in self?.declineIncomingChallenge() }
        let targetView: UIView = view.window ?? view
        banner.show(in: targetView, safeAreaTop: targetView.safeAreaInsets.top)
    }

    private func acceptIncomingChallenge(_ challenge: BlomixIncomingChallenge) {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        let localGameID = GKLocalPlayer.local.gamePlayerID

        var playerGroup = challenge.matchPlayerGroup
        if playerGroup == 0 {
            playerGroup = BlomixAvailablePlayersManager.matchPlayerGroup(
                id1: localGameID, id2: challenge.challengerGamePlayerID)
        }
        guard playerGroup != 0 else {
            print("[PvP] Acceptation défi impossible — matchPlayerGroup invalide")
            showChallengeTimeoutAlert()
            return
        }

        // Option B : annule proprement toute recherche automatique en cours
        // avant d'accepter un défi entrant, pour éviter le conflit GKMatchmaker.
        BlomixPvPAutoSearcher.shared.stopSearching()
        GKMatchmaker.shared().cancel()

        // On ne remet PAS clearLastNotifiedChallenger() ici :
        // le tracker doit rester positionné jusqu'à ce que le match soit lancé (ou échoue).
        // Il sera remis à nil par setActiveMatch(true) → stopChallengePolling (via GameScene)
        // ou par suppressChallengeWithDelay en cas d'échec.

        let request      = GKMatchRequest()
        request.minPlayers  = 2
        request.maxPlayers  = 2
        request.playerGroup = playerGroup

        // Affiche immédiatement l'overlay PvP (image + textes rotatifs) dès l'acceptation,
        // avant même que GKMatchmaker ait trouvé le match — évite les secondes de blanc.
        // On ferme d'abord tout modal ouvert (la bannière est une UIView, pas un modal,
        // mais l'écran de classement ou de réglages pourrait être présenté).
        if presentedViewController != nil {
            dismiss(animated: false)
        }
        if let scene = spriteKitView?.scene as? GameScene {
            scene.showPvPWaitingForMatchOverlay()
        }

        // Timer de sécurité : annule tout si le challenger ne se connecte pas dans 60 s.
        challengeMatchCancelTimer?.invalidate()
        challengeMatchCancelTimer = Timer.scheduledTimer(withTimeInterval: 60,
                                                         repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                GKMatchmaker.shared().cancel()
                self.pendingChallengeMatch?.delegate = nil
                self.pendingChallengeMatch?.disconnect()
                self.pendingChallengeMatch    = nil
                self.challengeMatchDelegate   = nil
                self.challengeMatchCancelTimer = nil
                // Retire l'overlay de préparation avant d'afficher l'alerte d'erreur.
                (self.spriteKitView?.scene as? GameScene)?.hidePvPWaitingForMatchOverlay()
                self.showChallengeTimeoutAlert()
            }
        }

        GKMatchmaker.shared().findMatch(for: request) { [weak self] match, error in
            let box = match.map { GKMatchInviteBox(match: $0) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let box {
                    // Stocker le match et attendre la connexion P2P complète via GKMatchDelegate,
                    // exactement comme le côté challenger — évite d'entrer en partie avant que
                    // expectedPlayerCount == 0 (cause principale des handshakes perdus).
                    let delegate = ChallengeMatchDelegate()
                    delegate.onConnected = { [weak self, weak delegate] in
                        guard let self else { return }
                        self.pendingChallengeMatch = nil
                        self.challengeMatchDelegate = nil
                        self.challengeMatchCancelTimer?.invalidate()
                        self.challengeMatchCancelTimer = nil
                        box.match.delegate = nil
                        GKMatchmaker.shared().finishMatchmaking(for: box.match)
                        self.beginPvPMatchOrQueueIfNeeded(box.match)
                        _ = delegate
                    }
                    delegate.onFailed = { [weak self] in
                        guard let self else { return }
                        self.pendingChallengeMatch = nil
                        self.challengeMatchDelegate = nil
                        self.challengeMatchCancelTimer?.invalidate()
                        self.challengeMatchCancelTimer = nil
                        GKMatchmaker.shared().cancel()
                        // Retire l'overlay de préparation avant d'afficher l'alerte d'erreur.
                        (self.spriteKitView?.scene as? GameScene)?.hidePvPWaitingForMatchOverlay()
                        // Échec matchmaking : libère le verrou avec délai (anti-rebond bannière).
                        BlomixAvailablePlayersManager.shared.suppressChallengeWithDelay(
                            challengedGamePlayerID: localGameID)
                        self.showChallengeTimeoutAlert()
                    }
                    self.pendingChallengeMatch  = box.match
                    self.challengeMatchDelegate = delegate
                    box.match.delegate          = delegate
                } else {
                    self.challengeMatchCancelTimer?.invalidate()
                    self.challengeMatchCancelTimer = nil
                    let desc = error?.localizedDescription ?? "inconnu"
                    print("[PvP] Défi CloudKit — matchmaking échoué : \(desc)")
                    // Retire l'overlay de préparation avant d'afficher l'alerte d'erreur.
                    (self.spriteKitView?.scene as? GameScene)?.hidePvPWaitingForMatchOverlay()
                    // Libère le verrou avec délai (anti-rebond bannière).
                    BlomixAvailablePlayersManager.shared.suppressChallengeWithDelay(
                        challengedGamePlayerID: localGameID)
                    self.showChallengeTimeoutAlert()
                }
            }
        }
    }

    private func showChallengeTimeoutAlert() {
        let alert = UIAlertController(
            title: BlomixL10n.pvpInviteErrorTitle,
            message: BlomixL10n.pvpInviteErrorMessage(""),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: BlomixL10n.ok, style: .default))
        topPresentedViewController().present(alert, animated: true)
    }

    private func declineIncomingChallenge() {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        let localGameID = GKLocalPlayer.local.gamePlayerID
        // Supprime le record et remet le tracker à nil après 8 s (anti-rebond CloudKit).
        BlomixAvailablePlayersManager.shared.suppressChallengeWithDelay(
            challengedGamePlayerID: localGameID)
    }

    // MARK: - GKLocalPlayerListener — invitation reçue

    /// Reçu quand un autre joueur BLOMIX nous invite directement (via "Adversaire récent").
    /// On crée le match sans UI native et on affiche une bannière BLOMIX.
    func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        _ = player  // local player — l'envoyeur est invite.sender
        let senderID = invite.sender.gamePlayerID
        // Ignore le callback parasite déclenché par GameKit côté émetteur lors d'une invitation sortante,
        // SAUF si c'est un "défi croisé" : l'expéditeur est le joueur qu'on est en train d'inviter.
        // Dans ce cas, son invitation constitue une réponse implicite ; on l'accepte et on annule la nôtre.
        if outgoingInviteActive {
            let isCrossChallenge = (outgoingInviteTargetPlayerID == senderID)
            if isCrossChallenge {
                print("[PvP] Défi croisé détecté avec \(invite.sender.displayName) — acceptation de son invitation")
                // On annule notre invitation sortante et on accepte la sienne.
                GKMatchmaker.shared().cancel()
                NotificationCenter.default.post(
                    name: .blomixPvPOutgoingInviteStateChanged,
                    object: nil,
                    userInfo: ["active": false]
                )
                outgoingInviteActive = false
                outgoingInviteTargetPlayerID = nil
                outgoingInviteSafetyTimer?.invalidate()
                outgoingInviteSafetyTimer = nil
            } else {
                print("[PvP] didAccept ignoré — invitation sortante en cours (expéditeur différent)")
                return
            }
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
                    let desc = error?.localizedDescription ?? "inconnu"
                    print("[PvP] Création du match depuis invitation échouée : \(desc)")
                    self.showInviteErrorAlert(senderName: inviterName)
                }
            }
        }
    }

    private func showInviteErrorAlert(senderName: String) {
        let alert = UIAlertController(
            title: BlomixL10n.pvpInviteErrorTitle,
            message: BlomixL10n.pvpInviteErrorMessage(senderName),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: BlomixL10n.ok, style: .default))
        topPresentedViewController().present(alert, animated: true)
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
