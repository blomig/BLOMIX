//
//  BLOMIXWatchApp.swift
//  BLOMIX Watch — cible dédiée, zéro import du jeu iPhone.
//

import SwiftUI

@main
struct BLOMIXWatchApp: App {
    init() {
        WatchZenScoreBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
        }
    }
}
