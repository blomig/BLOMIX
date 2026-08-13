//
//  BlomixPvPNetworking.swift
//  Blomix
//
//  Multijoueur temps réel (GKMatch) : messages, RNG synchronisé par graine, coordinateur.
//  Robustesse v2 : protocolVersion, file d'envoi + ack, heartbeat, grace déco mid-game,
//  ack iLost, attackId, pas de RNG local de secours.
//  Le solo n’instancie jamais ce module ; `GameScene` n’active ces chemins que si `pvpCoordinator != nil`.
//

import Foundation
import GameKit
import UIKit

// MARK: - Logs structurés

enum BlomixPvPLog {
    static func event(_ name: String, _ fields: [String: String] = [:]) {
        let extras = fields.isEmpty
            ? ""
            : " " + fields.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        print("[PvP] \(name)\(extras)")
    }
}

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
    private var findMatchRetryAttempt = 0

    private init() {}

    func startSearching() {
        guard !isSearching else { return }
        isSearching = true
        findMatchRetryAttempt = 0
        startMaxDurationTimer()
        Task { await launchFindMatch() }
        BlomixPvPLog.event("autosearch_start")
    }

    func stopSearching() {
        guard isSearching else { return }
        isSearching = false
        findMatchRetryAttempt = 0
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        GKMatchmaker.shared().cancel()
        BlomixPvPLog.event("autosearch_stop")
    }

    private func launchFindMatch() async {
        guard isSearching else { return }
        if findMatchRetryAttempt > 0 {
            let delay = min(pow(2.0, Double(findMatchRetryAttempt - 1)) * 2.0, 16.0)
            BlomixPvPLog.event("autosearch_retry", ["attempt": "\(findMatchRetryAttempt + 1)", "delay_s": "\(Int(delay))"])
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard isSearching else { return }
        }
        findMatchRetryAttempt += 1

        let request = await BlomixEloManager.shared.makePvPMatchRequest()
        guard isSearching else { return }

        GKMatchmaker.shared().cancel()
        do {
            let match = try await GKMatchmaker.shared().findMatch(for: request)
            guard isSearching else { return }
            isSearching = false
            findMatchRetryAttempt = 0
            maxDurationTimer?.invalidate()
            maxDurationTimer = nil
            GKMatchmaker.shared().finishMatchmaking(for: match)
            onMatch?(match)
            BlomixPvPLog.event("autosearch_match_found")
        } catch {
            guard isSearching else { return }
            BlomixPvPLog.event("autosearch_find_failed", [
                "error": error.localizedDescription
            ])
            await launchFindMatch()
        }
    }

    private func startMaxDurationTimer() {
        maxDurationTimer?.invalidate()
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: maxDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isSearching else { return }
                self.stopSearching()
                BlomixPvPLog.event("autosearch_timeout_15m")
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
    case ackVictory
    case rematchRequest
    case rematchCancel
    case ackMsg
    case keepAlive
    /// Snapshot H2H léger (2 ints) — merge max au contact ; clients anciens ignorent (decode fail soft).
    case h2hSnapshot
}

private struct BlomixPvPWireEnvelope: Codable {
    let k: BlomixPvPMessageKind
    var seed: UInt64? = nil
    var line: [String]? = nil
    var fillDepth: Int? = nil
    var score: Int? = nil
    /// Version de protocole applicatif (helloSeed).
    var protocolVersion: Int? = nil
    /// Build marketing app (helloSeed) — info diagnostic.
    var appBuild: Int? = nil
    /// Identifiant monoto d'envoi pour ack applicatif.
    var msgId: Int? = nil
    /// Id monoto d'attaque (anti-doublon côté récepteur).
    var attackId: Int? = nil
    /// Ack d'un msgId critique.
    var ackMsgId: Int? = nil
    /// H2H : mes victoires vs adversaire (POV émetteur).
    var h2hMyWins: Int? = nil
    /// H2H : victoires de l’adversaire (POV émetteur).
    var h2hTheirWins: Int? = nil
}

// MARK: - Blocs ↔ fil

extension BlockType {
    fileprivate func blomixPvPWireToken() -> String {
        switch self {
        case .empty:         return "e"
        case .color(let n):  return "c:\(n)"
        case .priks(let v):  return "p:\(v)"
        case .magix:         return "e"   // Magix n'existe pas en PvP — traité comme vide sur le fil
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

    /// Version de protocole filaire. Incrémenter à chaque breaking change.
    static let protocolVersion: Int = 1

    private struct QueuedAttackLine {
        let id: Int
        let line: [BlockType]
    }

    private struct PendingCriticalSend {
        var envelope: BlomixPvPWireEnvelope
        var attempts: Int
        let maxAttempts: Int
        var lastSentAt: Date
    }

    private weak var scene: GameScene?
    /// Canal online (GameKit) — mutuellement exclusif avec `localSession`.
    private var match: GKMatch?
    /// Canal local Multipeer — mutuellement exclusif avec `match`.
    private var localSession: BlomixPvPLocalSession?
    /// Identité distante (Elo / nom) — GC players online, ou handshake Multipeer en local.
    private(set) var remotePeerIdentity: BlomixPvPLocalPeerIdentity?
    private var rng: BlomixPvPSeededBlockRNG?
    private var didFinishHandshake = false
    /// Rôle déterminé par tri des gamePlayerID. Calculé paresseusement au 1er
    /// callback `.connected` si `match.players` était vide à la construction —
    /// évite le scénario « deux hôtes » qui bloque le handshake.
    private var isHost: Bool = false
    private var isHostResolved = false
    /// `true` si le match utilise Multipeer (Local) plutôt que GameKit.
    var isLocalMatch: Bool { localSession != nil }

    /// Même instance `GKMatch` déjà attachée (poll roster / `didChange` rejouent `beginPvP`).
    func isBoundTo(gkMatch other: GKMatch) -> Bool {
        match === other
    }

    private var incomingAttackLines: [QueuedAttackLine] = []
    private var nextIncomingAttackLineID: Int = 1
    /// Dernier attackId reçu (anti-doublon).
    private var lastReceivedAttackId: Int = 0
    /// Prochain attackId sortant.
    private var nextOutboundAttackId: Int = 1
    private var lastSentScoreAttackBracket: Int = 0
    private var lastSentBoardFillDepth: Int?
    private var lastSentScore: Int?

    private var turnTimer: Timer?
    private let turnSeconds: Int = 10
    private var countdownRemaining: Int = 10
    private var handshakeRetryTimer: Timer?
    private var handshakeSeed: UInt64?

    private var didReportLocalLoss = false
    private var didReceiveRemoteLoss = false
    private var awaitingVictoryAck = false
    private var localRematchRequested = false
    private var remoteRematchRequested = false
    private var rematchRetryTimer: Timer?
    private var isPreparingNextRound = false
    /// N’envoyer `helloSeed` qu’une fois tous les joueurs connectés (`expectedPlayerCount == 0`), sinon l’adversaire ne reçoit rien et la partie reste bloquée.
    private var didEmitHelloSeed = false

    // MARK: - Watchdogs / grace / heartbeat / send queue

    private var handshakeWatchdog: Timer?
    private let handshakeWatchdogTimeout: TimeInterval = 60.0
    private var disconnectionGraceTimer: Timer?
    /// Grace handshake (micro-coupure avant partie).
    private let handshakeDisconnectionGracePeriod: TimeInterval = 15.0
    /// Grace mid-game (cellulaire instable).
    private let inMatchDisconnectionGracePeriod: TimeInterval = 4.0
    /// Grace mid-game locale (Multipeer BT plus chahuté) — laisse le temps à rebuild+re-invite.
    private let localInMatchDisconnectionGracePeriod: TimeInterval = 45.0
    private var isInDisconnectionGrace = false

    private var heartbeatTimer: Timer?
    private let heartbeatInterval: TimeInterval = 2.5
    /// Silence peer online (cellulaire).
    private let peerSilenceTimeout: TimeInterval = 10.0
    /// Silence peer local : Multipeer peut rater des keepAlive ; le jeu est tour par tour.
    /// Plus court que la grace : on détecte un zombie et on force un reset transport.
    private let localPeerSilenceTimeout: TimeInterval = 12.0
    private var lastPeerAliveAt: Date?
    /// Throttle des force-reset local (évite rebuild en rafale).
    private var lastLocalForceResetAt: Date?

    private var nextMsgId: Int = 1
    private var pendingCriticalSends: [Int: PendingCriticalSend] = [:]
    private var criticalRetryTimer: Timer?
    private let criticalRetryInterval: TimeInterval = 1.5

    private static var localAppBuild: Int {
        let raw = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return Int(raw ?? "") ?? 0
    }

    init(match: GKMatch) {
        self.match = match
        self.localSession = nil
        super.init()
        match.delegate = self
        resolveHostRoleIfNeeded()
    }

    /// Match local Multipeer (identité déjà échangée dans la session).
    init(localSession: BlomixPvPLocalSession) {
        self.match = nil
        self.localSession = localSession
        self.remotePeerIdentity = localSession.remoteIdentity
        super.init()
        localSession.onData = { [weak self] data in
            Task { @MainActor in
                self?.handleLocalGameData(data)
            }
        }
        localSession.onDisconnected = { [weak self] in
            Task { @MainActor in
                self?.handleLocalDisconnect()
            }
        }
        localSession.onTransportRestored = { [weak self] in
            Task { @MainActor in
                self?.handleLocalTransportRestored()
            }
        }
        resolveHostRoleIfNeeded()
    }

    /// Calcule et gèle `isHost` dès que les IDs distants sont connus.
    private func resolveHostRoleIfNeeded() {
        guard !isHostResolved else { return }
        let remoteID: String?
        let localID: String
        if let match {
            guard !match.players.isEmpty else { return }
            remoteID = match.players.first?.gamePlayerID
            localID = GKLocalPlayer.local.gamePlayerID
        } else if let remote = remotePeerIdentity?.gamePlayerID, !remote.isEmpty {
            remoteID = remote
            // Local : utiliser l’ID du snapshot Multipeer (cache GC), pas seulement GK live
            // (hors ligne le gamePlayerID live peut être vide / différent).
            localID = localSession?.localPeerIdentity.gamePlayerID ?? GKLocalPlayer.local.gamePlayerID
        } else {
            return
        }
        guard let remoteID, !localID.isEmpty else { return }
        // Host = plus petit gamePlayerID (déterministe, même règle online / local).
        isHost = localID < remoteID
        isHostResolved = true
        BlomixPvPLog.event("host_resolved", [
            "isHost": "\(isHost)",
            "local": String(localID.prefix(12)),
            "remote": String(remoteID.prefix(12)),
            "channel": match != nil ? "gk" : "local"
        ])
    }

    func attach(to scene: GameScene) {
        self.scene = scene
        beginHandshakeMonitoringIfNeeded()
        startHandshakeWatchdog()
        startCriticalRetryTimer()
        // Filet : roster parfois vide juste après findMatch même si expectedPlayerCount == 0
        // (pas de nouveau .connected). On re-tente host resolve + helloSeed pendant ~12 s.
        // En local l’identité est déjà là → bootstrap court suffit.
        startRosterBootstrapPoll()
        if isLocalMatch {
            // Pousse immédiatement le helloSeed côté hôte + relance keepAlive pré-handshake.
            beginHandshakeMonitoringIfNeeded()
            // Relancer l’envoi d’identité n’est plus possible ici ; on force des helloSeed fréquents.
            // Le guest doit recevoir le seed avant le watchdog.
        }
    }

    private func handleLocalGameData(_ data: Data) {
        guard let env = try? JSONDecoder().decode(BlomixPvPWireEnvelope.self, from: data) else {
            BlomixPvPLog.event("local_decode_fail")
            return
        }
        let remoteID = remotePeerIdentity?.gamePlayerID ?? "local-peer"
        handleEnvelope(env, remoteSenderGamePlayerID: remoteID)
    }

    private func handleLocalDisconnect() {
        BlomixPvPLog.event("local_disconnect_mid_match", [
            "handshake": "\(didFinishHandshake)"
        ])
        // La session locale a déjà tenté rebuild+invite pendant le debounce.
        // On affiche « Reconnexion… » et on laisse encore une grace longue.
        if didFinishHandshake {
            beginInMatchDisconnectionGrace(reason: "local_disconnect")
            // Double filet : relancer explicitement la reconnexion active.
            localSession?.attemptMidGameReconnect()
        } else {
            // Pendant « P vs P / préparation » : grace au lieu d’échec immédiat.
            startDisconnectionGrace(
                period: localInMatchDisconnectionGracePeriod,
                reason: "local_disconnect_handshake"
            )
            localSession?.attemptMidGameReconnect()
        }
    }

    /// Multipeer de nouveau connecté mid-match — annuler grace et reprendre le heartbeat.
    private func handleLocalTransportRestored() {
        BlomixPvPLog.event("local_transport_restored", [
            "wasInGrace": "\(isInDisconnectionGrace)"
        ])
        lastPeerAliveAt = Date()
        cancelDisconnectionGrace()
        // Prouve immédiatement la vivacité aux deux côtés (et annule silence distant).
        if didFinishHandshake {
            sendEnvelopeRaw(BlomixPvPWireEnvelope(k: .keepAlive, seed: nil, line: nil, fillDepth: nil))
            // Rejouer les messages critiques non ackés (attaques / iLost / rematch).
            for id in pendingCriticalSends.keys {
                flushCriticalSend(id: id)
            }
        }
    }

    private var rosterBootstrapTimer: Timer?
    private var rosterBootstrapTicks = 0

    private func startRosterBootstrapPoll() {
        rosterBootstrapTimer?.invalidate()
        rosterBootstrapTicks = 0
        let t = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rosterBootstrapTicks += 1
                self.resolveHostRoleIfNeeded()
                self.beginHandshakeMonitoringIfNeeded()
                if self.didFinishHandshake || self.rosterBootstrapTicks >= 30 {
                    self.rosterBootstrapTimer?.invalidate()
                    self.rosterBootstrapTimer = nil
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        rosterBootstrapTimer = t
    }

    private func stopRosterBootstrapPoll() {
        rosterBootstrapTimer?.invalidate()
        rosterBootstrapTimer = nil
    }

    private func beginHandshakeMonitoringIfNeeded() {
        resolveHostRoleIfNeeded()
        // Tant que le rôle n'est pas résolu (roster vide), on ne peut pas décider host/guest.
        guard isHostResolved else { return }
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
        if let match {
            guard match.expectedPlayerCount == 0 else { return }
            guard !match.players.isEmpty else { return }
        } else {
            // Local : pair + identité déjà établis.
            guard localSession?.isConnected == true, remotePeerIdentity != nil else { return }
        }
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
            BlomixPvPLog.event("hello_seed_emit", [
                "seed": "\(seed)",
                "proto": "\(Self.protocolVersion)",
                "build": "\(Self.localAppBuild)",
                "channel": match != nil ? "gk" : "local"
            ])
        }
        var env = BlomixPvPWireEnvelope(k: .helloSeed, seed: seed, line: nil, fillDepth: nil)
        env.protocolVersion = Self.protocolVersion
        env.appBuild = Self.localAppBuild
        // helloSeed : envoi direct + retries timer hôte (pas la file critique générique,
        // pour ne pas empiler des msgId différents pour le même seed).
        sendEnvelopeRaw(env)
    }

    func stopTurnTimer() {
        turnTimer?.invalidate()
        turnTimer = nil
    }

    func tearDown() {
        stopTurnTimer()
        stopHandshakeMonitoring()
        stopHandshakeWatchdog()
        stopRosterBootstrapPoll()
        cancelDisconnectionGrace()
        stopRematchRetryTimer()
        stopHeartbeat()
        stopCriticalRetryTimer()
        pendingCriticalSends.removeAll()
        resetRematchFlags()
        if let match {
            match.delegate = nil
            match.disconnect()
        }
        localSession?.onData = nil
        localSession?.onDisconnected = nil
        localSession?.onTransportRestored = nil
        localSession?.tearDown()
        localSession = nil
        match = nil
        remotePeerIdentity = nil
        rng = nil
        handshakeSeed = nil
        scene = nil
        BlomixPvPLog.event("coordinator_teardown")
    }

    /// `nil` si le RNG partagé n'est pas prêt — **jamais** de fallback local (anti-désync).
    func nextPlayableBlockForSharedMatch() -> BlockType? {
        guard var g = rng else {
            BlomixPvPLog.event("rng_unavailable", ["op": "nextBlock"])
            return nil
        }
        let b = g.nextPlayableBlock()
        rng = g
        return b
    }

    /// `nil` si le RNG partagé n'est pas prêt — **jamais** de fallback local.
    func nextRandomBottomLineForSharedMatch() -> [BlockType]? {
        guard var g = rng else {
            BlomixPvPLog.event("rng_unavailable", ["op": "nextLine"])
            return nil
        }
        let line = g.nextRandomLineRowIndependentCells()
        rng = g
        return line
    }

    var hasSharedRNG: Bool { rng != nil }

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
        let attackId = nextOutboundAttackId
        nextOutboundAttackId += 1
        var env = BlomixPvPWireEnvelope(k: .attackLine, seed: nil, line: tokens, fillDepth: nil)
        env.attackId = attackId
        enqueueCritical(env, maxAttempts: 12)
        BlomixPvPLog.event("attack_sent", ["attackId": "\(attackId)", "bracket": "\(bracket)"])
        return true
    }

    func localBoardFillDepthDidUpdate(_ fillDepth: Int, score: Int) {
        guard didFinishHandshake else { return }
        let normalized = max(0, min(8, fillDepth))
        guard lastSentBoardFillDepth != normalized || lastSentScore != score else { return }
        lastSentBoardFillDepth = normalized
        lastSentScore = score
        // Best-effort (non critique) — le HUD distant peut rater une frame.
        sendEnvelopeRaw(BlomixPvPWireEnvelope(k: .boardFillDepth, seed: nil, line: nil, fillDepth: normalized, score: score))
    }

    func localPlayerLost() {
        guard didFinishHandshake, !didReportLocalLoss else { return }
        didReportLocalLoss = true
        awaitingVictoryAck = true
        stopTurnTimer()
        stopHeartbeat()
        enqueueCritical(BlomixPvPWireEnvelope(k: .iLost, seed: nil, line: nil, fillDepth: nil), maxAttempts: 20)
        BlomixPvPLog.event("local_lost_sent")
        scene?.blomixPvP_presentLocalDefeat()
    }

    /// Abandon volontaire en cours de partie (sortie via menu).
    func forfeitMatch() {
        guard didFinishHandshake, !didReportLocalLoss else { return }
        didReportLocalLoss = true
        awaitingVictoryAck = true
        stopTurnTimer()
        stopHeartbeat()
        enqueueCritical(BlomixPvPWireEnvelope(k: .iLost, seed: nil, line: nil, fillDepth: nil), maxAttempts: 20)
        BlomixPvPLog.event("forfeit_sent")
    }

    var isGameActive: Bool { didFinishHandshake }

    func sceneBecameIdleForLocalTurn() {
        guard didFinishHandshake, scene != nil else { return }
        restartTurnTimer()
    }

    var primaryRemotePlayer: GKPlayer? {
        match?.players.first
    }

    /// Profil Elo distant pour finalisation (online : via GC ; local : snapshot handshake).
    var remoteEloProfileForFinalize: BlomixEloProfile? {
        if let id = remotePeerIdentity {
            return BlomixEloProfile(rating: id.eloRating, completedMatchCount: id.completedMatchCount)
        }
        return nil
    }

    var remoteDisplayNameResolved: String {
        if let n = remotePeerIdentity?.displayName, !n.isEmpty { return n }
        if let n = match?.players.first?.displayName, !n.isEmpty { return n }
        return BlomixL10n.pvpUnknownOpponent
    }

    /// gamePlayerID distant (GK ou Multipeer) — pour H2H / logs. Vide si inconnu.
    var remoteGamePlayerIDResolved: String {
        if let id = match?.players.first?.gamePlayerID, !id.isEmpty { return id }
        if let id = remotePeerIdentity?.gamePlayerID, !id.isEmpty { return id }
        return ""
    }

    /// Canal pour stats H2H.
    var h2hChannelLabel: String { isLocalMatch ? "local" : "online" }

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
        // Pendant grace déco, on ne force pas d'auto-drop.
        guard !isInDisconnectionGrace else { return }
        guard scene.blomixPvP_shouldRunTurnTimer() else { return }
        countdownRemaining -= 1
        if countdownRemaining <= 0 {
            stopTurnTimer()
            scene.blomixPvP_performAutoRandomDrop()
            return
        }
        scene.blomixPvP_setTurnCountdown(countdownRemaining)
    }

    // MARK: - Envoi / file critique

    private func sendEnvelopeRaw(_ env: BlomixPvPWireEnvelope) {
        guard let data = try? JSONEncoder().encode(env) else { return }
        if let match {
            do {
                try match.sendData(toAllPlayers: data, with: .reliable)
            } catch {
                BlomixPvPLog.event("send_error", [
                    "kind": env.k.rawValue,
                    "error": error.localizedDescription
                ])
            }
        } else if let localSession {
            localSession.sendGameData(data)
        }
    }

    private func enqueueCritical(_ env: BlomixPvPWireEnvelope, maxAttempts: Int = 10) {
        var e = env
        let id = nextMsgId
        nextMsgId += 1
        e.msgId = id
        pendingCriticalSends[id] = PendingCriticalSend(
            envelope: e,
            attempts: 0,
            maxAttempts: maxAttempts,
            lastSentAt: .distantPast
        )
        flushCriticalSend(id: id)
    }

    private func flushCriticalSend(id: Int) {
        guard var pending = pendingCriticalSends[id] else { return }
        pending.attempts += 1
        pending.lastSentAt = Date()
        pendingCriticalSends[id] = pending
        sendEnvelopeRaw(pending.envelope)
        if pending.attempts >= pending.maxAttempts {
            BlomixPvPLog.event("critical_send_exhausted", [
                "kind": pending.envelope.k.rawValue,
                "msgId": "\(id)"
            ])
            pendingCriticalSends.removeValue(forKey: id)
        }
    }

    private func startCriticalRetryTimer() {
        stopCriticalRetryTimer()
        let t = Timer.scheduledTimer(withTimeInterval: criticalRetryInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.retryPendingCriticalSends() }
        }
        RunLoop.main.add(t, forMode: .common)
        criticalRetryTimer = t
    }

    private func stopCriticalRetryTimer() {
        criticalRetryTimer?.invalidate()
        criticalRetryTimer = nil
    }

    private func retryPendingCriticalSends() {
        let now = Date()
        for (id, pending) in pendingCriticalSends {
            if now.timeIntervalSince(pending.lastSentAt) >= criticalRetryInterval {
                flushCriticalSend(id: id)
            }
        }
    }

    private func acknowledgeMsgId(_ ackId: Int) {
        if pendingCriticalSends.removeValue(forKey: ackId) != nil {
            BlomixPvPLog.event("critical_acked", ["msgId": "\(ackId)"])
        }
    }

    private func sendAck(forMsgId msgId: Int?) {
        guard let msgId else { return }
        var env = BlomixPvPWireEnvelope(k: .ackMsg, seed: nil, line: nil, fillDepth: nil)
        env.ackMsgId = msgId
        sendEnvelopeRaw(env)
    }

    // MARK: - Réception

    private func handleEnvelope(_ env: BlomixPvPWireEnvelope, remoteSenderGamePlayerID: String) {
        lastPeerAliveAt = Date()
        // Pair de nouveau audible → fin de grace déco (surtout utile en Multipeer local).
        if isInDisconnectionGrace {
            cancelDisconnectionGrace()
            BlomixPvPLog.event("disconnect_grace_cancel_peer_alive", ["kind": env.k.rawValue])
        }

        switch env.k {
        case .helloSeed:
            guard !isHost, let seed = env.seed else { return }
            if let remoteProto = env.protocolVersion, remoteProto != Self.protocolVersion {
                BlomixPvPLog.event("protocol_mismatch", [
                    "remote": "\(remoteProto)",
                    "local": "\(Self.protocolVersion)"
                ])
                scene?.blomixPvP_matchFailed(
                    nil,
                    userMessage: BlomixL10n.pvpProtocolMismatchMessage
                )
                return
            }
            // Compat soft : ancien client sans protocolVersion → on accepte (build transition).
            if didFinishHandshake {
                sendEnvelopeRaw(BlomixPvPWireEnvelope(k: .ackReady, seed: nil, line: nil, fillDepth: nil))
                sendAck(forMsgId: env.msgId)
                return
            }
            rng = BlomixPvPSeededBlockRNG(seed: seed)
            markHandshakeComplete(isHostSide: false)
            sendEnvelopeRaw(BlomixPvPWireEnvelope(k: .ackReady, seed: nil, line: nil, fillDepth: nil))
            sendAck(forMsgId: env.msgId)
            scene?.blomixPvP_onHandshakeCompleteRestartBoard()

        case .ackReady:
            guard isHost else { return }
            if !didFinishHandshake {
                markHandshakeComplete(isHostSide: true)
                scene?.blomixPvP_onHandshakeCompleteRestartBoard()
            }
            sendAck(forMsgId: env.msgId)

        case .attackLine:
            sendAck(forMsgId: env.msgId)
            guard let tokens = env.line, let line = BlockType.lineFromWireTokens(tokens) else { return }
            let wireId = env.attackId ?? (lastReceivedAttackId + 1)
            if wireId <= lastReceivedAttackId {
                BlomixPvPLog.event("attack_duplicate_ignored", ["attackId": "\(wireId)"])
                return
            }
            lastReceivedAttackId = wireId
            incomingAttackLines.append(QueuedAttackLine(id: nextIncomingAttackLineID, line: line))
            nextIncomingAttackLineID += 1
            if var g = rng {
                g.discardNextRandomLineDrawsMatchingOpponentGeneration()
                rng = g
            }
            scene?.blomixPvP_refreshPendingAttackLinePreview()
            BlomixPvPLog.event("attack_received", ["attackId": "\(wireId)"])

        case .boardFillDepth:
            scene?.blomixPvP_setRemoteBoardFillDepth(env.fillDepth ?? 0)
            scene?.blomixPvP_setRemoteScore(env.score ?? 0)

        case .iLost:
            sendAck(forMsgId: env.msgId)
            guard remoteSenderGamePlayerID != GKLocalPlayer.local.gamePlayerID else { return }
            guard !didReceiveRemoteLoss else {
                // Renvoi iLost : re-ack victory
                enqueueCritical(BlomixPvPWireEnvelope(k: .ackVictory, seed: nil, line: nil, fillDepth: nil), maxAttempts: 8)
                return
            }
            didReceiveRemoteLoss = true
            stopTurnTimer()
            stopHeartbeat()
            enqueueCritical(BlomixPvPWireEnvelope(k: .ackVictory, seed: nil, line: nil, fillDepth: nil), maxAttempts: 8)
            BlomixPvPLog.event("remote_lost")
            scene?.blomixPvP_presentRemoteVictory()

        case .ackVictory:
            sendAck(forMsgId: env.msgId)
            if awaitingVictoryAck {
                awaitingVictoryAck = false
                // Retire les iLost encore en file.
                pendingCriticalSends = pendingCriticalSends.filter { $0.value.envelope.k != .iLost }
                BlomixPvPLog.event("victory_acked")
            }

        case .rematchRequest:
            sendAck(forMsgId: env.msgId)
            guard !remoteRematchRequested else { return }
            remoteRematchRequested = true
            scene?.blomixPvP_remotePlayerRequestedRematch()
            evaluateRematchLaunchIfReady()

        case .rematchCancel:
            sendAck(forMsgId: env.msgId)
            remoteRematchRequested = false
            stopRematchRetryTimer()
            scene?.blomixPvP_opponentCancelledRematch()

        case .ackMsg:
            if let ackId = env.ackMsgId {
                acknowledgeMsgId(ackId)
            }

        case .keepAlive:
            // lastPeerAliveAt déjà mis à jour en tête de handleEnvelope
            break

        case .h2hSnapshot:
            // Best-effort, non critique. Différé d’une frame pour ne pas geler le 1er drop.
            let peerOwn = env.h2hMyWins ?? 0
            let peerOurs = env.h2hTheirWins ?? 0
            Task { @MainActor in
                await Task.yield()
                self.scene?.blomixPvP_applyRemoteH2HSnapshot(peerOwnWins: peerOwn, peerClaimsOurWins: peerOurs)
            }
        }
    }

    private func markHandshakeComplete(isHostSide: Bool) {
        didFinishHandshake = true
        isPreparingNextRound = false
        if isHostSide {
            stopHandshakeMonitoring()
        }
        stopHandshakeWatchdog()
        stopRosterBootstrapPoll()
        cancelDisconnectionGrace()
        lastPeerAliveAt = Date()
        startHeartbeat()
        BlomixPvPLog.event("handshake_complete", ["host": "\(isHostSide)"])
        // Snapshot H2H : **pas** ici (freeze 1er blox). Déféré via GameScene après boards ready.
    }

    /// Envoie le cumul H2H local (2 entiers). Aucun CloudKit. Appeler **après** que la grille soit jouable.
    func sendH2HSnapshotBestEffort() {
        guard didFinishHandshake else { return }
        let remoteGame = remoteGamePlayerIDResolved
        let remoteTeam = primaryRemotePlayer?.teamPlayerID ?? ""
        guard !remoteGame.isEmpty || !remoteTeam.isEmpty else { return }
        let snap = BlomixPvPH2HManager.shared.wireSnapshot(
            remoteGamePlayerID: remoteGame.isEmpty ? remoteTeam : remoteGame,
            remoteTeamPlayerID: remoteTeam.isEmpty ? nil : remoteTeam
        )
        var env = BlomixPvPWireEnvelope(k: .h2hSnapshot, seed: nil, line: nil, fillDepth: nil)
        env.h2hMyWins = snap.myWins
        env.h2hTheirWins = snap.theirWins
        sendEnvelopeRaw(env)
        BlomixPvPLog.event("h2h_snapshot_sent", [
            "my": "\(snap.myWins)",
            "their": "\(snap.theirWins)"
        ])
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        lastPeerAliveAt = Date()
        let t = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickHeartbeat() }
        }
        RunLoop.main.add(t, forMode: .common)
        heartbeatTimer = t
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func tickHeartbeat() {
        guard didFinishHandshake, !didReportLocalLoss, !didReceiveRemoteLoss else { return }
        sendEnvelopeRaw(BlomixPvPWireEnvelope(k: .keepAlive, seed: nil, line: nil, fillDepth: nil))
        // Local Multipeer : keepAlive parfois perdu — seuil plus large (tour par tour).
        let silenceLimit = isLocalMatch ? localPeerSilenceTimeout : peerSilenceTimeout
        if let last = lastPeerAliveAt, Date().timeIntervalSince(last) > silenceLimit {
            BlomixPvPLog.event("peer_silence_timeout", [
                "silence_s": "\(Int(Date().timeIntervalSince(last)))",
                "limit": "\(Int(silenceLimit))",
                "local": "\(isLocalMatch)",
                "liveTransport": "\(localSession?.hasLiveTransport == true)"
            ])
            if isLocalMatch {
                // Cas fréquent : MCSession « zombie » (connectedPeers non vide mais plus de data).
                // Forcer un rebuild + re-invite plutôt que d’attendre passivement.
                let now = Date()
                let canReset: Bool = {
                    guard let t = lastLocalForceResetAt else { return true }
                    return now.timeIntervalSince(t) >= 8.0
                }()
                if canReset {
                    lastLocalForceResetAt = now
                    localSession?.forceTransportReset(reason: "peer_silence")
                } else {
                    localSession?.attemptMidGameReconnect()
                }
                if !isInDisconnectionGrace {
                    beginInMatchDisconnectionGrace(reason: "peer_silence_local")
                }
            } else if !isInDisconnectionGrace {
                beginInMatchDisconnectionGrace(reason: "peer_silence")
            }
        }
    }

    // MARK: - Revanche

    func localPlayerRequestedRematch() {
        guard !localRematchRequested else { return }
        localRematchRequested = true
        enqueueCritical(BlomixPvPWireEnvelope(k: .rematchRequest, seed: nil, line: nil, fillDepth: nil), maxAttempts: 15)
        startRematchRetryTimer()
        evaluateRematchLaunchIfReady()
    }

    func cancelRematchFlowAndNotifyPeer() {
        guard localRematchRequested, !isPreparingNextRound else {
            resetRematchFlags()
            return
        }
        enqueueCritical(BlomixPvPWireEnvelope(k: .rematchCancel, seed: nil, line: nil, fillDepth: nil), maxAttempts: 6)
        resetRematchFlags()
    }

    private func startRematchRetryTimer() {
        stopRematchRetryTimer()
        rematchRetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.localRematchRequested, !self.remoteRematchRequested else {
                    self.stopRematchRetryTimer()
                    return
                }
                self.enqueueCritical(
                    BlomixPvPWireEnvelope(k: .rematchRequest, seed: nil, line: nil, fillDepth: nil),
                    maxAttempts: 8
                )
            }
        }
        if let rematchRetryTimer {
            RunLoop.main.add(rematchRetryTimer, forMode: .common)
        }
    }

    private func stopRematchRetryTimer() {
        rematchRetryTimer?.invalidate()
        rematchRetryTimer = nil
    }

    private func resetRematchFlags() {
        stopRematchRetryTimer()
        localRematchRequested = false
        remoteRematchRequested = false
        isPreparingNextRound = false
    }

    private func evaluateRematchLaunchIfReady() {
        guard localRematchRequested, remoteRematchRequested else { return }
        prepareForNextRound()
    }

    private func prepareForNextRound() {
        guard !isPreparingNextRound else { return }
        isPreparingNextRound = true
        stopRematchRetryTimer()
        stopHeartbeat()
        pendingCriticalSends.removeAll()
        scene?.blomixPvP_startRematch()
        didFinishHandshake = false
        didEmitHelloSeed = false
        handshakeSeed = nil
        localRematchRequested = false
        remoteRematchRequested = false
        didReportLocalLoss = false
        didReceiveRemoteLoss = false
        awaitingVictoryAck = false
        incomingAttackLines = []
        nextIncomingAttackLineID = 1
        lastReceivedAttackId = 0
        nextOutboundAttackId = 1
        lastSentScoreAttackBracket = 0
        lastSentBoardFillDepth = nil
        lastSentScore = nil
        lastPeerAliveAt = nil
        beginHandshakeMonitoringIfNeeded()
        startHandshakeWatchdog()
        BlomixPvPLog.event("rematch_prepare")
    }

    // MARK: - Watchdog & grace

    private func startHandshakeWatchdog() {
        stopHandshakeWatchdog()
        guard !didFinishHandshake else { return }
        let t = Timer.scheduledTimer(withTimeInterval: handshakeWatchdogTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.didFinishHandshake else { return }
                BlomixPvPLog.event("handshake_watchdog_expired")
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

    private func beginInMatchDisconnectionGrace(reason: String) {
        guard didFinishHandshake else {
            let period = isLocalMatch ? localInMatchDisconnectionGracePeriod : handshakeDisconnectionGracePeriod
            startDisconnectionGrace(period: period, reason: reason)
            return
        }
        let period = isLocalMatch ? localInMatchDisconnectionGracePeriod : inMatchDisconnectionGracePeriod
        startDisconnectionGrace(period: period, reason: reason)
        scene?.blomixPvP_setReconnectingOverlayVisible(true)
    }

    private func startDisconnectionGrace(period: TimeInterval, reason: String) {
        // Ne pas raccourcir une grace locale déjà en cours.
        if isInDisconnectionGrace, isLocalMatch { return }
        cancelDisconnectionGrace()
        isInDisconnectionGrace = true
        BlomixPvPLog.event("disconnect_grace_start", [
            "period_s": "\(period)",
            "reason": reason,
            "inMatch": "\(didFinishHandshake)",
            "local": "\(isLocalMatch)"
        ])
        let t = Timer.scheduledTimer(withTimeInterval: period, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Pair local de retour (transport live) ?
                if self.isLocalMatch, self.localSession?.hasLiveTransport == true {
                    self.isInDisconnectionGrace = false
                    self.disconnectionGraceTimer = nil
                    self.scene?.blomixPvP_setReconnectingOverlayVisible(false)
                    self.lastPeerAliveAt = Date()
                    BlomixPvPLog.event("disconnect_grace_aborted_reconnected")
                    // KeepAlive pour resynchroniser le silence côté pair.
                    self.sendEnvelopeRaw(BlomixPvPWireEnvelope(k: .keepAlive, seed: nil, line: nil, fillDepth: nil))
                    return
                }
                self.isInDisconnectionGrace = false
                self.scene?.blomixPvP_setReconnectingOverlayVisible(false)
                BlomixPvPLog.event("disconnect_grace_expired", ["reason": reason])
                if self.didFinishHandshake {
                    self.scene?.blomixPvP_peerDisconnected()
                } else {
                    self.scene?.blomixPvP_matchFailed(nil)
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        disconnectionGraceTimer = t
    }

    private func cancelDisconnectionGrace() {
        if isInDisconnectionGrace {
            BlomixPvPLog.event("disconnect_grace_cancel")
        }
        isInDisconnectionGrace = false
        disconnectionGraceTimer?.invalidate()
        disconnectionGraceTimer = nil
        scene?.blomixPvP_setReconnectingOverlayVisible(false)
    }
}

extension BlomixPvPMatchCoordinator: GKMatchDelegate {
    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        let remoteID = player.gamePlayerID
        Task { @MainActor in
            guard let env = try? JSONDecoder().decode(BlomixPvPWireEnvelope.self, from: data) else {
                BlomixPvPLog.event("decode_failed")
                return
            }
            self.handleEnvelope(env, remoteSenderGamePlayerID: remoteID)
        }
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        let displayName = player.displayName
        let gamePlayerID = player.gamePlayerID
        let teamPlayerID = player.teamPlayerID
        Task { @MainActor in
            if state == .disconnected {
                BlomixPvPLog.event("peer_disconnected_gk", [
                    "id": gamePlayerID,
                    "handshakeDone": "\(self.didFinishHandshake)"
                ])
                if self.didFinishHandshake {
                    self.beginInMatchDisconnectionGrace(reason: "gk_disconnected")
                } else {
                    self.startDisconnectionGrace(
                        period: self.handshakeDisconnectionGracePeriod,
                        reason: "gk_disconnected_handshake"
                    )
                }
            } else if state == .connected {
                self.cancelDisconnectionGrace()
                self.lastPeerAliveAt = Date()
                self.resolveHostRoleIfNeeded()
                self.beginHandshakeMonitoringIfNeeded()
                BlomixRecentOpponentsCache.shared.record(gamePlayerID: gamePlayerID, displayName: displayName)
                // Alias H2H game ↔ team dès la connexion match (lookup Elo multi-ID).
                if !gamePlayerID.isEmpty || !teamPlayerID.isEmpty {
                    BlomixPvPH2HManager.shared.registerAliases(
                        [gamePlayerID, teamPlayerID].filter { !$0.isEmpty }
                    )
                }
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
            BlomixPvPLog.event("match_failed", ["error": error?.localizedDescription ?? "nil"])
            self.scene?.blomixPvP_matchFailed(error)
        }
    }
}
