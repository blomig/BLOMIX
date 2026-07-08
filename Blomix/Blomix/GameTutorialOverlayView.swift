//
//  GameTutorialOverlayView.swift
//  Blomix
//
//  Overlay tutoriel paginé : 3 pages swipables horizontalement,
//  callouts ancrés sur les éléments du jeu (score, file, bombe) affichés
//  uniquement sur la page concernée.  Bouton "J'ai compris" + switch
//  "Ne plus afficher" fixes en bas.
//

import UIKit

/// Cibles en coordonnées **UIKit** (origine haut-gauche du `GameViewController.view`), alignées sur le `SKView`.
struct TutorialLayoutAnchors {
    let scorePoint: CGPoint
    let gridCenter: CGPoint
    let nextQueuePoint: CGPoint
    let bombPoint: CGPoint
}

@MainActor
private enum TutorialOverlayFont {
    static func uiFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        BlomixTypography.uiFont(size: size, weight: weight)
    }
}

// MARK: - Overlay principal

@MainActor
final class GameTutorialOverlayView: UIView, UIScrollViewDelegate {

    // MARK: Callouts ancrés sur les éléments de jeu

    private let scoreCallout = TutorialCalloutView()
    /// File : flèche vers le bas-droite (rotation −45°) + décalage à gauche.
    private let queueHalfBand = TutorialHalfBandCalloutView(
        text: BlomixL10n.tutorialHintQueue,
        bodyFontSize: 12,
        isLeftBand: true,
        arrowHorizontalNudge: -20,
        arrowRotationRadians: -.pi / 4
    )
    private let bombHalfBand = TutorialHalfBandCalloutView(
        text: BlomixL10n.tutorialHintBomb,
        bodyFontSize: 12,
        isLeftBand: false
    )

    // MARK: Pagination

    private let pageScrollView = UIScrollView()
    private let pageControl = UIPageControl()
    private var currentPage = 0
    private let pageCount = 3

    // MARK: Fond + ancres

    private let dimBackground = UIView()
    private let anchors: TutorialLayoutAnchors?

    // MARK: Barre du bas

    private let understoodButton = BlomixUIButton()
    private let showOnStartupRadio = UIImageView()
    private let showOnStartupLabel = UILabel()
    // ON si le tutoriel n'a pas encore été désactivé, OFF si le joueur l'avait mis à false.
    private var showOnStartup = !UserDefaults.standard.hasSeenGameTutorial
    private let bottomStack = UIStackView()

    var onDismiss: (() -> Void)?

    private var didRunFadeIn = false
    private var pageViewsBuilt = false

    // MARK: Init

    init(anchors: TutorialLayoutAnchors?) {
        self.anchors = anchors
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        alpha = 0
        setupSubviews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    // MARK: Setup

    private func setupSubviews() {
        // Fond semi-transparent
        dimBackground.translatesAutoresizingMaskIntoConstraints = false
        dimBackground.backgroundColor = UIColor(white: 0, alpha: 0.55)
        dimBackground.isUserInteractionEnabled = true
        addSubview(dimBackground)

        // Blox flottants (au-dessus du fond dim, sous tout le contenu)
        let ambientBlocks = BlomixAmbientBlocksView()
        ambientBlocks.translatesAutoresizingMaskIntoConstraints = false
        ambientBlocks.isUserInteractionEnabled = false
        addSubview(ambientBlocks)
        NSLayoutConstraint.activate([
            ambientBlocks.topAnchor.constraint(equalTo: topAnchor),
            ambientBlocks.leadingAnchor.constraint(equalTo: leadingAnchor),
            ambientBlocks.trailingAnchor.constraint(equalTo: trailingAnchor),
            ambientBlocks.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // ScrollView paginé
        pageScrollView.isPagingEnabled = true
        pageScrollView.showsHorizontalScrollIndicator = false
        pageScrollView.showsVerticalScrollIndicator = false
        pageScrollView.bounces = false
        pageScrollView.backgroundColor = .clear
        pageScrollView.delegate = self
        addSubview(pageScrollView)

        // PageControl
        pageControl.numberOfPages = pageCount
        pageControl.currentPage = 0
        pageControl.pageIndicatorTintColor = UIColor(white: 1, alpha: 0.3)
        pageControl.currentPageIndicatorTintColor = .white
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pageControl)

        // Callouts (superposés à tout)
        scoreCallout.configure(
            text: BlomixL10n.tutorialHintScore,
            symbolName: "arrow.right",
            layout: .labelLeftArrowRight,
            bodyFontSize: 16
        )
        for v in [scoreCallout, queueHalfBand, bombHalfBand] as [UIView] {
            v.isUserInteractionEnabled = false
            addSubview(v)
        }

        // Barre du bas
        understoodButton.setTitle(BlomixL10n.tutorialGotIt, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: understoodButton)
        understoodButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        understoodButton.addTarget(self, action: #selector(understoodTapped), for: .touchUpInside)

        // Radio "Afficher ce guide au démarrage" — même style que skins / polices
        let radioCfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let initialRadioName = showOnStartup ? "largecircle.fill.circle" : "circle"
        showOnStartupRadio.image = UIImage(systemName: initialRadioName, withConfiguration: radioCfg)
        showOnStartupRadio.tintColor = .white
        showOnStartupRadio.contentMode = .scaleAspectFit
        showOnStartupRadio.setContentHuggingPriority(.required, for: .horizontal)

        showOnStartupLabel.text = BlomixL10n.tutorialDontShowAgain
        showOnStartupLabel.textColor = UIColor(white: 0.92, alpha: 1)
        showOnStartupLabel.font = TutorialOverlayFont.uiFont(size: 14)
        showOnStartupLabel.numberOfLines = 0

        let switchRow = UIStackView(arrangedSubviews: [showOnStartupRadio, showOnStartupLabel])
        switchRow.axis = .horizontal
        switchRow.spacing = 12
        switchRow.alignment = .center
        let radioTap = UITapGestureRecognizer(target: self, action: #selector(radioRowTapped))
        switchRow.isUserInteractionEnabled = true
        switchRow.addGestureRecognizer(radioTap)

        bottomStack.axis = .vertical
        bottomStack.spacing = 14
        bottomStack.alignment = .fill
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        bottomStack.addArrangedSubview(understoodButton)
        bottomStack.addArrangedSubview(switchRow)
        addSubview(bottomStack)

        NSLayoutConstraint.activate([
            dimBackground.topAnchor.constraint(equalTo: topAnchor),
            dimBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimBackground.bottomAnchor.constraint(equalTo: bottomAnchor),

            bottomStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            bottomStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            bottomStack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),

            pageControl.centerXAnchor.constraint(equalTo: centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: bottomStack.topAnchor, constant: -10),
        ])

        updateCalloutVisibility()
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width

        // ScrollView : de sous la safe-top à au-dessus du pageControl
        let topInset = safeAreaInsets.top + 8
        let pageCtrlMinY = pageControl.frame.minY
        let scrollBottom = pageCtrlMinY > topInset + 80 ? pageCtrlMinY - 8 : bounds.height - 120
        let scrollH = max(80, scrollBottom - topInset)
        let newScrollFrame = CGRect(x: 0, y: topInset, width: w, height: scrollH)
        if pageScrollView.frame != newScrollFrame {
            pageScrollView.frame = newScrollFrame
            pageScrollView.contentSize = CGSize(width: w * CGFloat(pageCount), height: scrollH)
            pageViewsBuilt = false  // reconstruire si la taille a changé
        }

        buildPageViewsIfNeeded()

        // Repositionner le contenu si la page était déjà définie
        if pageViewsBuilt {
            pageScrollView.setContentOffset(
                CGPoint(x: CGFloat(currentPage) * w, y: 0),
                animated: false
            )
        }

        // Callout score (à gauche du score, milieu vertical)
        let a = anchors ?? fallbackAnchors()
        let safeLeft = safeAreaInsets.left + 8
        let safeRight = w - safeAreaInsets.right - 8
        let scoreMaxW = min(220, w * 0.48)
        let scoreSize = scoreCallout.fittingSize(maxWidth: scoreMaxW)
        let scoreTrailing = min(a.scorePoint.x - 12, safeRight)
        let scoreX = scoreTrailing - scoreSize.width
        scoreCallout.frame = CGRect(
            x: max(safeLeft, scoreX),
            y: a.scorePoint.y - scoreSize.height / 2,
            width: scoreSize.width,
            height: scoreSize.height
        )

        // Callouts file + bombe (positionnés par updateLayout sur bounds entiers)
        let bandMargin: CGFloat = 10
        queueHalfBand.updateLayout(
            overlayBounds: bounds,
            safeInsets: safeAreaInsets,
            gridMidX: a.gridCenter.x,
            margin: bandMargin,
            arrowTarget: a.nextQueuePoint
        )
        bombHalfBand.updateLayout(
            overlayBounds: bounds,
            safeInsets: safeAreaInsets,
            gridMidX: a.gridCenter.x,
            margin: bandMargin,
            arrowTarget: a.bombPoint
        )
    }

    // MARK: Construction des pages

    private func buildPageViewsIfNeeded() {
        guard !pageViewsBuilt, pageScrollView.bounds.width > 0, pageScrollView.bounds.height > 0 else { return }
        pageViewsBuilt = true

        // Vider les anciennes pages
        pageScrollView.subviews.forEach { $0.removeFromSuperview() }

        let w = pageScrollView.bounds.width
        let h = pageScrollView.bounds.height

        let pages: [(title: String, body: String, visual: UIView?)] = [
            (
                BlomixL10n.tutorialPage1Title,
                BlomixL10n.tutorialPage1Body,
                TutorialChainExampleView()
            ),
            (
                BlomixL10n.tutorialPage2Title,
                BlomixL10n.tutorialPage2Body,
                TutorialBrixInfoView(text: "")   // icône Brix seule, sans texte redondant
            ),
            (
                BlomixL10n.tutorialPage3Title,
                BlomixL10n.tutorialPage3Body,
                nil
            ),
        ]

        for (i, page) in pages.enumerated() {
            let pageView = makePageView(
                title: page.title,
                body: page.body,
                visual: page.visual,
                width: w,
                height: h
            )
            pageView.frame = CGRect(x: CGFloat(i) * w, y: 0, width: w, height: h)
            pageScrollView.addSubview(pageView)
        }
    }

    private func makePageView(title: String, body: String, visual: UIView?, width: CGFloat, height: CGFloat) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = TutorialOverlayFont.uiFont(size: 20, weight: .semibold)
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center

        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.textColor = UIColor(white: 0.90, alpha: 1)
        bodyLabel.font = TutorialOverlayFont.uiFont(size: 13)
        bodyLabel.numberOfLines = 0
        bodyLabel.textAlignment = .center

        let margin: CGFloat = 22
        let contentW = width - 2 * margin
        let spacing: CGFloat = 20

        titleLabel.preferredMaxLayoutWidth = contentW
        bodyLabel.preferredMaxLayoutWidth = contentW
        let titleH = titleLabel.sizeThatFits(CGSize(width: contentW, height: .greatestFiniteMagnitude)).height
        let bodyH = bodyLabel.sizeThatFits(CGSize(width: contentW, height: .greatestFiniteMagnitude)).height

        var visualH: CGFloat = 0
        var visualW: CGFloat = contentW
        if let visual {
            if let chain = visual as? TutorialChainExampleView {
                let sz = chain.fittingSize()
                visualH = sz.height
                visualW = min(sz.width, contentW)
            } else if let brix = visual as? TutorialBrixInfoView {
                let sz = brix.fittingSize(maxWidth: contentW)
                visualH = sz.height
                visualW = min(sz.width, contentW)
            } else {
                visualH = 40
            }
        }

        let totalH = titleH + (visual != nil ? spacing + visualH : 0) + spacing + bodyH
        // Centrer verticalement, avec un léger décalage vers le haut pour laisser place aux callouts du bas
        var originY = max(16, (height - totalH) / 2 - 20)

        titleLabel.frame = CGRect(x: margin, y: originY, width: contentW, height: titleH)
        container.addSubview(titleLabel)
        originY += titleH + spacing

        if let visual {
            visual.isUserInteractionEnabled = false
            let vx = margin + (contentW - visualW) / 2
            visual.frame = CGRect(x: vx, y: originY, width: visualW, height: visualH)
            container.addSubview(visual)
            originY += visualH + spacing
        }

        bodyLabel.frame = CGRect(x: margin, y: originY, width: contentW, height: bodyH)
        container.addSubview(bodyLabel)

        return container
    }

    // MARK: Visibilité des callouts par page

    private func updateCalloutVisibility() {
        scoreCallout.isHidden = currentPage != 0
        queueHalfBand.isHidden = currentPage != 0
        bombHalfBand.isHidden = currentPage != 1
    }

    // MARK: UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.bounds.width > 0 else { return }
        let page = Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
        let clamped = max(0, min(pageCount - 1, page))
        guard clamped != currentPage else { return }
        currentPage = clamped
        pageControl.currentPage = currentPage
        updateCalloutVisibility()
    }

    // MARK: Animation + fallback

    private func fallbackAnchors() -> TutorialLayoutAnchors {
        let w = bounds.width
        let h = bounds.height
        return TutorialLayoutAnchors(
            scorePoint: CGPoint(x: w * 0.52, y: h * 0.26),
            gridCenter: CGPoint(x: w * 0.5, y: h * 0.48),
            nextQueuePoint: CGPoint(x: w * 0.5, y: h * 0.72),
            bombPoint: CGPoint(x: w * 0.9, y: h * 0.72)
        )
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard superview != nil, !didRunFadeIn else { return }
        didRunFadeIn = true
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut]) {
            self.alpha = 1
        }
    }

    @objc private func radioRowTapped() {
        showOnStartup.toggle()
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let name = showOnStartup ? "largecircle.fill.circle" : "circle"
        showOnStartupRadio.image = UIImage(systemName: name, withConfiguration: cfg)
    }

    @objc private func understoodTapped() {
        // Toujours écrire la valeur : ON → hasSeenGameTutorial=false (réaffichera le tutoriel),
        // OFF → hasSeenGameTutorial=true (ne plus afficher).
        UserDefaults.standard.hasSeenGameTutorial = !showOnStartup
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn]) {
            self.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
            self.onDismiss?()
        }
    }
}

// MARK: - Visuel page 1 : chaîne de 5 blox de même couleur

private final class TutorialChainExampleView: UIView {

    private let stack = UIStackView()
    private let caption = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        stack.axis = .horizontal
        stack.spacing = 5
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        let color = BlomixSkinCatalog.shared.bloxUIColor(forNormalizedKey: "blue") ?? .systemBlue
        for _ in 0..<5 {
            let block = UIView()
            block.translatesAutoresizingMaskIntoConstraints = false
            block.backgroundColor = color
            block.layer.cornerRadius = 5
            block.layer.borderWidth = 1
            block.layer.borderColor = UIColor(white: 1, alpha: 0.25).cgColor
            NSLayoutConstraint.activate([
                block.widthAnchor.constraint(equalToConstant: 24),
                block.heightAnchor.constraint(equalToConstant: 24),
            ])
            stack.addArrangedSubview(block)
        }

        caption.text = BlomixL10n.tutorialPage1ChainCaption
        caption.textColor = UIColor(white: 0.80, alpha: 1)
        caption.font = TutorialOverlayFont.uiFont(size: 11)
        caption.textAlignment = .center
        caption.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        addSubview(caption)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            caption.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 12),
            caption.centerXAnchor.constraint(equalTo: centerXAnchor),
            caption.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func fittingSize() -> CGSize {
        systemLayoutSizeFitting(
            CGSize(width: 300, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )
    }
}

// MARK: - Callout bande gauche/droite (file / bombe)

private final class TutorialHalfBandCalloutView: UIView {

    private let label = UILabel()
    private let arrow = UIImageView()
    private let isLeftBand: Bool
    private let arrowHorizontalNudge: CGFloat
    private let arrowRotationRadians: CGFloat

    private let arrowSide: CGFloat = 34

    init(
        text: String,
        bodyFontSize: CGFloat,
        isLeftBand: Bool,
        arrowHorizontalNudge: CGFloat = 0,
        arrowRotationRadians: CGFloat = 0
    ) {
        self.isLeftBand = isLeftBand
        self.arrowHorizontalNudge = arrowHorizontalNudge
        self.arrowRotationRadians = arrowRotationRadians
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        label.text = text
        label.textColor = .white
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.font = TutorialOverlayFont.uiFont(size: bodyFontSize, weight: .medium)
        label.textAlignment = isLeftBand ? .natural : .right

        let cfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        arrow.image = UIImage(systemName: "arrow.down", withConfiguration: cfg)
        arrow.contentMode = .scaleAspectFit
        arrow.tintColor = UIColor(white: 0.95, alpha: 1)

        addSubview(label)
        addSubview(arrow)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func updateLayout(
        overlayBounds: CGRect,
        safeInsets: UIEdgeInsets,
        gridMidX: CGFloat,
        margin: CGFloat,
        arrowTarget: CGPoint
    ) {
        frame = overlayBounds
        let w = overlayBounds.width
        let safeLeft = safeInsets.left
        let safeRight = w - safeInsets.right

        arrow.transform = .identity
        var ax = arrowTarget.x - arrowSide / 2 + arrowHorizontalNudge
        ax = min(max(ax, safeLeft + 4), safeRight - arrowSide - 4)
        var ay = arrowTarget.y - arrowSide
        ay = max(ay, safeInsets.top + 4)
        arrow.frame = CGRect(x: ax, y: ay, width: arrowSide, height: arrowSide)
        if arrowRotationRadians != 0 {
            arrow.transform = CGAffineTransform(rotationAngle: arrowRotationRadians)
        }

        let gapAboveArrow: CGFloat = 10
        let minLabelY = safeInsets.top + 8
        let labelBottom = arrow.frame.minY - gapAboveArrow

        let x0: CGFloat
        let x1: CGFloat
        if isLeftBand {
            x0 = safeLeft + margin
            x1 = gridMidX - margin
        } else {
            x0 = gridMidX + margin
            x1 = safeRight - margin
        }
        let labelW = max(44, x1 - x0)
        label.preferredMaxLayoutWidth = labelW
        let intrinsicH = label.sizeThatFits(CGSize(width: labelW, height: .greatestFiniteMagnitude)).height
        let maxH = max(0, labelBottom - minLabelY)
        var h = min(intrinsicH, maxH)
        var labelY = labelBottom - h
        if labelY < minLabelY {
            labelY = minLabelY
            h = max(0, labelBottom - labelY)
        }
        label.frame = CGRect(x: x0, y: labelY, width: labelW, height: h)
    }
}

// MARK: - Callout texte + SF Symbol

private final class TutorialCalloutView: UIView {

    enum LayoutKind {
        case labelLeftArrowRight
        case labelAboveArrowDown
    }

    private let label = UILabel()
    private let arrow = UIImageView()
    private let stack = UIStackView()
    private var layoutKind: LayoutKind = .labelAboveArrowDown

    var preferredMaxLayoutWidth: CGFloat = 280 {
        didSet { applyLabelPreferredWidth() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .natural
        label.lineBreakMode = .byWordWrapping

        arrow.contentMode = .scaleAspectFit
        arrow.tintColor = UIColor(white: 0.95, alpha: 1)
        arrow.setContentHuggingPriority(.required, for: .horizontal)
        arrow.setContentHuggingPriority(.required, for: .vertical)

        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func configure(text: String, symbolName: String, layout: LayoutKind, bodyFontSize: CGFloat) {
        layoutKind = layout
        label.text = text
        label.font = TutorialOverlayFont.uiFont(size: bodyFontSize, weight: .medium)
        let cfg = UIImage.SymbolConfiguration(pointSize: layout == .labelLeftArrowRight ? 24 : 22, weight: .semibold)
        arrow.image = UIImage(systemName: symbolName, withConfiguration: cfg)
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        switch layout {
        case .labelLeftArrowRight:
            stack.axis = .horizontal
            stack.alignment = .center
            stack.spacing = 10
            stack.addArrangedSubview(label)
            stack.addArrangedSubview(arrow)
            NSLayoutConstraint.activate([
                arrow.widthAnchor.constraint(equalToConstant: 32),
                arrow.heightAnchor.constraint(equalToConstant: 32),
            ])
            label.textAlignment = .natural
            applyLabelPreferredWidth()
        case .labelAboveArrowDown:
            stack.axis = .vertical
            stack.alignment = .center
            stack.spacing = 8
            stack.addArrangedSubview(label)
            stack.addArrangedSubview(arrow)
            NSLayoutConstraint.activate([
                arrow.widthAnchor.constraint(equalToConstant: 34),
                arrow.heightAnchor.constraint(equalToConstant: 34),
            ])
            label.textAlignment = .center
            applyLabelPreferredWidth()
        }
    }

    private func applyLabelPreferredWidth() {
        switch layoutKind {
        case .labelLeftArrowRight:
            label.preferredMaxLayoutWidth = max(60, preferredMaxLayoutWidth - 52)
        case .labelAboveArrowDown:
            label.preferredMaxLayoutWidth = max(80, preferredMaxLayoutWidth)
        }
    }

    func fittingSize(maxWidth: CGFloat) -> CGSize {
        preferredMaxLayoutWidth = maxWidth
        applyLabelPreferredWidth()
        let lw = label.preferredMaxLayoutWidth
        let lh = label.sizeThatFits(CGSize(width: lw, height: .greatestFiniteMagnitude)).height
        switch layoutKind {
        case .labelLeftArrowRight:
            return CGSize(width: min(maxWidth, lw + 10 + 32), height: max(lh, 32))
        case .labelAboveArrowDown:
            return CGSize(width: min(maxWidth, lw + 4), height: lh + 8 + 34)
        }
    }
}

// MARK: - Encart Brix (page 2)

private final class TutorialBrixInfoView: UIView {

    private let iconBox = UIView()
    private let iconDigit = UILabel()
    private let label = UILabel()
    private let stack = UIStackView()

    init(text: String) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        let hasText = !text.isEmpty
        let iconSide: CGFloat = hasText ? 24 : 36

        iconBox.translatesAutoresizingMaskIntoConstraints = false
        iconBox.backgroundColor = BlomixSkinCatalog.shared.priksUIColor()
        iconBox.layer.cornerRadius = 5
        iconBox.layer.borderWidth = 1
        iconBox.layer.borderColor = UIColor(white: 1, alpha: 0.22).cgColor

        iconDigit.translatesAutoresizingMaskIntoConstraints = false
        iconDigit.text = "5"
        iconDigit.textColor = .white
        iconDigit.font = TutorialOverlayFont.uiFont(size: hasText ? 14 : 18, weight: .semibold)
        iconDigit.textAlignment = .center
        iconBox.addSubview(iconDigit)

        if hasText {
            label.text = text
            label.textColor = .white
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.font = TutorialOverlayFont.uiFont(size: 12, weight: .medium)

            stack.axis = .horizontal
            stack.alignment = .top
            stack.spacing = 10
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(iconBox)
            stack.addArrangedSubview(label)
            addSubview(stack)

            NSLayoutConstraint.activate([
                iconBox.widthAnchor.constraint(equalToConstant: iconSide),
                iconBox.heightAnchor.constraint(equalToConstant: iconSide),
                iconDigit.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
                iconDigit.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
                stack.topAnchor.constraint(equalTo: topAnchor),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        } else {
            // Icône seule, centrée horizontalement
            addSubview(iconBox)
            NSLayoutConstraint.activate([
                iconBox.widthAnchor.constraint(equalToConstant: iconSide),
                iconBox.heightAnchor.constraint(equalToConstant: iconSide),
                iconDigit.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
                iconDigit.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
                iconBox.centerXAnchor.constraint(equalTo: centerXAnchor),
                iconBox.topAnchor.constraint(equalTo: topAnchor),
                iconBox.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func fittingSize(maxWidth: CGFloat) -> CGSize {
        if label.text?.isEmpty != false {
            // Mode icône seule
            return CGSize(width: 36, height: 36)
        }
        let labelWidth = min(210, max(120, maxWidth - 24 - 10))
        label.preferredMaxLayoutWidth = labelWidth
        let labelHeight = label.sizeThatFits(CGSize(width: labelWidth, height: .greatestFiniteMagnitude)).height
        return CGSize(width: 24 + 10 + labelWidth, height: max(24, labelHeight))
    }
}
