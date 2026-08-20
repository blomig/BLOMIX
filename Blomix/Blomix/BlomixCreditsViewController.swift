//
//  BlomixCreditsViewController.swift
//  Blomix
//
//  Écran Crédits en cartes (thème Jour/Nuit, accent skin, blox ambiants).
//  Contenu via BlomixL10n. Un bouton chrome « Laisser un avis » (lien App Store).
//

import UIKit

/// Section de crédits (titre + lignes de corps).
struct BlomixCreditsSection: Sendable {
    let title: String
    let lines: [String]
}

/// Crédits structurés : header BLOMIX + tagline + version, scroll de cartes.
@MainActor
final class BlomixCreditsViewController: UIViewController {

    private let closeButton = BlomixUIButton()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BlomixAppearance.sceneBackground
        addAmbientBlocksBackground(density: .low)
        buildChrome()
        buildContent()
    }

    // MARK: - Layout

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
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
        ])
    }

    private func buildContent() {
        contentStack.addArrangedSubview(makeHeaderBlock())
        contentStack.setCustomSpacing(22, after: contentStack.arrangedSubviews.last!)

        for section in BlomixL10n.creditsSections {
            contentStack.addArrangedSubview(makeSectionCard(section))
        }

        contentStack.setCustomSpacing(22, after: contentStack.arrangedSubviews.last!)
        contentStack.addArrangedSubview(makeReviewBlock())
    }

    // MARK: - Header

    private func makeHeaderBlock() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8

        let title = UILabel()
        title.text = "BLOMIX"
        title.textColor = BlomixAppearance.primaryText
        title.font = BlomixTypography.displayFont(size: 34, weight: .bold)
        title.textAlignment = .center
        title.numberOfLines = 1

        let tagline = UILabel()
        tagline.text = BlomixL10n.creditsTagline
        tagline.textColor = BlomixAppearance.secondaryText
        tagline.font = BlomixTypography.uiFont(size: 15, weight: .regular)
        tagline.textAlignment = .center
        tagline.numberOfLines = 0

        let version = UILabel()
        version.text = Self.appVersionLabelText()
        version.textColor = BlomixAppearance.tertiaryText
        version.font = BlomixTypography.uiFont(size: 13, weight: .regular)
        version.textAlignment = .center
        version.numberOfLines = 1

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(tagline)
        stack.addArrangedSubview(version)
        return stack
    }

    private static func appVersionLabelText() -> String {
        let marketing = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return BlomixL10n.creditsVersionLine(marketing: marketing, build: build)
    }

    // MARK: - Cartes

    private func makeSectionCard(_ section: BlomixCreditsSection) -> UIView {
        let card = UIView()
        card.backgroundColor = BlomixAppearance.panelFill
        card.layer.cornerRadius = 14
        card.layer.borderWidth = BlomixUIDestinationButtonStyle.hairlineBorderWidth
        card.layer.borderColor = BlomixAppearance.chipBorder.cgColor
        card.clipsToBounds = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let titleLabel = UILabel()
        titleLabel.text = section.title
        titleLabel.textColor = Self.sectionTitleAccentColor()
        titleLabel.font = BlomixTypography.uiFont(size: 17, weight: .semibold)
        titleLabel.numberOfLines = 1
        stack.addArrangedSubview(titleLabel)

        for line in section.lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let body = UILabel()
            body.text = line
            body.textColor = BlomixAppearance.primaryText
            body.font = BlomixTypography.uiFont(size: 14, weight: .regular)
            body.numberOfLines = 0
            stack.addArrangedSubview(body)
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])
        return card
    }

    /// Accent skin (orange blox) pour les titres de section.
    private static func sectionTitleAccentColor() -> UIColor {
        BlomixSkinCatalog.shared.bloxUIColor(forNormalizedKey: "orange")
            ?? UIColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 1)
    }

    // MARK: - Avis App Store

    private func makeReviewBlock() -> UIView {
        let wrap = UIView()

        let hint = UILabel()
        hint.text = BlomixL10n.creditsReviewHint
        hint.textColor = BlomixAppearance.tertiaryText
        hint.font = BlomixTypography.uiFont(size: 13, weight: .regular)
        hint.textAlignment = .center
        hint.numberOfLines = 0

        let button = BlomixUIButton()
        button.setTitle(BlomixL10n.creditsReviewButton, for: .normal)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: button)
        BlomixUIDestinationButtonStyle.applyContentInsets(
            UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16),
            to: button
        )
        button.addTarget(self, action: #selector(reviewTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [hint, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
        ])
        return wrap
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func reviewTapped() {
        BlomixReviewPrompt.openWriteReview()
    }
}
