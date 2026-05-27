//
//  UserDefaults+BlomixGameTutorial.swift
//  Blomix
//
//  `hasSeenGameTutorial == true` : ne plus afficher le tutoriel au démarrage de partie.
//  `false` (défaut si clé absente) : afficher l'overlay guide au début d'une partie.
//

import Foundation

extension UserDefaults {

    private static let blomixHasSeenGameTutorialKey = "BlomixHasSeenGameTutorial"

    /// `true` si le joueur a choisi de ne plus voir le tutoriel statique (maintenu pour compatibilité).
    var hasSeenGameTutorial: Bool {
        get { bool(forKey: Self.blomixHasSeenGameTutorialKey) }
        set { set(newValue, forKey: Self.blomixHasSeenGameTutorialKey) }
    }

    private static let blomixHasSeenInteractiveTutorialKey = "BlomixHasSeenInteractiveTutorial_v1"

    /// `true` après que le joueur a terminé ou passé le tutoriel interactif intégré au gameplay.
    /// `false` (défaut) → le premier lancement de partie démarrera le tutoriel interactif.
    var hasSeenInteractiveTutorial: Bool {
        get { bool(forKey: Self.blomixHasSeenInteractiveTutorialKey) }
        set { set(newValue, forKey: Self.blomixHasSeenInteractiveTutorialKey) }
    }
}
