//
//  BlomixRulesGuideViewController.swift
//  Blomix
//
//  Guide règles + Magix (6.4) : cartes chrome, blox ambiants, rejouer le tuto.
//

import UIKit

/// Modal lecture des règles (pas le tuto interactif).
@MainActor
final class BlomixRulesGuideViewController: UIViewController {

    var onReplayTutorial: (() -> Void)?

    private let closeButton = BlomixUIButton()
    private let replayButton = BlomixUIButton()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BlomixAppearance.sceneBackground
        addAmbientBlocksBackground(density: .low)
        buildChrome()
        buildContent()
    }

    private func buildChrome() {
        closeButton.setTitle(BlomixL10n.close, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: closeButton)
        BlomixUIDestinationButtonStyle.applyContentInsets(UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12), to: closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        replayButton.setTitle(BlomixL10n.guideReplayTutorial, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: replayButton)
        BlomixUIDestinationButtonStyle.applyContentInsets(UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16), to: replayButton)
        replayButton.translatesAutoresizingMaskIntoConstraints = false
        replayButton.addTarget(self, action: #selector(replayTapped), for: .touchUpInside)
        view.addSubview(replayButton)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.indicatorStyle = BlomixAppearance.isDark ? .white : .black
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            replayButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            replayButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            replayButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),

            scrollView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: replayButton.topAnchor, constant: -10),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
        ])
    }

    private func buildContent() {
        let title = UILabel()
        title.text = BlomixL10n.guideTitle
        title.textColor = BlomixAppearance.primaryText
        title.font = BlomixTypography.displayFont(size: 28, weight: .bold)
        title.textAlignment = .center
        contentStack.addArrangedSubview(title)
        contentStack.setCustomSpacing(18, after: title)

        for (index, section) in BlomixL10n.guideSections.enumerated() {
            let kind = BlomixGuideIllustrationKind(rawValue: index) ?? .blox
            contentStack.addArrangedSubview(makeSectionCard(section, kind: kind))
        }
    }

    private func makeSectionCard(_ section: BlomixCreditsSection, kind: BlomixGuideIllustrationKind) -> UIView {
        let card = UIView()
        card.backgroundColor = BlomixAppearance.panelFill
        card.layer.cornerRadius = 14
        card.layer.borderWidth = BlomixUIDestinationButtonStyle.hairlineBorderWidth
        card.layer.borderColor = BlomixAppearance.chipBorder.cgColor
        card.clipsToBounds = true

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        let illustration = BlomixGuideIllustrationView(kind: kind)
        illustration.translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 8

        let titleLabel = UILabel()
        titleLabel.text = section.title
        titleLabel.textColor = BlomixSkinCatalog.shared.bloxUIColor(forNormalizedKey: "orange")
            ?? UIColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 1)
        titleLabel.font = BlomixTypography.uiFont(size: 17, weight: .semibold)
        titleLabel.numberOfLines = 1
        textStack.addArrangedSubview(titleLabel)

        if kind == .magix {
            let intro = UILabel()
            intro.text = BlomixL10n.guideMagixIntro
            intro.textColor = BlomixAppearance.secondaryText
            intro.font = BlomixTypography.uiFont(size: 14, weight: .regular)
            intro.numberOfLines = 0
            textStack.addArrangedSubview(intro)

            let kinds = MagixKind.allCases
            for (i, line) in section.lines.enumerated() {
                let magixKind = kinds.indices.contains(i) ? kinds[i] : .chromax
                textStack.addArrangedSubview(makeMagixLineRow(line: line, magixKind: magixKind))
            }
            row.addArrangedSubview(textStack)
            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
                row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
                row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
                row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            ])
            return card
        }

        for line in section.lines {
            let body = UILabel()
            body.text = line
            body.textColor = BlomixAppearance.primaryText
            body.font = BlomixTypography.uiFont(size: 14, weight: .regular)
            body.numberOfLines = 0
            textStack.addArrangedSubview(body)
        }

        row.addArrangedSubview(illustration)
        row.addArrangedSubview(textStack)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),

            illustration.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.32),
            illustration.heightAnchor.constraint(equalTo: illustration.widthAnchor),
        ])
        return card
    }

    /// Une ligne Magix : sprite réel (dégradé + symbole) à gauche du texte.
    private func makeMagixLineRow(line: String, magixKind: MagixKind) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10

        let token = BlomixGuideIllustrationView(kind: .magix, magixKind: magixKind)
        token.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            token.widthAnchor.constraint(equalToConstant: 52),
            token.heightAnchor.constraint(equalToConstant: 52),
        ])

        let body = UILabel()
        body.text = line
        body.textColor = BlomixAppearance.primaryText
        body.font = BlomixTypography.uiFont(size: 14, weight: .regular)
        body.numberOfLines = 0

        row.addArrangedSubview(token)
        row.addArrangedSubview(body)
        return row
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func replayTapped() {
        let replay = onReplayTutorial
        dismiss(animated: true) { replay?() }
    }
}
