//
//  BlomixPvPUI.swift
//  Blomix
//
//  Lobby multijoueur (modal) + écran de résultat PvP.
//  Pas de `GKMatchmakerViewController` système (SharePlay / feuille à trois options) : choix maison + `findMatch`.
//

@preconcurrency import GameKit
import UIKit

/// `GKMatch` n’est pas `Sendable` ; on le transporte vers le MainActor sans avertissement Swift 6.
nonisolated struct BlomixPvPGKMatchBox: @unchecked Sendable {
    let match: GKMatch
}

@MainActor
final class BlomixPvPSearchBlocksView: UIView {
    /// Emprise visuelle ~119×119 (10×11 + 9×1).
    private let blockSize: CGFloat = 11
    private let blockSpacing: CGFloat = 1
    private let gridSize = 10          // 10×10
    private let snakeLength = 16       // longueur max du serpent
    private let tickInterval: TimeInterval = 0.10
    private let renderFadeDuration: TimeInterval = 0.10

    private var blockViews: [UIView] = []
    private var isAnimatingBlocks = false
    private var flickerTimer: Timer?

    // État du serpent : tête en premier.
    private var snakePositions: [(row: Int, col: Int)] = []
    private var snakeColors: [UIColor] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isUserInteractionEnabled = false

        for _ in 0..<(gridSize * gridSize) {
            let block = UIView()
            block.backgroundColor = .clear
            block.layer.cornerRadius = 0
            block.layer.borderWidth = 0.5
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
        isHidden = false
        snakePositions = []
        snakeColors = []
        // 1er tick immédiat (avant le Timer).
        snakeTick()
        // Timer déjà sur le RunLoop main : appeler snakeTick **directement**.
        // Un `Task { @MainActor }` re-file derrière le travail GC/Elo et gèle le serpent.
        let t = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            // Timer sur RunLoop.main : hop synchrone, sans `Task { @MainActor }`
            // (ce dernier passait derrière GC/Elo et gelait le serpent).
            MainActor.assumeIsolated {
                self?.snakeTick()
            }
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

    // MARK: - Logique serpent

    private func snakeTick() {
        guard isAnimatingBlocks else { return }
        let colors = blockColors()

        // Initialisation : placer la tête à une case aléatoire.
        if snakePositions.isEmpty {
            let row = Int.random(in: 0..<gridSize)
            let col = Int.random(in: 0..<gridSize)
            snakePositions = [(row, col)]
            snakeColors    = [colors.randomElement()!]
            renderSnake()
            return
        }

        let head = snakePositions[0]
        // Les cases occupées par le corps (la queue sera libérée si longueur max atteinte).
        let willRemoveTail = snakePositions.count >= snakeLength
        let bodySet = Set(snakePositions.dropLast(willRemoveTail ? 1 : 0)
                            .map { $0.row * gridSize + $0.col })

        let deltas = [(0, 1), (0, -1), (1, 0), (-1, 0)]

        // Cases voisines libres de la tête.
        let candidates: [(row: Int, col: Int)] = deltas.compactMap { dr, dc in
            let nr = head.row + dr; let nc = head.col + dc
            guard nr >= 0, nr < gridSize, nc >= 0, nc < gridSize else { return nil }
            guard !bodySet.contains(nr * gridSize + nc) else { return nil }
            return (nr, nc)
        }

        let nextPos: (row: Int, col: Int)
        if candidates.isEmpty {
            // Impasse : téléporter la tête sur une case libre aléatoire.
            let allFree = (0..<gridSize * gridSize)
                .map { (row: $0 / gridSize, col: $0 % gridSize) }
                .filter { !bodySet.contains($0.row * gridSize + $0.col) }
            guard let teleport = allFree.randomElement() else { return }
            nextPos = teleport
        } else {
            // Lookahead 1 : préférer les voisines qui ont le plus de voisines libres
            // (évite de foncer dans un cul-de-sac).
            let scored = candidates.map { pos -> (pos: (row: Int, col: Int), score: Int) in
                let free = deltas.filter { dr, dc in
                    let nr = pos.row + dr; let nc = pos.col + dc
                    guard nr >= 0, nr < gridSize, nc >= 0, nc < gridSize else { return false }
                    return !bodySet.contains(nr * gridSize + nc)
                }.count
                return (pos, free)
            }
            let maxScore = scored.map(\.score).max() ?? 0
            let best = scored.filter { $0.score == maxScore }.map(\.pos)
            nextPos = best.randomElement()!
        }

        // Avancer : nouvelle tête, couleur aléatoire.
        snakePositions.insert(nextPos, at: 0)
        snakeColors.insert(colors.randomElement()!, at: 0)

        // Tronquer la queue si longueur max dépassée.
        if snakePositions.count > snakeLength {
            snakePositions.removeLast()
            snakeColors.removeLast()
        }

        renderSnake()
    }

    private func renderSnake() {
        let snakeMap = Dictionary(
            uniqueKeysWithValues: snakePositions.enumerated()
                .map { idx, pos in (pos.row * gridSize + pos.col, idx) }
        )
        UIView.animate(withDuration: renderFadeDuration, delay: 0, options: [.beginFromCurrentState]) {
            for (i, block) in self.blockViews.enumerated() {
                let row = i / self.gridSize; let col = i % self.gridSize
                if let snakeIdx = snakeMap[row * self.gridSize + col] {
                    block.backgroundColor = self.snakeColors[snakeIdx]
                    block.alpha = 1
                } else {
                    block.alpha = 0
                }
            }
        }
    }

    // MARK: - Couleurs

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
    private let closeButton = BlomixUIButton()
    private let searchBlocksView = BlomixPvPSearchBlocksView()
    private let statusLabel = UILabel()
    private let hintLabel = UILabel()
    private var hasRegisteredPreparationObservers = false

    // MARK: - Mode choice UI
    private let modeStackView        = UIStackView()
    /// Statut dispo + compteur : sous la pile, hors du centre (ne décale pas les boutons).
    private let modeFooterStack      = UIStackView()
    private let modeQuickButton      = BlomixUIButton()
    private let modeLocalButton      = BlomixUIButton()
    private let modeAvailableButton  = BlomixUIButton()
    private let availabilityRow      = UIStackView()
    private let availabilityLabel    = UILabel()
    private let availabilitySwitch   = BlomixChromeSwitch()
    /// Statut du save CloudKit — affiché sous le toggle (debug / feedback joueur).
    private let availabilityStatusLabel = UILabel()
    /// Compteur du nombre de joueurs actuellement en recherche — affiché sous les boutons.
    private let modeActivityLabel    = UILabel()

    var onClose: (() -> Void)?
    var onMatch: ((GKMatch) -> Void)?
    /// Match Local Multipeer (Partie rapide → Local).
    var onLocalMatch: ((BlomixPvPLocalSession) -> Void)?
    private let foundTransitionDelay: TimeInterval = 0.75
    /// Session locale en cours de recherche (retenue tant que le lobby cherche).
    private var localSearchSession: BlomixPvPLocalSession?
    /// Évite d’empiler plusieurs dialogues de sélection de pairs.
    private var isShowingLocalPeerPicker = false

    // MARK: - Cycle de vie

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BlomixAppearance.sceneBackground
        addAmbientBlocksBackground()
        registerPreparationObserversIfNeeded()
        buildLayout()
        transitionTo(.choosingMode)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAvailabilityChanged),
            name: .blomixAvailabilityChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePublishResult(_:)),
            name: .blomixAvailabilityPublishResult,
            object: nil
        )
    }

    @objc private func handlePublishResult(_ notif: Notification) {
        let success = notif.userInfo?["success"] as? Bool ?? false
        let message = notif.userInfo?["message"] as? String ?? "?"
        let color: UIColor = success
            ? UIColor(red: 0.22, green: 0.72, blue: 0.37, alpha: 1)
            : .systemOrange
        setAvailabilityStatus(message, color: color)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // L'animation UIView démarrée dans viewDidLoad (avant la fenêtre) est annulée
        // par UIKit ; on la relance ici pour garantir le clignotement des dots.
        updateAvailableToggleAppearance()
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
        NotificationCenter.default.removeObserver(self, name: .blomixAvailabilityChanged, object: nil)
    }

    // MARK: - Action fermeture

    @objc private func closeTapped() {
        switch lobbyPhase {
        case .choosingMode:
            transitionTo(.cancelled)
            NotificationCenter.default.post(name: .blomixModalWillDismiss, object: nil)
            // Ne pas annuler la recherche auto : elle continue en arrière-plan si active.
            dismiss(animated: true) {
                NotificationCenter.default.post(name: .blomixModalDidDismiss, object: nil)
                self.onClose?()
            }
        case .searching, .failed:
            noPlayerTimeoutTimer?.invalidate()
            activityRefreshTimer?.invalidate()
            activityRefreshTimer = nil
            GKMatchmaker.shared().cancel()
            localSearchSession?.tearDown()
            localSearchSession = nil
            isShowingLocalPeerPicker = false
            view.window.map { host in
                host.subviews.compactMap { $0 as? BlomixInAppDialogView }.forEach { $0.removeFromSuperview() }
            }
            transitionTo(.cancelled)
            NotificationCenter.default.post(name: .blomixModalWillDismiss, object: nil)
            dismiss(animated: true) {
                NotificationCenter.default.post(name: .blomixModalDidDismiss, object: nil)
                self.onClose?()
            }
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
            setModeChoiceChromeHidden(false)
            queryAndDisplayPlayerActivity()
        case .searching:
            modeActivityLabel.text = ""
            setModeChoiceChromeHidden(true)
            closeButton.alpha = 1
            closeButton.isEnabled = true
            statusLabel.text = BlomixL10n.pvpLobbyStatusSearching
            hintLabel.text = BlomixL10n.pvpLobbySearchHint
            searchBlocksView.startAnimating()
        case .matchFound(let name):
            setModeChoiceChromeHidden(true)
            closeButton.alpha = 0.45
            closeButton.isEnabled = false
            statusLabel.text = BlomixL10n.pvpLobbyOpponentFound(name)
        case .preparingBoards:
            setModeChoiceChromeHidden(true)
            closeButton.alpha = 0.45
            closeButton.isEnabled = false
            hintLabel.text = BlomixL10n.pvpLobbyPreparingBoards
            searchBlocksView.startAnimating()
            startBoardsPreparationWatchdog()
        case .failed(let message):
            setModeChoiceChromeHidden(true)
            closeButton.alpha = 1
            closeButton.isEnabled = true
            statusLabel.text = message
            searchBlocksView.stopAnimating(settle: true)
            cancelBoardsPreparationWatchdog()
        case .cancelled:
            setModeChoiceChromeHidden(true)
            searchBlocksView.stopAnimating(settle: false)
            cancelBoardsPreparationWatchdog()
        }
    }

    private func setModeChoiceChromeHidden(_ hidden: Bool) {
        modeStackView.isHidden = hidden
        modeFooterStack.isHidden = hidden
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
        NotificationCenter.default.post(name: .blomixModalWillDismiss, object: nil)
        dismiss(animated: true) {
            NotificationCenter.default.post(name: .blomixModalDidDismiss, object: nil)
            self.onClose?()
        }
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

            do {
                let match = try await GKMatchmaker.shared().findMatch(for: request)
                guard case .searching = self.lobbyPhase else { return }
                self.handleMatchSearchCompletion(matchBox: BlomixPvPGKMatchBox(match: match), errorText: nil)
            } catch {
                guard case .searching = self.lobbyPhase else { return }
                self.handleMatchSearchCompletion(matchBox: nil, errorText: error.localizedDescription)
            }
        }
    }

    private func queryAndDisplayPlayerActivity() {
        GKMatchmaker.shared().queryActivity { [weak self] count, error in
            Task { @MainActor in
                guard let self else { return }
                switch self.lobbyPhase {
                case .choosingMode:
                    // Affiche le compteur sous les boutons ; masque si rien ou erreur.
                    if error == nil, count > 0 {
                        self.modeActivityLabel.text = BlomixL10n.pvpLobbyActivePlayersHint(count)
                    } else {
                        self.modeActivityLabel.text = ""
                    }
                case .searching:
                    if error == nil, count > 0 {
                        self.hintLabel.text = BlomixL10n.pvpLobbyActivePlayersHint(count)
                    }
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
    private weak var opponentNamePollMatch: GKMatch?

    private func startOpponentNamePolling(match: GKMatch) {
        opponentNamePollingTimer?.invalidate()
        opponentNamePollMatch = match
        let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickOpponentNamePolling()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        opponentNamePollingTimer = t
    }

    private func tickOpponentNamePolling() {
        switch lobbyPhase {
        case .matchFound, .preparingBoards:
            guard let player = opponentNamePollMatch?.players.first else { return }
            let name = player.displayName
            guard !name.isEmpty, !name.hasPrefix("G:"), !name.hasPrefix("A:"),
                  name != BlomixL10n.pvpUnknownOpponent else { return }
            applyResolvedOpponentName(name)
            opponentNamePollingTimer?.invalidate()
            opponentNamePollingTimer = nil
            opponentNamePollMatch = nil
        default:
            opponentNamePollingTimer?.invalidate()
            opponentNamePollingTimer = nil
            opponentNamePollMatch = nil
        }
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
        // Pas d'API async non-dépréciée pour un joueur arbitraire (seul loadFriends pour les amis).
        // On garde le callback déprécié encapsulé ; extraction Sendable du displayName dans le callback.
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
            NotificationCenter.default.post(name: .blomixModalWillDismiss, object: nil)
            dismiss(animated: true) {
                NotificationCenter.default.post(name: .blomixModalDidDismiss, object: nil)
                self.onClose?()
            }
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
        titleLabel.textColor = BlomixAppearance.primaryText
        titleLabel.font = FontTheme.gameFont(size: 26, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        closeButton.setTitle(BlomixL10n.close, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: closeButton)
        BlomixUIDestinationButtonStyle.applyContentInsets(UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12), to: closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        view.addSubview(searchBlocksView)

        statusLabel.textColor = BlomixAppearance.secondaryText
        statusLabel.font = FontTheme.gameFont(size: 18, weight: .regular)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        hintLabel.textColor = BlomixAppearance.tertiaryText
        hintLabel.font = FontTheme.gameFont(size: 12, weight: .regular)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)

        // Mode choice buttons — hint label intégré au-dessus des boutons
        let modeHintLabel = UILabel()
        modeHintLabel.text = BlomixL10n.pvpModeChoiceHint
        modeHintLabel.textColor = BlomixAppearance.secondaryText
        modeHintLabel.font = FontTheme.gameFont(size: 15, weight: .regular)
        modeHintLabel.textAlignment = .center
        modeHintLabel.numberOfLines = 0

        func styleModeButton(_ btn: UIButton, title: String, hero: Bool) {
            btn.setTitle(title, for: .normal)
            BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: btn)
            BlomixUIDestinationButtonStyle.applyContentInsets(UIEdgeInsets(top: 14, left: 24, bottom: 14, right: 24), to: btn)
            btn.titleLabel?.font = FontTheme.gameFont(size: hero ? 19 : 17, weight: .semibold)
        }
        styleModeButton(modeAvailableButton, title: BlomixL10n.pvpModeAvailableDesc, hero: true)
        let heroAccent = BlomixSkinCatalog.shared.bloxUIColor(forNormalizedKey: "blue")
            ?? UIColor(red: 0.35, green: 0.55, blue: 0.95, alpha: 1)
        modeAvailableButton.layer.borderWidth = 2
        modeAvailableButton.layer.borderColor = heroAccent.cgColor
        styleModeButton(modeQuickButton, title: BlomixL10n.pvpQuickMatchOnlineTitle, hero: false)
        styleModeButton(modeLocalButton, title: BlomixL10n.pvpQuickMatchLocalTitle, hero: false)
        modeAvailableButton.addTarget(self, action: #selector(modeAvailableTapped), for: .touchUpInside)
        modeQuickButton.addTarget(self, action: #selector(modeQuickTapped), for: .touchUpInside)
        modeLocalButton.addTarget(self, action: #selector(modeLocalTapped), for: .touchUpInside)

        availabilityLabel.text = BlomixL10n.pvpAvailableToggleLabel
        availabilityLabel.textColor = BlomixAppearance.primaryText
        availabilityLabel.font = FontTheme.gameFont(size: 15, weight: .regular)
        availabilityLabel.numberOfLines = 2
        availabilitySwitch.addTarget(self, action: #selector(modeAvailableToggleTapped), for: .valueChanged)
        availabilityRow.axis = .horizontal
        availabilityRow.alignment = .center
        availabilityRow.spacing = 12
        availabilityRow.addArrangedSubview(availabilityLabel)
        availabilityRow.addArrangedSubview(availabilitySwitch)

        // Message d'attente / compteur joueurs actifs (sous les boutons)
        modeActivityLabel.font = FontTheme.gameFont(size: 13, weight: .regular)
        modeActivityLabel.textAlignment = .center
        modeActivityLabel.textColor = BlomixAppearance.tertiaryText.withAlphaComponent(0.85)
        modeActivityLabel.numberOfLines = 0
        modeActivityLabel.text = ""

        modeStackView.axis = .vertical
        modeStackView.spacing = 16
        modeStackView.alignment = .fill
        modeStackView.addArrangedSubview(modeHintLabel)
        modeStackView.setCustomSpacing(24, after: modeHintLabel)
        modeStackView.addArrangedSubview(modeAvailableButton)
        let pair = UIStackView(arrangedSubviews: [modeQuickButton, modeLocalButton])
        pair.axis = .horizontal
        pair.spacing = 12
        pair.distribution = .fillEqually
        modeStackView.addArrangedSubview(pair)
        modeStackView.addArrangedSubview(availabilityRow)
        modeStackView.translatesAutoresizingMaskIntoConstraints = false
        modeStackView.isHidden = true
        view.addSubview(modeStackView)

        availabilityStatusLabel.font = FontTheme.gameFont(size: 12, weight: .regular)
        availabilityStatusLabel.textAlignment = .center
        availabilityStatusLabel.numberOfLines = 0
        availabilityStatusLabel.textColor = BlomixAppearance.tertiaryText
        availabilityStatusLabel.text = ""

        modeFooterStack.axis = .vertical
        modeFooterStack.alignment = .fill
        modeFooterStack.spacing = 8
        modeFooterStack.addArrangedSubview(availabilityStatusLabel)
        modeFooterStack.addArrangedSubview(modeActivityLabel)
        modeFooterStack.translatesAutoresizingMaskIntoConstraints = false
        modeFooterStack.isHidden = true
        view.addSubview(modeFooterStack)

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

            // Boutons centrés — le footer (statut / activité) s'affiche dessous sans les déplacer.
            modeStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            modeStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            modeStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            modeFooterStack.leadingAnchor.constraint(equalTo: modeStackView.leadingAnchor),
            modeFooterStack.trailingAnchor.constraint(equalTo: modeStackView.trailingAnchor),
            modeFooterStack.topAnchor.constraint(equalTo: modeStackView.bottomAnchor, constant: 10),
        ])
    }

    // MARK: - Mode choice actions

    @objc private func handleAvailabilityChanged() {
        updateAvailableToggleAppearance()
    }

    /// Host pour les dialogues in-app (fenêtre si dispo).
    private var dialogHostView: UIView {
        view.window ?? view
    }

    /// En ligne — matchmaking Game Center (plus de dialogue intermédiaire).
    @objc private func modeQuickTapped() {
        BlomixPvPLog.event("lobby_quick_match_online")
        beginMatchSearch()
    }

    /// Local — Multipeer (Bluetooth / Wi‑Fi).
    @objc private func modeLocalTapped() {
        beginLocalMatchSearch()
    }

    /// Ancien dialogue Partie rapide (conservé hors chemin 6.1).
    @objc private func modeQuickTappedLegacy() {
        BlomixPvPLog.event("lobby_quick_match_menu")
        BlomixInAppDialogView.presentChoices(
            in: dialogHostView,
            title: BlomixL10n.pvpQuickMatchTitle,
            message: nil,
            actions: [
                BlomixInAppDialogAction(
                    title: BlomixL10n.pvpQuickMatchLocalTitle,
                    subtitle: BlomixL10n.pvpQuickMatchLocalSubtitle
                ) { [weak self] in
                    self?.beginLocalMatchSearch()
                },
                BlomixInAppDialogAction(
                    title: BlomixL10n.pvpQuickMatchOnlineTitle,
                    subtitle: BlomixL10n.pvpQuickMatchOnlineSubtitle
                ) { [weak self] in
                    BlomixPvPLog.event("lobby_quick_match_online")
                    self?.beginMatchSearch()
                },
            ],
            cancelTitle: BlomixL10n.cancel,
            onCancel: nil
        )
    }

    /// Recherche Multipeer (Bluetooth / Wi‑Fi local).
    private func beginLocalMatchSearch() {
        BlomixPvPLog.event("lobby_quick_match_local")
        guard BlomixEloManager.shared.canStartLocalPvP,
              let session = BlomixPvPLocalSession.makeIfGCCacheAvailable() else {
            BlomixInAppDialogView.present(
                in: dialogHostView,
                title: BlomixL10n.pvpLocalGCRequiredTitle,
                message: BlomixL10n.pvpLocalGCRequiredMessage,
                buttonTitle: BlomixL10n.ok
            )
            return
        }

        localSearchSession?.tearDown()
        localSearchSession = session
        transitionTo(.searching)
        statusLabel.text = BlomixL10n.pvpLocalSearching
        hintLabel.text = BlomixL10n.pvpQuickMatchLocalSubtitle
        noPlayerTimeoutTimer?.invalidate()

        session.onPhaseChange = { [weak self] phase in
            guard let self, case .searching = self.lobbyPhase else { return }
            switch phase {
            case .searching:
                self.statusLabel.text = BlomixL10n.pvpLocalSearching
            case .connecting:
                self.statusLabel.text = BlomixL10n.pvpLocalConnecting
            case .failed(let msg):
                self.localSearchSession = nil
                self.transitionTo(.failed(message: msg))
            default:
                break
            }
        }
        session.onPeerDiscovered = { [weak self] peer, name in
            self?.presentLocalPeerPickerIfNeeded()
            _ = peer
            _ = name
        }
        session.onReady = { [weak self] readySession in
            guard let self else { return }
            guard case .searching = self.lobbyPhase else {
                readySession.tearDown()
                return
            }
            let name = readySession.remoteIdentity?.displayName ?? BlomixL10n.pvpUnknownOpponent
            self.transitionTo(.matchFound(opponentName: name))
            // Notifie la scène AVANT de lâcher la ref — le coordinateur prend ownership.
            self.onLocalMatch?(readySession)
            // Garder une ref tant que le coordinator n’a pas le strong retain (sécurité).
            self.localSearchSession = readySession
            self.searchBlocksView.stopAnimating(settle: true) { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + (self?.foundTransitionDelay ?? 0.75)) { [weak self] in
                    guard let self else { return }
                    guard case .matchFound(let n) = self.lobbyPhase else { return }
                    self.transitionTo(.preparingBoards(opponentName: n))
                }
            }
        }

        session.startSearching(timeout: 60)
        noPlayerTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, case .searching = self.lobbyPhase else { return }
                self.localSearchSession?.tearDown()
                self.localSearchSession = nil
                self.transitionTo(.failed(message: BlomixL10n.pvpLocalTimeout))
            }
        }
    }

    /// Si plusieurs pairs : liste style BLOMIX ; si un seul l’auto-invite de la session suffit.
    private func presentLocalPeerPickerIfNeeded() {
        guard case .searching = lobbyPhase else { return }
        guard let session = localSearchSession else { return }
        let peers = session.discoveredPeers
        guard peers.count > 1 else { return }
        guard !isShowingLocalPeerPicker else { return }
        isShowingLocalPeerPicker = true

        let actions: [BlomixInAppDialogAction] = peers.map { peer, name in
            BlomixInAppDialogAction(title: name) { [weak self] in
                self?.isShowingLocalPeerPicker = false
                self?.localSearchSession?.invite(peer)
            }
        }
        BlomixInAppDialogView.presentChoices(
            in: dialogHostView,
            title: BlomixL10n.pvpLocalPickPeerTitle,
            message: BlomixL10n.pvpLocalPickPeerMessage,
            actions: actions,
            cancelTitle: BlomixL10n.cancel,
            onCancel: { [weak self] in
                self?.isShowingLocalPeerPicker = false
            }
        )
    }

    @objc private func modeAvailableTapped() {
        let availVC = BlomixPvPAvailablePlayersViewController()
        availVC.modalPresentationStyle = .overFullScreen
        availVC.modalTransitionStyle = .crossDissolve
        availVC.onMatch = { [weak self] match in
            guard let self else { return }
            self.presentingViewController?.dismiss(animated: false) {
                self.onMatch?(match)
            }
        }
        present(availVC, animated: true)
    }

    @objc private func modeAvailableToggleTapped() {
        let nowActive = availabilitySwitch.isOn
        BlomixAvailablePlayersManager.shared.isAvailableForChallenge = nowActive
        // La notification blomixAvailabilityChanged déclenchera updateAvailableToggleAppearance().
        if nowActive {
            let gcOK = GKLocalPlayer.local.isAuthenticated
            if !gcOK {
                setAvailabilityStatus(BlomixL10n.pvpGcNotConnected, color: .systemOrange)
            } else {
                setAvailabilityStatus(BlomixL10n.pvpAvailabilitySending, color: BlomixAppearance.tertiaryText)
            }
        } else {
            setAvailabilityStatus("", color: .clear)
        }
    }

    private func setAvailabilityStatus(_ text: String, color: UIColor) {
        availabilityStatusLabel.text = text
        availabilityStatusLabel.textColor = color
    }

    private func updateAvailableToggleAppearance() {
        let active = BlomixAvailablePlayersManager.shared.isAvailableForChallenge
        let green  = UIColor(red: 0.22, green: 0.72, blue: 0.37, alpha: 1)
        if availabilitySwitch.isOn != active {
            availabilitySwitch.isOn = active
        }
        availabilitySwitch.refreshChrome()

        if active {
            if availabilityStatusLabel.text?.isEmpty != false {
                let player = GKLocalPlayer.local
                if player.isAuthenticated {
                    setAvailabilityStatus(BlomixL10n.pvpGcConnected(player.displayName), color: green)
                } else {
                    setAvailabilityStatus(BlomixL10n.pvpGcNotConnected, color: .systemOrange)
                }
            }
        } else {
            setAvailabilityStatus("", color: .clear)
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
    private var rematchTimeoutTimer: Timer?
    private let rematchTimeoutSeconds: TimeInterval = 45
    /// `false` tant que `applyEloResult` n'a pas été appelé (succès ou indispo).
    private var eloSettled = false
    /// Tap Accueil → récap série en cours : serpent maintenu, anti double-tap.
    private var isTransitioningToSeriesEnd = false

    // MARK: - Sous-vues

    private let didWin: Bool
    private let opponentName: String
    /// Score de la série session (ex. « ABC  1  ·  0  DEF »), nil si non affiché.
    private let seriesScoreText: String?
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let eloCurrentLabel = UILabel()
    private let eloDeltaLabel = UILabel()
    private let eloNewLabel = UILabel()
    private let seriesCaptionLabel = UILabel()
    private let seriesScoreLabel = UILabel()
    private let eloLoadingSnakeView = BlomixPvPSearchBlocksView()
    private let homeButton = BlomixUIButton()
    private let rematchButton = BlomixUIButton()

    var onHome: (() -> Void)?
    var onRematch: (() -> Void)?
    /// Appelé quand le joueur quitte pendant une attente de revanche (Accueil).
    var onRematchAbandoned: (() -> Void)?
    /// Appelé si l'adversaire ne confirme pas la revanche à temps.
    var onRematchTimeout: (() -> Void)?

    init(didWin: Bool, opponentName: String, seriesScoreText: String? = nil) {
        self.didWin = didWin
        self.opponentName = opponentName
        self.seriesScoreText = seriesScoreText
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopRematchTimeout()
        eloLoadingSnakeView.stopAnimating(settle: false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BlomixAppearance.sceneBackground.withAlphaComponent(BlomixAppearance.isDark ? 0.92 : 0.96)
        // Ambient **après** le serpent : le chrome d'attente doit être prêt dès la 1ʳᵉ frame.

        titleLabel.text = didWin
            ? BlomixL10n.pvpResultVictoryAgainst(opponentName)
            : BlomixL10n.pvpResultDefeatAgainst(opponentName)
        subtitleLabel.text = didWin ? BlomixL10n.pvpResultWinSubtitle : BlomixL10n.pvpResultLoseSubtitle
        titleLabel.textColor = BlomixAppearance.primaryText
        titleLabel.font = BlomixTypography.displayFont(size: 28, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        subtitleLabel.textColor = BlomixAppearance.secondaryText
        subtitleLabel.font = FontTheme.gameFont(size: 15, weight: .regular)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitleLabel)

        eloCurrentLabel.textColor = BlomixAppearance.secondaryText
        eloCurrentLabel.font = FontTheme.gameFont(size: 15, weight: .regular)
        eloCurrentLabel.textAlignment = .center
        eloCurrentLabel.numberOfLines = 1
        eloCurrentLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(eloCurrentLabel)

        // Texte loading par défaut ; écrasé si `applyEloResult` a déjà été appelé avant viewDidLoad.
        if !eloSettled {
            eloDeltaLabel.text = BlomixL10n.pvpResultEloLoading
            eloDeltaLabel.textColor = BlomixAppearance.secondaryText
        }
        eloDeltaLabel.font = FontTheme.gameFont(size: 18, weight: .semibold)
        eloDeltaLabel.textAlignment = .center
        eloDeltaLabel.numberOfLines = 1
        eloDeltaLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(eloDeltaLabel)

        eloNewLabel.textColor = BlomixAppearance.secondaryText
        eloNewLabel.font = FontTheme.gameFont(size: 15, weight: .regular)
        eloNewLabel.textAlignment = .center
        eloNewLabel.numberOfLines = 1
        eloNewLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(eloNewLabel)

        // Score de la série en cours (session revanches) — pure mise en page.
        let showSeries = seriesScoreText != nil
        seriesCaptionLabel.text = BlomixL10n.pvpSeriesEndSeriesCaption
        seriesCaptionLabel.textColor = BlomixAppearance.tertiaryText
        seriesCaptionLabel.font = FontTheme.gameFont(size: 13, weight: .regular)
        seriesCaptionLabel.textAlignment = .center
        seriesCaptionLabel.isHidden = !showSeries
        seriesCaptionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(seriesCaptionLabel)

        seriesScoreLabel.text = seriesScoreText
        seriesScoreLabel.textColor = BlomixAppearance.primaryText
        seriesScoreLabel.font = FontTheme.gameFont(size: 20, weight: .semibold)
        seriesScoreLabel.textAlignment = .center
        seriesScoreLabel.isHidden = !showSeries
        seriesScoreLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(seriesScoreLabel)

        eloLoadingSnakeView.translatesAutoresizingMaskIntoConstraints = false
        eloLoadingSnakeView.isHidden = true
        view.addSubview(eloLoadingSnakeView)

        homeButton.setTitle(BlomixL10n.pvpResultBackHome, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: homeButton)
        BlomixUIDestinationButtonStyle.applyContentInsets(UIEdgeInsets(top: 14, left: 28, bottom: 14, right: 28), to: homeButton)
        homeButton.translatesAutoresizingMaskIntoConstraints = false
        homeButton.addTarget(self, action: #selector(homeTapped), for: .touchUpInside)
        view.addSubview(homeButton)

        BlomixUIDestinationButtonStyle.applyContentInsets(UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24), to: rematchButton)
        rematchButton.translatesAutoresizingMaskIntoConstraints = false
        rematchButton.addTarget(self, action: #selector(rematchTapped), for: .touchUpInside)
        view.addSubview(rematchButton)
        applyRematchButtonStyle()
        applyHomeButtonStyle()

        // Zone Elo à hauteurs min fixes → pas de saut quand current/new se remplissent.
        // Boutons ancrés bas d'écran (stables, indépendants de la pile Elo).
        let constraints: [NSLayoutConstraint] = [
            eloLoadingSnakeView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            eloLoadingSnakeView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),

            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -72),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            eloCurrentLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 20),
            eloCurrentLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            eloCurrentLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            eloCurrentLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 20),

            eloDeltaLabel.topAnchor.constraint(equalTo: eloCurrentLabel.bottomAnchor, constant: 10),
            eloDeltaLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            eloDeltaLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            eloDeltaLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),

            eloNewLabel.topAnchor.constraint(equalTo: eloDeltaLabel.bottomAnchor, constant: 10),
            eloNewLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            eloNewLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            eloNewLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 20),

            seriesCaptionLabel.topAnchor.constraint(equalTo: eloNewLabel.bottomAnchor, constant: showSeries ? 16 : 0),
            seriesCaptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            seriesCaptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            seriesCaptionLabel.heightAnchor.constraint(equalToConstant: showSeries ? 18 : 0),

            seriesScoreLabel.topAnchor.constraint(equalTo: seriesCaptionLabel.bottomAnchor, constant: showSeries ? 4 : 0),
            seriesScoreLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            seriesScoreLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            seriesScoreLabel.heightAnchor.constraint(equalToConstant: showSeries ? 24 : 0),

            homeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            homeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),

            rematchButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            rematchButton.bottomAnchor.constraint(equalTo: homeButton.topAnchor, constant: -14),
        ]
        NSLayoutConstraint.activate(constraints)

        // Serpent d'attente **avant** le fond ambient (priorité 1ʳᵉ frame).
        applyEloLoadingChrome(loading: !eloSettled)
        addAmbientBlocksBackground()
    }

    // MARK: - Elo

    func applyEloResult(_ result: BlomixEloResult?) {
        guard let result else {
            eloCurrentLabel.text = nil
            eloDeltaLabel.text = BlomixL10n.pvpResultEloUnavailable
            eloDeltaLabel.textColor = BlomixAppearance.secondaryText
            eloNewLabel.text = nil
            markEloSettled()
            return
        }

        let delta = result.localNewRating - result.localOldRating
        eloCurrentLabel.text = BlomixL10n.pvpResultEloCurrent(result.localOldRating)
        eloDeltaLabel.text = BlomixL10n.pvpResultEloDelta(delta)
        eloDeltaLabel.textColor = didWin
            ? UIColor(red: 0.36, green: 0.82, blue: 0.42, alpha: 1)
            : UIColor(red: 0.95, green: 0.62, blue: 0.22, alpha: 1)
        eloNewLabel.text = BlomixL10n.pvpResultEloNew(result.localNewRating)
        markEloSettled()
    }

    private func markEloSettled() {
        guard !eloSettled else {
            if isViewLoaded { applyEloLoadingChrome(loading: false) }
            return
        }
        eloSettled = true
        if isViewLoaded {
            applyEloLoadingChrome(loading: false)
        }
    }

    /// Serpent haut d'écran + verrou Revanche pendant la maj Elo. Accueil reste cliquable.
    private func applyEloLoadingChrome(loading: Bool) {
        if loading {
            eloLoadingSnakeView.isHidden = false
            eloLoadingSnakeView.startAnimating()
        } else {
            // Ne pas couper le serpent s'il sert déjà de transition vers le récap série.
            if !isTransitioningToSeriesEnd {
                eloLoadingSnakeView.stopAnimating(settle: true) { [weak self] in
                    self?.eloLoadingSnakeView.isHidden = true
                }
            }
            // Un rematchRequest reçu pendant le loading n'a pas démarré le timeout.
            startRematchTimeoutIfNeeded()
        }
        applyRematchButtonStyle()
        applyHomeButtonStyle()
    }

    /// Pendant le calcul / present du récap série : serpent visible sur cet écran, Accueil locké.
    func beginSeriesEndLoadingChrome() {
        isTransitioningToSeriesEnd = true
        eloLoadingSnakeView.isHidden = false
        eloLoadingSnakeView.startAnimating()
        homeButton.isEnabled = false
        homeButton.alpha = 0.45
        rematchButton.isEnabled = false
        rematchButton.alpha = 0.55
    }

    // MARK: - Gestion de l'état Revanche

    /// Appelé par GameScene quand le coordinateur reçoit un `rematchRequest` de l'adversaire.
    func markRemotePlayerRequestedRematch() {
        switch rematchPhase {
        case .idle:
            rematchPhase = .remoteReady
            // Timeout seulement une fois Elo settled (sinon on mémorise l'état et on attend).
            if eloSettled { startRematchTimeoutIfNeeded() }
        case .localWaiting:
            // Les deux ont demandé — le coordinateur lancera prepareForNextRound.
            break
        default:
            break
        }
        applyRematchButtonStyle()
    }

    /// Appelé par GameScene juste avant de fermer la VC (les deux joueurs ont confirmé).
    func markLaunchingRematch() {
        stopRematchTimeout()
        rematchPhase = .launching
        applyRematchButtonStyle()
        applyHomeButtonStyle()
    }

    /// L'adversaire a quitté ou annulé la revanche.
    func handleOpponentCancelledRematch() {
        guard rematchPhase == .localWaiting || rematchPhase == .launching || rematchPhase == .remoteReady else { return }
        stopRematchTimeout()
        rematchPhase = .idle
        applyRematchButtonStyle()
        applyHomeButtonStyle()
    }

    private func startRematchTimeoutIfNeeded() {
        guard eloSettled else { return }
        guard rematchPhase == .localWaiting || rematchPhase == .remoteReady else { return }
        stopRematchTimeout()
        rematchTimeoutTimer = Timer.scheduledTimer(withTimeInterval: rematchTimeoutSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleRematchTimeout() }
        }
    }

    private func stopRematchTimeout() {
        rematchTimeoutTimer?.invalidate()
        rematchTimeoutTimer = nil
    }

    private func handleRematchTimeout() {
        guard rematchPhase == .localWaiting || rematchPhase == .remoteReady else { return }
        onRematchTimeout?()
        rematchPhase = .idle
        applyRematchButtonStyle()
    }

    private func applyRematchButtonStyle() {
        // Titre selon la phase rematch (même pendant le lock Elo).
        switch rematchPhase {
        case .idle:
            rematchButton.setTitle(BlomixL10n.pvpResultRematchAsk, for: .normal)
            BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: rematchButton)
        case .localWaiting:
            rematchButton.setTitle(BlomixL10n.pvpResultRematchWaiting, for: .normal)
            BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: rematchButton)
        case .remoteReady:
            rematchButton.setTitle(BlomixL10n.pvpResultRematchOpponentReady, for: .normal)
            BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: rematchButton)
        case .launching:
            rematchButton.setTitle(BlomixL10n.pvpResultRematchLaunching, for: .normal)
            BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: rematchButton)
        }

        // Lock pendant maj Elo : Revanche grisée / non cliquable. Accueil reste libre.
        if !eloSettled {
            rematchButton.isEnabled = false
            rematchButton.alpha = 0.55
            return
        }

        switch rematchPhase {
        case .idle, .remoteReady:
            rematchButton.isEnabled = true
            rematchButton.alpha = 1
        case .localWaiting, .launching:
            rematchButton.isEnabled = false
            rematchButton.alpha = 0.55
        }
    }

    private func applyHomeButtonStyle() {
        // Accueil cliquable sauf pendant le lancement de revanche (les deux ont confirmé).
        if rematchPhase == .launching {
            homeButton.isEnabled = false
            homeButton.alpha = 0.4
        } else {
            homeButton.isEnabled = true
            homeButton.alpha = 1
            BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: homeButton)
        }
    }

    // MARK: - Actions

    @objc private func rematchTapped() {
        guard eloSettled else { return }
        guard rematchPhase == .idle || rematchPhase == .remoteReady else { return }
        rematchPhase = .localWaiting
        applyRematchButtonStyle()
        startRematchTimeoutIfNeeded()
        onRematch?()
    }

    @objc private func homeTapped() {
        guard !isTransitioningToSeriesEnd else { return }
        if rematchPhase == .localWaiting || rematchPhase == .remoteReady {
            onRematchAbandoned?()
        }
        stopRematchTimeout()
        // Ne pas couper le serpent ici : le récap série peut l'utiliser pendant le chargement ;
        // `returnToHome` dismiss la pile entière ensuite.
        // Ne pas dismiss ici : GameScene enchaîne série-end **par-dessus** le résultat
        // (évite flash grille/solo entre les deux overlays).
        onHome?()
    }
}

// MARK: - Fin de série PvP (revanches enchaînées)

/// Overlay court après ≥ 2 parties enchaînées par revanches — style résultat PvP (Jour/Nuit).
/// Affiche la **série** session + le **total H2H** (CloudKit / cache) en best-effort.
@MainActor
final class BlomixPvPSeriesEndViewController: UIViewController {

    private let localPrefix: String
    private let remotePrefix: String
    private let localWins: Int
    private let remoteWins: Int
    private let gamesPlayed: Int
    private var h2hTotals: BlomixPvPH2HTotals?

    private let titleLabel = UILabel()
    private let seriesCaptionLabel = UILabel()
    private let scoreLabel = UILabel()
    private let totalCaptionLabel = UILabel()
    private let totalScoreLabel = UILabel()
    private let outcomeLabel = UILabel()
    private let gamesLabel = UILabel()
    private let okButton = BlomixUIButton()

    var onDismiss: (() -> Void)?

    init(
        localPrefix: String,
        remotePrefix: String,
        localWins: Int,
        remoteWins: Int,
        gamesPlayed: Int,
        initialH2HTotals: BlomixPvPH2HTotals? = nil
    ) {
        self.localPrefix = localPrefix
        self.remotePrefix = remotePrefix
        self.localWins = localWins
        self.remoteWins = remoteWins
        self.gamesPlayed = gamesPlayed
        self.h2hTotals = initialH2HTotals
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BlomixAppearance.sceneBackground.withAlphaComponent(BlomixAppearance.isDark ? 0.92 : 0.96)
        addAmbientBlocksBackground()

        titleLabel.text = BlomixL10n.pvpSeriesEndTitle
        titleLabel.textColor = BlomixAppearance.primaryText
        titleLabel.font = BlomixTypography.uiFont(size: 26, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        seriesCaptionLabel.text = BlomixL10n.pvpSeriesEndSeriesCaption
        seriesCaptionLabel.textColor = BlomixAppearance.tertiaryText
        seriesCaptionLabel.font = BlomixTypography.uiFont(size: 13, weight: .regular)
        seriesCaptionLabel.textAlignment = .center
        seriesCaptionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(seriesCaptionLabel)

        scoreLabel.text = BlomixL10n.pvpHudSeriesScore(
            localPrefix: localPrefix,
            localWins: localWins,
            remoteWins: remoteWins,
            remotePrefix: remotePrefix
        )
        scoreLabel.textColor = BlomixAppearance.primaryText
        scoreLabel.font = BlomixTypography.uiFont(size: 28, weight: .semibold)
        scoreLabel.textAlignment = .center
        scoreLabel.numberOfLines = 1
        scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scoreLabel)

        totalCaptionLabel.text = BlomixL10n.pvpSeriesEndTotalCaption
        totalCaptionLabel.textColor = BlomixAppearance.tertiaryText
        totalCaptionLabel.font = BlomixTypography.uiFont(size: 13, weight: .regular)
        totalCaptionLabel.textAlignment = .center
        totalCaptionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(totalCaptionLabel)

        totalScoreLabel.textColor = BlomixAppearance.secondaryText
        totalScoreLabel.font = BlomixTypography.uiFont(size: 20, weight: .semibold)
        totalScoreLabel.textAlignment = .center
        totalScoreLabel.numberOfLines = 1
        totalScoreLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(totalScoreLabel)
        refreshTotalLabel()

        if localWins > remoteWins {
            outcomeLabel.text = BlomixL10n.pvpSeriesEndYouLead
        } else if localWins < remoteWins {
            outcomeLabel.text = BlomixL10n.pvpSeriesEndYouTrail
        } else {
            outcomeLabel.text = BlomixL10n.pvpSeriesEndTied
        }
        outcomeLabel.textColor = BlomixAppearance.secondaryText
        outcomeLabel.font = BlomixTypography.uiFont(size: 16, weight: .regular)
        outcomeLabel.textAlignment = .center
        outcomeLabel.numberOfLines = 0
        outcomeLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(outcomeLabel)

        gamesLabel.text = BlomixL10n.pvpSeriesEndGames(gamesPlayed)
        gamesLabel.textColor = BlomixAppearance.tertiaryText
        gamesLabel.font = BlomixTypography.uiFont(size: 14, weight: .regular)
        gamesLabel.textAlignment = .center
        gamesLabel.numberOfLines = 0
        gamesLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gamesLabel)

        okButton.setTitle(BlomixL10n.pvpSeriesEndOK, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: okButton)
        BlomixUIDestinationButtonStyle.applyContentInsets(UIEdgeInsets(top: 14, left: 28, bottom: 14, right: 28), to: okButton)
        okButton.translatesAutoresizingMaskIntoConstraints = false
        okButton.addTarget(self, action: #selector(okTapped), for: .touchUpInside)
        view.addSubview(okButton)

        NSLayoutConstraint.activate([
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -100),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            seriesCaptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            seriesCaptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            seriesCaptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            scoreLabel.topAnchor.constraint(equalTo: seriesCaptionLabel.bottomAnchor, constant: 4),
            scoreLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            scoreLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            // Total historique sous le bloc série (plus bas : sous le bouton OK).
            outcomeLabel.topAnchor.constraint(equalTo: scoreLabel.bottomAnchor, constant: 14),
            outcomeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            outcomeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            gamesLabel.topAnchor.constraint(equalTo: outcomeLabel.bottomAnchor, constant: 10),
            gamesLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            gamesLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            okButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            okButton.topAnchor.constraint(equalTo: gamesLabel.bottomAnchor, constant: 28),

            totalCaptionLabel.topAnchor.constraint(equalTo: okButton.bottomAnchor, constant: 28),
            totalCaptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            totalCaptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            totalScoreLabel.topAnchor.constraint(equalTo: totalCaptionLabel.bottomAnchor, constant: 4),
            totalScoreLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            totalScoreLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
        ])
    }

    /// Mise à jour async après fetch CloudKit — **vérité cloud** (remplace, pas de max local).
    func applyH2HTotals(_ totals: BlomixPvPH2HTotals?) {
        h2hTotals = totals
        guard isViewLoaded else { return }
        refreshTotalLabel()
    }

    private func refreshTotalLabel() {
        if let t = h2hTotals, t.localWins + t.remoteWins > 0 {
            totalScoreLabel.text = BlomixL10n.pvpHudSeriesScore(
                localPrefix: localPrefix,
                localWins: t.localWins,
                remoteWins: t.remoteWins,
                remotePrefix: remotePrefix
            )
            totalScoreLabel.isHidden = false
            totalCaptionLabel.isHidden = false
        } else if let t = h2hTotals {
            // 0–0 connu
            totalScoreLabel.text = BlomixL10n.pvpHudSeriesScore(
                localPrefix: localPrefix,
                localWins: t.localWins,
                remoteWins: t.remoteWins,
                remotePrefix: remotePrefix
            )
            totalScoreLabel.isHidden = false
            totalCaptionLabel.isHidden = false
        } else {
            // Pas encore de donnée : masquer plutôt qu’afficher un faux 0–0.
            totalScoreLabel.isHidden = true
            totalCaptionLabel.isHidden = true
        }
    }

    @objc private func okTapped() {
        // Le parent (`GameScene`) prépare l'accueil sous les modales puis dismiss la pile entière
        // — éviter un dismiss local qui ferait réapparaître le résultat / la grille un instant.
        onDismiss?()
    }
}

// MARK: - Adversaires récents

/// Wrapper Sendable pour [GKPlayer] (non-Sendable) traversant les frontières d'acteur.
private struct BlomixRecentPlayersBox: @unchecked Sendable {
    let players: [GKPlayer]
}

// MARK: - Cache local des adversaires récents

struct BlomixCachedOpponent: Codable {
    var gamePlayerID: String
    var displayName: String
    var lastKnownElo: Int?
    var lastMatchDate: Date
}

/// Persiste en local (UserDefaults) la liste des N derniers adversaires rencontrés.
/// Permet d'afficher la liste immédiatement à l'ouverture, avant que GameCenter réponde.
@MainActor
final class BlomixRecentOpponentsCache {
    static let shared = BlomixRecentOpponentsCache()
    private static let defaultsKey = "blomixRecentOpponents_v1"
    private static let maxEntries = 6

    private init() {}

    func all() -> [BlomixCachedOpponent] {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let entries = try? JSONDecoder().decode([BlomixCachedOpponent].self, from: data)
        else { return [] }
        return entries
    }

    /// Enregistre ou met à jour un adversaire (tri par date décroissante, max 6 entrées).
    func record(gamePlayerID: String, displayName: String, elo: Int? = nil) {
        var entries = all()
        let now = Date()
        if let idx = entries.firstIndex(where: { $0.gamePlayerID == gamePlayerID }) {
            entries[idx].displayName = displayName
            entries[idx].lastMatchDate = now
            if let elo { entries[idx].lastKnownElo = elo }
        } else {
            entries.insert(BlomixCachedOpponent(
                gamePlayerID: gamePlayerID, displayName: displayName,
                lastKnownElo: elo, lastMatchDate: now), at: 0)
        }
        entries.sort { $0.lastMatchDate > $1.lastMatchDate }
        entries = Array(entries.prefix(Self.maxEntries))
        persist(entries)
    }

    /// Met à jour uniquement l'Elo d'un adversaire déjà enregistré.
    func updateElo(gamePlayerID: String, elo: Int?) {
        var entries = all()
        guard let idx = entries.firstIndex(where: { $0.gamePlayerID == gamePlayerID }) else { return }
        entries[idx].lastKnownElo = elo
        persist(entries)
    }

    private func persist(_ entries: [BlomixCachedOpponent]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
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
        let gamePlayerID: String
        let displayName: String
        /// nil tant que le `GKPlayer` n'est pas encore chargé depuis GameCenter (affichage depuis cache).
        var player: GKPlayer?
        var elo: Int?
        var eloLoading: Bool

        init(player: GKPlayer, elo: Int? = nil, eloLoading: Bool = true) {
            self.gamePlayerID = player.gamePlayerID
            self.displayName = player.displayName
            self.player = player
            self.elo = elo
            self.eloLoading = eloLoading
        }

        init(cached: BlomixCachedOpponent) {
            self.gamePlayerID = cached.gamePlayerID
            self.displayName = cached.displayName
            self.player = nil
            self.elo = cached.lastKnownElo
            self.eloLoading = false
        }
    }

    // MARK: - Properties

    var onMatch: ((GKMatch) -> Void)?

    private var phase: Phase = .loading
    /// Match en attente de connexion complète (expectedPlayerCount > 0) après findMatch.
    private var pendingInviteMatch: GKMatch?
    private var inviteTimer: Timer?

    // MARK: - UI

    private let titleLabel       = UILabel()
    private let closeButton      = BlomixUIButton()
    private let statusLabel      = UILabel()
    private let hintLabel        = UILabel()
    private let countdownLabel   = UILabel()
    private let searchBlocksView = BlomixPvPSearchBlocksView()
    private let scrollView       = UIScrollView()
    private let playerStackView  = UIStackView()
    private var countdownTick:        Timer?
    private var countdownSecondsLeft = 0

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BlomixAppearance.sceneBackground
        addAmbientBlocksBackground()
        buildLayout()
        loadRecentPlayers()
    }

    // inviteTimer est géré par [weak self] et invalidé explicitement dans les handlers — pas besoin de deinit.

    // MARK: - Layout

    private func buildLayout() {
        titleLabel.text = BlomixL10n.pvpRecentTitle
        titleLabel.textColor = BlomixAppearance.primaryText
        titleLabel.font = FontTheme.gameFont(size: 26, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        closeButton.setTitle(BlomixL10n.close, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: closeButton)
        BlomixUIDestinationButtonStyle.applyContentInsets(UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12), to: closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        view.addSubview(searchBlocksView)

        statusLabel.textColor = BlomixAppearance.secondaryText
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

        countdownLabel.textColor = BlomixAppearance.primaryText
        countdownLabel.font = FontTheme.gameFont(size: 52, weight: .regular)
        countdownLabel.textAlignment = .center
        countdownLabel.isHidden = true
        countdownLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(countdownLabel)

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

            countdownLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            countdownLabel.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 20),

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
            stopCountdown()
            closeButton.alpha = 1; closeButton.isEnabled = true

        case .loaded(let items):
            scrollView.isHidden = false
            statusLabel.text = ""
            hintLabel.text = ""
            searchBlocksView.stopAnimating(settle: false)
            searchBlocksView.isHidden = true
            stopCountdown()
            closeButton.alpha = 1; closeButton.isEnabled = true
            rebuildPlayerList(items: items)

        case .empty:
            scrollView.isHidden = true
            statusLabel.text = BlomixL10n.pvpRecentNoPlayers
            hintLabel.text = ""
            searchBlocksView.stopAnimating(settle: false)
            searchBlocksView.isHidden = true
            stopCountdown()
            closeButton.alpha = 1; closeButton.isEnabled = true

        case .inviting(let name):
            scrollView.isHidden = true
            statusLabel.text = BlomixL10n.pvpRecentInviteSent(name)
            hintLabel.text = BlomixL10n.pvpRecentInviteHint
            searchBlocksView.isHidden = false
            searchBlocksView.startAnimating()
            startCountdown(seconds: 60)
            closeButton.alpha = 1; closeButton.isEnabled = true

        case .failed(let msg):
            scrollView.isHidden = true
            statusLabel.text = msg
            hintLabel.text = ""
            searchBlocksView.isHidden = false
            searchBlocksView.stopAnimating(settle: true)
            stopCountdown()
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
        nameLabel.text = item.displayName
        nameLabel.textColor = BlomixAppearance.primaryText
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
        eloLabel.textColor = BlomixAppearance.tertiaryText
        eloLabel.font = FontTheme.gameFont(size: 13, weight: .regular)
        eloLabel.translatesAutoresizingMaskIntoConstraints = false

        let challengeBtn = BlomixUIButton()
        challengeBtn.setTitle(BlomixL10n.pvpRecentChallenge, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: challengeBtn)
        BlomixUIDestinationButtonStyle.applyContentInsets(UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14), to: challengeBtn)
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
        // ── Affichage immédiat depuis le cache local ─────────────────────────────
        let cached = BlomixRecentOpponentsCache.shared.all()
        if cached.isEmpty {
            applyPhase(.loading)
        } else {
            applyPhase(.loaded(cached.map { RecentPlayerItem(cached: $0) }))
        }

        // ── Refresh GameCenter en arrière-plan ───────────────────────────────────
        Task { @MainActor [weak self] in
            guard let self else { return }
            let box: BlomixRecentPlayersBox = await withCheckedContinuation { cont in
                GKLocalPlayer.local.loadRecentPlayers { players, _ in
                    cont.resume(returning: BlomixRecentPlayersBox(players: players ?? []))
                }
            }
            let gkPlayers = box.players

            if gkPlayers.isEmpty {
                // GC ne renvoie rien : conserver le cache ou passer à empty.
                if cached.isEmpty { self.applyPhase(.empty) }
                return
            }

            // Construire la liste fraîche à partir des joueurs GK.
            // Les entrées cache absentes de la liste GK sont conservées en queue.
            var items: [RecentPlayerItem] = gkPlayers.map { player in
                var item = RecentPlayerItem(player: player, eloLoading: true)
                // Pré-remplir avec l'Elo du cache pour que l'UI ne régresse pas.
                item.elo = cached.first(where: { $0.gamePlayerID == player.gamePlayerID })?.lastKnownElo
                return item
            }
            for entry in cached where !items.contains(where: { $0.gamePlayerID == entry.gamePlayerID }) {
                items.append(RecentPlayerItem(cached: entry))
            }
            self.applyPhase(.loaded(items))

            // Charger l'Elo frais pour chaque joueur GC (un par un, comme avant).
            for index in items.indices {
                guard let player = items[index].player else { continue }
                if let profile = try? await BlomixEloManager.shared.fetchProfile(for: player),
                   profile.completedMatchCount > 0 {
                    items[index].elo = profile.rating
                    BlomixRecentOpponentsCache.shared.updateElo(gamePlayerID: player.gamePlayerID, elo: profile.rating)
                } else {
                    items[index].elo = nil
                    BlomixRecentOpponentsCache.shared.updateElo(gamePlayerID: player.gamePlayerID, elo: nil)
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
        if let player = item.player {
            invitePlayer(player)
        } else {
            // GKPlayer pas encore résolu (ligne du cache) : on le charge à la demande.
            // loadPlayers(forIdentifiers:) reste le seul chemin pour un non-ami (déprécié iOS 14.5 ;
            // le remplacement loadFriends ne couvre que la liste d'amis).
            let name = item.displayName
            let gid  = item.gamePlayerID
            applyPhase(.inviting(playerName: name))
            GKPlayer.loadPlayers(forIdentifiers: [gid]) { [weak self] players, error in
                // Snapshot Sendable avant le hop MainActor (GKPlayer non-Sendable).
                struct PlayerBox: @unchecked Sendable { let player: GKPlayer }
                let box = players?.first.map { PlayerBox(player: $0) }
                let errText = error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let box {
                        self.sendInvitation(to: box.player)
                    } else {
                        let msg = errText.map { BlomixL10n.pvpLobbyMatchmakingError($0) }
                            ?? BlomixL10n.pvpRecentInviteFailed
                        self.notifyOutgoingInviteEnded()
                        self.applyPhase(.failed(message: msg))
                    }
                }
            }
        }
    }

    private func invitePlayer(_ player: GKPlayer) {
        applyPhase(.inviting(playerName: player.displayName))
        sendInvitation(to: player)
    }

    /// Envoie réellement l'invitation GKMatchmaker (appelé après que l'état .inviting est posé).
    private func sendInvitation(to player: GKPlayer) {
        // Signale à GameViewController qu'une invitation sortante est active.
        // On inclut l'ID du joueur cible pour détecter un "défi croisé" (chacun défie l'autre en même temps).
        NotificationCenter.default.post(
            name: .blomixPvPOutgoingInviteStateChanged,
            object: nil,
            userInfo: ["active": true, "targetPlayerID": player.gamePlayerID]
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
        // AVANT que l'invité ait accepté. On attend la connexion P2P via GKMatchDelegate.
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let match = try await GKMatchmaker.shared().findMatch(for: request)
                self.pendingInviteMatch = match
                match.delegate = self
            } catch {
                self.inviteTimer?.invalidate()
                self.inviteTimer = nil
                self.notifyOutgoingInviteEnded()
                self.applyPhase(.failed(message: BlomixL10n.pvpLobbyMatchmakingError(error.localizedDescription)))
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

    // MARK: - Countdown

    private func startCountdown(seconds: Int) {
        stopCountdown()
        countdownSecondsLeft = seconds
        countdownLabel.text = "\(countdownSecondsLeft)"
        countdownLabel.isHidden = false
        countdownTick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.countdownSecondsLeft = max(0, self.countdownSecondsLeft - 1)
                self.countdownLabel.text = "\(self.countdownSecondsLeft)"
            }
        }
    }

    private func stopCountdown() {
        countdownTick?.invalidate()
        countdownTick = nil
        countdownLabel.isHidden = true
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

extension BlomixPvPRecentPlayersViewController: GKMatchDelegate {

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        guard state == .connected else { return }
        let box = BlomixPvPGKMatchBox(match: match)
        Task { @MainActor [weak self] in
            guard let self, let pending = self.pendingInviteMatch, pending === box.match else { return }
            // Attendre que tous les joueurs soient connectés (expectedPlayerCount == 0 = match complet).
            guard box.match.expectedPlayerCount == 0 else { return }
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
    private let acceptButton = BlomixUIButton()
    private let declineButton = BlomixUIButton()
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
        backgroundColor = BlomixAppearance.panelFillTranslucent
        layer.cornerRadius = 16
        layer.masksToBounds = true
        layer.borderColor = UIColor(white: 0.3, alpha: 0.6).cgColor
        layer.borderWidth = 1

        challengeLabel.textColor = BlomixAppearance.primaryText
        challengeLabel.font = FontTheme.gameFont(size: 17, weight: .semibold)
        challengeLabel.textAlignment = .center
        challengeLabel.numberOfLines = 0
        challengeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(challengeLabel)

        acceptButton.setTitle(BlomixL10n.pvpInviteAccept, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: acceptButton)
        BlomixUIDestinationButtonStyle.applyContentInsets(UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20), to: acceptButton)
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
        parentView.bringSubviewToFront(self)
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

// MARK: - Bannière overlay défi CloudKit entrant (globale — affichée depuis GameViewController)

/// Bannière slide-in identique à `BlomixPvPInviteBannerView` mais pour les défis CloudKit.
/// Affiche un countdown visible et se ferme automatiquement après 60 s.
final class BlomixChallengeBannerView: UIView {

    @MainActor
    private enum FontTheme {
        static func gameFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
            BlomixTypography.uiFont(size: size, weight: weight)
        }
    }

    private let challengeLabel   = UILabel()
    private let countdownLabel   = UILabel()
    private let acceptButton     = BlomixUIButton()
    private let declineButton    = BlomixUIButton()
    private var countdownTick:   Timer?
    private var secondsLeft      = 60

    var onAccept: (() -> Void)?
    var onDecline: (() -> Void)?

    override init(frame: CGRect) { super.init(frame: frame); setupView() }
    required init?(coder: NSCoder) { super.init(coder: coder); setupView() }

    private func setupView() {
        backgroundColor = BlomixAppearance.panelFillTranslucent
        layer.cornerRadius = 16
        layer.masksToBounds = true
        layer.borderColor = UIColor(red: 0.22, green: 0.72, blue: 0.37, alpha: 0.5).cgColor
        layer.borderWidth = 1

        challengeLabel.textColor = BlomixAppearance.primaryText
        challengeLabel.font = FontTheme.gameFont(size: 17, weight: .semibold)
        challengeLabel.textAlignment = .center
        challengeLabel.numberOfLines = 0
        challengeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(challengeLabel)

        countdownLabel.textColor = UIColor(white: 0.5, alpha: 1)
        countdownLabel.font = FontTheme.gameFont(size: 13, weight: .regular)
        countdownLabel.textAlignment = .center
        countdownLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(countdownLabel)

        acceptButton.setTitle(BlomixL10n.pvpInviteAccept, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: acceptButton)
        BlomixUIDestinationButtonStyle.applyContentInsets(UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20), to: acceptButton)
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

            countdownLabel.topAnchor.constraint(equalTo: challengeLabel.bottomAnchor, constant: 4),
            countdownLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            buttonStack.topAnchor.constraint(equalTo: countdownLabel.bottomAnchor, constant: 14),
            buttonStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
        ])
    }

    func configure(challengerName: String) {
        challengeLabel.text = "⚔️ " + BlomixL10n.pvpInviteChallenge(challengerName)
        updateCountdown()
        countdownTick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.secondsLeft = max(0, self.secondsLeft - 1)
                self.updateCountdown()
                if self.secondsLeft == 0 { self.declineTapped() }
            }
        }
    }

    private func updateCountdown() {
        countdownLabel.text = "\(secondsLeft)s"
    }

    @objc private func acceptTapped() {
        countdownTick?.invalidate(); countdownTick = nil
        dismiss { self.onAccept?() }
    }

    @objc private func declineTapped() {
        countdownTick?.invalidate(); countdownTick = nil
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

    func show(in parentView: UIView, safeAreaTop: CGFloat) {
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: -40)
        translatesAutoresizingMaskIntoConstraints = false
        parentView.addSubview(self)
        parentView.bringSubviewToFront(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parentView.topAnchor, constant: safeAreaTop + 12),
            leadingAnchor.constraint(equalTo: parentView.leadingAnchor, constant: 16),
            trailingAnchor.constraint(equalTo: parentView.trailingAnchor, constant: -16),
        ])
        parentView.layoutIfNeeded()
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.8,
                       initialSpringVelocity: 0.5) {
            self.alpha = 1
            self.transform = .identity
        }
    }
}

// MARK: - Dialogue in-app (style BLOMIX — pas UIAlertController système)

/// Action d’un dialogue multi-choix (titre + sous-titre optionnel, style chip).
struct BlomixInAppDialogAction {
    let title: String
    let subtitle: String?
    let handler: () -> Void

    init(title: String, subtitle: String? = nil, handler: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.handler = handler
    }
}

/// Boîte de dialogue centrée alignée sur la confirmation « Quitter » et les bannières PvP :
/// voile, panneau arrondi, police jeu, boutons chip — thèmes Sombre / Clair via `BlomixAppearance`.
@MainActor
final class BlomixInAppDialogView: UIView {

    @MainActor
    private enum FontTheme {
        static func gameFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
            BlomixTypography.uiFont(size: size, weight: weight)
        }
    }

    private let dimView = UIView()
    private let panel = UIView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionsStack = UIStackView()
    private var actionHandlers: [() -> Void] = []
    private var onCancel: (() -> Void)?
    private var actionsTopToMessageConstraint: NSLayoutConstraint?
    private var actionsTopToTitleConstraint: NSLayoutConstraint?

    /// Présente un dialogue simple (1 bouton) — API historique.
    static func present(
        in host: UIView,
        title: String,
        message: String,
        buttonTitle: String = BlomixL10n.ok,
        onDismiss: (() -> Void)? = nil
    ) {
        presentChoices(
            in: host,
            title: title,
            message: message.isEmpty ? nil : message,
            actions: [BlomixInAppDialogAction(title: buttonTitle, handler: { onDismiss?() })],
            cancelTitle: nil,
            onCancel: nil
        )
    }

    /// Présente un dialogue multi-choix (ex. Partie rapide Local / En ligne).
    /// Boutons principaux en pile verticale ; optionnellement un bouton Annuler en bas.
    static func presentChoices(
        in host: UIView,
        title: String,
        message: String? = nil,
        actions: [BlomixInAppDialogAction],
        cancelTitle: String? = BlomixL10n.cancel,
        onCancel: (() -> Void)? = nil
    ) {
        host.subviews.compactMap { $0 as? BlomixInAppDialogView }.forEach { $0.removeFromSuperview() }
        let dialog = BlomixInAppDialogView()
        dialog.configureChoices(
            title: title,
            message: message,
            actions: actions,
            cancelTitle: cancelTitle,
            onCancel: onCancel
        )
        dialog.show(in: host)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear

        // Voile : même logique que la confirmation Quitter (Sombre / Clair).
        dimView.backgroundColor = BlomixAppearance.isDark
            ? UIColor.black.withAlphaComponent(0.72)
            : UIColor.black.withAlphaComponent(0.45)
        dimView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dimView)
        let dimTap = UITapGestureRecognizer(target: self, action: #selector(dimTapped))
        dimView.addGestureRecognizer(dimTap)

        panel.backgroundColor = BlomixAppearance.panelFill
        panel.layer.cornerRadius = 14
        panel.layer.masksToBounds = true
        panel.layer.borderWidth = 0.75
        panel.layer.borderColor = BlomixAppearance.chipBorder.cgColor
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)

        titleLabel.textColor = BlomixAppearance.primaryText
        titleLabel.font = FontTheme.gameFont(size: 18, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(titleLabel)

        messageLabel.textColor = BlomixAppearance.secondaryText
        messageLabel.font = FontTheme.gameFont(size: 13, weight: .regular)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(messageLabel)

        actionsStack.axis = .vertical
        actionsStack.spacing = 10
        actionsStack.alignment = .fill
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(actionsStack)

        let actionsTopToMessage = actionsStack.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 18)
        actionsTopToMessage.priority = .defaultHigh
        let actionsTopToTitle = actionsStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18)
        actionsTopToTitle.priority = .defaultLow
        actionsTopToMessageConstraint = actionsTopToMessage
        actionsTopToTitleConstraint = actionsTopToTitle

        NSLayoutConstraint.activate([
            dimView.topAnchor.constraint(equalTo: topAnchor),
            dimView.bottomAnchor.constraint(equalTo: bottomAnchor),
            dimView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: trailingAnchor),

            panel.centerXAnchor.constraint(equalTo: centerXAnchor),
            panel.centerYAnchor.constraint(equalTo: centerYAnchor),
            panel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 28),
            panel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -28),
            panel.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            panel.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),

            titleLabel.topAnchor.constraint(equalTo: panel.topAnchor, constant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -20),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            messageLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -20),

            actionsTopToMessage,
            actionsTopToTitle,
            actionsStack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            actionsStack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            actionsStack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -18),
        ])
    }

    private func configureChoices(
        title: String,
        message: String?,
        actions: [BlomixInAppDialogAction],
        cancelTitle: String?,
        onCancel: (() -> Void)?
    ) {
        titleLabel.text = title
        let hasMessage = message.map { !$0.isEmpty } ?? false
        if hasMessage {
            messageLabel.text = message
            messageLabel.isHidden = false
        } else {
            messageLabel.text = nil
            messageLabel.isHidden = true
        }
        actionsTopToMessageConstraint?.priority = hasMessage ? .required : .defaultLow
        actionsTopToTitleConstraint?.priority = hasMessage ? .defaultLow : .required
        self.onCancel = onCancel
        actionHandlers = []

        actionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (index, action) in actions.enumerated() {
            let btn = makeChoiceButton(title: action.title, subtitle: action.subtitle, tag: index, isCancel: false)
            actionHandlers.append(action.handler)
            actionsStack.addArrangedSubview(btn)
        }

        if let cancelTitle {
            let cancelIndex = actionHandlers.count
            actionHandlers.append { [weak self] in self?.onCancel?() }
            let cancelBtn = makeChoiceButton(title: cancelTitle, subtitle: nil, tag: cancelIndex, isCancel: true)
            actionsStack.addArrangedSubview(cancelBtn)
        }
    }

    private func makeChoiceButton(title: String, subtitle: String?, tag: Int, isCancel: Bool) -> UIButton {
        let btn = BlomixUIButton(type: .system)
        btn.tag = tag
        btn.translatesAutoresizingMaskIntoConstraints = false
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: btn)
        BlomixUIDestinationButtonStyle.applyContentInsets(
            UIEdgeInsets(top: subtitle == nil ? 12 : 10, left: 16, bottom: subtitle == nil ? 12 : 10, right: 16),
            to: btn
        )
        btn.titleLabel?.numberOfLines = 0
        btn.titleLabel?.textAlignment = .center
        btn.titleLabel?.lineBreakMode = .byWordWrapping

        let titleFont = FontTheme.gameFont(size: 16, weight: .semibold)
        let subFont = FontTheme.gameFont(size: 12, weight: .regular)
        let titleColor = BlomixAppearance.chipTitle
        let subColor = BlomixAppearance.secondaryText

        let attr = NSMutableAttributedString()
        attr.append(NSAttributedString(string: title, attributes: [
            .font: titleFont,
            .foregroundColor: titleColor
        ]))
        if let subtitle, !subtitle.isEmpty {
            attr.append(NSAttributedString(string: "\n", attributes: [.font: subFont]))
            attr.append(NSAttributedString(string: subtitle, attributes: [
                .font: subFont,
                .foregroundColor: subColor
            ]))
        }
        btn.setAttributedTitle(attr, for: .normal)

        // Annuler : un peu plus discret (même chip, alpha titre).
        if isCancel {
            btn.alpha = 0.92
        }

        btn.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
        btn.heightAnchor.constraint(greaterThanOrEqualToConstant: subtitle == nil ? 44 : 52).isActive = true
        return btn
    }

    private func show(in host: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(self)
        host.bringSubviewToFront(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: host.topAnchor),
            bottomAnchor.constraint(equalTo: host.bottomAnchor),
            leadingAnchor.constraint(equalTo: host.leadingAnchor),
            trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        alpha = 0
        panel.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(withDuration: 0.22, delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0.4) {
            self.alpha = 1
            self.panel.transform = .identity
        }
    }

    private func dismiss(then handler: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.18, animations: {
            self.alpha = 0
            self.panel.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        }, completion: { _ in
            self.removeFromSuperview()
            handler?()
        })
    }

    @objc private func actionTapped(_ sender: UIButton) {
        let index = sender.tag
        let handler = (index >= 0 && index < actionHandlers.count) ? actionHandlers[index] : nil
        dismiss(then: handler)
    }

    @objc private func dimTapped() {
        // Tap hors panneau = annuler si un cancel existe, sinon ignorer (dialogue simple OK).
        if onCancel != nil || actionHandlers.count > 1 {
            let cancelHandler = onCancel
            dismiss(then: cancelHandler)
        }
    }
}

// MARK: - Joueurs disponibles pour un défi

@MainActor
final class BlomixPvPAvailablePlayersViewController: UIViewController {

    @MainActor
    private enum FontTheme {
        static func gameFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
            BlomixTypography.uiFont(size: size, weight: weight)
        }
    }

    // MARK: - État

    private enum Phase {
        case loading
        case loaded([BlomixAvailablePlayer])
        case empty
        case inviting(playerName: String)
        case failed(message: String)
    }

    var onMatch: ((GKMatch) -> Void)?

    private var phase: Phase = .loading
    private var pendingInviteMatch:  GKMatch?
    private var inviteTimer:         Timer?
    private var countdownTick:       Timer?
    private var countdownSecondsLeft = 0
    /// Empêche les taps multiples pendant l'écriture CloudKit du défi.
    private var isSendingChallenge   = false
    // MARK: - Vues

    private let titleLabel       = UILabel()
    private let closeButton      = BlomixUIButton()
    private let statusLabel      = UILabel()
    private let hintLabel        = UILabel()
    private let countdownLabel   = UILabel()
    private let searchBlocksView = BlomixPvPSearchBlocksView()
    private let scrollView       = UIScrollView()
    private let playerStackView  = UIStackView()

    // MARK: - Cycle de vie

    private var autoRefreshTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BlomixAppearance.sceneBackground
        addAmbientBlocksBackground()
        buildLayout()
        loadAvailablePlayers()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startAutoRefresh()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopAutoRefresh()
    }

    private func startAutoRefresh() {
        stopAutoRefresh()
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch self.phase {
                case .loaded, .empty: self.refreshSilently()
                default: break
                }
            }
        }
    }

    private func refreshSilently() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let (players, _) = try? await BlomixAvailablePlayersManager.shared
                    .fetchAvailablePlayersAndChallenge() else { return }
            let newPhase: Phase = players.isEmpty ? .empty : .loaded(players)
            self.applyPhase(newPhase)
        }
    }

    private func stopAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
    }

    // MARK: - Layout

    private func buildLayout() {
        titleLabel.text = BlomixL10n.pvpAvailableTitle
        titleLabel.textColor = BlomixAppearance.primaryText
        titleLabel.font = FontTheme.gameFont(size: 26, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        closeButton.setTitle(BlomixL10n.close, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: closeButton)
        BlomixUIDestinationButtonStyle.applyContentInsets(UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12), to: closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        view.addSubview(searchBlocksView)

        statusLabel.textColor = BlomixAppearance.secondaryText
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

        countdownLabel.textColor = BlomixAppearance.primaryText
        countdownLabel.font = FontTheme.gameFont(size: 52, weight: .regular)
        countdownLabel.textAlignment = .center
        countdownLabel.isHidden = true
        countdownLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(countdownLabel)

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

            countdownLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            countdownLabel.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 20),

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

    // MARK: - Transitions d'état

    private func applyPhase(_ newPhase: Phase) {
        phase = newPhase
        switch newPhase {
        case .loading:
            scrollView.isHidden = true
            statusLabel.text = BlomixL10n.loading
            hintLabel.text = ""
            searchBlocksView.isHidden = false
            searchBlocksView.startAnimating()
            stopCountdown()
            closeButton.alpha = 1; closeButton.isEnabled = true

        case .loaded(let items):
            scrollView.isHidden = false
            statusLabel.text = ""
            hintLabel.text = items.isEmpty ? BlomixL10n.pvpAvailableEmptyHint : ""
            searchBlocksView.stopAnimating(settle: false)
            searchBlocksView.isHidden = true
            stopCountdown()
            closeButton.alpha = 1; closeButton.isEnabled = true
            rebuildPlayerList(items: items)

        case .empty:
            scrollView.isHidden = true
            statusLabel.text = BlomixL10n.pvpAvailableEmpty
            hintLabel.text = BlomixL10n.pvpAvailableEmptyHint
            searchBlocksView.stopAnimating(settle: false)
            searchBlocksView.isHidden = true
            stopCountdown()
            closeButton.alpha = 1; closeButton.isEnabled = true

        case .inviting(let name):
            scrollView.isHidden = true
            statusLabel.text = BlomixL10n.pvpRecentInviteSent(name)
            hintLabel.text = BlomixL10n.pvpAvailableInviteAppOpenHint
            searchBlocksView.isHidden = false
            searchBlocksView.startAnimating()
            startCountdown(seconds: 60)
            closeButton.alpha = 1; closeButton.isEnabled = true

        case .failed(let msg):
            scrollView.isHidden = true
            statusLabel.text = msg
            hintLabel.text = ""
            searchBlocksView.isHidden = false
            searchBlocksView.stopAnimating(settle: true)
            stopCountdown()
            closeButton.alpha = 1; closeButton.isEnabled = true
        }
    }

    // MARK: - Liste des joueurs

    private func rebuildPlayerList(items: [BlomixAvailablePlayer]) {
        playerStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Indicateur de visibilité du joueur local (rappel discret)
        let visibilityBadge = makeVisibilityBadge()
        playerStackView.addArrangedSubview(visibilityBadge)
        playerStackView.setCustomSpacing(20, after: visibilityBadge)

        for (index, item) in items.enumerated() {
            playerStackView.addArrangedSubview(makePlayerRow(item: item, index: index))
        }
    }

    /// Petite pastille indiquant si le joueur local est lui-même visible.
    private func makeVisibilityBadge() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let dot = UIView()
        let isVisible = BlomixAvailablePlayersManager.shared.isAvailableForChallenge
        let dotColor  = isVisible
            ? UIColor(red: 0.22, green: 0.72, blue: 0.37, alpha: 1)
            : UIColor(white: 0.45, alpha: 1)
        dot.backgroundColor = dotColor
        dot.layer.cornerRadius = 5
        dot.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = isVisible
            ? BlomixL10n.pvpAvailableYouAreVisible
            : BlomixL10n.pvpAvailableYouAreNotVisible
        label.textColor = dotColor
        label.font = FontTheme.gameFont(size: 13, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(dot)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 28),
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),
            dot.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            dot.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
        ])
        return container
    }

    private func makePlayerRow(item: BlomixAvailablePlayer, index: Int) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Séparateur (sauf première ligne)
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
        nameLabel.text = item.displayName
        nameLabel.textColor = item.inMatch ? BlomixAppearance.tertiaryText : BlomixAppearance.primaryText
        nameLabel.font = FontTheme.gameFont(size: 16, weight: .semibold)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let eloLabel = UILabel()
        if let elo = item.eloRating, elo > 0 {
            eloLabel.text = BlomixL10n.leaderboardElo(elo)
        } else {
            eloLabel.text = BlomixL10n.pvpRecentEloUnavailable
        }
        eloLabel.textColor = UIColor(white: item.inMatch ? 0.35 : 0.55, alpha: 1)
        eloLabel.font = FontTheme.gameFont(size: 13, weight: .regular)
        eloLabel.translatesAutoresizingMaskIntoConstraints = false

        if item.inMatch {
            // Badge "En match" — remplace le bouton Défier
            let badge = UILabel()
            badge.text = BlomixL10n.pvpPlayerInMatch
            badge.textColor = UIColor(white: 0.45, alpha: 1)
            badge.font = FontTheme.gameFont(size: 13, weight: .regular)
            badge.translatesAutoresizingMaskIntoConstraints = false

            [nameLabel, eloLabel, badge].forEach { container.addSubview($0) }

            let topPad: CGFloat = index == 0 ? 10 : 18
            NSLayoutConstraint.activate([
                nameLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: topPad),
                nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),

                eloLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
                eloLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
                eloLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),

                badge.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                badge.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                badge.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            ])
        } else {
            let challengeBtn = BlomixUIButton()
            challengeBtn.setTitle(BlomixL10n.pvpRecentChallenge, for: .normal)
            BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: challengeBtn)
            BlomixUIDestinationButtonStyle.applyContentInsets(UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14), to: challengeBtn)
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
        }

        return container
    }

    // MARK: - Chargement CloudKit

    private func loadAvailablePlayers() {
        applyPhase(.loading)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let (players, _) = try await BlomixAvailablePlayersManager.shared
                    .fetchAvailablePlayersAndChallenge()
                let newPhase: Phase = players.isEmpty ? .empty : .loaded(players)
                self.applyPhase(newPhase)
            } catch {
                self.applyPhase(.failed(message: BlomixL10n.pvpAvailableError(error.localizedDescription)))
            }
        }
    }

    // MARK: - Défi sortant (CloudKit rendez-vous + GKMatchmaker playerGroup)

    @objc private func challengeTapped(_ sender: UIButton) {
        guard !isSendingChallenge else { return }
        guard case .loaded(let items) = phase, sender.tag < items.count else { return }
        let item = items[sender.tag]
        guard GKLocalPlayer.local.isAuthenticated else { return }

        let localGameID  = GKLocalPlayer.local.gamePlayerID
        let localName    = GKLocalPlayer.local.displayName
        let targetGameID = item.gamePlayerID
        let matchGroup   = BlomixAvailablePlayersManager.matchPlayerGroup(id1: localGameID, id2: targetGameID)

        isSendingChallenge = true
        statusLabel.text = BlomixL10n.pvpAvailabilitySending

        Task { [weak self] in
            defer { self?.isSendingChallenge = false }
            guard let self else { return }
            do {
                try await BlomixAvailablePlayersManager.shared.createChallenge(
                    challengerGamePlayerID: localGameID,
                    challengerDisplayName:  localName,
                    challengedGamePlayerID: targetGameID,
                    matchPlayerGroup:       matchGroup
                )
                self.applyPhase(.inviting(playerName: item.displayName))
                self.startChallengeMatchmaking(targetGameID: targetGameID, playerGroup: matchGroup)
            } catch {
                print("[Available] challenge create error: \(error.localizedDescription)")
                self.applyPhase(.failed(
                    message: BlomixL10n.pvpAvailabilityCloudKitError(error.localizedDescription)))
            }
        }
    }

    /// Démarre GKMatchmaker avec un playerGroup déterministe — pas de recipients nécessaire.
    private func startChallengeMatchmaking(targetGameID: String, playerGroup: Int) {
        // Option B : annule proprement toute recherche automatique en cours
        // avant d'initier un défi direct, pour éviter le conflit GKMatchmaker.
        BlomixPvPAutoSearcher.shared.stopSearching()
        GKMatchmaker.shared().cancel()

        NotificationCenter.default.post(
            name: .blomixPvPOutgoingInviteStateChanged, object: nil,
            userInfo: ["active": true, "targetPlayerID": targetGameID])

        let request = GKMatchRequest()
        request.minPlayers   = 2
        request.maxPlayers   = 2
        request.playerGroup  = playerGroup

        let localGameID = GKLocalPlayer.local.isAuthenticated
            ? GKLocalPlayer.local.gamePlayerID : nil

        inviteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                GKMatchmaker.shared().cancel()
                self.pendingInviteMatch?.delegate = nil
                self.pendingInviteMatch?.disconnect()
                self.pendingInviteMatch = nil
                self.notifyOutgoingInviteEnded()
                // Supprimer le record de défi (timeout — le challengé n'a pas répondu)
                if let gid = localGameID {
                    BlomixAvailablePlayersManager.shared.clearOutgoingChallenge()
                    _ = gid
                }
                self.applyPhase(.failed(message: BlomixL10n.pvpRecentInviteFailed))
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let match = try await GKMatchmaker.shared().findMatch(for: request)
                // Défi accepté : supprimer le record CloudKit sortant local
                BlomixAvailablePlayersManager.shared.clearOutgoingChallenge()
                self.pendingInviteMatch = match
                match.delegate = self
                // Peer déjà connecté : didChange ne se rejoue pas — check immédiat + poll.
                self.checkChallengeMatchReady(match)
                self.startChallengeMatchRosterPoll(match)
            } catch {
                self.inviteTimer?.invalidate()
                self.inviteTimer = nil
                self.notifyOutgoingInviteEnded()
                self.applyPhase(.failed(message: BlomixL10n.pvpLobbyMatchmakingError(error.localizedDescription)))
            }
        }
    }

    /// Si `expectedPlayerCount == 0` et roster non vide → lance la partie.
    private func checkChallengeMatchReady(_ match: GKMatch) {
        guard pendingInviteMatch === match else { return }
        guard match.expectedPlayerCount == 0, !match.players.isEmpty else { return }
        pendingInviteMatch = nil
        match.delegate = nil
        inviteTimer?.invalidate()
        inviteTimer = nil
        challengeRosterPollTimer?.invalidate()
        challengeRosterPollTimer = nil
        notifyOutgoingInviteEnded()
        GKMatchmaker.shared().finishMatchmaking(for: match)
        onMatch?(match)
    }

    private var challengeRosterPollTimer: Timer?
    private weak var challengeRosterPollMatch: GKMatch?
    private var challengeRosterPollTicks = 0

    private func startChallengeMatchRosterPoll(_ match: GKMatch) {
        challengeRosterPollTimer?.invalidate()
        challengeRosterPollMatch = match
        challengeRosterPollTicks = 0
        let t = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickChallengeMatchRosterPoll()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        challengeRosterPollTimer = t
    }

    private func tickChallengeMatchRosterPoll() {
        guard let match = challengeRosterPollMatch else {
            challengeRosterPollTimer?.invalidate()
            challengeRosterPollTimer = nil
            return
        }
        challengeRosterPollTicks += 1
        checkChallengeMatchReady(match)
        if pendingInviteMatch == nil || challengeRosterPollTicks >= 40 {
            challengeRosterPollTimer?.invalidate()
            challengeRosterPollTimer = nil
            challengeRosterPollMatch = nil
        }
    }

    private func notifyOutgoingInviteEnded() {
        NotificationCenter.default.post(
            name: .blomixPvPOutgoingInviteStateChanged, object: nil,
            userInfo: ["active": false])
    }

    // MARK: - Décompte

    private func startCountdown(seconds: Int) {
        stopCountdown()
        countdownSecondsLeft = seconds
        countdownLabel.text = "\(countdownSecondsLeft)"
        countdownLabel.isHidden = false
        countdownTick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.countdownSecondsLeft = max(0, self.countdownSecondsLeft - 1)
                self.countdownLabel.text = "\(self.countdownSecondsLeft)"
            }
        }
    }

    private func stopCountdown() {
        countdownTick?.invalidate()
        countdownTick = nil
        countdownLabel.isHidden = true
    }

    // MARK: - Fermeture

    @objc private func closeTapped() {
        inviteTimer?.invalidate()
        inviteTimer = nil
        challengeRosterPollTimer?.invalidate()
        challengeRosterPollTimer = nil
        GKMatchmaker.shared().cancel()
        pendingInviteMatch?.delegate = nil
        pendingInviteMatch?.disconnect()
        pendingInviteMatch = nil
        notifyOutgoingInviteEnded()
        BlomixAvailablePlayersManager.shared.clearOutgoingChallenge()
        switch phase {
        case .failed, .inviting:
            presentingViewController?.dismiss(animated: true)
        default:
            dismiss(animated: true)
        }
    }
}

// MARK: - GKMatchDelegate (attend la connexion de l'invité)

extension BlomixPvPAvailablePlayersViewController: GKMatchDelegate {

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        guard state == .connected else { return }
        let box = BlomixPvPGKMatchBox(match: match)
        Task { @MainActor [weak self] in
            self?.checkChallengeMatchReady(box.match)
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
