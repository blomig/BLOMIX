//
//  BlomixDailyHubViewController.swift
//  Blomix
//
//  Hub du Défi du jour : liste CloudKit du jour affiché (save X pendant la
//  grâce, sinon aujourd’hui), podium d’hier, CTA (Défi ! / Continuer / Revenez demain).
//

@preconcurrency import GameKit
import UIKit

@MainActor
final class BlomixDailyHubViewController: UIViewController, UITableViewDataSource {

    var onPlay: (() -> Void)?
    var onContinue: (() -> Void)?

    private let titleView = BlomixCutoutTitleView(text: BlomixL10n.dailyHubTitle, fontSize: 28)
    private let dateLabel = UILabel()
    private let deadlineLabel = UILabel()
    private let headerTextStack = UIStackView()
    private let ghostRow = UIStackView()
    private let ghostTitleLabel = UILabel()
    private let ghostValueLabel = UILabel()
    private let ghostSpinner = UIActivityIndicatorView(style: .medium)
    private var ghostWaitRevealWork: DispatchWorkItem?
    private let closeButton = BlomixUIButton()
    private let statusLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let spinner = BlomixPvPSearchBlocksView()
    private let ctaButton = BlomixUIButton()
    private let yesterdayPodiumBox = UIView()
    private let yesterdayPodiumLabel = UILabel()
    private let bottomStack = UIStackView()

    private var entries: [BlomixDailyScoreEntry] = [] {
        didSet { tableView.reloadData() }
    }
    private var ctaKind = BlomixDailyChallenge.shared.hubCTA
    private var displayedDay = BlomixDailyChallenge.shared.displayedHubDay

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BlomixAppearance.sceneBackground
        addAmbientBlocksBackground(density: .low)
        buildChrome()
        refreshHubState(reloadScores: true)
        BlomixDailyGhostController.shared.onDisplayChange = { [weak self] display in
            self?.applyGhostDisplay(display)
        }
        applyGhostDisplay(BlomixDailyGhostController.shared.display)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshHubState(reloadScores: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        BlomixDailyGhostController.shared.hubAppeared(day: displayedDay)
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

        dateLabel.textColor = BlomixAppearance.primaryText
        dateLabel.font = BlomixTypography.displayFont(size: 26)
        dateLabel.textAlignment = .center
        dateLabel.numberOfLines = 2
        dateLabel.adjustsFontSizeToFitWidth = true
        dateLabel.minimumScaleFactor = 0.7
        dateLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        deadlineLabel.textColor = BlomixAppearance.secondaryText
        deadlineLabel.font = BlomixTypography.uiFont(size: 13, weight: .medium)
        deadlineLabel.textAlignment = .center
        deadlineLabel.numberOfLines = 1
        deadlineLabel.adjustsFontSizeToFitWidth = true
        deadlineLabel.minimumScaleFactor = 0.8

        ghostTitleLabel.text = BlomixL10n.dailyGhostTitle
        ghostTitleLabel.textColor = BlomixAppearance.tertiaryText
        ghostTitleLabel.font = BlomixTypography.uiFont(size: 12, weight: .regular)
        ghostTitleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        ghostValueLabel.textColor = BlomixAppearance.tertiaryText
        ghostValueLabel.font = BlomixTypography.uiFont(size: 12, weight: .medium)
        ghostValueLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        ghostSpinner.color = BlomixAppearance.tertiaryText
        ghostSpinner.hidesWhenStopped = true
        ghostSpinner.transform = CGAffineTransform(scaleX: 0.72, y: 0.72)

        ghostRow.axis = .horizontal
        ghostRow.alignment = .center
        ghostRow.spacing = 8
        ghostRow.addArrangedSubview(ghostTitleLabel)
        ghostRow.addArrangedSubview(ghostValueLabel)
        ghostRow.addArrangedSubview(ghostSpinner)
        ghostRow.isAccessibilityElement = true

        headerTextStack.axis = .vertical
        headerTextStack.alignment = .center
        headerTextStack.spacing = 8
        headerTextStack.translatesAutoresizingMaskIntoConstraints = false
        headerTextStack.addArrangedSubview(dateLabel)
        headerTextStack.addArrangedSubview(ghostRow)
        headerTextStack.addArrangedSubview(deadlineLabel)
        headerTextStack.setCustomSpacing(10, after: dateLabel)
        headerTextStack.setCustomSpacing(6, after: ghostRow)
        view.addSubview(headerTextStack)

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

        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: ctaButton)
        BlomixUIDestinationButtonStyle.applyContentInsets(UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16), to: ctaButton)
        ctaButton.addTarget(self, action: #selector(ctaTapped), for: .touchUpInside)

        yesterdayPodiumBox.backgroundColor = BlomixAppearance.chipFill
        yesterdayPodiumBox.layer.cornerRadius = 10
        yesterdayPodiumBox.layer.borderWidth = 1
        yesterdayPodiumBox.layer.borderColor = BlomixAppearance.chipBorder.cgColor
        yesterdayPodiumBox.clipsToBounds = true
        yesterdayPodiumBox.isHidden = true
        yesterdayPodiumBox.isAccessibilityElement = true

        yesterdayPodiumLabel.translatesAutoresizingMaskIntoConstraints = false
        yesterdayPodiumLabel.textColor = BlomixAppearance.primaryText
        yesterdayPodiumLabel.font = BlomixTypography.uiFont(size: 13, weight: .medium)
        yesterdayPodiumLabel.textAlignment = .center
        yesterdayPodiumLabel.numberOfLines = 2
        yesterdayPodiumLabel.lineBreakMode = .byTruncatingTail
        yesterdayPodiumBox.addSubview(yesterdayPodiumLabel)

        bottomStack.axis = .vertical
        bottomStack.spacing = 10
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        bottomStack.addArrangedSubview(yesterdayPodiumBox)
        bottomStack.addArrangedSubview(ctaButton)
        view.addSubview(bottomStack)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            titleView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            titleView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleView.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12),

            headerTextStack.topAnchor.constraint(equalTo: titleView.bottomAnchor, constant: 14),
            headerTextStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            headerTextStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            dateLabel.widthAnchor.constraint(equalTo: headerTextStack.widthAnchor),
            deadlineLabel.widthAnchor.constraint(equalTo: headerTextStack.widthAnchor),

            statusLabel.topAnchor.constraint(equalTo: headerTextStack.bottomAnchor, constant: 14),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            bottomStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            bottomStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            bottomStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            ctaButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            yesterdayPodiumLabel.topAnchor.constraint(equalTo: yesterdayPodiumBox.topAnchor, constant: 8),
            yesterdayPodiumLabel.bottomAnchor.constraint(equalTo: yesterdayPodiumBox.bottomAnchor, constant: -8),
            yesterdayPodiumLabel.leadingAnchor.constraint(equalTo: yesterdayPodiumBox.leadingAnchor, constant: 12),
            yesterdayPodiumLabel.trailingAnchor.constraint(equalTo: yesterdayPodiumBox.trailingAnchor, constant: -12),

            tableView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tableView.bottomAnchor.constraint(equalTo: bottomStack.topAnchor, constant: -12),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func refreshHubState(reloadScores: Bool) {
        let previousDay = displayedDay
        ctaKind = BlomixDailyChallenge.shared.hubCTA
        displayedDay = BlomixDailyChallenge.shared.displayedHubDay
        dateLabel.text = Self.utcDateCaption(forDay: displayedDay)
        if let time = BlomixDailyChallenge.shared.localizedClosureTime(forDay: displayedDay) {
            deadlineLabel.text = BlomixL10n.dailyDeadlineCompleteBy(time)
            deadlineLabel.isHidden = false
        } else {
            deadlineLabel.text = nil
            deadlineLabel.isHidden = true
        }
        applyCTA()
        BlomixDailyGhostController.shared.hubAppeared(day: displayedDay)
        if reloadScores || previousDay != displayedDay {
            loadScores()
        }
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
        let day = displayedDay
        let worldToday = BlomixDailyChallenge.shared.utcToday
        let yesterday = BlomixDailySeed.previousUtcDayString()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let showWorldYesterday = (day == worldToday)
            let yesterdayOpen = showWorldYesterday && !BlomixDailySeed.isUtcDayClosed(yesterday)
            async let dayLoad = BlomixDailyChallenge.shared.fetchScores(day: day)
            let today = await dayLoad
            let yesterdayResult: BlomixDailyScoresLoad
            if showWorldYesterday, !yesterdayOpen {
                yesterdayResult = await BlomixDailyChallenge.shared.fetchScores(day: yesterday)
            } else {
                yesterdayResult = .loaded([])
            }
            self.spinner.stopAnimating(settle: false) { [weak self] in
                self?.spinner.isHidden = true
            }
            switch today {
            case .loaded(let rows):
                self.entries = rows
                self.statusLabel.text = rows.isEmpty
                    ? BlomixL10n.dailyHubEmpty
                    : BlomixL10n.leaderboardTopCount(rows.count)
            case .unavailable:
                self.entries = []
                self.statusLabel.text = BlomixL10n.dailyHubError
            }
            if !showWorldYesterday {
                self.applyYesterdayPodium(names: [], stillOpen: false, hide: true)
            } else if yesterdayOpen {
                self.applyYesterdayPodium(names: [], stillOpen: true, hide: false)
            } else {
                switch yesterdayResult {
                case .loaded(let rows):
                    self.applyYesterdayPodium(names: BlomixDailyChallenge.podiumDisplayNames(in: rows), stillOpen: false, hide: false)
                case .unavailable:
                    self.applyYesterdayPodium(names: [], stillOpen: false, hide: true)
                }
            }
        }
    }

    private func applyYesterdayPodium(names: [String], stillOpen: Bool, hide: Bool) {
        if hide {
            yesterdayPodiumBox.isHidden = true
            yesterdayPodiumLabel.text = nil
            yesterdayPodiumBox.accessibilityLabel = nil
            return
        }
        if stillOpen {
            let caption = BlomixL10n.dailyHubYesterdayOpen
            yesterdayPodiumLabel.text = caption
            yesterdayPodiumBox.accessibilityLabel = caption
            yesterdayPodiumBox.isHidden = false
            return
        }
        guard !names.isEmpty else {
            yesterdayPodiumBox.isHidden = true
            yesterdayPodiumLabel.text = nil
            yesterdayPodiumBox.accessibilityLabel = nil
            return
        }
        let caption = BlomixL10n.dailyHubYesterdayPodium(names.joined(separator: ", "))
        yesterdayPodiumLabel.text = caption
        yesterdayPodiumBox.accessibilityLabel = caption
        yesterdayPodiumBox.isHidden = false
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

    private func applyGhostDisplay(_ display: BlomixDailyGhostDisplay) {
        ghostWaitRevealWork?.cancel()
        ghostWaitRevealWork = nil
        switch display {
        case .ready(let score):
            ghostSpinner.stopAnimating()
            ghostValueLabel.text = Self.ghostScoreCaption(score)
            ghostRow.accessibilityLabel = BlomixL10n.dailyGhostAccessibility(score)
        case .computing:
            ghostValueLabel.text = nil
            ghostSpinner.stopAnimating()
            ghostRow.accessibilityLabel = BlomixL10n.dailyGhostAccessibilityComputing
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if case .computing = BlomixDailyGhostController.shared.display {
                    self.ghostValueLabel.text = BlomixL10n.dailyGhostComputing
                    self.ghostSpinner.startAnimating()
                }
            }
            ghostWaitRevealWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
    }

    private static func ghostScoreCaption(_ score: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        return formatter.string(from: NSNumber(value: score)) ?? "\(score)"
    }

    private static func utcDateCaption(forDay day: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = BlomixDailySeed.utcCalendar()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("yMMMMd")
        if let date = BlomixDailySeed.startOfUtcDay(day) {
            return formatter.string(from: date)
        }
        return formatter.string(from: BlomixDailySeed.now())
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
