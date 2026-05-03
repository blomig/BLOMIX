//
//  BlomixPvPUI.swift
//  Blomix
//
//  Lobby multijoueur (modal) + écran de résultat PvP.
//  Pas de `GKMatchmakerViewController` système (SharePlay / feuille à trois options) : choix maison + `findMatch`.
//

import GameKit
import UIKit

/// `GKMatch` n’est pas `Sendable` ; on le transporte vers le MainActor sans avertissement Swift 6.
nonisolated struct BlomixPvPGKMatchBox: @unchecked Sendable {
    let match: GKMatch
}

@MainActor
final class BlomixPvPSearchBlocksView: UIView {
    private let blockSize: CGFloat = 18
    private let blockSpacing: CGFloat = 8
    private let gridSize = 5   // 5×5
    private var blockViews: [UIView] = []
    private var isAnimatingBlocks = false
    private var flickerTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isUserInteractionEnabled = false

        let colors = blockColors()
        for i in 0..<(gridSize * gridSize) {
            let block = UIView()
            block.backgroundColor = colors[i % colors.count]
            block.layer.cornerRadius = 3
            block.layer.borderWidth = 1
            block.layer.borderColor = UIColor(white: 1, alpha: 0.18).cgColor
            block.alpha = 0
            addSubview(block)
            blockViews.append(block)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override var intrinsicContentSize: CGSize {
        let side = CGFloat(gridSize) * blockSize + CGFloat(gridSize - 1) * blockSpacing
        return CGSize(width: side, height: side)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (index, block) in blockViews.enumerated() {
            let col = index % gridSize
            let row = index / gridSize
            let x = CGFloat(col) * (blockSize + blockSpacing)
            let y = CGFloat(row) * (blockSize + blockSpacing)
            block.frame = CGRect(x: x, y: y, width: blockSize, height: blockSize)
        }
    }

    func startAnimating() {
        guard !isAnimatingBlocks else { return }
        isAnimatingBlocks = true
        alpha = 1
        flickTick()
        let t = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.flickTick()
        }
        RunLoop.main.add(t, forMode: .common)
        flickerTimer = t
    }

    func stopAnimating(settle: Bool, completion: (() -> Void)? = nil) {
        isAnimatingBlocks = false
        flickerTimer?.invalidate()
        flickerTimer = nil
        UIView.animate(withDuration: settle ? 0.28 : 0.1,
                       delay: 0,
                       options: [.beginFromCurrentState, .curveEaseOut]) {
            self.blockViews.forEach { $0.alpha = 0 }
        } completion: { _ in
            completion?()
        }
    }

    private func flickTick() {
        guard isAnimatingBlocks else { return }
        let total = blockViews.count           // 25
        let visibleCount = total / 2           // 12
        var indices = Array(0..<total)
        indices.shuffle()
        let visible = Set(indices.prefix(visibleCount))
        UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState]) {
            for (i, block) in self.blockViews.enumerated() {
                block.alpha = visible.contains(i) ? 1 : 0
            }
        }
    }

    private func blockColors() -> [UIColor] {
        let keys = ["red", "blue", "green", "yellow", "purple", "orange"]
        let fallback: [UIColor] = [
            UIColor(red: 0xE6 / 255, green: 0x6F / 255, blue: 0x51 / 255, alpha: 1),
            UIColor(red: 0x29 / 255, green: 0x9D / 255, blue: 0x8F / 255, alpha: 1),
            UIColor(red: 0x8B / 255, green: 0xB1 / 255, blue: 0x7D / 255, alpha: 1),
            UIColor(red: 0xE8 / 255, green: 0xC4 / 255, blue: 0x6A / 255, alpha: 1),
            UIColor(red: 0x26 / 255, green: 0x47 / 255, blue: 0x53 / 255, alpha: 1),
            UIColor(red: 0xF4 / 255, green: 0xA2 / 255, blue: 0x61 / 255, alpha: 1),
        ]
        return keys.enumerated().map { index, key in
            BlomixSkinCatalog.shared.bloxUIColor(forNormalizedKey: key) ?? fallback[index]
        }
    }
}

// MARK: - Lobby / recherche

@MainActor
final class BlomixPvPLobbyViewController: UIViewController {

    @MainActor
    private enum FontTheme {
        static func gameFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
            BlomixTypography.uiFont(size: size, weight: weight)
        }
    }

    // MARK: - Machine d'état

    private enum LobbyPhase {
        /// Choix du mode : recherche auto ou adversaire récent.
        case choosingMode
        /// Recherche d'adversaire en cours via GKMatchmaker.
        case searching
        /// Adversaire trouvé ; son nom est affiché pendant la courte transition.
        case matchFound(opponentName: String)
        /// Handshake PvP en cours — grilles en préparation.
        case preparingBoards(opponentName: String)
        /// Fin anormale : message d'erreur, bouton Fermer réactivé.
        case failed(message: String)
        /// Fermeture volontaire de l'utilisateur — tous les callbacks suivants sont ignorés.
        case cancelled
    }

    private var lobbyPhase: LobbyPhase = .choosingMode

    // MARK: - Timers

    /// Déclenche « Pas de joueur présent » si findMatch ne répond pas à temps.
    private var noPlayerTimeoutTimer: Timer?
    /// Abandonne si les grilles ne sont pas prêtes dans le délai imparti.
    private var boardsPreparationWatchdog: Timer?
    private let boardsPreparationTimeout: TimeInterval = 30.0
    /// Rafraîchit l'affichage du nombre de joueurs en ligne pendant la recherche.
    private var activityRefreshTimer: Timer?
    /// Scrute match.players.first?.displayName toutes les 0,5 s pour l'afficher
    /// dès qu'il est disponible (GameKit le peuple de façon asynchrone après .connected).
    private var opponentNamePollingTimer: Timer?

    // MARK: - UI

    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let searchBlocksView = BlomixPvPSearchBlocksView()
    private let statusLabel = UILabel()
    private let hintLabel = UILabel()
    private var hasRegisteredPreparationObservers = false

    // MARK: - Mode choice UI
    private let modeStackView = UIStackView()
    private let modeAutoButton = UIButton(type: .system)
    private let modeRecentButton = UIButton(type: .system)

    var onClose: (() -> Void)?
    var onMatch: ((GKMatch) -> Void)?
    private let foundTransitionDelay: TimeInterval = 0.75

    // MARK: - Cycle de vie

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addAmbientBlocksBackground()
        registerPreparationObserversIfNeeded()
        buildLayout()
        transitionTo(.choosingMode)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAutoSearchStateChanged),
            name: .blomixPvPAutoSearchStateChanged,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // L'animation UIView démarrée dans viewDidLoad (avant la fenêtre) est annulée
        // par UIKit ; on la relance ici pour garantir le clignotement du dot.
        updateAutoButtonAppearance()
    }

    deinit {
        // opponentNamePollingTimer n'est pas invalidé ici : deinit est nonisolated (Swift 6)
        // et Timer n'est pas Sendable. Le timer se termine seul via [weak self] dès que
        // self est nil, et il est explicitement stoppé dans les handlers de fermeture.
        if hasRegisteredPreparationObservers {
            NotificationCenter.default.removeObserver(self, name: .blomixPvPBoardsReady, object: nil)
            NotificationCenter.default.removeObserver(self, name: .blomixPvPPreparationFailed, object: nil)
            NotificationCenter.default.removeObserver(self, name: .blomixPvPOpponentConnected, object: nil)
        }
        NotificationCenter.default.removeObserver(self, name: .blomixPvPAutoSearchStateChanged, object: nil)
    }

    // MARK: - Action fermeture

    @objc private func closeTapped() {
        switch lobbyPhase {
        case .choosingMode:
            transitionTo(.cancelled)
            // Ne pas annuler la recherche auto : elle continue en arrière-plan si active.
            dismiss(animated: true) { self.onClose?() }
        case .searching, .failed:
            noPlayerTimeoutTimer?.invalidate()
            activityRefreshTimer?.invalidate()
            activityRefreshTimer = nil
            GKMatchmaker.shared().cancel()
            transitionTo(.cancelled)
            dismiss(animated: true) { self.onClose?() }
        default:
            return
        }
    }

    // MARK: - Transitions d'état

    private func transitionTo(_ phase: LobbyPhase) {
        lobbyPhase = phase
        applyPhaseUI(phase)
    }

    private func applyPhaseUI(_ phase: LobbyPhase) {
        switch phase {
        case .choosingMode:
            closeButton.alpha = 1
            closeButton.isEnabled = true
            statusLabel.text = ""
            searchBlocksView.stopAnimating(settle: false)
            modeStackView.isHidden = false
            updateAutoButtonAppearance()
            queryAndDisplayPlayerActivity()
        case .searching:
            modeStackView.isHidden = true
            closeButton.alpha = 1
            closeButton.isEnabled = true
            statusLabel.text = BlomixL10n.pvpLobbyStatusSearching
            hintLabel.text = BlomixL10n.pvpLobbySearchHint
            searchBlocksView.startAnimating()
        case .matchFound(let name):
            modeStackView.isHidden = true
            closeButton.alpha = 0.45
            closeButton.isEnabled = false
            statusLabel.text = BlomixL10n.pvpLobbyOpponentFound(name)
        case .preparingBoards:
            modeStackView.isHidden = true
            closeButton.alpha = 0.45
            closeButton.isEnabled = false
            hintLabel.text = BlomixL10n.pvpLobbyPreparingBoards
            searchBlocksView.startAnimating()
            startBoardsPreparationWatchdog()
        case .failed(let message):
            modeStackView.isHidden = true
            closeButton.alpha = 1
            closeButton.isEnabled = true
            statusLabel.text = message
            searchBlocksView.stopAnimating(settle: true)
            cancelBoardsPreparationWatchdog()
        case .cancelled:
            modeStackView.isHidden = true
            searchBlocksView.stopAnimating(settle: false)
            cancelBoardsPreparationWatchdog()
        }
    }

    // MARK: - Watchdog préparation des grilles

    private func startBoardsPreparationWatchdog() {
        cancelBoardsPreparationWatchdog()
        let t = Timer.scheduledTimer(withTimeInterval: boardsPreparationTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.handleBoardsPreparationTimeout() }
        }
        RunLoop.main.add(t, forMode: .common)
        boardsPreparationWatchdog = t
    }

    private func cancelBoardsPreparationWatchdog() {
        boardsPreparationWatchdog?.invalidate()
        boardsPreparationWatchdog = nil
    }

    private func handleBoardsPreparationTimeout() {
        guard case .preparingBoards = lobbyPhase else { return }
        print("[PvP Lobby] Watchdog de préparation expiré — abandon.")
        GKMatchmaker.shared().cancel()
        transitionTo(.failed(message: BlomixL10n.pvpLobbyPreparationTimeout))
        dismiss(animated: true) { self.onClose?() }
    }

    // MARK: - Recherche d'adversaire

    private func beginMatchSearch() {
        transitionTo(.searching)
        noPlayerTimeoutTimer?.invalidate()
        activityRefreshTimer?.invalidate()
        GKMatchmaker.shared().cancel()

        // 60 s : couvre le cas où les deux joueurs n'ouvrent pas le lobby en même temps.
        noPlayerTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.handleNoPlayersTimeout() }
        }

        // Rafraîchit le compteur de joueurs en ligne toutes les 10 s pendant la recherche.
        queryAndDisplayPlayerActivity()
        let refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, case .searching = self.lobbyPhase else { return }
                self.queryAndDisplayPlayerActivity()
            }
        }
        RunLoop.main.add(refreshTimer, forMode: .common)
        activityRefreshTimer = refreshTimer

        Task { @MainActor [weak self] in
            guard let self else { return }
            let request = await BlomixEloManager.shared.makePvPMatchRequest()
            guard case .searching = self.lobbyPhase else { return }

            GKMatchmaker.shared().findMatch(for: request) { [weak self] match, error in
                let matchBox = match.map { BlomixPvPGKMatchBox(match: $0) }
                let errorText = error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.handleMatchSearchCompletion(matchBox: matchBox, errorText: errorText)
                }
            }
        }
    }

    private func queryAndDisplayPlayerActivity() {
        GKMatchmaker.shared().queryActivity { [weak self] count, error in
            Task { @MainActor in
                guard let self else { return }
                guard error == nil, count > 0 else { return }
                switch self.lobbyPhase {
                case .searching, .choosingMode:
                    self.hintLabel.text = BlomixL10n.pvpLobbyActivePlayersHint(count)
                default:
                    break
                }
            }
        }
    }

    private func handleNoPlayersTimeout() {
        guard case .searching = lobbyPhase else { return }
        activityRefreshTimer?.invalidate()
        activityRefreshTimer = nil
        GKMatchmaker.shared().cancel()
        transitionTo(.failed(message: BlomixL10n.pvpLobbyNoPlayersAvailable))
    }

    private func handleMatchSearchCompletion(matchBox: BlomixPvPGKMatchBox?, errorText: String?) {
        guard case .searching = lobbyPhase else { return }
        noPlayerTimeoutTimer?.invalidate()
        noPlayerTimeoutTimer = nil

        if let match = matchBox?.match {
            GKMatchmaker.shared().finishMatchmaking(for: match)
            activityRefreshTimer?.invalidate()
            activityRefreshTimer = nil

            // Affichage immédiat avec le meilleur nom disponible.
            let rawName = match.players.first?.displayName ?? ""
            let immediateOpponentName = (!rawName.isEmpty && !rawName.hasPrefix("G:") && !rawName.hasPrefix("A:"))
                ? rawName : BlomixL10n.pvpUnknownOpponent
            transitionTo(.matchFound(opponentName: immediateOpponentName))

            // FIX : on notifie GameScene IMMÉDIATEMENT (avant le délai d'animation)
            // pour que le coordinateur soit créé et que match.delegate soit positionné
            // maintenant — élimine la fenêtre aveugle de ~1 s où les callbacks
            // GKMatchDelegate (notamment .connected) pouvaient être perdus.
            let safeMatchBox = BlomixPvPGKMatchBox(match: match)
            onMatch?(safeMatchBox.match)

            // Scrutation active : vérifie toutes les 0,5 s si match.players.first?.displayName
            // est enfin disponible. GameKit peuple cette propriété de façon asynchrone après .connected ;
            // cela permet de mettre à jour le label dès que le nom est prêt, sans attendre la fin du handshake.
            startOpponentNamePolling(match: safeMatchBox.match)
            // Résolution authoritative en parallèle (si match.players est déjà peuplé).
            Task { @MainActor [weak self] in
                guard let self else { return }
                let resolved = await self.resolveOpponentName(from: match)
                guard resolved != BlomixL10n.pvpUnknownOpponent else { return }
                self.applyResolvedOpponentName(resolved)
            }

            // Délai purement cosmétique avant de passer à l'état "préparation".
            searchBlocksView.stopAnimating(settle: true) { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + (self?.foundTransitionDelay ?? 0.75)) { [weak self] in
                    guard let self else { return }
                    guard case .matchFound(let name) = self.lobbyPhase else { return }
                    self.transitionTo(.preparingBoards(opponentName: name))
                    // onMatch déjà appelé ci-dessus — pas de double appel.
                }
            }
            return
        }

        let message = errorText.map { BlomixL10n.pvpLobbyMatchmakingError($0) } ?? BlomixL10n.pvpLobbyMatchFailed
        transitionTo(.failed(message: message))
    }

    /// Met à jour le nom de l'adversaire dans les états .matchFound et .preparingBoards
    /// sans relancer le watchdog ni perturber les autres transitions.
    private func applyResolvedOpponentName(_ name: String) {
        switch lobbyPhase {
        case .matchFound:
            transitionTo(.matchFound(opponentName: name))
        case .preparingBoards:
            // statusLabel affiche toujours le nom issu du passage par .matchFound ;
            // on le met à jour directement sans recréer l'état (évite de relancer le watchdog).
            statusLabel.text = BlomixL10n.pvpLobbyOpponentFound(name)
        default:
            break
        }
    }

    // MARK: - Scrutation du nom de l'adversaire

    /// Démarre un timer qui sonde match.players.first?.displayName toutes les 0,5 s.
    /// Dès qu'un nom valide est disponible il est affiché et le timer s'arrête.
    /// GameKit peuple match.players et les propriétés des GKPlayer de façon asynchrone
    /// après la transition .connected ; la scrutation garantit qu'on affiche le nom
    /// dès qu'il est lisible, sans dépendre de loadPlayers ni du handshake.
    private func startOpponentNamePolling(match: GKMatch) {
        opponentNamePollingTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            switch self.lobbyPhase {
            case .matchFound, .preparingBoards:
                guard let player = match.players.first else { return }
                let name = player.displayName
                guard !name.isEmpty, !name.hasPrefix("G:"), !name.hasPrefix("A:"),
                      name != BlomixL10n.pvpUnknownOpponent else { return }
                self.applyResolvedOpponentName(name)
                timer.invalidate()
                self.opponentNamePollingTimer = nil
            default:
                timer.invalidate()
                self.opponentNamePollingTimer = nil
            }
        }
        RunLoop.main.add(t, forMode: .common)
        opponentNamePollingTimer = t
    }

    // MARK: - Résolution du nom de l'adversaire

    /// Tente de charger le nom Game Center réel du joueur distant.
    /// Retourne le nom immédiat si déjà valide, sinon force un chargement serveur.
    private func resolveOpponentName(from match: GKMatch) async -> String {
        guard let player = match.players.first else { return BlomixL10n.pvpUnknownOpponent }
        let immediate = player.displayName
        // Le nom est déjà valide si non vide et pas un ID technique Game Center.
        if !immediate.isEmpty && !immediate.hasPrefix("G:") && !immediate.hasPrefix("A:") {
            return immediate
        }
        // Chargement forcé depuis les serveurs Game Center.
        // On extrait le displayName (String, Sendable) dans le callback pour éviter
        // de traverser la frontière d'acteur avec un [GKPlayer] non-Sendable.
        do {
            let name: String = try await withCheckedThrowingContinuation { cont in
                GKPlayer.loadPlayers(forIdentifiers: [player.gamePlayerID]) { players, error in
                    if let error { cont.resume(throwing: error) }
                    else { cont.resume(returning: players?.first?.displayName ?? "") }
                }
            }
            return name.isEmpty ? BlomixL10n.pvpUnknownOpponent : name
        } catch {
            return immediate.isEmpty ? BlomixL10n.pvpUnknownOpponent : immediate
        }
    }

    // MARK: - Observers

    private func registerPreparationObserversIfNeeded() {
        guard !hasRegisteredPreparationObservers else { return }
        hasRegisteredPreparationObservers = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePvPBoardsReadyNotification),
            name: .blomixPvPBoardsReady,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePvPPreparationFailedNotification),
            name: .blomixPvPPreparationFailed,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpponentConnectedNotification(_:)),
            name: .blomixPvPOpponentConnected,
            object: nil
        )
    }

    @objc private func handlePvPBoardsReadyNotification() {
        // Accepte .matchFound, .preparingBoards et .choosingMode.
        // Le cas .choosingMode couvre la recherche auto : onMatch est appelé directement
        // par BlomixPvPAutoSearcher, la phase reste .choosingMode jusqu'à ce que les
        // grilles soient prêtes — on ferme alors le lobby silencieusement.
        switch lobbyPhase {
        case .matchFound, .preparingBoards, .choosingMode:
            opponentNamePollingTimer?.invalidate()
            opponentNamePollingTimer = nil
            cancelBoardsPreparationWatchdog()
            dismiss(animated: true)
        default:
            return
        }
    }

    @objc private func handlePvPPreparationFailedNotification() {
        // Même logique : accepte .choosingMode pour la recherche auto.
        switch lobbyPhase {
        case .matchFound, .preparingBoards, .choosingMode:
            opponentNamePollingTimer?.invalidate()
            opponentNamePollingTimer = nil
            transitionTo(.failed(message: BlomixL10n.pvpLobbyMatchFailed))
            dismiss(animated: true) { self.onClose?() }
        default:
            return
        }
    }

    @objc private func handleOpponentConnectedNotification(_ notification: Notification) {
        let displayName = notification.userInfo?["displayName"] as? String ?? ""
        let gamePlayerID = notification.userInfo?["gamePlayerID"] as? String ?? ""
        // Si le nom est déjà valide (ex. posté depuis blomixPvP_onHandshakeCompleteRestartBoard),
        // l'appliquer directement sans appel réseau supplémentaire.
        if !displayName.isEmpty, !displayName.hasPrefix("G:"), !displayName.hasPrefix("A:"),
           displayName != BlomixL10n.pvpUnknownOpponent {
            applyResolvedOpponentName(displayName)
            return
        }
        // Fallback : nom indisponible au moment du callback .connected → loadPlayers.
        guard !gamePlayerID.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let resolved: String = try await withCheckedThrowingContinuation { cont in
                    GKPlayer.loadPlayers(forIdentifiers: [gamePlayerID]) { players, error in
                        if let error { cont.resume(throwing: error) }
                        else { cont.resume(returning: players?.first?.displayName ?? "") }
                    }
                }
                if !resolved.isEmpty, resolved != BlomixL10n.pvpUnknownOpponent {
                    self.applyResolvedOpponentName(resolved)
                }
            } catch { /* reste sur le nom courant */ }
        }
    }

    // MARK: - Layout

    private func buildLayout() {
        titleLabel.text = BlomixL10n.pvpLobbyTitle
        titleLabel.textColor = .white
        titleLabel.font = FontTheme.gameFont(size: 26, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        closeButton.setTitle(BlomixL10n.close, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: closeButton)
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        view.addSubview(searchBlocksView)

        statusLabel.textColor = UIColor(white: 0.78, alpha: 1)
        statusLabel.font = FontTheme.gameFont(size: 18, weight: .regular)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        hintLabel.textColor = UIColor(white: 0.58, alpha: 1)
        hintLabel.font = FontTheme.gameFont(size: 12, weight: .regular)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)

        // Mode choice buttons — hint label intégré au-dessus des boutons
        let modeHintLabel = UILabel()
        modeHintLabel.text = BlomixL10n.pvpModeChoiceHint
        modeHintLabel.textColor = UIColor(white: 0.65, alpha: 1)
        modeHintLabel.font = FontTheme.gameFont(size: 15, weight: .regular)
        modeHintLabel.textAlignment = .center
        modeHintLabel.numberOfLines = 0

        for (btn, title) in [(modeAutoButton, BlomixL10n.pvpModeAutoDesc),
                             (modeRecentButton, BlomixL10n.pvpModeRecentDesc)] {
            btn.setTitle(title, for: .normal)
            BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: btn)
            btn.contentEdgeInsets = UIEdgeInsets(top: 14, left: 24, bottom: 14, right: 24)
            btn.titleLabel?.font = FontTheme.gameFont(size: 17, weight: .semibold)
        }
        modeAutoButton.addTarget(self, action: #selector(modeAutoTapped), for: .touchUpInside)
        modeRecentButton.addTarget(self, action: #selector(modeRecentTapped), for: .touchUpInside)

        modeStackView.axis = .vertical
        modeStackView.spacing = 16
        modeStackView.alignment = .fill
        modeStackView.addArrangedSubview(modeHintLabel)
        modeStackView.setCustomSpacing(24, after: modeHintLabel)
        modeStackView.addArrangedSubview(modeAutoButton)
        modeStackView.addArrangedSubview(modeRecentButton)
        modeStackView.translatesAutoresizingMaskIntoConstraints = false
        modeStackView.isHidden = true
        view.addSubview(modeStackView)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            searchBlocksView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            searchBlocksView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),

            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            statusLabel.topAnchor.constraint(equalTo: searchBlocksView.bottomAnchor, constant: 24),

            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 26),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -26),
            hintLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 14),

            // Buttons centered, below title — independent of searchBlocksView
            modeStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            modeStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            modeStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - Mode choice actions

    @objc private func handleAutoSearchStateChanged() {
        updateAutoButtonAppearance()
    }

    @objc private func modeAutoTapped() {
        if BlomixPvPAutoSearcher.shared.isSearching {
            BlomixPvPAutoSearcher.shared.stopSearching()
        } else {
            BlomixPvPAutoSearcher.shared.startSearching()
        }
        updateAutoButtonAppearance()
    }

    private func updateAutoButtonAppearance() {
        let active = BlomixPvPAutoSearcher.shared.isSearching
        let green = UIColor(red: 0.22, green: 0.72, blue: 0.37, alpha: 1)

        // Retirer le dot existant (tag 9901)
        modeAutoButton.viewWithTag(9901)?.removeFromSuperview()

        if active {
            modeAutoButton.layer.borderColor = green.cgColor
            modeAutoButton.layer.borderWidth = 1.5
            modeAutoButton.setTitleColor(green, for: .normal)
            hintLabel.text = BlomixL10n.pvpAutoSearchActiveHint

            // Dot vert pulsant à droite du texte
            let dotSize: CGFloat = 10
            let dot = UIView()
            dot.tag = 9901
            dot.backgroundColor = green
            dot.layer.cornerRadius = dotSize / 2
            dot.isUserInteractionEnabled = false
            dot.translatesAutoresizingMaskIntoConstraints = false
            modeAutoButton.addSubview(dot)
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: dotSize),
                dot.heightAnchor.constraint(equalToConstant: dotSize),
                dot.centerYAnchor.constraint(equalTo: modeAutoButton.centerYAnchor),
                dot.trailingAnchor.constraint(equalTo: modeAutoButton.trailingAnchor, constant: -16),
            ])
            UIView.animate(withDuration: 0.65, delay: 0,
                           options: [.repeat, .autoreverse, .allowUserInteraction],
                           animations: { dot.alpha = 0.25 })
        } else {
            modeAutoButton.layer.borderColor = BlomixUIDestinationButtonStyle.borderColor.cgColor
            modeAutoButton.layer.borderWidth = BlomixUIDestinationButtonStyle.hairlineBorderWidth
            modeAutoButton.setTitleColor(.white, for: .normal)
            hintLabel.text = ""
            queryAndDisplayPlayerActivity()
        }
    }

    @objc private func modeRecentTapped() {
        let recentVC = BlomixPvPRecentPlayersViewController()
        recentVC.modalPresentationStyle = .overFullScreen
        recentVC.modalTransitionStyle = .crossDissolve
        recentVC.onMatch = { [weak self] match in
            guard let self else { return }
            // Dismiss the whole stack (lobby + recentVC) then start the game.
            self.presentingViewController?.dismiss(animated: false) {
                self.onMatch?(match)
            }
        }
        present(recentVC, animated: true)
    }
}

// MARK: - Résultat

@MainActor
final class BlomixPvPResultViewController: UIViewController {

    @MainActor
    private enum FontTheme {
        static func gameFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
            BlomixTypography.uiFont(size: size, weight: weight)
        }
    }

    // MARK: - État du bouton Revanche

    private enum RematchButtonPhase {
        /// État initial — bouton "Revanche ?" actif.
        case idle
        /// Local a tapé, en attente de l'adversaire.
        case localWaiting
        /// L'adversaire a tapé en premier, en attente du local pour confirmer.
        case remoteReady
        /// Les deux ont tapé — lancement imminent.
        case launching
    }

    private var rematchPhase: RematchButtonPhase = .idle

    // MARK: - Sous-vues

    private let didWin: Bool
    private let opponentName: String
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let eloCurrentLabel = UILabel()
    private let eloDeltaLabel = UILabel()
    private let eloNewLabel = UILabel()
    private let homeButton = UIButton(type: .system)
    private let rematchButton = UIButton(type: .system)

    var onHome: (() -> Void)?
    var onRematch: (() -> Void)?

    init(didWin: Bool, opponentName: String) {
        self.didWin = didWin
        self.opponentName = opponentName
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0, alpha: 0.92)
        addAmbientBlocksBackground()

        titleLabel.text = didWin
            ? BlomixL10n.pvpResultVictoryAgainst(opponentName)
            : BlomixL10n.pvpResultDefeatAgainst(opponentName)
        subtitleLabel.text = didWin ? BlomixL10n.pvpResultWinSubtitle : BlomixL10n.pvpResultLoseSubtitle
        titleLabel.textColor = .white
        titleLabel.font = FontTheme.gameFont(size: 28, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        subtitleLabel.textColor = UIColor(white: 0.82, alpha: 1)
        subtitleLabel.font = FontTheme.gameFont(size: 15, weight: .regular)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitleLabel)

        eloCurrentLabel.textColor = UIColor(white: 0.88, alpha: 1)
        eloCurrentLabel.font = FontTheme.gameFont(size: 15, weight: .regular)
        eloCurrentLabel.textAlignment = .center
        eloCurrentLabel.numberOfLines = 0
        eloCurrentLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(eloCurrentLabel)

        eloDeltaLabel.text = BlomixL10n.pvpResultEloLoading
        eloDeltaLabel.textColor = UIColor(white: 0.82, alpha: 1)
        eloDeltaLabel.font = FontTheme.gameFont(size: 18, weight: .semibold)
        eloDeltaLabel.textAlignment = .center
        eloDeltaLabel.numberOfLines = 0
        eloDeltaLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(eloDeltaLabel)

        eloNewLabel.textColor = UIColor(white: 0.88, alpha: 1)
        eloNewLabel.font = FontTheme.gameFont(size: 15, weight: .regular)
        eloNewLabel.textAlignment = .center
        eloNewLabel.numberOfLines = 0
        eloNewLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(eloNewLabel)

        homeButton.setTitle(BlomixL10n.pvpResultBackHome, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: homeButton)
        homeButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 28, bottom: 14, right: 28)
        homeButton.translatesAutoresizingMaskIntoConstraints = false
        homeButton.addTarget(self, action: #selector(homeTapped), for: .touchUpInside)
        view.addSubview(homeButton)

        rematchButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        rematchButton.translatesAutoresizingMaskIntoConstraints = false
        rematchButton.addTarget(self, action: #selector(rematchTapped), for: .touchUpInside)
        view.addSubview(rematchButton)
        applyRematchButtonStyle()

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -60),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            eloCurrentLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 20),
            eloCurrentLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            eloCurrentLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            eloDeltaLabel.topAnchor.constraint(equalTo: eloCurrentLabel.bottomAnchor, constant: 10),
            eloDeltaLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            eloDeltaLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            eloNewLabel.topAnchor.constraint(equalTo: eloDeltaLabel.bottomAnchor, constant: 10),
            eloNewLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            eloNewLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            rematchButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            rematchButton.topAnchor.constraint(equalTo: eloNewLabel.bottomAnchor, constant: 28),

            homeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            homeButton.topAnchor.constraint(equalTo: rematchButton.bottomAnchor, constant: 14),
        ])
    }

    // MARK: - Elo

    func applyEloResult(_ result: BlomixEloResult?) {
        guard let result else {
            eloCurrentLabel.text = nil
            eloDeltaLabel.text = BlomixL10n.pvpResultEloUnavailable
            eloDeltaLabel.textColor = UIColor(white: 0.78, alpha: 1)
            eloNewLabel.text = nil
            return
        }

        let delta = result.localNewRating - result.localOldRating
        eloCurrentLabel.text = BlomixL10n.pvpResultEloCurrent(result.localOldRating)
        eloDeltaLabel.text = BlomixL10n.pvpResultEloDelta(delta)
        eloDeltaLabel.textColor = didWin
            ? UIColor(red: 0.36, green: 0.82, blue: 0.42, alpha: 1)
            : UIColor(red: 0.95, green: 0.62, blue: 0.22, alpha: 1)
        eloNewLabel.text = BlomixL10n.pvpResultEloNew(result.localNewRating)
    }

    // MARK: - Gestion de l'état Revanche

    /// Appelé par GameScene quand le coordinateur reçoit un `rematchRequest` de l'adversaire.
    func markRemotePlayerRequestedRematch() {
        switch rematchPhase {
        case .idle:
            rematchPhase = .remoteReady
        case .localWaiting:
            // Les deux ont demandé — le coordinateur va déclencher prepareForNextRound.
            rematchPhase = .launching
        default:
            break
        }
        applyRematchButtonStyle()
    }

    /// Appelé par GameScene juste avant de fermer la VC (les deux joueurs ont confirmé).
    func markLaunchingRematch() {
        rematchPhase = .launching
        applyRematchButtonStyle()
    }

    private func applyRematchButtonStyle() {
        switch rematchPhase {
        case .idle:
            rematchButton.setTitle(BlomixL10n.pvpResultRematchAsk, for: .normal)
            rematchButton.isEnabled = true
            rematchButton.alpha = 1
            BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: rematchButton)
        case .localWaiting:
            rematchButton.setTitle(BlomixL10n.pvpResultRematchWaiting, for: .normal)
            rematchButton.isEnabled = false
            rematchButton.alpha = 0.55
        case .remoteReady:
            rematchButton.setTitle(BlomixL10n.pvpResultRematchOpponentReady, for: .normal)
            rematchButton.isEnabled = true
            rematchButton.alpha = 1
            BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: rematchButton)
        case .launching:
            rematchButton.setTitle(BlomixL10n.pvpResultRematchLaunching, for: .normal)
            rematchButton.isEnabled = false
            rematchButton.alpha = 0.55
            homeButton.isEnabled = false
            homeButton.alpha = 0.4
        }
    }

    // MARK: - Actions

    @objc private func rematchTapped() {
        guard rematchPhase == .idle || rematchPhase == .remoteReady else { return }
        rematchPhase = rematchPhase == .remoteReady ? .launching : .localWaiting
        applyRematchButtonStyle()
        onRematch?()
    }

    @objc private func homeTapped() {
        dismiss(animated: true) { self.onHome?() }
    }
}

// MARK: - Adversaires récents

/// Wrapper Sendable pour [GKPlayer] (non-Sendable) traversant les frontières d'acteur.
private struct BlomixRecentPlayersBox: @unchecked Sendable {
    let players: [GKPlayer]
}

@MainActor
final class BlomixPvPRecentPlayersViewController: UIViewController {

    @MainActor
    private enum FontTheme {
        static func gameFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
            BlomixTypography.uiFont(size: size, weight: weight)
        }
    }

    // MARK: - State

    private enum Phase {
        case loading
        case loaded([RecentPlayerItem])
        case empty
        case inviting(playerName: String)
        case failed(message: String)
    }

    struct RecentPlayerItem {
        let player: GKPlayer
        var elo: Int?
        var eloLoading: Bool = true
    }

    // MARK: - Properties

    var onMatch: ((GKMatch) -> Void)?

    private var phase: Phase = .loading
    /// Match en attente de connexion complète (expectedPlayerCount > 0) après findMatch.
    private var pendingInviteMatch: GKMatch?
    private var inviteTimer: Timer?

    // MARK: - UI

    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let hintLabel = UILabel()
    private let searchBlocksView = BlomixPvPSearchBlocksView()
    private let scrollView = UIScrollView()
    private let playerStackView = UIStackView()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addAmbientBlocksBackground()
        buildLayout()
        loadRecentPlayers()
    }

    // inviteTimer est géré par [weak self] et invalidé explicitement dans les handlers — pas besoin de deinit.

    // MARK: - Layout

    private func buildLayout() {
        titleLabel.text = BlomixL10n.pvpRecentTitle
        titleLabel.textColor = .white
        titleLabel.font = FontTheme.gameFont(size: 26, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        closeButton.setTitle(BlomixL10n.close, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: closeButton)
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        view.addSubview(searchBlocksView)

        statusLabel.textColor = UIColor(white: 0.78, alpha: 1)
        statusLabel.font = FontTheme.gameFont(size: 18, weight: .regular)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        hintLabel.textColor = UIColor(white: 0.58, alpha: 1)
        hintLabel.font = FontTheme.gameFont(size: 13, weight: .regular)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)

        playerStackView.axis = .vertical
        playerStackView.spacing = 0
        playerStackView.alignment = .fill
        playerStackView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(playerStackView)
        scrollView.isHidden = true
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            searchBlocksView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            searchBlocksView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),

            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            statusLabel.topAnchor.constraint(equalTo: searchBlocksView.bottomAnchor, constant: 24),

            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 26),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -26),
            hintLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            playerStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            playerStackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            playerStackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            playerStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
        ])
    }

    // MARK: - Phase transitions

    private func applyPhase(_ newPhase: Phase) {
        phase = newPhase
        switch newPhase {
        case .loading:
            scrollView.isHidden = true
            statusLabel.text = BlomixL10n.loading
            hintLabel.text = ""
            searchBlocksView.isHidden = false
            searchBlocksView.startAnimating()
            closeButton.alpha = 1; closeButton.isEnabled = true

        case .loaded(let items):
            scrollView.isHidden = false
            statusLabel.text = ""
            hintLabel.text = ""
            searchBlocksView.stopAnimating(settle: false)
            searchBlocksView.isHidden = true
            closeButton.alpha = 1; closeButton.isEnabled = true
            rebuildPlayerList(items: items)

        case .empty:
            scrollView.isHidden = true
            statusLabel.text = BlomixL10n.pvpRecentNoPlayers
            hintLabel.text = ""
            searchBlocksView.stopAnimating(settle: false)
            searchBlocksView.isHidden = true
            closeButton.alpha = 1; closeButton.isEnabled = true

        case .inviting(let name):
            scrollView.isHidden = true
            statusLabel.text = BlomixL10n.pvpRecentInviteSent(name)
            hintLabel.text = BlomixL10n.pvpRecentInviteHint
            searchBlocksView.isHidden = false
            searchBlocksView.startAnimating()
            closeButton.alpha = 1; closeButton.isEnabled = true

        case .failed(let msg):
            scrollView.isHidden = true
            statusLabel.text = msg
            hintLabel.text = ""
            searchBlocksView.isHidden = false
            searchBlocksView.stopAnimating(settle: true)
            closeButton.alpha = 1; closeButton.isEnabled = true
        }
    }

    // MARK: - Player list

    private func rebuildPlayerList(items: [RecentPlayerItem]) {
        playerStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, item) in items.enumerated() {
            let row = makePlayerRow(item: item, index: index, totalCount: items.count)
            playerStackView.addArrangedSubview(row)
        }
    }

    private func makePlayerRow(item: RecentPlayerItem, index: Int, totalCount: Int) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Separator (skip top one)
        if index > 0 {
            let sep = UIView()
            sep.backgroundColor = UIColor(white: 0.22, alpha: 1)
            sep.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(sep)
            NSLayoutConstraint.activate([
                sep.topAnchor.constraint(equalTo: container.topAnchor),
                sep.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                sep.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                sep.heightAnchor.constraint(equalToConstant: 1),
            ])
        }

        let nameLabel = UILabel()
        nameLabel.text = item.player.displayName
        nameLabel.textColor = .white
        nameLabel.font = FontTheme.gameFont(size: 16, weight: .semibold)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let eloLabel = UILabel()
        if item.eloLoading {
            eloLabel.text = BlomixL10n.pvpRecentEloLoading
        } else if let elo = item.elo {
            eloLabel.text = BlomixL10n.leaderboardElo(elo)
        } else {
            eloLabel.text = BlomixL10n.pvpRecentEloUnavailable
        }
        eloLabel.textColor = UIColor(white: 0.55, alpha: 1)
        eloLabel.font = FontTheme.gameFont(size: 13, weight: .regular)
        eloLabel.translatesAutoresizingMaskIntoConstraints = false

        let challengeBtn = UIButton(type: .system)
        challengeBtn.setTitle(BlomixL10n.pvpRecentChallenge, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: challengeBtn)
        challengeBtn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        challengeBtn.titleLabel?.font = FontTheme.gameFont(size: 14, weight: .semibold)
        challengeBtn.translatesAutoresizingMaskIntoConstraints = false
        challengeBtn.tag = index
        challengeBtn.addTarget(self, action: #selector(challengeTapped(_:)), for: .touchUpInside)

        [nameLabel, eloLabel, challengeBtn].forEach { container.addSubview($0) }

        let topPad: CGFloat = index == 0 ? 10 : 18
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: topPad),
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),

            eloLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            eloLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            eloLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),

            challengeBtn.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            challengeBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            challengeBtn.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
        ])

        return container
    }

    // MARK: - Load recent players

    /// Trie les joueurs par Elo décroissant ; les joueurs sans Elo (jamais joué) vont en fin de liste.
    private static func sortedByElo(_ items: [RecentPlayerItem]) -> [RecentPlayerItem] {
        items.sorted {
            switch ($0.elo, $1.elo) {
            case (let a?, let b?): return a > b
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return false
            }
        }
    }

    private func loadRecentPlayers() {
        applyPhase(.loading)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let box: BlomixRecentPlayersBox = await withCheckedContinuation { cont in
                GKLocalPlayer.local.loadRecentPlayers { players, _ in
                    cont.resume(returning: BlomixRecentPlayersBox(players: players ?? []))
                }
            }
            let players = box.players
            guard !players.isEmpty else {
                self.applyPhase(.empty)
                return
            }
            var items = players.map { RecentPlayerItem(player: $0, elo: nil, eloLoading: true) }
            self.applyPhase(.loaded(items))
            // Load Elo for each player asynchronously.
            // Si completedMatchCount == 0, le joueur n'a jamais joué → Elo affiché "—".
            for index in items.indices {
                let player = items[index].player
                if let profile = try? await BlomixEloManager.shared.fetchProfile(for: player),
                   profile.completedMatchCount > 0 {
                    items[index].elo = profile.rating
                } else {
                    items[index].elo = nil  // jamais joué → "—"
                }
                items[index].eloLoading = false
                if case .loaded = self.phase {
                    self.applyPhase(.loaded(Self.sortedByElo(items)))
                }
            }
        }
    }

    // MARK: - Challenge action

    @objc private func challengeTapped(_ sender: UIButton) {
        guard case .loaded(let items) = phase, sender.tag < items.count else { return }
        let item = items[sender.tag]
        invitePlayer(item.player)
    }

    private func invitePlayer(_ player: GKPlayer) {
        let playerName = player.displayName
        applyPhase(.inviting(playerName: playerName))
        // Signale à GameViewController qu'une invitation sortante est active.
        NotificationCenter.default.post(
            name: .blomixPvPOutgoingInviteStateChanged,
            object: nil,
            userInfo: ["active": true]
        )

        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.recipients = [player]

        // 60s invite timeout : nettoie le match en attente si l'invité ne répond pas.
        inviteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                GKMatchmaker.shared().cancel()
                self.pendingInviteMatch?.delegate = nil
                self.pendingInviteMatch?.disconnect()
                self.pendingInviteMatch = nil
                self.notifyOutgoingInviteEnded()
                self.applyPhase(.failed(message: BlomixL10n.pvpRecentInviteFailed))
            }
        }

        // findMatch avec recipients se termine dès que le match est créé côté serveur,
        // AVANT que l'invité ait accepté. On ignore expectedPlayerCount (toujours 0 dans ce cas)
        // et on attend systématiquement la connexion P2P effective via GKMatchDelegate.
        GKMatchmaker.shared().findMatch(for: request) { [weak self] match, error in
            let box = match.map { BlomixPvPGKMatchBox(match: $0) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let box {
                    // Attendre la connexion effective de l'invité via GKMatchDelegate.
                    self.pendingInviteMatch = box.match
                    box.match.delegate = self
                } else {
                    self.inviteTimer?.invalidate()
                    self.inviteTimer = nil
                    self.notifyOutgoingInviteEnded()
                    let msg = error.map { BlomixL10n.pvpLobbyMatchmakingError($0.localizedDescription) }
                        ?? BlomixL10n.pvpRecentInviteFailed
                    self.applyPhase(.failed(message: msg))
                }
            }
        }
    }

    private func notifyOutgoingInviteEnded() {
        NotificationCenter.default.post(
            name: .blomixPvPOutgoingInviteStateChanged,
            object: nil,
            userInfo: ["active": false]
        )
    }

    // MARK: - Close

    @objc private func closeTapped() {
        inviteTimer?.invalidate()
        inviteTimer = nil
        GKMatchmaker.shared().cancel()
        pendingInviteMatch?.delegate = nil
        pendingInviteMatch?.disconnect()
        pendingInviteMatch = nil
        notifyOutgoingInviteEnded()
        switch phase {
        case .failed, .inviting:
            // Invite échouée ou abandonnée : ferme l'ensemble du stack (récents + lobby).
            presentingViewController?.dismiss(animated: true)
        default:
            // L'utilisateur explore la liste : revient au choix de mode.
            dismiss(animated: true)
        }
    }
}

// MARK: - GKMatchDelegate (attend la connexion complète de l'invité)

extension BlomixPvPRecentPlayersViewController: @preconcurrency GKMatchDelegate {

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        guard state == .connected else { return }
        let box = BlomixPvPGKMatchBox(match: match)
        Task { @MainActor [weak self] in
            guard let self, let pending = self.pendingInviteMatch, pending === box.match else { return }
            // Un joueur s'est connecté : vérifier que le match est complet.
            guard !box.match.players.isEmpty else { return }
            self.pendingInviteMatch = nil
            box.match.delegate = nil
            self.inviteTimer?.invalidate()
            self.inviteTimer = nil
            self.notifyOutgoingInviteEnded()
            GKMatchmaker.shared().finishMatchmaking(for: box.match)
            self.onMatch?(box.match)
        }
    }

    nonisolated func match(_ match: GKMatch, didFailWithError error: (any Error)?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.pendingInviteMatch = nil
            self.inviteTimer?.invalidate()
            self.inviteTimer = nil
            GKMatchmaker.shared().cancel()
            self.applyPhase(.failed(message: BlomixL10n.pvpRecentInviteFailed))
        }
    }
}

// MARK: - Bannière invitation in-app

/// Vue flottante qui apparaît quand un joueur reçoit une invitation pendant que l'app est au premier plan.
@MainActor
final class BlomixPvPInviteBannerView: UIView {

    @MainActor
    private enum FontTheme {
        static func gameFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
            BlomixTypography.uiFont(size: size, weight: weight)
        }
    }

    private let challengeLabel = UILabel()
    private let acceptButton = UIButton(type: .system)
    private let declineButton = UIButton(type: .system)
    private var dismissTimer: Timer?

    var onAccept: (() -> Void)?
    var onDecline: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = UIColor(white: 0.08, alpha: 0.96)
        layer.cornerRadius = 16
        layer.masksToBounds = true
        layer.borderColor = UIColor(white: 0.3, alpha: 0.6).cgColor
        layer.borderWidth = 1

        challengeLabel.textColor = .white
        challengeLabel.font = FontTheme.gameFont(size: 17, weight: .semibold)
        challengeLabel.textAlignment = .center
        challengeLabel.numberOfLines = 0
        challengeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(challengeLabel)

        acceptButton.setTitle(BlomixL10n.pvpInviteAccept, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: acceptButton)
        acceptButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        acceptButton.titleLabel?.font = FontTheme.gameFont(size: 15, weight: .semibold)
        acceptButton.translatesAutoresizingMaskIntoConstraints = false
        acceptButton.addTarget(self, action: #selector(acceptTapped), for: .touchUpInside)
        addSubview(acceptButton)

        declineButton.setTitle(BlomixL10n.pvpInviteDecline, for: .normal)
        declineButton.setTitleColor(UIColor(white: 0.55, alpha: 1), for: .normal)
        declineButton.titleLabel?.font = FontTheme.gameFont(size: 15, weight: .regular)
        declineButton.translatesAutoresizingMaskIntoConstraints = false
        declineButton.addTarget(self, action: #selector(declineTapped), for: .touchUpInside)
        addSubview(declineButton)

        let buttonStack = UIStackView(arrangedSubviews: [declineButton, acceptButton])
        buttonStack.axis = .horizontal
        buttonStack.spacing = 16
        buttonStack.alignment = .center
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(buttonStack)

        NSLayoutConstraint.activate([
            challengeLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            challengeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            challengeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            buttonStack.topAnchor.constraint(equalTo: challengeLabel.bottomAnchor, constant: 16),
            buttonStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
        ])
    }

    func configure(inviterName: String) {
        challengeLabel.text = BlomixL10n.pvpInviteChallenge(inviterName)
        // Auto-dismiss after 30s if no response
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.declineTapped() }
        }
    }

    @objc private func acceptTapped() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        dismiss { self.onAccept?() }
    }

    @objc private func declineTapped() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        dismiss { self.onDecline?() }
    }

    private func dismiss(completion: @escaping () -> Void) {
        UIView.animate(withDuration: 0.25, animations: {
            self.alpha = 0
            self.transform = CGAffineTransform(translationX: 0, y: -20)
        }, completion: { _ in
            self.removeFromSuperview()
            completion()
        })
    }

    /// Affiche la bannière dans la vue fournie (typiquement `rootViewController.view`), avec slide-in depuis le haut.
    func show(in parentView: UIView, safeAreaTop: CGFloat) {
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: -40)
        translatesAutoresizingMaskIntoConstraints = false
        parentView.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parentView.topAnchor, constant: safeAreaTop + 12),
            leadingAnchor.constraint(equalTo: parentView.leadingAnchor, constant: 16),
            trailingAnchor.constraint(equalTo: parentView.trailingAnchor, constant: -16),
        ])
        parentView.layoutIfNeeded()
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
            self.alpha = 1
            self.transform = .identity
        }
    }
}
