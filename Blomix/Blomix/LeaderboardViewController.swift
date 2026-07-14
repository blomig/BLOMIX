//
//  LeaderboardViewController.swift
//  Blomix
//
//  Écran classement custom (in-app) alimenté par Game Center.
//

import GameKit
import UIKit

/// Présenté depuis `GameScene.showLeaderboard()` : écran in-app (fond noir) listant les meilleurs scores.
@MainActor
final class LeaderboardViewController: UIViewController, UITableViewDataSource {
    /// Onglet affiché à l'ouverture (disques de rang sur l'accueil, etc.).
    enum InitialTab {
        case mainScore
        case averageScore
        case zenScore
    }

    var initialTab: InitialTab = .mainScore

    @MainActor
    private enum FontTheme {
        static func gameFont(size: CGFloat, fallbackWeight: UIFont.Weight = .regular) -> UIFont {
            BlomixTypography.uiFont(size: size, weight: fallbackWeight)
        }
    }

    private struct LeaderboardRow: Sendable {
        let rank: Int
        let playerName: String
        let gamePlayerID: String
        let score: Int
        let isLocalPlayer: Bool
        /// Nombre de parties ayant servi au calcul (uniquement renseigné pour `.averageScore`, via `entry.context`).
        let gameCount: Int
    }

    private enum LeaderboardKind: CaseIterable {
        case mainScore
        case elo
        case averageScore
        case zenScore

        var title: String {
            switch self {
            case .mainScore:    return BlomixL10n.leaderboardMainTab
            case .elo:          return BlomixL10n.leaderboardEloTab
            case .averageScore: return BlomixL10n.leaderboardAvgTab
            case .zenScore:     return BlomixL10n.leaderboardZenTab
            }
        }

        var subtitle: String {
            switch self {
            case .mainScore:    return ScoreManager.mainLeaderboardID
            case .elo:          return "elotype"
            case .averageScore: return ScoreManager.averageLeaderboardID
            case .zenScore:     return ScoreManager.zenLeaderboardID
            }
        }

        var leaderboardID: String {
            switch self {
            case .mainScore:    return ScoreManager.mainLeaderboardID
            case .elo:          return "elotype"
            case .averageScore: return ScoreManager.averageLeaderboardID
            case .zenScore:     return ScoreManager.zenLeaderboardID
            }
        }

        func secondaryText(for score: Int) -> String {
            switch self {
            case .mainScore:    return BlomixL10n.leaderboardPoints(score)
            case .elo:          return BlomixL10n.leaderboardElo(score)
            case .averageScore: return BlomixL10n.leaderboardAverage(score)
            case .zenScore:     return BlomixL10n.leaderboardPoints(score)
            }
        }
    }

    // MARK: - Callback PvP
    /// Appelé quand un match GK est établi depuis le leaderboard. GameScene le branche sur `beginPvPWithMatch`.
    var onMatch: ((GKMatch) -> Void)?

    // MARK: - UI principale
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let closeButton = BlomixUIButton()
    private let tabsStack = UIStackView()
    private let mainTabButton = BlomixUIButton()
    private let eloTabButton  = BlomixUIButton()
    private let avgTabButton  = BlomixUIButton()
    private let zenTabButton  = BlomixUIButton()
    private let statusLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let spinner = BlomixPvPSearchBlocksView()
    private var selectedLeaderboardKind: LeaderboardKind = .mainScore

    private var rows: [LeaderboardRow] = [] {
        didSet { tableView.reloadData() }
    }
    /// Cache des GKPlayer de l'onglet Elo, indexés par gamePlayerID.
    /// Évite tout appel à `GKPlayer.loadPlayers(forIdentifiers:)` (source de l'erreur 5005).
    private var eloGKPlayers: [String: GKPlayer] = [:]

    // MARK: - État invitation sortante
    private var pendingInviteMatch: GKMatch?
    private var inviteTimer: Timer?
    private let inviteOverlay        = UIView()
    private let inviteAmbientBg      = BlomixAmbientBlocksView()
    private let inviteSpinner        = BlomixPvPSearchBlocksView()
    private let inviteStatusLabel    = UILabel()
    private let inviteHintLabel      = UILabel()
    private let inviteCountdownLabel = UILabel()
    private let cancelInviteBtn      = BlomixUIButton()
    private var countdownTick:        Timer?
    private var countdownSecondsLeft = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addAmbientBlocksBackground()

        selectedLeaderboardKind = leaderboardKind(for: initialTab)
        setupUI()
        loadLeaderboard()
    }

    private func leaderboardKind(for tab: InitialTab) -> LeaderboardKind {
        switch tab {
        case .mainScore:    return .mainScore
        case .averageScore: return .averageScore
        case .zenScore:     return .zenScore
        }
    }

    private func setupUI() {
        titleLabel.text = BlomixL10n.leaderboardTitle
        titleLabel.textColor = .white
        titleLabel.font = FontTheme.gameFont(size: 28, fallbackWeight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        subtitleLabel.text = BlomixL10n.leaderboardSubtitle
        subtitleLabel.textColor = UIColor(white: 0.75, alpha: 1)
        subtitleLabel.font = FontTheme.gameFont(size: 13, fallbackWeight: .medium)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitleLabel)

        tabsStack.axis = .horizontal
        tabsStack.spacing = 10
        tabsStack.distribution = .fillEqually
        tabsStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabsStack)

        mainTabButton.setTitle(BlomixL10n.leaderboardMainTab, for: .normal)
        eloTabButton.setTitle(BlomixL10n.leaderboardEloTab,  for: .normal)
        avgTabButton.setTitle(BlomixL10n.leaderboardAvgTab,  for: .normal)
        zenTabButton.setTitle(BlomixL10n.leaderboardZenTab,  for: .normal)
        [mainTabButton, eloTabButton, avgTabButton, zenTabButton].forEach {
            BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: $0)
            $0.contentEdgeInsets = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        }
        mainTabButton.addTarget(self, action: #selector(mainTabTapped), for: .touchUpInside)
        eloTabButton.addTarget(self,  action: #selector(eloTabTapped),  for: .touchUpInside)
        avgTabButton.addTarget(self,  action: #selector(avgTabTapped),  for: .touchUpInside)
        zenTabButton.addTarget(self,  action: #selector(zenTabTapped),  for: .touchUpInside)
        tabsStack.addArrangedSubview(mainTabButton)
        tabsStack.addArrangedSubview(eloTabButton)
        tabsStack.addArrangedSubview(avgTabButton)
        tabsStack.addArrangedSubview(zenTabButton)

        closeButton.setTitle(BlomixL10n.close, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: closeButton)
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        statusLabel.textColor = UIColor(white: 0.82, alpha: 1)
        statusLabel.font = FontTheme.gameFont(size: 14, fallbackWeight: .regular)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        tableView.backgroundColor = .clear
        tableView.separatorColor = UIColor(white: 0.2, alpha: 1)
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "LeaderboardCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        // ── Overlay invitation ─────────────────────────────────────────────────
        inviteOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.92)
        inviteOverlay.translatesAutoresizingMaskIntoConstraints = false
        inviteOverlay.isHidden = true
        view.addSubview(inviteOverlay)

        // Fond animé (mini-blox montants) interne à l'overlay.
        inviteAmbientBg.translatesAutoresizingMaskIntoConstraints = false
        inviteOverlay.insertSubview(inviteAmbientBg, at: 0)

        inviteSpinner.translatesAutoresizingMaskIntoConstraints = false
        inviteOverlay.addSubview(inviteSpinner)

        inviteStatusLabel.textColor = UIColor(white: 0.82, alpha: 1)
        inviteStatusLabel.font = FontTheme.gameFont(size: 18, fallbackWeight: .regular)
        inviteStatusLabel.textAlignment = .center
        inviteStatusLabel.numberOfLines = 0
        inviteStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        inviteOverlay.addSubview(inviteStatusLabel)

        inviteHintLabel.textColor = UIColor(white: 0.55, alpha: 1)
        inviteHintLabel.font = FontTheme.gameFont(size: 13, fallbackWeight: .regular)
        inviteHintLabel.textAlignment = .center
        inviteHintLabel.numberOfLines = 0
        inviteHintLabel.translatesAutoresizingMaskIntoConstraints = false
        inviteOverlay.addSubview(inviteHintLabel)

        inviteCountdownLabel.textColor = UIColor(white: 0.9, alpha: 1)
        inviteCountdownLabel.font = FontTheme.gameFont(size: 52, fallbackWeight: .regular)
        inviteCountdownLabel.textAlignment = .center
        inviteCountdownLabel.translatesAutoresizingMaskIntoConstraints = false
        inviteOverlay.addSubview(inviteCountdownLabel)

        cancelInviteBtn.setTitle(BlomixL10n.close, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: cancelInviteBtn)
        cancelInviteBtn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        cancelInviteBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelInviteBtn.addTarget(self, action: #selector(cancelInviteTapped), for: .touchUpInside)
        inviteOverlay.addSubview(cancelInviteBtn)

        NSLayoutConstraint.activate([
            inviteOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            inviteOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inviteOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inviteOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            inviteAmbientBg.topAnchor.constraint(equalTo: inviteOverlay.topAnchor),
            inviteAmbientBg.leadingAnchor.constraint(equalTo: inviteOverlay.leadingAnchor),
            inviteAmbientBg.trailingAnchor.constraint(equalTo: inviteOverlay.trailingAnchor),
            inviteAmbientBg.bottomAnchor.constraint(equalTo: inviteOverlay.bottomAnchor),

            // Spinner remonté pour laisser de la place aux labels dessous.
            inviteSpinner.centerXAnchor.constraint(equalTo: inviteOverlay.centerXAnchor),
            inviteSpinner.centerYAnchor.constraint(equalTo: inviteOverlay.centerYAnchor, constant: -80),

            inviteStatusLabel.topAnchor.constraint(equalTo: inviteSpinner.bottomAnchor, constant: 20),
            inviteStatusLabel.leadingAnchor.constraint(equalTo: inviteOverlay.leadingAnchor, constant: 24),
            inviteStatusLabel.trailingAnchor.constraint(equalTo: inviteOverlay.trailingAnchor, constant: -24),

            inviteHintLabel.topAnchor.constraint(equalTo: inviteStatusLabel.bottomAnchor, constant: 8),
            inviteHintLabel.leadingAnchor.constraint(equalTo: inviteOverlay.leadingAnchor, constant: 26),
            inviteHintLabel.trailingAnchor.constraint(equalTo: inviteOverlay.trailingAnchor, constant: -26),

            inviteCountdownLabel.topAnchor.constraint(equalTo: inviteHintLabel.bottomAnchor, constant: 20),
            inviteCountdownLabel.centerXAnchor.constraint(equalTo: inviteOverlay.centerXAnchor),

            cancelInviteBtn.topAnchor.constraint(equalTo: inviteOverlay.safeAreaLayoutGuide.topAnchor, constant: 8),
            cancelInviteBtn.trailingAnchor.constraint(equalTo: inviteOverlay.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])

        updateSelectedLeaderboardUI()

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            tabsStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 14),
            tabsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            tabsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            statusLabel.topAnchor.constraint(equalTo: tabsStack.bottomAnchor, constant: 14),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            tableView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    @objc private func closeTapped() {
        NotificationCenter.default.post(name: .blomixModalWillDismiss, object: nil)
        dismiss(animated: true) {
            NotificationCenter.default.post(name: .blomixModalDidDismiss, object: nil)
        }
    }

    @objc private func mainTabTapped() {
        switchToLeaderboard(.mainScore)
    }

    @objc private func eloTabTapped() {
        switchToLeaderboard(.elo)
    }

    @objc private func avgTabTapped() {
        switchToLeaderboard(.averageScore)
    }

    @objc private func zenTabTapped() {
        switchToLeaderboard(.zenScore)
    }

    private func switchToLeaderboard(_ kind: LeaderboardKind) {
        guard selectedLeaderboardKind != kind else { return }
        selectedLeaderboardKind = kind
        rows = []
        eloGKPlayers = [:]
        updateSelectedLeaderboardUI()
        loadLeaderboard()
    }

    private func updateSelectedLeaderboardUI() {
        subtitleLabel.text = selectedLeaderboardKind.subtitle
        applyTabSelectionStyle(button: mainTabButton, selected: selectedLeaderboardKind == .mainScore)
        applyTabSelectionStyle(button: eloTabButton,  selected: selectedLeaderboardKind == .elo)
        applyTabSelectionStyle(button: avgTabButton,  selected: selectedLeaderboardKind == .averageScore)
        applyTabSelectionStyle(button: zenTabButton,  selected: selectedLeaderboardKind == .zenScore)
    }

    private func applyTabSelectionStyle(button: UIButton, selected: Bool) {
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: button)
        button.alpha = selected ? 1.0 : 0.7
        button.layer.borderColor = (selected ? UIColor.white : BlomixUIDestinationButtonStyle.borderColor).cgColor
        button.layer.borderWidth = selected ? 1.0 : BlomixUIDestinationButtonStyle.hairlineBorderWidth
    }

    private func setLoading(_ loading: Bool) {
        if loading {
            spinner.isHidden = false
            spinner.startAnimating()
            statusLabel.text = BlomixL10n.leaderboardLoading
        } else {
            spinner.stopAnimating(settle: false) { [weak self] in
                self?.spinner.isHidden = true
            }
        }
    }

    private func loadLeaderboard() {
        guard GKLocalPlayer.local.isAuthenticated else {
            statusLabel.text = BlomixL10n.leaderboardGcSignIn
            rows = []
            return
        }

        setLoading(true)
        let selectedKind = selectedLeaderboardKind

        if selectedKind == .elo {
            Task { @MainActor in
                let localProfile = try? await BlomixEloManager.shared.fetchLocalPlayerProfile()
                guard self.selectedLeaderboardKind == selectedKind else { return }
                self.loadLeaderboardEntries(for: selectedKind, localEloOverride: localProfile?.rating)
            }
            return
        }

        loadLeaderboardEntries(for: selectedKind, localEloOverride: nil)
    }

    private func loadLeaderboardEntries(for selectedKind: LeaderboardKind, localEloOverride: Int?) {
        GKLeaderboard.loadLeaderboards(IDs: [selectedKind.leaderboardID]) { [weak self] leaderboards, error in
            if let error {
                Task { @MainActor [weak self] in
                    guard self?.selectedLeaderboardKind == selectedKind else { return }
                    self?.setLoading(false)
                    self?.statusLabel.text = BlomixL10n.leaderboardGcError(error.localizedDescription)
                    self?.rows = []
                }
                return
            }

            guard let leaderboard = leaderboards?.first else {
                Task { @MainActor [weak self] in
                    guard self?.selectedLeaderboardKind == selectedKind else { return }
                    self?.setLoading(false)
                    self?.statusLabel.text = BlomixL10n.leaderboardNotFound
                    self?.rows = []
                }
                return
            }

            let localPlayer = GKLocalPlayer.local
            let localStableID = localPlayer.teamPlayerID.isEmpty ? localPlayer.gamePlayerID : localPlayer.teamPlayerID
            // Lu sur le main actor ici (avant le callback non-isolé) puis capturé comme constante.
            let localAvgGameCount = selectedKind == .averageScore ? ScoreManager.shared.localGameCount() : 0
            leaderboard.loadEntries(for: .global, timeScope: .allTime, range: NSRange(location: 1, length: 100)) { _, rankedEntries, _, loadError in
                if let loadError {
                    Task { @MainActor [weak self] in
                        guard self?.selectedLeaderboardKind == selectedKind else { return }
                        self?.setLoading(false)
                        self?.statusLabel.text = BlomixL10n.leaderboardLoadError(loadError.localizedDescription)
                        self?.rows = []
                    }
                    return
                }

                func stablePlayerID(for player: GKPlayer) -> String {
                    player.teamPlayerID.isEmpty ? player.gamePlayerID : player.teamPlayerID
                }

                func buildRow(from entry: GKLeaderboard.Entry) -> LeaderboardRow {
                    let isLocalPlayer = stablePlayerID(for: entry.player) == localStableID
                    let resolvedScore: Int
                    if selectedKind == .elo, isLocalPlayer, let localEloOverride {
                        resolvedScore = max(Int(entry.score), localEloOverride)
                    } else {
                        resolvedScore = Int(entry.score)
                    }
                    // Pour le leaderboard de moyenne, le nombre de parties est stocké dans `context`.
                    // Fallback UserDefaults pour le joueur local si context = 0 (entrée soumise avant
                    // l'introduction du context dans la version actuelle).
                    let gameCount: Int
                    if selectedKind == .averageScore {
                        let ctx = Int(entry.context)
                        if ctx > 0 {
                            gameCount = ctx
                        } else if isLocalPlayer {
                            gameCount = localAvgGameCount
                        } else {
                            gameCount = 0
                        }
                    } else {
                        gameCount = 0
                    }
                    return LeaderboardRow(
                        rank: entry.rank,
                        playerName: entry.player.displayName,
                        gamePlayerID: entry.player.gamePlayerID,
                        score: resolvedScore,
                        isLocalPlayer: isLocalPlayer,
                        gameCount: gameCount
                    )
                }

                // Elo : exclure les joueurs sans aucune partie jouée (context == 0 → Elo par défaut 800).
                // Pour le classement principal, on garde tout.
                let eligibleEntries = selectedKind == .elo
                    ? (rankedEntries ?? []).filter { $0.context > 0 }
                    : (rankedEntries ?? [])
                let mappedGlobal: [LeaderboardRow] = eligibleEntries.map(buildRow)

                guard selectedKind == .elo else {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        guard self.selectedLeaderboardKind == selectedKind else { return }
                        self.setLoading(false)
                        self.rows = mappedGlobal
                        self.statusLabel.text = mappedGlobal.isEmpty ? BlomixL10n.leaderboardEmpty : BlomixL10n.leaderboardTopCount(mappedGlobal.count)
                    }
                    return
                }

                // Cache des GKPlayer pour l'onglet Elo : évite tout appel ultérieur à loadPlayers.
                struct GKPlayerMapBox: @unchecked Sendable { let map: [String: GKPlayer] }
                var playerMap: [String: GKPlayer] = [:]
                for entry in rankedEntries ?? [] {
                    playerMap[entry.player.gamePlayerID] = entry.player
                }
                let playerMapBox = GKPlayerMapBox(map: playerMap)

                leaderboard.loadEntries(for: [localPlayer], timeScope: .allTime) { _, localEntries, localLoadError in
                    var mergedRows = mappedGlobal

                    // Inclure le joueur local seulement s'il a au moins une partie jouée.
                    if let localEntry = localEntries?.first, localEntry.context > 0 {
                        let localRow = buildRow(from: localEntry)
                        if let localIndex = mergedRows.firstIndex(where: { $0.isLocalPlayer }) {
                            mergedRows[localIndex] = localRow
                        } else {
                            mergedRows.insert(localRow, at: 0)
                        }
                    }

                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        guard self.selectedLeaderboardKind == selectedKind else { return }
                        self.eloGKPlayers = playerMapBox.map
                        self.setLoading(false)
                        self.rows = mergedRows
                        if let localLoadError {
                            self.statusLabel.text = BlomixL10n.leaderboardLoadError(localLoadError.localizedDescription)
                        } else {
                            self.statusLabel.text = mergedRows.isEmpty ? BlomixL10n.leaderboardEmpty : BlomixL10n.leaderboardTopCount(mergedRows.count)
                        }
                    }
                }
            }
        }
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "LeaderboardCell", for: indexPath)
        cell.backgroundColor = row.isLocalPlayer ? UIColor(white: 0.16, alpha: 1) : UIColor.clear
        cell.selectionStyle = .none

        var content = UIListContentConfiguration.subtitleCell()
        content.text = "#\(row.rank)  \(row.playerName)"
        content.secondaryText = selectedLeaderboardKind.secondaryText(for: row.score)
        content.textProperties.color = .white
        content.secondaryTextProperties.color = row.isLocalPlayer ? .white : UIColor(white: 0.78, alpha: 1)
        content.textProperties.font = FontTheme.gameFont(size: 16, fallbackWeight: row.isLocalPlayer ? .bold : .regular)
        content.secondaryTextProperties.font = FontTheme.gameFont(size: 13, fallbackWeight: .medium)
        cell.contentConfiguration = content

        // Nombre de parties (onglet Moyenne uniquement) — affiché à droite de la ligne.
        if selectedLeaderboardKind == .averageScore && row.gameCount > 0 {
            let countLabel = UILabel()
            countLabel.text = BlomixL10n.leaderboardAvgGameCount(row.gameCount)
            countLabel.font = FontTheme.gameFont(size: 12, fallbackWeight: .regular)
            countLabel.textColor = row.isLocalPlayer ? UIColor(white: 0.9, alpha: 1) : UIColor(white: 0.55, alpha: 1)
            countLabel.textAlignment = .right
            countLabel.sizeToFit()
            cell.accessoryView = countLabel
            return cell
        }

        // Bouton "Défier" uniquement sur l'onglet Elo, pour les autres joueurs.
        if selectedLeaderboardKind == .elo && !row.isLocalPlayer && onMatch != nil {
            let btn = BlomixUIButton()
            btn.setTitle(BlomixL10n.pvpRecentChallenge, for: .normal)
            BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: btn)
            btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
            btn.titleLabel?.font = FontTheme.gameFont(size: 14, fallbackWeight: .semibold)
            btn.tag = indexPath.row
            btn.addTarget(self, action: #selector(challengeTapped(_:)), for: .touchUpInside)
            btn.sizeToFit()
            cell.accessoryView = btn
        } else {
            cell.accessoryView = nil
        }
        return cell
    }

    // MARK: - Invitation sortante

    @objc private func challengeTapped(_ sender: UIButton) {
        guard sender.tag < rows.count else { return }
        let row = rows[sender.tag]
        guard let player = eloGKPlayers[row.gamePlayerID] else { return }
        showInviteOverlay(playerName: row.playerName)
        sendInvitation(to: player)
    }

    private func showInviteOverlay(playerName: String) {
        inviteStatusLabel.text = BlomixL10n.pvpRecentInviteSent(playerName)
        inviteHintLabel.text   = BlomixL10n.pvpRecentInviteHint
        inviteHintLabel.isHidden      = false
        inviteCountdownLabel.isHidden = false
        inviteOverlay.isHidden = false
        inviteSpinner.startAnimating()
        startCountdown(seconds: 60)
        NotificationCenter.default.post(
            name: .blomixPvPOutgoingInviteStateChanged,
            object: nil,
            userInfo: ["active": true]
        )
    }

    private func hideInviteOverlay() {
        stopCountdown()
        inviteSpinner.stopAnimating(settle: false)
        inviteOverlay.isHidden = true
        notifyInviteEnded()
    }

    private func startCountdown(seconds: Int) {
        stopCountdown()
        countdownSecondsLeft = seconds
        inviteCountdownLabel.text    = "\(countdownSecondsLeft)"
        inviteHintLabel.isHidden     = false
        inviteCountdownLabel.isHidden = false
        countdownTick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.countdownSecondsLeft = max(0, self.countdownSecondsLeft - 1)
                self.inviteCountdownLabel.text = "\(self.countdownSecondsLeft)"
            }
        }
    }

    private func stopCountdown() {
        countdownTick?.invalidate()
        countdownTick = nil
        inviteHintLabel.isHidden      = true
        inviteCountdownLabel.isHidden = true
    }

    private func notifyInviteEnded() {
        NotificationCenter.default.post(
            name: .blomixPvPOutgoingInviteStateChanged,
            object: nil,
            userInfo: ["active": false]
        )
    }

    @objc private func cancelInviteTapped() {
        inviteTimer?.invalidate()
        inviteTimer = nil
        GKMatchmaker.shared().cancel()
        pendingInviteMatch?.delegate = nil
        pendingInviteMatch?.disconnect()
        pendingInviteMatch = nil
        hideInviteOverlay()
    }

    private func sendInvitation(to player: GKPlayer) {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.recipients = [player]

        inviteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                GKMatchmaker.shared().cancel()
                self.pendingInviteMatch?.delegate = nil
                self.pendingInviteMatch?.disconnect()
                self.pendingInviteMatch = nil
                self.hideInviteOverlay()
                self.inviteStatusLabel.text = BlomixL10n.pvpRecentInviteFailed
                self.inviteOverlay.isHidden = false
            }
        }

        GKMatchmaker.shared().findMatch(for: request) { [weak self] match, error in
            let box = match.map { BlomixPvPGKMatchBox(match: $0) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let box {
                    self.pendingInviteMatch = box.match
                    box.match.delegate = self
                } else {
                    self.inviteTimer?.invalidate()
                    self.inviteTimer = nil
                    let msg = Self.inviteErrorMessage(from: error)
                    self.hideInviteOverlay()
                    self.inviteStatusLabel.text = msg
                    self.inviteOverlay.isHidden = false
                }
            }
        }
    }

    /// Traduit une erreur `findMatch` en message utilisateur.
    /// Détecte spécifiquement le code 5121 (joueurs n'ayant jamais joué ensemble) pour
    /// afficher un message explicatif plutôt que le message générique de GK.
    private static func inviteErrorMessage(from error: Error?) -> String {
        guard let nsError = error as NSError? else { return BlomixL10n.pvpRecentInviteFailed }
        // Erreur racine : code 8 "invalidPlayer" de GKErrorDomain
        // Cause sous-jacente : GKServerStatusCode 5121 "never played together"
        let isNeverPlayed: Bool = {
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
               underlying.code == 5121 { return true }
            return nsError.domain == GKErrorDomain && nsError.code == 8
        }()
        if isNeverPlayed { return BlomixL10n.pvpLeaderboardInviteNotRecentPlayer }
        return BlomixL10n.pvpLobbyMatchmakingError(nsError.localizedDescription)
    }

}

// MARK: - GKMatchDelegate (invitation sortante depuis leaderboard)

extension LeaderboardViewController: @preconcurrency GKMatchDelegate {
    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {}

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        let box = BlomixPvPGKMatchBox(match: match)
        Task { @MainActor [weak self] in
            guard let self else { return }
            if state == .connected, box.match.expectedPlayerCount == 0 {
                self.inviteTimer?.invalidate()
                self.inviteTimer = nil
                self.pendingInviteMatch?.delegate = nil
                self.pendingInviteMatch = nil
                self.hideInviteOverlay()
                GKMatchmaker.shared().finishMatchmaking(for: box.match)
                self.dismiss(animated: true) {
                    self.onMatch?(box.match)
                }
            }
        }
    }

    nonisolated func match(_ match: GKMatch, didFailWithError error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.inviteTimer?.invalidate()
            self.inviteTimer = nil
            self.pendingInviteMatch = nil
            self.hideInviteOverlay()
            let msg = error.map { BlomixL10n.pvpLobbyMatchmakingError($0.localizedDescription) }
                ?? BlomixL10n.pvpRecentInviteFailed
            self.inviteStatusLabel.text = msg
            self.inviteOverlay.isHidden = false
        }
    }
}

// MARK: - Règles / crédits (texte long, modal comme Settings)

/// Texte brut multiligne (`rules.txt`, `credits.txt`) : même présentation que les autres écrans UIKit plein écran.
@MainActor
final class BlomixPlainTextModalViewController: UIViewController {

    private let screenTitle: String
    private let body: String
    private let showStartupGuideToggle: Bool

    @MainActor
    private enum FontTheme {
        static func gameFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
            BlomixTypography.uiFont(size: size, weight: weight)
        }
    }

    private let closeButton = BlomixUIButton()
    private let titleLabel = UILabel()
    private let textView = UITextView()
    private let guideFooter = UIStackView()
    private let guideSwitch = UISwitch()
    private let guideLabel = UILabel()

    init(screenTitle: String, body: String, showStartupGuideToggle: Bool = false) {
        self.screenTitle = screenTitle
        self.body = body
        self.showStartupGuideToggle = showStartupGuideToggle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addAmbientBlocksBackground()

        titleLabel.text = screenTitle
        titleLabel.textColor = .white
        titleLabel.font = FontTheme.gameFont(size: 28, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        closeButton.setTitle(BlomixL10n.close, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: closeButton)
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        textView.text = body
        textView.textColor = UIColor(white: 0.92, alpha: 1)
        textView.font = FontTheme.gameFont(size: 14, weight: .regular)
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = true
        textView.indicatorStyle = .white
        textView.dataDetectorTypes = []
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 16, right: 4)
        textView.textContainer.lineFragmentPadding = 0
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)

        var constraints: [NSLayoutConstraint] = [
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12),

            textView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ]

        if showStartupGuideToggle {
            guideSwitch.onTintColor = UIColor(red: 0.72, green: 0.53, blue: 0.04, alpha: 1)
            guideSwitch.isOn = !UserDefaults.standard.hasSeenGameTutorial
            guideSwitch.addTarget(self, action: #selector(guideSwitchChanged(_:)), for: .valueChanged)

            guideLabel.text = BlomixL10n.rulesShowGuidesAtStart
            guideLabel.textColor = UIColor(white: 0.88, alpha: 1)
            guideLabel.font = FontTheme.gameFont(size: 14, weight: .regular)
            guideLabel.numberOfLines = 0

            guideFooter.axis = .horizontal
            guideFooter.spacing = 12
            guideFooter.alignment = .center
            guideFooter.translatesAutoresizingMaskIntoConstraints = false
            guideFooter.addArrangedSubview(guideSwitch)
            guideFooter.addArrangedSubview(guideLabel)
            view.addSubview(guideFooter)

            constraints += [
                guideFooter.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                guideFooter.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
                guideFooter.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
                textView.bottomAnchor.constraint(equalTo: guideFooter.topAnchor, constant: -12),
            ]
        } else {
            constraints.append(textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12))
        }

        NSLayoutConstraint.activate(constraints)
    }

    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(closeTapped))]
    }

    @objc private func closeTapped() {
        NotificationCenter.default.post(name: .blomixModalWillDismiss, object: nil)
        dismiss(animated: true) {
            NotificationCenter.default.post(name: .blomixModalDidDismiss, object: nil)
        }
    }

    @objc private func guideSwitchChanged(_ sender: UISwitch) {
        UserDefaults.standard.hasSeenGameTutorial = !sender.isOn
    }
}

// MARK: - Settings (écran réglages : volume + skins)

extension UIColor {
    /// Hex `#RRGGBB` pour persistance du skin Perso (sRGB).
    func blomixHexForPersoSave(traitCollection: UITraitCollection) -> String? {
        let c = resolvedColor(with: traitCollection)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard c.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int(max(0, min(255, round(r * 255)))),
            Int(max(0, min(255, round(g * 255)))),
            Int(max(0, min(255, round(b * 255))))
        )
    }
}

fileprivate func blomixSettingsHexUIColor(_ raw: String) -> UIColor? {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
    let r = CGFloat((v >> 16) & 0xff) / 255
    let g = CGFloat((v >> 8) & 0xff) / 255
    let b = CGFloat(v & 0xff) / 255
    return UIColor(red: r, green: g, blue: b, alpha: 1)
}

@MainActor
final class BlomixGridSoundSlider: UIView {

    var value: Float = 1 {
        didSet { setNeedsLayout(); updateThumb(animated: false); updateSegmentFill() }
    }

    var onValueChange: ((Float) -> Void)?

    private let segmentCount = 10
    private let segmentGap: CGFloat = 2
    private let segmentHeight: CGFloat = 6
    private let trackDim = UIColor(white: 0.2, alpha: 1)
    private let trackFill = UIColor(red: CGFloat(0xAD) / 255, green: CGFloat(0xAD) / 255, blue: CGFloat(0xAD) / 255, alpha: 1)

    private var segmentViews: [UIView] = []
    private let thumb = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        for _ in 0..<segmentCount {
            let v = UIView()
            v.backgroundColor = trackDim
            v.layer.cornerRadius = 1
            addSubview(v)
            segmentViews.append(v)
        }
        thumb.backgroundColor = BlomixSkinCatalog.shared.bloxUIColor(forNormalizedKey: "orange") ?? blomixSettingsHexUIColor("#F4A261") ?? .orange
        thumb.layer.cornerRadius = 4
        thumb.layer.borderWidth = 1
        thumb.layer.borderColor = UIColor(white: 1, alpha: 0.35).cgColor
        addSubview(thumb)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        thumb.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTrackTap(_:)))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = segmentHeight
        let cy = bounds.midY
        let totalGaps = segmentGap * CGFloat(segmentCount - 1)
        let segW = (bounds.width - totalGaps) / CGFloat(segmentCount)
        var x: CGFloat = 0
        for v in segmentViews {
            v.frame = CGRect(x: x, y: cy - h / 2, width: segW, height: h)
            x += segW + segmentGap
        }
        updateThumb(animated: false)
        updateSegmentFill()
    }

    private func thumbX(for value: Float) -> CGFloat {
        let t = CGFloat(min(1, max(0, value)))
        let thumbW: CGFloat = 22
        let inset = thumbW / 2
        return inset + (bounds.width - thumbW * 2) * t + thumbW / 2
    }

    private func updateThumb(animated: Bool) {
        let tx = thumbX(for: value)
        let thumbH: CGFloat = 22
        let r = CGRect(x: tx - 11, y: bounds.midY - thumbH / 2, width: 22, height: thumbH)
        if animated {
            UIView.animate(withDuration: 0.12) { self.thumb.frame = r }
        } else {
            thumb.frame = r
        }
    }

    private func updateSegmentFill() {
        let filled = Int(round(CGFloat(value) * CGFloat(segmentCount)))
        for (i, v) in segmentViews.enumerated() {
            v.backgroundColor = i < filled ? trackFill : trackDim
        }
    }

    private func valueFromSceneX(_ x: CGFloat) -> Float {
        let thumbW: CGFloat = 22
        let inset = thumbW / 2
        let usable = bounds.width - thumbW * 2
        guard usable > 1 else { return 0 }
        let t = (x - inset) / usable
        return Float(min(1, max(0, t)))
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let x = g.location(in: self).x
        value = valueFromSceneX(x)
        onValueChange?(value)
        setNeedsLayout()
    }

    @objc private func handleTrackTap(_ g: UITapGestureRecognizer) {
        let x = g.location(in: self).x
        value = valueFromSceneX(x)
        onValueChange?(value)
        setNeedsLayout()
    }
}

@MainActor
private final class RelativeSoundMixRowView: UIView {

    private let titleLabel = UILabel()
    private let percentLabel = UILabel()
    private let slider = BlomixGridSoundSlider()
    private let soundName: String

    init(soundName: String) {
        self.soundName = soundName
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor(white: 0.1, alpha: 1)
        layer.cornerRadius = 8
        layer.borderWidth = 0.5
        layer.borderColor = UIColor(white: 0.32, alpha: 1).cgColor
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)

        titleLabel.text = BlomixL10n.settingsSoundName(forSoundNamed: soundName)
        titleLabel.textColor = .white
        titleLabel.font = BlomixTypography.uiFont(size: 15, weight: .medium)
        titleLabel.numberOfLines = 2

        percentLabel.textColor = UIColor(white: 0.82, alpha: 1)
        percentLabel.font = BlomixTypography.uiFont(size: 13, weight: .regular)
        percentLabel.textAlignment = .right

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.value = BlomixAudioMixSettings.shared.relativeVolume(forSoundNamed: soundName)
        slider.onValueChange = { [weak self] value in
            BlomixAudioMixSettings.shared.setRelativeVolume(value, forSoundNamed: soundName)
            self?.updatePercentLabel(value)
        }
        slider.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, percentLabel])
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.spacing = 12
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [headerStack, slider])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            percentLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),
        ])

        updatePercentLabel(slider.value)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    private func updatePercentLabel(_ value: Float) {
        percentLabel.text = BlomixL10n.settingsSoundPercent(Int(round(value * 100)))
    }
}

// MARK: -

@MainActor
final class SoundMixSettingsViewController: UIViewController {

    @MainActor
    private enum FontTheme {
        static func gameFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
            BlomixTypography.uiFont(size: size, weight: weight)
        }
    }

    private let closeButton = BlomixUIButton()
    private let titleLabel = UILabel()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addAmbientBlocksBackground()

        titleLabel.text = BlomixL10n.settingsSoundMixTitle
        titleLabel.textColor = .white
        titleLabel.font = FontTheme.gameFont(size: 28, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        closeButton.setTitle(BlomixL10n.close, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: closeButton)
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        for soundName in BlomixAudioMixSettings.adjustableSoundNames {
            contentStack.addArrangedSubview(RelativeSoundMixRowView(soundName: soundName))
        }

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(closeTapped))]
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}

/// Ligne de réglage de volume maître (Sons ou Musique) : carte grise, label, % et tirette.
@MainActor
private final class BlomixMasterVolumeRowView: UIView {
    private let titleLabel   = UILabel()
    private let percentLabel = UILabel()
    private let slider       = BlomixGridSoundSlider()

    var onValueChange: ((Float) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor(white: 0.1, alpha: 1)
        layer.cornerRadius = 8
        layer.borderWidth = 0.5
        layer.borderColor = UIColor(white: 0.32, alpha: 1).cgColor
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)

        titleLabel.textColor = .white
        titleLabel.font = BlomixTypography.uiFont(size: 15, weight: .medium)

        percentLabel.textColor = UIColor(white: 0.82, alpha: 1)
        percentLabel.font = BlomixTypography.uiFont(size: 13, weight: .regular)
        percentLabel.textAlignment = .right

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.onValueChange = { [weak self] value in
            self?.updatePercent(value)
            self?.onValueChange?(value)
        }
        slider.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, percentLabel])
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.spacing = 12
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [headerStack, slider])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            percentLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func configure(title: String, value: Float) {
        titleLabel.text = title
        slider.value = value
        updatePercent(value)
    }

    private func updatePercent(_ value: Float) {
        percentLabel.text = BlomixL10n.settingsSoundPercent(Int(round(value * 100)))
    }
}

// MARK: -

@MainActor
final class SettingsViewController: UIViewController, UIColorPickerViewControllerDelegate {

    @MainActor
    private enum FontTheme {
        static func gameFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
            BlomixTypography.uiFont(size: size, weight: weight)
        }
    }

    private let closeButton       = BlomixUIButton()
    private let titleLabel        = UILabel()
    private let scrollView        = UIScrollView()
    private let contentStack      = UIStackView()
    private let soundsVolumeRow   = BlomixMasterVolumeRowView()
    private let musicVolumeRow    = BlomixMasterVolumeRowView()
    private let soundSectionLabel = UILabel()
    private let fontSectionLabel = UILabel()
    private let colorsSectionLabel = UILabel()
    private let fontStack = UIStackView()
    private let skinsStack = UIStackView()
    private var persoPickerSlot: BlomixPersoColorSlot?
    private var persoPickerSkinId: String = BlomixSkinCatalog.persoSkinId

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addAmbientBlocksBackground()

        titleLabel.text = BlomixL10n.settingsTitle
        titleLabel.textColor = .white
        titleLabel.font = FontTheme.gameFont(size: 28, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        closeButton.setTitle(BlomixL10n.close, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: closeButton)
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 18
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        configureSectionHeading(soundSectionLabel, text: BlomixL10n.settingsSoundSection)
        contentStack.addArrangedSubview(soundSectionLabel)

        soundsVolumeRow.configure(
            title: BlomixL10n.settingsSoundsSliderLabel,
            value: BlomixMatchAudioSettings.shared.masterVolume
        )
        soundsVolumeRow.onValueChange = { v in
            BlomixMatchAudioSettings.shared.masterVolume = v
        }
        contentStack.addArrangedSubview(soundsVolumeRow)

        musicVolumeRow.configure(
            title: BlomixL10n.settingsMusicSliderLabel,
            value: BlomixMatchAudioSettings.shared.masterMusicVolume
        )
        musicVolumeRow.onValueChange = { v in
            BlomixMatchAudioSettings.shared.masterMusicVolume = v
        }
        contentStack.addArrangedSubview(musicVolumeRow)

        configureSectionHeading(fontSectionLabel, text: BlomixL10n.settingsFontSection)
        contentStack.addArrangedSubview(fontSectionLabel)

        fontStack.axis = .vertical
        fontStack.spacing = 10
        contentStack.addArrangedSubview(fontStack)
        rebuildFontRows()

        configureSectionHeading(colorsSectionLabel, text: BlomixL10n.settingsColorsSection)
        contentStack.addArrangedSubview(colorsSectionLabel)

        skinsStack.axis = .vertical
        skinsStack.spacing = 10
        contentStack.addArrangedSubview(skinsStack)
        rebuildSkinRows()
        refreshTypography()

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    private func configureSectionHeading(_ label: UILabel, text: String) {
        label.text = text
        label.textColor = UIColor(white: 0.88, alpha: 1)
        label.font = FontTheme.gameFont(size: 16, weight: .semibold)
    }

    private func refreshTypography() {
        titleLabel.font = FontTheme.gameFont(size: 28, weight: .bold)
        configureSectionHeading(soundSectionLabel, text: BlomixL10n.settingsSoundSection)
        configureSectionHeading(fontSectionLabel, text: BlomixL10n.settingsFontSection)
        configureSectionHeading(colorsSectionLabel, text: BlomixL10n.settingsColorsSection)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: closeButton)
    }

    private func rebuildFontRows() {
        fontStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let selected = BlomixTypography.shared.selectedFontChoice
        for choice in BlomixTypography.shared.allChoices() {
            let row = FontChoiceRowView(
                choice: choice,
                isSelected: choice == selected,
                onSelect: { [weak self] selectedChoice in
                    BlomixTypography.shared.selectedFontChoice = selectedChoice
                    self?.refreshTypography()
                    self?.rebuildFontRows()
                    self?.rebuildSkinRows()
                }
            )
            fontStack.addArrangedSubview(row)
        }
    }

    private func rebuildSkinRows() {
        skinsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let catalog = BlomixSkinCatalog.shared
        let selected = catalog.selectedSkinId
        for skin in catalog.allSkins() {
            let isPerso = skin.id == BlomixSkinCatalog.persoSkinId || skin.id == BlomixSkinCatalog.persoSkin2Id
            let persoTap: ((BlomixPersoColorSlot) -> Void)? = isPerso
                ? { [weak self, skinId = skin.id] slot in
                    BlomixSkinCatalog.shared.selectedSkinId = skinId
                    self?.presentPersoColorPicker(slot: slot, skinId: skinId)
                }
                : nil
            let aleaTap: (() -> Void)? = skin.id == BlomixSkinCatalog.aleaSkinId
                ? { [weak self] in
                    BlomixSkinCatalog.shared.generateAndSaveAleaColors()
                    BlomixSkinCatalog.shared.selectedSkinId = BlomixSkinCatalog.aleaSkinId
                    self?.rebuildSkinRows()
                }
                : nil
            let row = SkinChoiceRowView(
                skin: skin,
                isSelected: skin.id == selected,
                onSelect: { [weak self] id in
                    BlomixSkinCatalog.shared.selectedSkinId = id
                    self?.rebuildSkinRows()
                },
                onPersoSwatchTapped: persoTap,
                onAleaNewTapped: aleaTap
            )
            skinsStack.addArrangedSubview(row)
        }
    }

    private func presentPersoColorPicker(slot: BlomixPersoColorSlot, skinId: String = BlomixSkinCatalog.persoSkinId) {
        persoPickerSlot   = slot
        persoPickerSkinId = skinId
        let picker = UIColorPickerViewController()
        picker.delegate = self
        picker.selectedColor = BlomixSkinCatalog.shared.uiColorForPersoSlot(slot, skinId: skinId)
        picker.supportsAlpha = false
        present(picker, animated: true)
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        defer {
            persoPickerSlot   = nil
            persoPickerSkinId = BlomixSkinCatalog.persoSkinId
        }
        guard let slot = persoPickerSlot else {
            viewController.dismiss(animated: true)
            return
        }
        let c = viewController.selectedColor.resolvedColor(with: view.traitCollection)
        if let hex = c.blomixHexForPersoSave(traitCollection: view.traitCollection) {
            BlomixSkinCatalog.shared.applyPersoColorSave(hex: hex, slot: slot, skinId: persoPickerSkinId)
        }
        viewController.dismiss(animated: true)
        rebuildSkinRows()
    }

    @objc private func closeTapped() {
        NotificationCenter.default.post(name: .blomixModalWillDismiss, object: nil)
        dismiss(animated: true) {
            NotificationCenter.default.post(name: .blomixModalDidDismiss, object: nil)
        }
    }

}

@MainActor
private final class SkinChoiceRowView: UIView {

    private let skinId: String
    private let onSelect: (String) -> Void
    private let onPersoSwatchTapped: ((BlomixPersoColorSlot) -> Void)?
    private let onAleaNewTapped: (() -> Void)?
    private let radio = UIImageView()
    private let nameLabel = UILabel()
    private let swatchStack = UIStackView()

    init(
        skin: BlomixSkinDefinition,
        isSelected: Bool,
        onSelect: @escaping (String) -> Void,
        onPersoSwatchTapped: ((BlomixPersoColorSlot) -> Void)? = nil,
        onAleaNewTapped: (() -> Void)? = nil
    ) {
        self.skinId = skin.id
        self.onSelect = onSelect
        self.onPersoSwatchTapped = onPersoSwatchTapped
        self.onAleaNewTapped = onAleaNewTapped
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 8
        layer.borderWidth = isSelected ? 1.5 : 0.5
        layer.borderColor = (isSelected ? UIColor.white : UIColor(white: 0.35, alpha: 1)).cgColor
        backgroundColor = UIColor(white: 0.1, alpha: 1)

        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let img = UIImage(systemName: isSelected ? "largecircle.fill.circle" : "circle", withConfiguration: config)
        radio.image = img
        radio.tintColor = .white
        radio.translatesAutoresizingMaskIntoConstraints = false
        addSubview(radio)

        nameLabel.text = skin.displayName
        nameLabel.textColor = .white
        nameLabel.font = BlomixTypography.uiFont(size: 15, weight: .medium)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        swatchStack.axis = .horizontal
        swatchStack.spacing = 4
        swatchStack.alignment = .center
        swatchStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(swatchStack)

        if (skin.id == BlomixSkinCatalog.persoSkinId || skin.id == BlomixSkinCatalog.persoSkin2Id),
           onPersoSwatchTapped != nil {
            var lastPriksFill: UIView?
            for slot in BlomixPersoColorSlot.displayOrdered {
                let hex: String?
                switch slot {
                case .priks: hex = skin.priks
                case .prikstext: hex = skin.prikstext
                default: hex = skin.blox[slot.rawValue]
                }
                guard let h = hex, let c = blomixSettingsHexUIColor(h) else { continue }
                let dot = UIView()
                dot.translatesAutoresizingMaskIntoConstraints = false
                dot.backgroundColor = c
                dot.layer.cornerRadius = 3
                dot.widthAnchor.constraint(equalToConstant: 16).isActive = true
                dot.heightAnchor.constraint(equalToConstant: 16).isActive = true
                dot.accessibilityIdentifier = slot.rawValue
                let tap = UITapGestureRecognizer(target: self, action: #selector(persoSwatchTapped(_:)))
                dot.addGestureRecognizer(tap)
                dot.isUserInteractionEnabled = true
                swatchStack.addArrangedSubview(dot)
                if slot == .priks { lastPriksFill = dot }
                if slot == .prikstext, let priV = lastPriksFill {
                    swatchStack.setCustomSpacing(5, after: priV)
                }
                if slot == .prikstext {
                    dot.layer.borderWidth = 1
                    dot.layer.borderColor = UIColor(white: 1, alpha: 0.22).cgColor
                }
            }
        } else {
            for key in BlomixSkinCatalog.bloxDisplayOrder {
                if let hex = skin.blox[key.lowercased()],
                   let c = blomixSettingsHexUIColor(hex) {
                    let dot = UIView()
                    dot.translatesAutoresizingMaskIntoConstraints = false
                    dot.backgroundColor = c
                    dot.layer.cornerRadius = 3
                    dot.widthAnchor.constraint(equalToConstant: 16).isActive = true
                    dot.heightAnchor.constraint(equalToConstant: 16).isActive = true
                    swatchStack.addArrangedSubview(dot)
                }
            }
            let pri = UIView()
            pri.translatesAutoresizingMaskIntoConstraints = false
            pri.backgroundColor = blomixSettingsHexUIColor(skin.priks) ?? UIColor(white: 0.45, alpha: 1)
            pri.layer.cornerRadius = 3
            pri.widthAnchor.constraint(equalToConstant: 16).isActive = true
            pri.heightAnchor.constraint(equalToConstant: 16).isActive = true
            swatchStack.addArrangedSubview(pri)

            let priText = UIView()
            priText.translatesAutoresizingMaskIntoConstraints = false
            if let raw = skin.prikstext, let c = blomixSettingsHexUIColor(raw) {
                priText.backgroundColor = c
            } else {
                priText.backgroundColor = .white
            }
            priText.layer.cornerRadius = 3
            priText.layer.borderWidth = 1
            priText.layer.borderColor = UIColor(white: 1, alpha: 0.22).cgColor
            priText.widthAnchor.constraint(equalToConstant: 16).isActive = true
            priText.heightAnchor.constraint(equalToConstant: 16).isActive = true
            swatchStack.addArrangedSubview(priText)
            swatchStack.setCustomSpacing(5, after: pri)
        }

        // Bouton ↺ pour le skin Alea : inséré entre le nom et les swatches.
        if skin.id == BlomixSkinCatalog.aleaSkinId, let handler = onAleaNewTapped {
            let btn = UIButton(type: .system)
            btn.setTitle("↺", for: .normal)
            btn.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .medium)
            btn.setTitleColor(UIColor(white: 0.72, alpha: 1), for: .normal)
            btn.setTitleColor(UIColor.white, for: .highlighted)
            btn.translatesAutoresizingMaskIntoConstraints = false
            addSubview(btn)
            btn.addAction(UIAction { _ in handler() }, for: .touchUpInside)

            NSLayoutConstraint.activate([
                heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
                radio.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                radio.centerYAnchor.constraint(equalTo: centerYAnchor),
                nameLabel.leadingAnchor.constraint(equalTo: radio.trailingAnchor, constant: 10),
                nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                btn.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
                btn.centerYAnchor.constraint(equalTo: centerYAnchor),
                btn.trailingAnchor.constraint(lessThanOrEqualTo: swatchStack.leadingAnchor, constant: -6),
                swatchStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                swatchStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
                radio.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                radio.centerYAnchor.constraint(equalTo: centerYAnchor),
                nameLabel.leadingAnchor.constraint(equalTo: radio.trailingAnchor, constant: 10),
                nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                swatchStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                swatchStack.centerYAnchor.constraint(equalTo: centerYAnchor),
                nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: swatchStack.leadingAnchor, constant: -8),
            ])
        }

        if skin.id == BlomixSkinCatalog.persoSkinId {
            radio.isUserInteractionEnabled = true
            nameLabel.isUserInteractionEnabled = true
            let pickRow = UITapGestureRecognizer(target: self, action: #selector(tapped))
            radio.addGestureRecognizer(pickRow)
            nameLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        } else {
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            addGestureRecognizer(tap)
            isUserInteractionEnabled = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    @objc private func tapped() {
        onSelect(skinId)
    }

    @objc private func persoSwatchTapped(_ g: UITapGestureRecognizer) {
        guard let id = g.view?.accessibilityIdentifier,
              let slot = BlomixPersoColorSlot(rawValue: id) else { return }
        onPersoSwatchTapped?(slot)
    }
}

@MainActor
private final class FontChoiceRowView: UIView {

    private let choice: BlomixFontChoice
    private let onSelect: (BlomixFontChoice) -> Void
    private let radio = UIImageView()
    private let nameLabel = UILabel()
    private let previewLabel = UILabel()

    init(choice: BlomixFontChoice, isSelected: Bool, onSelect: @escaping (BlomixFontChoice) -> Void) {
        self.choice = choice
        self.onSelect = onSelect
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 8
        layer.borderWidth = isSelected ? 1.5 : 0.5
        layer.borderColor = (isSelected ? UIColor.white : UIColor(white: 0.35, alpha: 1)).cgColor
        backgroundColor = UIColor(white: 0.1, alpha: 1)

        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        radio.image = UIImage(systemName: isSelected ? "largecircle.fill.circle" : "circle", withConfiguration: config)
        radio.tintColor = .white
        radio.translatesAutoresizingMaskIntoConstraints = false
        addSubview(radio)

        nameLabel.text = BlomixTypography.shared.fontDisplayName(for: choice)
        nameLabel.textColor = .white
        nameLabel.font = BlomixTypography.uiFont(size: 15, weight: .medium)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        previewLabel.text = BlomixL10n.settingsFontPreview
        previewLabel.textColor = UIColor(white: 0.82, alpha: 1)
        previewLabel.font = UIFont(name: choice.postScriptName, size: 15) ?? .systemFont(ofSize: 15, weight: .regular)
        previewLabel.textAlignment = .right
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(previewLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            radio.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            radio.centerYAnchor.constraint(equalTo: centerYAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: radio.trailingAnchor, constant: 10),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            previewLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            previewLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            previewLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 10),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    @objc private func tapped() {
        onSelect(choice)
    }
}
