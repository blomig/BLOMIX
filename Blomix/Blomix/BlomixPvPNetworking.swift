//
//  BlomixPvPNetworking.swift
//  Blomix
//
//  Multijoueur temps réel (GKMatch) : messages, RNG synchronisé par graine, coordinateur.
//  Le solo n’instancie jamais ce module ; `GameScene` n’active ces chemins que si `pvpCoordinator != nil`.
//

import Foundation
import GameKit
import UIKit

// MARK: - Recherche automatique d'adversaire (arrière-plan)

/// Gère une recherche GKMatchmaker persistante en arrière-plan avec auto-relance et timeout 15 min.
/// Le lobby active/désactive ce singleton ; GameScene reçoit le match via `onMatch`.
@MainActor
final class BlomixPvPAutoSearcher: @unchecked Sendable {
    static let shared = BlomixPvPAutoSearcher()

    private(set) var isSearching = false
    var onMatch: ((GKMatch) -> Void)?

    private var maxDurationTimer: Timer?
    private let maxDuration: TimeInterval = 15 * 60

    private init() {}

    func startSearching() {
        guard !isSearching else { return }
        isSearching = true
        startMaxDurationTimer()
        Task { await launchFindMatch() }
        NotificationCenter.default.post(name: .blomixPvPAutoSearchStateChanged, object: nil)
        print("[PvP AutoSearch] Démarré — disponible pendant 15 min.")
    }

    func stopSearching() {
        guard isSearching else { return }
        isSearching = false
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        GKMatchmaker.shared().cancel()
        NotificationCenter.default.post(name: .blomixPvPAutoSearchStateChanged, object: nil)
        print("[PvP AutoSearch] Arrêté.")
    }

    private func launchFindMatch() async {
        guard isSearching else { return }
        let request = await BlomixEloManager.shared.makePvPMatchRequest()
        guard isSearching else { return }

        GKMatchmaker.shared().cancel()
        GKMatchmaker.shared().findMatch(for: request) { [weak self] match, error in
            let matchBox = match.map { BlomixPvPGKMatchBox(match: $0) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let box = matchBox {
                    self.isSearching = false
                    self.maxDurationTimer?.invalidate()
                    self.maxDurationTimer = nil
                    GKMatchmaker.shared().finishMatchmaking(for: box.match)
                    NotificationCenter.default.post(name: .blomixPvPAutoSearchStateChanged, object: nil)
                    self.onMatch?(box.match)
                    print("[PvP AutoSearch] Match trouvé !")
                } else if self.isSearching {
                    print("[PvP AutoSearch] Timeout/erreur, relance…")
                    await self.launchFindMatch()
                }
            }
        }
    }

    private func startMaxDurationTimer() {
        maxDurationTimer?.invalidate()
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: maxDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isSearching else { return }
                self.stopSearching()
                print("[PvP AutoSearch] 15 min écoulées, arrêt automatique.")
            }
        }
    }
}

// MARK: - Messages filaires (JSON compact)

private enum BlomixPvPMessageKind: String, Codable {
    case helloSeed
    case ackReady
    case attackLine
    case boardFillDepth
    case iLost
    case rematchRequest
}

private struct BlomixPvPWireEnvelope: Codable {
    let k: BlomixPvPMessageKind
    var seed: UInt64?
    var line: [String]?
    var fillDepth: Int?
}

// MARK: - Blocs ↔ fil

extension BlockType {
    fileprivate func blomixPvPWireToken() -> String {
        switch self {
        case .empty: return "e"
        case .color(let n): return "c:\(n)"
        case .priks(let v): return "p:\(v)"
        }
    }

    fileprivate static func fromBlomixPvPWireToken(_ s: String) -> BlockType? {
        if s == "e" { return .empty }
        if s.hasPrefix("c:") {
            let name = String(s.dropFirst(2))
            return name.isEmpty ? nil : .color(name)
        }
        if s.hasPrefix("p:"), let v = Int(s.dropFirst(2)) {
            return .priks(v)
        }
        return nil
    }

    fileprivate static func lineFromWireTokens(_ tokens: [String]) -> [BlockType]? {
        guard tokens.count == 8 else { return nil }
        var out: [BlockType] = []
        for t in tokens {
            guard let b = Self.fromBlomixPvPWireToken(t) else { return nil }
            out.append(b)
        }
        return out
    }
}

// MARK: - RNG déterministe (même loi que le solo : 1/8 Priks à 5 coups, sinon couleur parmi 6)

struct BlomixPvPSeededBlockRNG {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xDEADBEEF_CAFE_BABE : seed
    }

    mutating func nextUInt64() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1
        return state
    }

    mutating func nextUnitDouble() -> Double {
        Double(nextUInt64() % 9_007_199_254_740_992) / 9_007_199_254_740_992
    }

    mutating func nextPlayableBlock() -> BlockType {
        if nextUnitDouble() < (1.0 / 8.0) {
            return .priks(5)
        }
        let palette = ["red", "blue", "green", "yellow", "purple", "orange"]
        let i = Int(nextUInt64() % UInt64(palette.count))
        return .color(palette[i])
    }

    mutating func nextRandomLineRowIndependentCells() -> [BlockType] {
        (0..<8).map { _ in nextPlayableBlock() }
    }

    /// Avance l’état comme après un `nextRandomLineRowIndependentCells()` sans utiliser le résultat (sync avec l’hôte qui a généré la ligne d’attaque).
    mutating func discardNextRandomLineDrawsMatchingOpponentGeneration() {
        _ = nextRandomLineRowIndependentCells()
    }
}

// MARK: - Coordinateur

@MainActor
final class BlomixPvPMatchCoordinator: NSObject {
    private struct QueuedAttackLine {
        let id: Int
        let line: [BlockType]
    }

    private weak var scene: GameScene?
    private let match: GKMatch
    private var rng: BlomixPvPSeededBlockRNG?
    private var didFinishHandshake = false
    /// Rôle déterminé par tri des gamePlayerID. Calculé paresseusement au 1er
    /// callback `.connected` si `match.players` était vide à la construction —
    /// évite le scénario « deux hôtes » qui bloque le handshake.
    private var isHost: Bool = false
    private var isHostResolved = false

    private var incomingAttackLines: [QueuedAttackLine] = []
    private var nextIncomingAttackLineID: Int = 1
    private var lastSentScoreAttackBracket: Int = 0
    private var lastSentBoardFillDepth: Int?

    private var turnTimer: Timer?
    private let turnSeconds: Int = 10
    private var countdownRemaining: Int = 10
    private var handshakeRetryTimer: Timer?
    private var handshakeSeed: UInt64?

    private var didReportLocalLoss = false
    private var localRematchRequested = false
    private var remoteRematchRequested = false
    /// N’envoyer `helloSeed` qu’une fois tous les joueurs connectés (`expectedPlayerCount == 0`), sinon l’adversaire ne reçoit rien et la partie reste bloquée.
    private var didEmitHelloSeed = false

    // MARK: - Watchdogs robustesse

    /// Abandonne si le handshake n'est pas termine apres ce delai.
    private var handshakeWatchdog: Timer?
    private let handshakeWatchdogTimeout: TimeInterval = 30.0
    /// Fenetre de grace avant d'abandonner en cas de micro-deconnexion pendant le handshake.
    private var disconnectionGraceTimer: Timer?
    private let disconnectionGracePeriod: TimeInterval = 8.0

    init(match: GKMatch) {
        self.match = match
        super.init()
        match.delegate = self
        // Tentative de résolution immédiate si les joueurs distants sont déjà présents.
        // Si match.players est encore vide (cas fréquent quand onMatch est appelé tôt),
        // la résolution est différée au 1er callback .connected — voir resolveHostRoleIfNeeded().
        resolveHostRoleIfNeeded()
    }

    /// Calcule et gèle `isHost` dès que `match.players` est peuplé.
    /// Appel idempotent : ne fait rien si déjà résolu ou si players encore vides.
    private func resolveHostRoleIfNeeded() {
        guard !isHostResolved, !match.players.isEmpty else { return }
        let locals = [GKLocalPlayer.local] + match.players
        let sorted = locals.sorted { $0.gamePlayerID < $1.gamePlayerID }
        isHost = sorted.first?.gamePlayerID == GKLocalPlayer.local.gamePlayerID
        isHostResolved = true
        print("[PvP] isHost résolu : \(isHost) (peers : \(match.players.map { $0.gamePlayerID }))")
    }

    func attach(to scene: GameScene) {
        self.scene = scene
        beginHandshakeMonitoringIfNeeded()
        startHandshakeWatchdog()
    }

    private func beginHandshakeMonitoringIfNeeded() {
        resolveHostRoleIfNeeded()
        guard isHost else { return }
        handshakeRetryTimer?.invalidate()
        attemptHostHandshakeSendIfReady()
        guard !didFinishHandshake else { return }
        handshakeRetryTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.attemptHostHandshakeSendIfReady()
            }
        }
        if let handshakeRetryTimer {
            RunLoop.main.add(handshakeRetryTimer, forMode: .common)
        }
    }

    private func stopHandshakeMonitoring() {
        handshakeRetryTimer?.invalidate()
        handshakeRetryTimer = nil
    }

    private func attemptHostHandshakeSendIfReady() {
        resolveHostRoleIfNeeded()
        guard isHost else { return }
        guard scene != nil else { return }
        guard !match.players.isEmpty else { return }
        let seed: UInt64
        if let handshakeSeed {
            seed = handshakeSeed
        } else {
            seed = UInt64.random(in: 1...UInt64.max)
            handshakeSeed = seed
        }
        rng = BlomixPvPSeededBlockRNG(seed: seed)
        if !didEmitHelloSeed {
            didEmitHelloSeed = true
            didFinishHandshake = false
        }
        sendEnvelope(BlomixPvPWireEnvelope(k: .helloSeed, seed: seed, line: nil, fillDepth: nil))
    }

    func stopTurnTimer() {
        turnTimer?.invalidate()
        turnTimer = nil
    }

    func tearDown() {
        stopTurnTimer()
        stopHandshakeMonitoring()
        stopHandshakeWatchdog()
        cancelDisconnectionGrace()
        match.delegate = nil
        match.disconnect()
        rng = nil
        handshakeSeed = nil
        scene = nil
    }

    func nextPlayableBlockForSharedMatch() -> BlockType {
        guard var g = rng else {
            return GameScene.randomNextPlayableBlock()
        }
        let b = g.nextPlayableBlock()
        rng = g
        return b
    }

    func nextRandomBottomLineForSharedMatch() -> [BlockType] {
        guard var g = rng else {
            return (0..<8).map { _ in GameScene.randomNextPlayableBlock() }
        }
        let line = g.nextRandomLineRowIndependentCells()
        rng = g
        return line
    }

    func consumeNextIncomingAttackLineIfAny() -> [BlockType]? {
        guard !incomingAttackLines.isEmpty else { return nil }
        return incomingAttackLines.removeFirst().line
    }

    func peekNextIncomingAttackLinePreview() -> (id: Int, line: [BlockType])? {
        guard let first = incomingAttackLines.first else { return nil }
        return (id: first.id, line: first.line)
    }

    @discardableResult
    func localScoreDidUpdate(_ score: Int) -> Bool {
        guard didFinishHandshake else { return false }
        let bracket = score / 50
        guard bracket > lastSentScoreAttackBracket else { return false }
        lastSentScoreAttackBracket = bracket
        guard var g = rng else { return false }
        let line = g.nextRandomLineRowIndependentCells()
        rng = g
        let tokens = line.map { $0.blomixPvPWireToken() }
        sendEnvelope(BlomixPvPWireEnvelope(k: .attackLine, seed: nil, line: tokens, fillDepth: nil))
        return true
    }

    func localBoardFillDepthDidUpdate(_ fillDepth: Int) {
        guard didFinishHandshake else { return }
        let normalized = max(0, min(8, fillDepth))
        guard lastSentBoardFillDepth != normalized else { return }
        lastSentBoardFillDepth = normalized
        sendEnvelope(BlomixPvPWireEnvelope(k: .boardFillDepth, seed: nil, line: nil, fillDepth: normalized))
    }

    func localPlayerLost() {
        guard didFinishHandshake, !didReportLocalLoss else { return }
        didReportLocalLoss = true
        stopTurnTimer()
        sendEnvelope(BlomixPvPWireEnvelope(k: .iLost, seed: nil, line: nil, fillDepth: nil))
        scene?.blomixPvP_presentLocalDefeat()
    }

    /// Abandon volontaire en cours de partie (sortie via menu).
    /// Informe le pair de la defaite locale sans afficher l'ecran de resultat.
    func forfeitMatch() {
        guard didFinishHandshake, !didReportLocalLoss else { return }
        didReportLocalLoss = true
        stopTurnTimer()
        sendEnvelope(BlomixPvPWireEnvelope(k: .iLost, seed: nil, line: nil, fillDepth: nil))
    }

    /// Indique si la partie PvP est actuellement en cours (handshake termine).
    var isGameActive: Bool { didFinishHandshake }

    func sceneBecameIdleForLocalTurn() {
        guard didFinishHandshake, scene != nil else { return }
        restartTurnTimer()
    }

    /// Match 1v1 actuel : renvoie l’unique adversaire attendu par le mode PvP.
    var primaryRemotePlayer: GKPlayer? {
        match.players.first
    }

    private func restartTurnTimer() {
        turnTimer?.invalidate()
        countdownRemaining = turnSeconds
        scene?.blomixPvP_setTurnCountdown(countdownRemaining)
        turnTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickTurnTimer()
            }
        }
        if let turnTimer {
            RunLoop.main.add(turnTimer, forMode: .common)
        }
    }

    private func tickTurnTimer() {
        guard let scene else {
            stopTurnTimer()
            return
        }
        guard scene.blomixPvP_shouldRunTurnTimer() else { return }
        countdownRemaining -= 1
        if countdownRemaining <= 0 {
            stopTurnTimer()
            scene.blomixPvP_performAutoRandomDrop()
            return
        }
        scene.blomixPvP_setTurnCountdown(countdownRemaining)
    }

    private func sendEnvelope(_ env: BlomixPvPWireEnvelope) {
        guard let data = try? JSONEncoder().encode(env) else { return }
        do {
            try match.sendData(toAllPlayers: data, with: .reliable)
        } catch {
            print("[PvP] send error: \(error)")
        }
    }

    private func handleEnvelope(_ env: BlomixPvPWireEnvelope, remoteSenderGamePlayerID: String) {
        switch env.k {
        case .helloSeed:
            guard !isHost, let seed = env.seed else { return }
            // Si le handshake est déjà terminé (timer de retry de l'hôte encore actif),
            // on renvoie juste ackReady pour arrêter les retries sans réinitialiser le jeu.
            if didFinishHandshake {
                sendEnvelope(BlomixPvPWireEnvelope(k: .ackReady, seed: nil, line: nil, fillDepth: nil))
                return
            }
            rng = BlomixPvPSeededBlockRNG(seed: seed)
            didFinishHandshake = true
            lastSentScoreAttackBracket = 0
            stopHandshakeWatchdog()
            cancelDisconnectionGrace()
            sendEnvelope(BlomixPvPWireEnvelope(k: .ackReady, seed: nil, line: nil, fillDepth: nil))
            scene?.blomixPvP_onHandshakeCompleteRestartBoard()
        case .ackReady:
            guard isHost else { return }
            if !didFinishHandshake {
                didFinishHandshake = true
                stopHandshakeMonitoring()
                stopHandshakeWatchdog()
                cancelDisconnectionGrace()
                scene?.blomixPvP_onHandshakeCompleteRestartBoard()
            }
        case .attackLine:
            guard let tokens = env.line, let line = BlockType.lineFromWireTokens(tokens) else { return }
            incomingAttackLines.append(QueuedAttackLine(id: nextIncomingAttackLineID, line: line))
            nextIncomingAttackLineID += 1
            if var g = rng {
                g.discardNextRandomLineDrawsMatchingOpponentGeneration()
                rng = g
            }
            scene?.blomixPvP_refreshPendingAttackLinePreview()
        case .boardFillDepth:
            scene?.blomixPvP_setRemoteBoardFillDepth(env.fillDepth ?? 0)
        case .iLost:
            guard remoteSenderGamePlayerID != GKLocalPlayer.local.gamePlayerID else { return }
            stopTurnTimer()
            scene?.blomixPvP_presentRemoteVictory()
        case .rematchRequest:
            guard !remoteRematchRequested else { return }
            remoteRematchRequested = true
            scene?.blomixPvP_remotePlayerRequestedRematch()
            evaluateRematchLaunchIfReady()
        }
    }

    // MARK: - Revanche

    func localPlayerRequestedRematch() {
        guard !localRematchRequested else { return }
        localRematchRequested = true
        sendEnvelope(BlomixPvPWireEnvelope(k: .rematchRequest, seed: nil, line: nil, fillDepth: nil))
        evaluateRematchLaunchIfReady()
    }

    private func evaluateRematchLaunchIfReady() {
        guard localRematchRequested, remoteRematchRequested else { return }
        prepareForNextRound()
    }

    private func prepareForNextRound() {
        // Informe GameScene de se preparer avant de relancer le handshake.
        scene?.blomixPvP_startRematch()
        // Remet a zero l'etat du coordinateur.
        didFinishHandshake = false
        didEmitHelloSeed = false
        handshakeSeed = nil
        localRematchRequested = false
        remoteRematchRequested = false
        didReportLocalLoss = false
        incomingAttackLines = []
        nextIncomingAttackLineID = 1
        lastSentScoreAttackBracket = 0
        lastSentBoardFillDepth = nil
        // Relance le handshake (l'hote enverra un nouveau helloSeed).
        beginHandshakeMonitoringIfNeeded()
        startHandshakeWatchdog()
    }

        // MARK: - Helpers watchdog & grace

    private func startHandshakeWatchdog() {
        stopHandshakeWatchdog()
        guard !didFinishHandshake else { return }
        let t = Timer.scheduledTimer(withTimeInterval: handshakeWatchdogTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.didFinishHandshake else { return }
                print("[PvP] Handshake watchdog expire apres \(self.handshakeWatchdogTimeout)s — abandon.")
                self.scene?.blomixPvP_matchFailed(nil)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        handshakeWatchdog = t
    }

    private func stopHandshakeWatchdog() {
        handshakeWatchdog?.invalidate()
        handshakeWatchdog = nil
    }

    private func startDisconnectionGrace() {
        cancelDisconnectionGrace()
        let t = Timer.scheduledTimer(withTimeInterval: disconnectionGracePeriod, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.didFinishHandshake else { return }
                print("[PvP] Grace de deconnexion expiree — session consideree perdue.")
                self.scene?.blomixPvP_peerDisconnected()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        disconnectionGraceTimer = t
    }

    private func cancelDisconnectionGrace() {
        disconnectionGraceTimer?.invalidate()
        disconnectionGraceTimer = nil
    }
}

extension BlomixPvPMatchCoordinator: GKMatchDelegate {
    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        let remoteID = player.gamePlayerID
        Task { @MainActor in
            guard let env = try? JSONDecoder().decode(BlomixPvPWireEnvelope.self, from: data) else { return }
            self.handleEnvelope(env, remoteSenderGamePlayerID: remoteID)
        }
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        // Extraire les String (Sendable) AVANT le Task pour éviter de capturer GKPlayer
        // (non-Sendable) à travers la frontière d'acteur.
        let displayName = player.displayName
        let gamePlayerID = player.gamePlayerID
        Task { @MainActor in
            if state == .disconnected {
                if self.didFinishHandshake {
                    // Partie en cours : signal immediat de deconnexion.
                    self.scene?.blomixPvP_peerDisconnected()
                } else {
                    // Handshake en cours : fenetre de grace pour micro-deconnexion.
                    print("[PvP] Deconnexion pendant handshake — grace de \(self.disconnectionGracePeriod)s.")
                    self.startDisconnectionGrace()
                }
            } else if state == .connected {
                self.cancelDisconnectionGrace()
                self.resolveHostRoleIfNeeded()
                self.beginHandshakeMonitoringIfNeeded()
                // Notifie les couches UI avec les chaînes déjà extraites (Sendable).
                NotificationCenter.default.post(
                    name: .blomixPvPOpponentConnected,
                    object: nil,
                    userInfo: [
                        "displayName": displayName,
                        "gamePlayerID": gamePlayerID
                    ]
                )
            }
        }
    }

    nonisolated func match(_ match: GKMatch, didFailWithError error: Error?) {
        Task { @MainActor in
            self.scene?.blomixPvP_matchFailed(error)
        }
    }
}
