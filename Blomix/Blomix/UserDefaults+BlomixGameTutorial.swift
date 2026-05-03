//
//  UserDefaults+BlomixGameTutorial.swift
//  Blomix
//
//  `hasSeenGameTutorial == true` : ne plus afficher le tutoriel au démarrage de partie.
//  `false` (défaut si clé absente) : afficher l’overlay guide au début d’une partie.
//

import Foundation

extension UserDefaults {

    private static let blomixHasSeenGameTutorialKey = "BlomixHasSeenGameTutorial"

    /// `true` si le joueur a choisi de ne plus voir le tutoriel (ou a désactivé l’option dans les règles).
    var hasSeenGameTutorial: Bool {
        get { bool(forKey: Self.blomixHasSeenGameTutorialKey) }
        set { set(newValue, forKey: Self.blomixHasSeenGameTutorialKey) }
    }
}
