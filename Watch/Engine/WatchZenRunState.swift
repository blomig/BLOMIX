//
//  WatchZenRunState.swift
//  Snapshot Codable — sans visée bombe (hors JSON).
//

import Foundation

struct WatchZenRunState: Codable, Equatable {
    var version: Int
    var grid: [[WatchBlockType]]
    var p0: WatchBlockType
    var p1: WatchBlockType
    var p2: WatchBlockType
    var moveCount: Int
    var nextBottomLine: [WatchBlockType]
    var bombCount: Int
    var isBombMode: Bool
    var score: Int
    var chainSeriesLevel: Int
    var chainClearWaveCount: Int
    var savedAt: Date

    static func newGame(now: Date = Date()) -> WatchZenRunState {
        WatchZenRunState(
            version: 1,
            grid: WatchZenRules.emptyGrid(),
            p0: WatchZenRules.randomPlayableBlock(),
            p1: WatchZenRules.randomPlayableBlock(),
            p2: WatchZenRules.randomPlayableBlock(),
            moveCount: 0,
            nextBottomLine: WatchZenRules.randomBottomLineRow(),
            bombCount: WatchZenRules.zenBombStock,
            isBombMode: false,
            score: 0,
            chainSeriesLevel: 0,
            chainClearWaveCount: 0,
            savedAt: now
        )
    }
}

struct WatchLiveCell: Identifiable, Equatable {
    let id: UUID
    var row: Int
    var col: Int
    var block: WatchBlockType
}
