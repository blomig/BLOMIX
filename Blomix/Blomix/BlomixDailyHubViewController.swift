//
//  BlomixDailyHubViewController.swift
//  Blomix
//
//  Hub du Défi du jour : liste CloudKit du jour UTC + un CTA
//  (Défi ! / Continuer / Revenez demain).
//

@preconcurrency import GameKit
import UIKit

@MainActor
final class BlomixDailyHubViewController: UIViewController, UITableViewDataSource {

    var onPlay: (() -> Void)?
    var onContinue: (() -> Void)?

    private let titleView = BlomixCutoutTitleView(text: BlomixL10n.dailyHubTitle, fontSize: 28)
    private let dateLabel = UILabel()
    private let closeButton = BlomixUIButton()
    private let statusLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let spinner = BlomixPvPSearchBlocksView()
    private let ctaButton = BlomixUIButton()

    private var entries: [BlomixDailyScoreEntry] = [] {
        didSet { tableView.reloadData() }
    }
    private let ctaKind = BlomixDailyChallenge.shared.hubCTA

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BlomixAppearance.sceneBackground
        addAmbientBlocksBackground(density: .low)
        buildChrome()
        applyCTA()
        loadScores()
    }

    private func buildChrome() {
        closeButton.setTitle(BlomixL10n.close, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: closeButton)
        BlomixUIDestinationButtonStyle.applyContentInsets(UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12), to: closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        titleView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleView)

        dateLabel.text = Self.utcDateCaption()
        dateLabel.textColor = BlomixAppearance.secondaryText
        dateLabel.font = BlomixTypography.uiFont(size: 13, weight: .medium)
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dateLabel)

        statusLabel.textColor = BlomixAppearance.secondaryText
        statusLabel.font = BlomixTypography.uiFont(size: 14, weight: .regular)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        tableView.backgroundColor = .clear
        tableView.separatorColor = UIColor(white: 0.2, alpha: 1)
        tableView.dataSource = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "DailyHubCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        ctaButton.translatesAutoresizingMaskIntoConstraints = false
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: ctaButton)
        BlomixUIDestinationButtonStyle.applyContentInsets(UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16), to: ctaButton)
        ctaButton.addTarget(self, action: #selector(ctaTapped), for: .touchUpInside)
        view.addSubview(ctaButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            titleView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            titleView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleView.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12),

            dateLabel.topAnchor.constraint(equalTo: titleView.bottomAnchor, constant: 4),
            dateLabel.leadingAnchor.constraint(equalTo: titleView.leadingAnchor),

            statusLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            ctaButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            ctaButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            ctaButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            ctaButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            tableView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tableView.bottomAnchor.constraint(equalTo: ctaButton.topAnchor, constant: -12),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func applyCTA() {
        switch ctaKind {
        case .play:
            ctaButton.setTitle(BlomixL10n.dailyCTAPlay, for: .normal)
            ctaButton.isEnabled = true
            ctaButton.isUserInteractionEnabled = true
            BlomixUIDestinationButtonStyle.applySelectionChrome(to: ctaButton, selected: true)
            ctaButton.alpha = 1
        case .resume:
            ctaButton.setTitle(BlomixL10n.dailyCTAContinue, for: .normal)
            ctaButton.isEnabled = true
            ctaButton.isUserInteractionEnabled = true
            BlomixUIDestinationButtonStyle.applySelectionChrome(to: ctaButton, selected: true)
            ctaButton.alpha = 1
        case .finished:
            ctaButton.setTitle(BlomixL10n.dailyCTATomorrow, for: .normal)
            ctaButton.isEnabled = false
            ctaButton.isUserInteractionEnabled = false
            BlomixUIDestinationButtonStyle.applySelectionChrome(to: ctaButton, selected: false)
            ctaButton.alpha = 0.32
            ctaButton.setTitleColor(BlomixAppearance.tertiaryText, for: .disabled)
        }
    }

    private func loadScores() {
        spinner.isHidden = false
        spinner.startAnimating()
        statusLabel.text = BlomixL10n.loading
        let day = BlomixDailyChallenge.shared.utcToday
        Task { @MainActor [weak self] in
            guard let self else { return }
            let load = await BlomixDailyChallenge.shared.fetchScores(day: day)
            self.spinner.stopAnimating(settle: false) { [weak self] in
                self?.spinner.isHidden = true
            }
            switch load {
            case .loaded(let rows):
                self.entries = rows
                self.statusLabel.text = rows.isEmpty
                    ? BlomixL10n.dailyHubEmpty
                    : BlomixL10n.leaderboardTopCount(rows.count)
            case .unavailable:
                self.entries = []
                self.statusLabel.text = BlomixL10n.dailyHubError
            }
        }
    }

    @objc private func closeTapped() {
        NotificationCenter.default.post(name: .blomixModalWillDismiss, object: nil)
        dismiss(animated: true) {
            NotificationCenter.default.post(name: .blomixModalDidDismiss, object: nil)
        }
    }

    @objc private func ctaTapped() {
        switch ctaKind {
        case .play:
            dismissThen { self.onPlay?() }
        case .resume:
            dismissThen { self.onContinue?() }
        case .finished:
            break
        }
    }

    private func dismissThen(_ action: @escaping () -> Void) {
        NotificationCenter.default.post(name: .blomixModalWillDismiss, object: nil)
        // Restaurer / lancer sous le hub : le crossDissolve révèle la grille, pas un
        // écran vide (et un « 32s » Stage 1 orphelin) pendant l’animation.
        action()
        dismiss(animated: true) {
            NotificationCenter.default.post(name: .blomixModalDidDismiss, object: nil)
        }
    }

    private static func utcDateCaption() -> String {
        let formatter = DateFormatter()
        formatter.calendar = BlomixDailySeed.utcCalendar()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("yMMMMd")
        return formatter.string(from: Date())
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DailyHubCell", for: indexPath)
        cell.backgroundColor = .clear
        cell.selectionStyle = .none
        cell.accessoryView = nil
        let entry = entries[indexPath.row]
        let rank = BlomixDailyChallenge.denseRank(of: entry.gamePlayerID, in: entries) ?? (indexPath.row + 1)
        let localID = GKLocalPlayer.local.gamePlayerID
        let isLocal = !localID.isEmpty && entry.gamePlayerID == localID
        var content = UIListContentConfiguration.subtitleCell()
        content.text = "#\(rank)  \(entry.displayName)"
        content.secondaryText = BlomixL10n.leaderboardPoints(entry.score)
        content.textProperties.color = BlomixAppearance.primaryText
        content.secondaryTextProperties.color = isLocal
            ? BlomixAppearance.primaryText
            : BlomixAppearance.secondaryText
        content.secondaryTextProperties.font = BlomixTypography.uiFont(size: 13, weight: .medium)

        let podium = BlomixDailyChallenge.podiumPoints(for: entry.gamePlayerID, in: entries)
        if podium > 0 {
            content.textProperties.font = BlomixTypography.displayFont(size: rank == 1 ? 24 : 18)
            cell.accessoryView = Self.makePodiumPointsBadge(points: podium, isFirst: rank == 1)
        } else {
            content.textProperties.font = BlomixTypography.uiFont(size: 16, weight: isLocal ? .bold : .regular)
        }
        cell.contentConfiguration = content
        return cell
    }

    /// `accessoryView` exige un frame (pas l’Auto Layout du titre gouttière, qui masquait les lignes).
    private static func makePodiumPointsBadge(points: Int, isFirst: Bool) -> UIView {
        let cutout = BlomixCutoutTitleView(
            text: "+\(points)",
            fontSize: isFirst ? 26 : 20,
            pad: 3
        )
        let size = cutout.intrinsicContentSize
        cutout.translatesAutoresizingMaskIntoConstraints = true
        cutout.frame = CGRect(origin: .zero, size: size)
        let host = UIView(frame: cutout.bounds)
        host.translatesAutoresizingMaskIntoConstraints = true
        host.addSubview(cutout)
        host.isAccessibilityElement = true
        host.accessibilityLabel = "+\(points)"
        return host
    }
}
