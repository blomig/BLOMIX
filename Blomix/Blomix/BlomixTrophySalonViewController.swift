//
//  BlomixTrophySalonViewController.swift
//  Blomix
//
//  Salon des trophées — modal famille Crédits : murs, grille de cibles, fiche.
//

import UIKit

@MainActor
final class BlomixTrophySalonViewController: UIViewController {

    private let closeButton = BlomixUIButton()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let bannerLabel = UILabel()
    private let lastLabel = UILabel()
    private var cellByID: [String: TrophyCell] = [:]
    private let focusID: String?

    private var dimView: UIView?
    private var ficheView: UIView?

    init(focusID: String? = nil) {
        self.focusID = focusID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BlomixAppearance.sceneBackground
        addAmbientBlocksBackground(density: .low)
        buildChrome()
        rebuildContent()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(trophiesDidChange),
            name: .blomixTrophiesDidChange,
            object: nil
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let focusID {
            DispatchQueue.main.async { [weak self] in
                self?.openFiche(id: focusID, scroll: true)
            }
        }
    }

    // MARK: - Chrome

    private func buildChrome() {
        closeButton.setTitle(BlomixL10n.close, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: closeButton)
        BlomixUIDestinationButtonStyle.applyContentInsets(UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12), to: closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.indicatorStyle = BlomixAppearance.isDark ? .white : .black
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 18
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 4),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        cellByID.removeAll()

        let title = BlomixCutoutTitleView(text: BlomixL10n.trophySalonTitle, fontSize: 26, pad: 6)
        contentStack.addArrangedSubview(title)

        bannerLabel.font = BlomixTypography.uiFont(size: 13, weight: .regular)
        bannerLabel.textColor = BlomixAppearance.secondaryText
        bannerLabel.textAlignment = .center
        bannerLabel.numberOfLines = 2
        refreshBanner()
        contentStack.addArrangedSubview(bannerLabel)

        lastLabel.font = BlomixTypography.uiFont(size: 12, weight: .regular)
        lastLabel.textColor = BlomixAppearance.tertiaryText
        lastLabel.textAlignment = .center
        lastLabel.numberOfLines = 1
        refreshLast()
        contentStack.addArrangedSubview(lastLabel)

        #if DEBUG
        let debugHint = UILabel()
        debugHint.text = "DEBUG · appui long sur une cible : +1"
        debugHint.font = BlomixTypography.uiFont(size: 11, weight: .regular)
        debugHint.textColor = BlomixAppearance.tertiaryText
        debugHint.textAlignment = .center
        contentStack.addArrangedSubview(debugHint)
        #endif

        for wall in BlomixTrophyWall.allCases {
            contentStack.addArrangedSubview(makeWallBlock(wall))
        }
    }

    private func refreshBanner() {
        let store = BlomixTrophyStore.shared
        let ranks = store.rankCounts()
        bannerLabel.text = BlomixL10n.trophySalonBanner(
            lit: store.litVisibleCount,
            total: store.visibleTotal,
            i: ranks.i,
            ii: ranks.ii,
            iii: ranks.iii
        )
    }

    private func refreshLast() {
        if let promo = BlomixTrophyStore.shared.lastPromotion,
           let def = BlomixTrophyCatalog.def(id: promo.id) {
            lastLabel.text = BlomixL10n.trophySalonLast(
                name: Self.displayTitle(def),
                rank: promo.rank.roman
            )
        } else {
            lastLabel.text = " "
        }
    }

    private func makeWallBlock(_ wall: BlomixTrophyWall) -> UIView {
        let wrap = UIStackView()
        wrap.axis = .vertical
        wrap.alignment = .fill
        wrap.spacing = 10

        let heading = UILabel()
        heading.text = BlomixL10n.trophyWallTitle(wall)
        heading.font = BlomixTypography.displayFont(size: 18)
        heading.textColor = BlomixAppearance.primaryText
        wrap.addArrangedSubview(heading)

        let trophies = BlomixTrophyCatalog.trophies(on: wall)
        let columns = 4
        var row = UIStackView()
        row.axis = .horizontal
        row.alignment = .top
        row.distribution = .fillEqually
        row.spacing = 8

        func flushRow() {
            while row.arrangedSubviews.count < columns {
                row.addArrangedSubview(UIView())
            }
            wrap.addArrangedSubview(row)
            row = UIStackView()
            row.axis = .horizontal
            row.alignment = .top
            row.distribution = .fillEqually
            row.spacing = 8
        }

        for (i, def) in trophies.enumerated() {
            let cell = TrophyCell(def: def)
            cell.onTap = { [weak self] in self?.openFiche(id: def.id, scroll: false) }
            cell.onDebugBump = { [weak self] in
                BlomixTrophyStore.shared.debugAdd(def.id)
                self?.refreshBanner()
                self?.refreshLast()
            }
            cellByID[def.id] = cell
            row.addArrangedSubview(cell)
            if (i + 1) % columns == 0 {
                wrap.addArrangedSubview(row)
                row = UIStackView()
                row.axis = .horizontal
                row.alignment = .top
                row.distribution = .fillEqually
                row.spacing = 8
            }
        }
        if !row.arrangedSubviews.isEmpty {
            flushRow()
        }
        return wrap
    }

    // MARK: - Fiche

    private func openFiche(id: String, scroll: Bool) {
        guard let def = BlomixTrophyCatalog.def(id: id) else { return }
        if scroll, let cell = cellByID[id] {
            let rect = cell.convert(cell.bounds, to: scrollView)
            scrollView.scrollRectToVisible(rect.insetBy(dx: 0, dy: -40), animated: true)
        }
        let store = BlomixTrophyStore.shared
        let progress = store.progress(for: id)
        let lockedSecret = def.isSecret && progress.value <= 0
        store.markSeen(id)

        dimView?.removeFromSuperview()
        ficheView?.removeFromSuperview()

        let dim = UIView()
        dim.backgroundColor = UIColor.black.withAlphaComponent(BlomixAppearance.isDark ? 0.55 : 0.28)
        dim.translatesAutoresizingMaskIntoConstraints = false
        dim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissFiche)))
        view.addSubview(dim)
        NSLayoutConstraint.activate([
            dim.topAnchor.constraint(equalTo: view.topAnchor),
            dim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dim.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        dimView = dim

        let card = UIView()
        card.backgroundColor = BlomixAppearance.panelFill
        card.layer.cornerRadius = 18
        card.layer.borderWidth = BlomixUIDestinationButtonStyle.hairlineBorderWidth
        card.layer.borderColor = BlomixAppearance.chipBorder.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        ficheView = card

        let cible = BlomixTrophyCibleView()
        cible.value = progress.value
        cible.curve = def.curve
        cible.showsLegends = !lockedSecret
        cible.isSecretLocked = lockedSecret
        cible.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.font = BlomixTypography.displayFont(size: 22)
        title.textColor = BlomixAppearance.primaryText
        title.textAlignment = .center
        title.numberOfLines = 2
        title.text = lockedSecret ? BlomixL10n.trophySecretTitle : Self.displayTitle(def)

        let body = UILabel()
        body.font = BlomixTypography.uiFont(size: 14, weight: .regular)
        body.textColor = BlomixAppearance.secondaryText
        body.textAlignment = .center
        body.numberOfLines = 0
        body.text = lockedSecret ? BlomixL10n.trophySecretHint : BlomixL10n.trophyBody(def.id)

        let dates = UILabel()
        dates.font = BlomixTypography.uiFont(size: 12, weight: .regular)
        dates.textColor = BlomixAppearance.tertiaryText
        dates.textAlignment = .center
        dates.numberOfLines = 2
        dates.text = lockedSecret ? " " : Self.datesLine(progress)

        let stack = UIStackView(arrangedSubviews: [cible, title, body, dates])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            card.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),

            cible.widthAnchor.constraint(equalToConstant: 168),
            cible.heightAnchor.constraint(equalToConstant: 168),
            title.widthAnchor.constraint(equalTo: stack.widthAnchor),
            body.widthAnchor.constraint(equalTo: stack.widthAnchor),
            dates.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @objc private func dismissFiche() {
        dimView?.removeFromSuperview()
        ficheView?.removeFromSuperview()
        dimView = nil
        ficheView = nil
        refreshBanner()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func trophiesDidChange() {
        for (id, cell) in cellByID {
            cell.reload()
            _ = id
        }
        refreshBanner()
        refreshLast()
        if let ficheView, let id = cellByID.first(where: { $0.value.window != nil })?.key {
            _ = (ficheView, id)
        }
    }

    static func displayTitle(_ def: BlomixTrophyDef) -> String {
        if let magix = def.magixTitle { return magix }
        return BlomixL10n.trophyTitle(def.id)
    }

    private static func datesLine(_ p: BlomixTrophyProgress) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .none
        var bits: [String] = []
        if let d = p.firstAt { bits.append("I · \(fmt.string(from: d))") }
        if let d = p.iiAt { bits.append("II · \(fmt.string(from: d))") }
        if let d = p.iiiAt { bits.append("III · \(fmt.string(from: d))") }
        return bits.isEmpty ? " " : bits.joined(separator: "   ")
    }
}

// MARK: - Cellule mur

@MainActor
private final class TrophyCell: UIView {
    let def: BlomixTrophyDef
    var onTap: (() -> Void)?
    var onDebugBump: (() -> Void)?

    private let cible = BlomixTrophyCibleView()
    private let caption = UILabel()

    init(def: BlomixTrophyDef) {
        self.def = def
        super.init(frame: .zero)
        cible.translatesAutoresizingMaskIntoConstraints = false
        caption.font = BlomixTypography.uiFont(size: 10, weight: .regular)
        caption.textColor = BlomixAppearance.tertiaryText
        caption.textAlignment = .center
        caption.numberOfLines = 1
        caption.adjustsFontSizeToFitWidth = true
        caption.minimumScaleFactor = 0.7
        caption.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cible)
        addSubview(caption)
        NSLayoutConstraint.activate([
            cible.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            cible.centerXAnchor.constraint(equalTo: centerXAnchor),
            cible.widthAnchor.constraint(equalToConstant: 52),
            cible.heightAnchor.constraint(equalToConstant: 52),
            caption.topAnchor.constraint(equalTo: cible.bottomAnchor, constant: 4),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            caption.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            caption.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        #if DEBUG
        let long = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        long.minimumPressDuration = 0.45
        addGestureRecognizer(long)
        #endif
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func reload() {
        let p = BlomixTrophyStore.shared.progress(for: def.id)
        let locked = def.isSecret && p.value <= 0
        cible.value = p.value
        cible.curve = def.curve
        cible.showsLegends = false
        cible.isSecretLocked = locked
        caption.text = locked ? BlomixL10n.trophySecretCaption : BlomixTrophySalonViewController.displayTitle(def)
        caption.textColor = p.value > 0
            ? BlomixAppearance.secondaryText
            : BlomixAppearance.tertiaryText
    }

    @objc private func tapped() { onTap?() }

    @objc private func longPressed(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        onDebugBump?()
        reload()
    }
}
