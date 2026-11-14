//
//  BlomixVisualStyle.swift
//  Blomix
//
//  Style de rendu Old / New (9.0). Orthogonal au thème chrome (`BlomixAppearance`)
//  et aux skins de couleurs. Défaut = Old.
//
//  Étape 0 : le réglage est persisté. Aucune scène n’écoute la notification.
//  Étape 1 : `GameScene` fige `current` au début de partie (`visualStyleForRun`).
//  New ne change que les Blox couleur de la fabrique principale.
//  Voir docs/PLAN_9.0.md, décisions V3 et V5.
//

import Foundation

// MARK: - Style

enum BlomixVisualStyle: String {
    case old
    case new

    private static let defaultsKey = "BlomixVisualStyle"

    /// Style courant. Défaut `.old` si la clé est absente ou illisible.
    /// Un joueur qui ne touche à rien reste en Old.
    static var current: BlomixVisualStyle {
        get {
            if let raw = UserDefaults.standard.string(forKey: defaultsKey),
               let style = BlomixVisualStyle(rawValue: raw) {
                return style
            }
            return .old
        }
        set {
            let old = current
            guard newValue != old else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: .blomixVisualStyleDidChange, object: newValue)
        }
    }

    static var isNew: Bool { current == .new }
}

// MARK: - Notification

extension Notification.Name {
    /// Postée après un vrai changement de `BlomixVisualStyle.current`.
    /// `object` est le nouveau `BlomixVisualStyle`. Étape 0 : aucun abonné.
    static let blomixVisualStyleDidChange = Notification.Name("blomixVisualStyleDidChange")
}
