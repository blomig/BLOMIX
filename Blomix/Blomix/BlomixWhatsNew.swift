//
//  BlomixWhatsNew.swift
//  Blomix
//
//  Popup « changements de version » sur l’accueil, après le splash.
//  Ok = cette session seulement ; « Ne plus montrer » = UserDefaults (campagne 6.5).
//

import SpriteKit
import UIKit

@MainActor
enum BlomixWhatsNew {
    /// Identifiant de cette note (pas seulement MARKETING_VERSION : 6.6 sans note ne réaffiche pas).
    static let campaignID = "6.5_slashx_twistx"
    private static let defaultsKey = "blomix_whatsnew_dont_show_\(campaignID)"

    /// Fermeture Ok : ne plus montrer jusqu’au prochain cold start.
    private static var dismissedThisSession = false

    static var shouldPresent: Bool {
        !dismissedThisSession && !UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func markDismissedForSession() {
        dismissedThisSession = true
    }

    static func markDontShowAgain() {
        dismissedThisSession = true
        UserDefaults.standard.set(true, forKey: defaultsKey)
    }

    static func present(in host: UIView) {
        guard shouldPresent else { return }
        host.subviews.compactMap { $0 as? BlomixWhatsNewDialogView }.forEach { $0.removeFromSuperview() }
        let dialog = BlomixWhatsNewDialogView()
        dialog.show(in: host)
    }
}

/// Dialogue changelog 6.5 : voile + panneau Sombre/Clair, pastilles Magix shader.
@MainActor
final class BlomixWhatsNewDialogView: UIView {

    private let dimView = UIView()
    private let panel = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(in host: UIView) {
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

    private func setup() {
        backgroundColor = .clear

        dimView.backgroundColor = BlomixAppearance.isDark
            ? UIColor.black.withAlphaComponent(0.72)
            : UIColor.black.withAlphaComponent(0.45)
        dimView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dimView)

        panel.backgroundColor = BlomixAppearance.panelFill
        panel.layer.cornerRadius = 14
        panel.layer.masksToBounds = true
        panel.layer.borderWidth = 0.75
        panel.layer.borderColor = BlomixAppearance.chipBorder.cgColor
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)

        let title = UILabel()
        title.text = BlomixL10n.whatsNewTitle
        title.textColor = BlomixAppearance.primaryText
        title.font = BlomixTypography.uiFont(size: 18, weight: .semibold)
        title.textAlignment = .center
        title.numberOfLines = 0
        title.translatesAutoresizingMaskIntoConstraints = false

        let twistRow = makeFactRow(text: BlomixL10n.whatsNewTwistx, magix: .twistx)
        let slashRow = makeFactRow(text: BlomixL10n.whatsNewSlashx, magix: .slashx)

        let okButton = makeButton(title: BlomixL10n.ok, isSecondary: false)
        okButton.addTarget(self, action: #selector(okTapped), for: .touchUpInside)
        let hideButton = makeButton(title: BlomixL10n.whatsNewDontShow, isSecondary: true)
        hideButton.addTarget(self, action: #selector(dontShowTapped), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [okButton, hideButton])
        buttons.axis = .vertical
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let facts = UIStackView(arrangedSubviews: [twistRow, slashRow])
        facts.axis = .vertical
        facts.spacing = 14
        facts.translatesAutoresizingMaskIntoConstraints = false

        panel.addSubview(title)
        panel.addSubview(facts)
        panel.addSubview(buttons)

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

            title.topAnchor.constraint(equalTo: panel.topAnchor, constant: 22),
            title.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -20),

            facts.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            facts.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            facts.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),

            buttons.topAnchor.constraint(equalTo: facts.bottomAnchor, constant: 20),
            buttons.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            buttons.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            buttons.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -18),
        ])
    }

    private func makeFactRow(text: String, magix: MagixKind) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = text
        label.textColor = BlomixAppearance.primaryText
        label.font = BlomixTypography.uiFont(size: 14, weight: .regular)
        label.numberOfLines = 0
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let token = MagixWhatsNewTokenView(kind: magix)
        token.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            token.widthAnchor.constraint(equalToConstant: 56),
            token.heightAnchor.constraint(equalToConstant: 56),
        ])

        row.addArrangedSubview(label)
        row.addArrangedSubview(token)
        return row
    }

    private func makeButton(title: String, isSecondary: Bool) -> UIButton {
        let btn = BlomixUIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: btn)
        BlomixUIDestinationButtonStyle.applyContentInsets(
            UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16),
            to: btn
        )
        let font = BlomixTypography.uiFont(size: 16, weight: .semibold)
        btn.setAttributedTitle(NSAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: BlomixAppearance.chipTitle,
        ]), for: .normal)
        if isSecondary { btn.alpha = 0.92 }
        btn.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return btn
    }

    private func dismiss(then: @escaping () -> Void) {
        UIView.animate(withDuration: 0.18, animations: {
            self.alpha = 0
            self.panel.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        }, completion: { _ in
            self.removeFromSuperview()
            then()
        })
    }

    @objc private func okTapped() {
        dismiss { BlomixWhatsNew.markDismissedForSession() }
    }

    @objc private func dontShowTapped() {
        dismiss { BlomixWhatsNew.markDontShowAgain() }
    }
}

/// Pastille Magix (shader + glyphe), même pipeline que le Guide.
@MainActor
private final class MagixWhatsNewTokenView: UIView {
    private let skView = SKView()

    init(kind: MagixKind) {
        super.init(frame: .zero)
        clipsToBounds = true
        layer.cornerRadius = 10
        backgroundColor = BlomixAppearance.emptyCell
        skView.allowsTransparency = false
        skView.backgroundColor = BlomixAppearance.emptyCell
        skView.isAsynchronous = true
        skView.ignoresSiblingOrder = true
        skView.preferredFramesPerSecond = 30
        skView.isUserInteractionEnabled = false
        skView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(skView)
        NSLayoutConstraint.activate([
            skView.topAnchor.constraint(equalTo: topAnchor),
            skView.bottomAnchor.constraint(equalTo: bottomAnchor),
            skView.leadingAnchor.constraint(equalTo: leadingAnchor),
            skView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        let scene = MagixWhatsNewPreviewScene(kind: kind)
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }
}

@MainActor
private final class MagixWhatsNewPreviewScene: SKScene {
    private let magixKind: MagixKind
    private var sprite: SKSpriteNode?

    init(kind: MagixKind) {
        self.magixKind = kind
        super.init(size: CGSize(width: 56, height: 56))
        backgroundColor = SKColor(cgColor: BlomixAppearance.emptyCell.cgColor)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:)") }

    override func didMove(to view: SKView) {
        installSprite()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        installSprite()
    }

    private func installSprite() {
        let available = min(size.width, size.height)
        guard available >= 24 else { return }
        sprite?.removeFromParent()
        let side = min(available * 0.72, 44)
        let node = GameScene.makeGuideMagixPreviewSprite(
            size: CGSize(width: side, height: side),
            kind: magixKind
        )
        node.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(node)
        sprite = node
    }
}
