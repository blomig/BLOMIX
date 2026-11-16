//
//  BlomixVisualStyle.swift
//  Blomix
//
//  Style de rendu Classique / Encre (9.0). Orthogonal au thème chrome (`BlomixAppearance`)
//  et aux skins de couleurs. Défaut = Classique (`.old`).
//
//  `.new` est la piste Encre (Lomig, 15/11/2026) : elle remplace la gelée comme mode New.
//  Pas de troisième cas. E0 ne change que le libellé. Le rendu de `.new` reste la gelée
//  jusqu’aux étapes E1+ de docs/DA_ENCRE_WASHI.md.
//  `GameScene` fige `current` au début de partie (`visualStyleForRun`).
//  Voir docs/PLAN_9.0.md, décisions V3, V5 et E0.
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
            let changed = newValue != old
            if changed {
                UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            }
            // Encre ne se joue qu’en clair. Le sombre enregistré à côté est effacé.
            if newValue == .new, BlomixAppearance.mode != .light {
                BlomixAppearance.mode = .light
            }
            if changed {
                NotificationCenter.default.post(name: .blomixVisualStyleDidChange, object: newValue)
            }
        }
    }

    static var isNew: Bool { current == .new }

    /// Partie Encre en cours. Le chrome reste clair jusqu’au retour accueil,
    /// même si le joueur a déjà choisi Sombre pour la partie suivante.
    nonisolated(unsafe) static var activeRunIsInk = false
}

/// Les trois apparences proposées au joueur. Pas un troisième style de rendu :
/// Sombre et Clair sont le Classique, Encre est le Classique clair + le style `.new`.
enum BlomixLook {
    case classicDark
    case classicLight
    case ink

    /// Préférence enregistrée. Une partie Encre en cours ne change pas ce choix.
    static var current: BlomixLook {
        if BlomixVisualStyle.isNew { return .ink }
        return BlomixAppearance.mode == .dark ? .classicDark : .classicLight
    }

    /// Un ancien « Encre + Sombre » devient l’Encre clair.
    static func reconcile() {
        guard BlomixVisualStyle.isNew, BlomixAppearance.mode != .light else { return }
        BlomixAppearance.mode = .light
    }

    static func apply(_ look: BlomixLook) {
        switch look {
        case .classicDark:
            // Classique d’abord, pour ne pas peindre l’Encre avec le papier sombre.
            BlomixVisualStyle.current = .old
            BlomixAppearance.mode = .dark
        case .classicLight:
            BlomixVisualStyle.current = .old
            BlomixAppearance.mode = .light
        case .ink:
            BlomixAppearance.mode = .light
            BlomixVisualStyle.current = .new
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    /// Postée après un vrai changement de `BlomixVisualStyle.current`.
    /// `object` est le nouveau `BlomixVisualStyle`. Étape 0 : aucun abonné.
    static let blomixVisualStyleDidChange = Notification.Name("blomixVisualStyleDidChange")
}
