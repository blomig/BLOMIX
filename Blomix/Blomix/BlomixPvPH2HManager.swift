//
//  BlomixPvPH2HManager.swift
//  Blomix
//
//  Historique tête-à-tête PvP (1 point = 1 manche gagnée) via CloudKit Public DB.
//
//  Isolation stricte : tout est best-effort / async. Un échec n’affecte que l’affichage
//  du total H2H — jamais le match, l’Elo, la série session ou la reconnexion.
//
//  Schéma CloudKit (Record Type `PvPH2HEvent`, Public DB) :
//    pairKey        String   Queryable
//    winnerID       String
//    loserID        String
//    channel        String   ("online" | "local")
//    clientEventId  String
//    createdAt      Date
//    matchId        String   Queryable (114+) — 1 manche = 1 id partagé
//    reporterId     String   (114+) — auteur du record (WRITE OK)
//  recordName = "h2h_{clientEventId}" (chaque côté crée le sien).
//  Juge : 1 matchId unique = 1 point (vieux records : 1 clientEventId).
//
//  Identité : GameKit expose parfois des chaînes différentes selon l’API
//  (`GKMatch` vs `GKLeaderboard.Entry`) pour le même joueur (`gamePlayerID` vs
//  `teamPlayerID`, formats `A:_…` vs hex). Le cache est multi-clés + alias ;
//  les queries cloud tentent les combinaisons d’IDs locaux/distants.
//
//  Modèle produit (v6.6 / 124) — **CloudKit = vérité d’affichage** :
//
//  1) Cache local = dernier **snapshot cloud** (toutes les clés du duo à la même valeur).
//     Plus de max(cache, plancher, grâce 24 h).
//  2) **Pendant le match** : 0 CloudKit. Affichage = snapshot + Δ de **cette** série.
//  3) **Fin de série** : le récap peut montrer snapshot+Δ ; on n’écrit **pas** ça dans le cache.
//  4) **Juge** (accueil / Elo) : lecture cloud → stamp snapshot ; pending = uploads only.
//  5) Lecture : `pairKey` A:_×A:_ puis filet `winnerID` ; IDs appris depuis pairKey si un côté est local.
//  6) Handshake : bootstrap si snapshot vide — pas de MAX.
//
//  BlomixPvPH2HManager est @MainActor : tout CloudKit lourd pendant isGameActive = FREEZE.
//

import CloudKit
import Foundation
import GameKit
import UIKit

extension Notification.Name {
    static let blomixH2HCacheDidChange = Notification.Name("blomixH2HCacheDidChange")
}

// MARK: - Models

struct BlomixPvPH2HTotals: Equatable, Sendable, Codable {
    /// Victoires du joueur local face à cet adversaire.
    var localWins: Int
    /// Victoires de l’adversaire face au local.
    var remoteWins: Int

    static let zero = BlomixPvPH2HTotals(localWins: 0, remoteWins: 0)

    var hasHistory: Bool { localWins + remoteWins > 0 }

    /// Fusion conservative (max par côté) — évite de sous-compter si sources partielles.
    func merging(_ other: BlomixPvPH2HTotals) -> BlomixPvPH2HTotals {
        BlomixPvPH2HTotals(
            localWins: max(localWins, other.localWins),
            remoteWins: max(remoteWins, other.remoteWins)
        )
    }
}

// MARK: - Manager

@MainActor
final class BlomixPvPH2HManager {

    static let shared = BlomixPvPH2HManager()

    private let ckContainer = CKContainer(identifier: "iCloud.blomig.BLOMIX")
    private var publicDB: CKDatabase { ckContainer.publicCloudDatabase }
    private static let recordType = "PvPH2HEvent"

    /// Cache v2 : n’importe quel ID distant connu → totaux (POV local).
    private static let cacheKeyV2 = "blomixPvPH2HCache_v2"
    private static let cacheKeyV1 = "blomixPvPH2HCache_v1"
    private static let pendingKey = "blomixPvPH2HPending_v1"
    /// Alias ID → ID canonique (union-find aplati). Relie gamePlayerID ↔ teamPlayerID, etc.
    private static let aliasKey = "blomixPvPH2HAliases_v1"
    /// Plancher de session : confirmed + deltas tant que le cloud n’a pas rattrapé.
    private static let sessionFloorKey = "blomixPvPH2HSessionFloor_v1"
    /// pairKeys déjà vus (écriture ou lecture) — pour retrouver l’historique multi-ID.
    private static let knownPairKeysKey = "blomixPvPH2HKnownPairKeys_v1"
    /// Série live : baseline cloud + deltas (affichage session).
    private static let liveSeriesKey = "blomixPvPH2HLiveSeries_v1"
    /// Plancher **durable** : dernier cumul session verrouillé (baseline+série) jusqu’à rattrapage cloud.
    /// Survit au kill app — évite 13-11 → 12-10 si upload encore absent.
    private static let committedFloorKey = "blomixPvPH2HCommittedFloor_v1"
    /// Après fin de série : ne pas redescendre sous baseline+série pendant cette durée (live series).
    private static let seriesGraceDuration: TimeInterval = 24 * 3600
    /// Expire un plancher non rattrapé (évite inflation éternelle si bug d’enregistrement).
    private static let sessionFloorMaxAge: TimeInterval = 7 * 24 * 3600
    private static let committedFloorMaxAge: TimeInterval = 7 * 24 * 3600

    private var isFlushing = false
    private var didRegisterLifecycle = false
    private var didMigrateCache = false
    private var didPruneEmpty = false
    /// Dernier adversaire PvP (1 duo) — réconciliation cloud après retour accueil / filet Elo.
    private var lastOpponentGameID: String = ""
    private var lastOpponentTeamID: String = ""
    private var lastOpponentDisplayName: String?
    private var homeReconcileTask: Task<Void, Never>?
    private var eloReconcileTask: Task<Void, Never>?
    private var lastCloudReconcileAt: Date?
    private var lastEloReconcileAt: Date?
    private static let homeReconcileMinInterval: TimeInterval = 20
    private static let eloReconcileMinInterval: TimeInterval = 45
    private static let eloIdleDelayNanoseconds: UInt64 = 1_200_000_000
    private static let maxEloDuosPerWave = 4
    private static let lastOpponentPersistKey = "blomixPvPH2HLastOpponent_v1"

    private init() {
        restorePersistedLastOpponent()
        registerLifecycleIfNeeded()
        migrateCacheV1IfNeeded()
        pruneEmptyCacheEntriesIfNeeded()
    }

    private func registerLifecycleIfNeeded() {
        guard !didRegisterLifecycle else { return }
        didRegisterLifecycle = true
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Un flush calme seulement — jamais le juge ici (sinon 503 + lobby / défis cassés).
                if !BlomixPublicCloudGate.shared.isBlocked {
                    self?.flushPendingEventsBestEffort()
                }
            }
        }
    }

    // MARK: - Pair key (CloudKit)

    /// Clé stable de la paire (ordre lexicographique des IDs).
    static func pairKey(localID: String, remoteID: String) -> String? {
        let a = localID.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = remoteID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty, !b.isEmpty, a != b else { return nil }
        return [a, b].sorted().joined(separator: "|")
    }

    // MARK: - Public API (best-effort)

    /// Snapshot filaire (2 ints) au contact PvP. Lecture cache pure, 0 CloudKit.
    func wireSnapshot(
        remoteGamePlayerID: String,
        remoteTeamPlayerID: String? = nil
    ) -> (myWins: Int, theirWins: Int) {
        let remoteIDs = Self.normalizedIDList([remoteGamePlayerID, remoteTeamPlayerID ?? ""])
        let t = displayedTotalsPreferringLive(againstRemoteIDs: remoteIDs)
        return (t.localWins, t.remoteWins)
    }

    /// Snapshot peer (6.6) : **pas** de MAX sur l’historique (ça gonflait le plancher).
    /// Bootstrap seulement si le local n’a aucun historique. N’écrase pas les Δ de série.
    /// - peerOwnWins : victoires que le peer s’attribue
    /// - peerClaimsOurWins : victoires qu’il nous attribue
    func mergeMaxFromPeerSnapshot(
        peerOwnWins: Int,
        peerClaimsOurWins: Int,
        remoteGamePlayerID: String,
        remoteTeamPlayerID: String? = nil
    ) {
        registerLifecycleIfNeeded()
        migrateCacheV1IfNeeded()
        let remoteIDs = Self.normalizedIDList([remoteGamePlayerID, remoteTeamPlayerID ?? ""])
        guard !remoteIDs.isEmpty else { return }
        registerAliases(remoteIDs)
        let remotes = expandedRemoteIDs(remoteIDs)

        let peer = BlomixPvPH2HTotals(
            localWins: max(0, peerClaimsOurWins),
            remoteWins: max(0, peerOwnWins)
        )

        if let live = liveSeries(forRemoteIDs: remotes),
           live.isActive,
           live.seriesLocal + live.seriesRemote > 0 {
            print("[H2H] peer snapshot ignored mid-series \(live.seriesLocal)-\(live.seriesRemote)")
            return
        }

        let ours = historicalTotals(againstRemoteIDs: remotes)
        guard !ours.hasHistory, peer.hasHistory else {
            print("[H2H] peer snapshot no max-merge ours=\(ours.localWins)-\(ours.remoteWins) peer=\(peer.localWins)-\(peer.remoteWins)")
            return
        }

        replaceTotals(peer, underRemoteIDs: remotes)
        if var live = liveSeries(forRemoteIDs: remotes), live.isActive {
            live.baselineLocal = peer.localWins
            live.baselineRemote = peer.remoteWins
            live.updatedAt = Date()
            saveLiveSeries(live)
        } else if liveSeries(forRemoteIDs: remotes) == nil {
            let ctx = LiveSeriesContext(
                remoteKey: sessionStorageKey(forRemoteIDs: remotes),
                remoteIDs: remotes,
                baselineLocal: peer.localWins,
                baselineRemote: peer.remoteWins,
                seriesLocal: 0,
                seriesRemote: 0,
                isActive: true,
                graceUntil: nil,
                updatedAt: Date()
            )
            saveLiveSeries(ctx)
        }
        print("[H2H] peer snapshot bootstrap \(peer.localWins)-\(peer.remoteWins)")
    }

    /// Une seule vérité d’affichage (récap, Duel) : historique + Δ de série, jamais `max(cache, 1-2)`.
    /// Jamais de lecture CloudKit.
    func displayedTotalsForUI(
        againstRemoteIDs remoteIDs: [String],
        displayName: String? = nil
    ) -> BlomixPvPH2HTotals {
        migrateCacheV1IfNeeded()
        if let displayName {
            bridgeAliasesUsingDisplayName(displayName, eloIDs: remoteIDs)
        }
        registerAliases(remoteIDs)
        return displayedTotalsPreferringLive(againstRemoteIDs: Self.normalizedIDList(remoteIDs))
    }

    /// Dernier snapshot cloud (pas de plancher, pas de max entre clés).
    private func historicalTotals(againstRemoteIDs remoteIDs: [String]) -> BlomixPvPH2HTotals {
        cachedTotals(againstRemoteIDs: expandedRemoteIDs(remoteIDs)) ?? .zero
    }

    /// Série **en cours** : snapshot (baseline live) + Δ. Hors série : snapshot seul (pas de grâce 24 h).
    private func composeDisplayed(historical: BlomixPvPH2HTotals, live: LiveSeriesContext?) -> BlomixPvPH2HTotals {
        guard let live, live.isActive else { return historical }
        return BlomixPvPH2HTotals(
            localWins: live.baselineLocal + live.seriesLocal,
            remoteWins: live.baselineRemote + live.seriesRemote
        )
    }

    private func displayedTotalsPreferringLive(againstRemoteIDs remoteIDs: [String]) -> BlomixPvPH2HTotals {
        let remotes = expandedRemoteIDs(remoteIDs)
        return composeDisplayed(
            historical: historicalTotals(againstRemoteIDs: remotes),
            live: liveSeries(forRemoteIDs: remotes)
        )
    }

    /// Mémorise le duo courant (IDs match) pour une lecture cloud **plus tard**, hors gameplay.
    func rememberOpponentForReconcile(
        remoteGamePlayerID: String,
        remoteTeamPlayerID: String? = nil,
        displayName: String? = nil
    ) {
        let game = remoteGamePlayerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let team = (remoteTeamPlayerID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !game.isEmpty || !team.isEmpty else { return }
        lastOpponentGameID = game
        lastOpponentTeamID = team
        if let displayName, !displayName.isEmpty {
            lastOpponentDisplayName = displayName
        }
        persistLastOpponent()
    }

    private func persistLastOpponent() {
        var payload: [String: String] = [:]
        if !lastOpponentGameID.isEmpty { payload["g"] = lastOpponentGameID }
        if !lastOpponentTeamID.isEmpty { payload["t"] = lastOpponentTeamID }
        if let n = lastOpponentDisplayName, !n.isEmpty { payload["n"] = n }
        UserDefaults.standard.set(payload, forKey: Self.lastOpponentPersistKey)
    }

    private func restorePersistedLastOpponent() {
        guard let payload = UserDefaults.standard.dictionary(forKey: Self.lastOpponentPersistKey) as? [String: String] else { return }
        lastOpponentGameID = payload["g"] ?? ""
        lastOpponentTeamID = payload["t"] ?? ""
        lastOpponentDisplayName = payload["n"]
    }

    static func lightLookupKey(forRemoteIDs ids: [String]) -> String {
        normalizedIDList(ids).joined(separator: "|")
    }

    /// Lecture **légère** pour le tableau Elo : 1 decode cache/live/floor/alias + récents, puis lookups.
    /// Pont nom → ID match pour **toutes** les lignes (pas seulement le dernier adversaire).
    /// Alias **en mémoire uniquement** (pas d’écriture). 0 CloudKit.
    func precomputedLightTotals(idGroups: [[String]], displayNames: [String] = []) -> [String: BlomixPvPH2HTotals] {
        migrateCacheV1IfNeeded()
        let cache = loadCacheV2()
        let lives = loadLiveSeriesMap()
        let aliases = loadAliases()
        let lastKeys = Set(Self.normalizedIDList([lastOpponentGameID, lastOpponentTeamID]))
        var idsByNormalizedName: [String: [String]] = [:]
        for recent in BlomixRecentOpponentsCache.shared.all() {
            let n = recent.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !n.isEmpty else { continue }
            idsByNormalizedName[n, default: []].append(recent.gamePlayerID)
        }
        if let lastName = lastOpponentDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !lastName.isEmpty, !lastKeys.isEmpty {
            idsByNormalizedName[lastName.lowercased(), default: []].append(contentsOf: lastKeys)
        }

        var out: [String: BlomixPvPH2HTotals] = [:]
        out.reserveCapacity(idGroups.count)
        for (index, ids) in idGroups.enumerated() {
            var keys = Set(Self.normalizedIDList(ids))
            guard !keys.isEmpty else { continue }
            let mapKey = Self.lightLookupKey(forRemoteIDs: ids)
            for id in Array(keys) {
                keys.insert(Self.aliasRoot(id, map: aliases))
            }
            if !lastKeys.isEmpty, !keys.isDisjoint(with: lastKeys) {
                keys.formUnion(lastKeys)
            }
            if index < displayNames.count {
                let rowName = displayNames[index].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if let extra = idsByNormalizedName[rowName] {
                    keys.formUnion(extra)
                }
            }
            var live: LiveSeriesContext?
            for k in keys {
                if live == nil, let l = lives[k], l.isActive {
                    live = l
                }
            }
            let hist = pickCloudSnapshot(from: cache, keys: keys) ?? .zero
            let best = composeDisplayed(historical: hist, live: live)
            if best.hasHistory { out[mapKey] = best }
        }
        return out
    }

    /// Juge CloudKit **1 duo** (dernier adversaire), après overlays PvP fermés / accueil.
    /// Ne bloque pas l’UI : délai de pose puis `refreshTotals`. 0 effet si un match a repris.
    func scheduleHomeReconcileAfterReturnToMenu() {
        let game = lastOpponentGameID
        let team = lastOpponentTeamID
        let name = lastOpponentDisplayName
        guard !game.isEmpty || !team.isEmpty else { return }
        homeReconcileTask?.cancel()
        homeReconcileTask = Task { @MainActor [weak self] in
            let extra = UInt64(max(0, BlomixPublicCloudGate.shared.retryRemainingSeconds)) * 1_000_000_000
            try? await Task.sleep(nanoseconds: 8_000_000_000 + extra)
            guard !Task.isCancelled else { return }
            if BlomixPublicCloudGate.shared.isBlocked
                || BlomixAvailablePlayersManager.shared.isInActiveMatch {
                print("[H2H] reconcile skip (home delayed) — gate/match")
                return
            }
            await self?.performRememberedOpponentReconcile(
                remoteGamePlayerID: game,
                remoteTeamPlayerID: team.isEmpty ? nil : team,
                displayName: name,
                reason: "home"
            )
        }
    }

    /// Filet classement Elo : même duo, si pas déjà recalé récemment. N’itère pas les lignes.
    func reconcileRememberedOpponentForEloDisplay() async {
        let game = lastOpponentGameID
        let team = lastOpponentTeamID
        guard !game.isEmpty || !team.isEmpty else { return }
        await performRememberedOpponentReconcile(
            remoteGamePlayerID: game,
            remoteTeamPlayerID: team.isEmpty ? nil : team,
            displayName: lastOpponentDisplayName,
            reason: "elo"
        )
    }

    /// Juge CloudKit **1 vague** à l’ouverture Elo : dernier adversaire d’abord, puis duos
    /// déjà présents en cache. Délai idle ; jamais en Duel ; jamais par cellule / scroll.
    func scheduleEloIdleReconcile(idGroups: [[String]], displayNames: [String]) {
        eloReconcileTask?.cancel()
        let groups = idGroups
        let names = displayNames
        eloReconcileTask = Task { @MainActor [weak self] in
            let extra = UInt64(max(0, BlomixPublicCloudGate.shared.retryRemainingSeconds)) * 1_000_000_000
            try? await Task.sleep(nanoseconds: Self.eloIdleDelayNanoseconds + extra)
            guard !Task.isCancelled else { return }
            await self?.performEloIdleReconcile(idGroups: groups, displayNames: names)
        }
    }

    private func performEloIdleReconcile(idGroups: [[String]], displayNames: [String]) async {
        guard !BlomixAvailablePlayersManager.shared.isInActiveMatch else {
            print("[H2H] elo-wave skip — match actif")
            return
        }
        if BlomixPublicCloudGate.shared.isBlocked {
            print("[H2H] elo-wave skip — CK gate")
            return
        }
        if let last = lastEloReconcileAt,
           Date().timeIntervalSince(last) < Self.eloReconcileMinInterval {
            print("[H2H] elo-wave skip — déjà fait il y a \(Int(Date().timeIntervalSince(last)))s")
            return
        }
        lastEloReconcileAt = Date()

        var seen = Set<String>()
        var duos: [(ids: [String], name: String?)] = []

        func consider(_ ids: [String], name: String?) {
            let norm = Self.normalizedIDList(ids)
            guard !norm.isEmpty else { return }
            let key = norm.sorted().joined(separator: "|")
            guard !seen.contains(key) else { return }
            seen.insert(key)
            duos.append((norm, name))
        }

        consider([lastOpponentGameID, lastOpponentTeamID], name: lastOpponentDisplayName)
        for (index, ids) in idGroups.enumerated() {
            guard duos.count < Self.maxEloDuosPerWave else { break }
            let name = index < displayNames.count ? displayNames[index] : nil
            let hist = displayedTotalsPreferringLive(againstRemoteIDs: ids)
            guard hist.hasHistory else { continue }
            consider(ids, name: name)
        }
        duos = Array(duos.prefix(Self.maxEloDuosPerWave))
        print("[H2H] elo-wave start duos=\(duos.count)")

        var flushed = false
        for duo in duos {
            guard !Task.isCancelled else { return }
            if BlomixAvailablePlayersManager.shared.isInActiveMatch
                || BlomixPublicCloudGate.shared.isBlocked {
                print("[H2H] elo-wave stop — gate/match")
                return
            }
            _ = await refreshTotals(
                againstRemoteIDs: duo.ids,
                displayName: duo.name,
                flushPending: !flushed
            )
            flushed = true
            lastCloudReconcileAt = Date()
        }
        print("[H2H] elo-wave done")
    }

    private func performRememberedOpponentReconcile(
        remoteGamePlayerID: String,
        remoteTeamPlayerID: String?,
        displayName: String?,
        reason: String
    ) async {
        guard !BlomixAvailablePlayersManager.shared.isInActiveMatch else {
            print("[H2H] reconcile skip (\(reason)) — match actif")
            return
        }
        if BlomixPublicCloudGate.shared.isBlocked {
            print("[H2H] reconcile skip (\(reason)) — CK gate")
            return
        }
        if let last = lastCloudReconcileAt,
           Date().timeIntervalSince(last) < Self.homeReconcileMinInterval {
            print("[H2H] reconcile skip (\(reason)) — déjà fait il y a \(Int(Date().timeIntervalSince(last)))s")
            return
        }
        lastCloudReconcileAt = Date()
        print("[H2H] reconcile start (\(reason)) remote=\(debugID(remoteGamePlayerID))")
        _ = await refreshTotals(
            againstRemoteIDs: [remoteGamePlayerID, remoteTeamPlayerID ?? ""],
            displayName: displayName
        )
        print("[H2H] reconcile done (\(reason))")
    }

    /// Baseline **locale immédiate** (cache uniquement, 0 réseau).
    /// À appeler au début de série / lancement match — ne bloque jamais le handshake.
    /// - Parameter forceNewSeries: nouveau Duel lobby (pas revanche) — oublie les Δ H2H de l’ancienne série.
    func seedSeriesBaselineFromCache(
        remoteGamePlayerID: String,
        remoteTeamPlayerID: String? = nil,
        displayName: String? = nil,
        forceNewSeries: Bool = false
    ) {
        registerLifecycleIfNeeded()
        migrateCacheV1IfNeeded()
        let remoteIDs = Self.normalizedIDList([remoteGamePlayerID, remoteTeamPlayerID ?? ""])
        guard !remoteIDs.isEmpty else { return }
        if let name = displayName { bridgeAliasesUsingDisplayName(name, eloIDs: remoteIDs) }
        registerAliases(remoteIDs)

        if !forceNewSeries,
           let live = liveSeries(forRemoteIDs: remoteIDs),
           live.isActive,
           live.seriesLocal + live.seriesRemote > 0 {
            return
        }

        let remotes = augmentedRemoteIDs(remoteIDs, displayName: displayName)
        // Historique seulement (pas les Δ d’une vieille série). Nouveau lobby : reset Δ, même baseline.
        let base = historicalTotals(againstRemoteIDs: remotes)
        if forceNewSeries {
            clearLiveSeries(forRemoteIDs: remotes)
        }
        // Nouvelle série : baseline propre, Δ à 0 (évite de rejouer les Δ de la série précédente).
        let ctx = LiveSeriesContext(
            remoteKey: sessionStorageKey(forRemoteIDs: remoteIDs),
            remoteIDs: remotes,
            baselineLocal: base.localWins,
            baselineRemote: base.remoteWins,
            seriesLocal: 0,
            seriesRemote: 0,
            isActive: true,
            graceUntil: nil,
            updatedAt: Date()
        )
        saveLiveSeries(ctx)
        print("[H2H] series baseline seed \(base.localWins)-\(base.remoteWins) (cloud snapshot)")
    }

    /// Raffine la baseline via CloudKit. **Après handshake uniquement** (jamais pendant l’appariement).
    func beginSeriesBaseline(
        remoteGamePlayerID: String,
        remoteTeamPlayerID: String? = nil,
        displayName: String? = nil
    ) async {
        registerLifecycleIfNeeded()
        migrateCacheV1IfNeeded()
        let remoteIDs = Self.normalizedIDList([remoteGamePlayerID, remoteTeamPlayerID ?? ""])
        guard !remoteIDs.isEmpty else { return }
        if let name = displayName { bridgeAliasesUsingDisplayName(name, eloIDs: remoteIDs) }
        registerAliases(remoteIDs)

        // Ne pas écraser si des manches de la série sont déjà comptées.
        if let live = liveSeries(forRemoteIDs: remoteIDs),
           live.isActive,
           live.seriesLocal + live.seriesRemote > 0 {
            print("[H2H] series baseline skipped — already \(live.seriesLocal)-\(live.seriesRemote) on base \(live.baselineLocal)-\(live.baselineRemote)")
            return
        }

        // Pas de flush lourd ici (évite contention MainActor) : lecture cloud seule.
        let localIDs = resolvedLocalPlayerIDs()
        let remotes = expandedRemoteIDs(remoteIDs)
        let cloud = await fetchCloudSum(localIDs: localIDs, remotes: remotes, flushFirst: false)
        let baseline: BlomixPvPH2HTotals
        if cloud.querySucceeded {
            baseline = cloud.sum
            if baseline.hasHistory {
                replaceTotals(baseline, underRemoteIDs: remotes)
            } else {
                clearTotals(underRemoteIDs: remotes)
            }
        } else {
            baseline = cachedTotals(againstRemoteIDs: remotes) ?? .zero
            print("[H2H] series baseline OFFLINE fallback cache \(baseline.localWins)-\(baseline.remoteWins)")
        }

        // Si une série 0–0 active existe déjà (fallback), on met à jour sa baseline cloud.
        let existingSeries = liveSeries(forRemoteIDs: remoteIDs)
        let ctx = LiveSeriesContext(
            remoteKey: sessionStorageKey(forRemoteIDs: remoteIDs),
            remoteIDs: remotes,
            baselineLocal: baseline.localWins,
            baselineRemote: baseline.remoteWins,
            seriesLocal: existingSeries?.seriesLocal ?? 0,
            seriesRemote: existingSeries?.seriesRemote ?? 0,
            isActive: true,
            graceUntil: nil,
            updatedAt: Date()
        )
        saveLiveSeries(ctx)
        let disp = ctx.displayedTotals
        if disp.hasHistory {
            replaceTotals(disp, underRemoteIDs: remotes)
        }
        print("[H2H] series baseline set \(baseline.localWins)-\(baseline.remoteWins) +série \(ctx.seriesLocal)-\(ctx.seriesRemote) (cloudOK=\(cloud.querySucceeded))")
    }

    /// Total affiché série = baseline + deltas de série (GameScene fait foi pour les deltas en fin).
    /// Fige la grâce post-série (Elo ne redescend pas tant que cloud n’a pas rattrapé).
    /// Ne lance **pas** de replace par le cloud.
    /// - Parameter flushPending: si `false`, ne lance **pas** le flush CloudKit (UI récap d’abord ;
    ///   appeler `flushPendingEventsBestEffort()` après le present). Défaut `true` pour les autres chemins.
    @discardableResult
    func lockSeriesEndDisplay(
        remoteGamePlayerID: String,
        remoteTeamPlayerID: String? = nil,
        seriesLocalWins: Int,
        seriesRemoteWins: Int,
        flushPending: Bool = true
    ) -> BlomixPvPH2HTotals {
        let remoteIDs = Self.normalizedIDList([remoteGamePlayerID, remoteTeamPlayerID ?? ""])
        let remotes = augmentedRemoteIDs(remoteIDs, displayName: lastOpponentDisplayName)
        let live = liveSeries(forRemoteIDs: remotes)
        let hist = historicalTotals(againstRemoteIDs: remotes)
        let seriesL = max(0, seriesLocalWins)
        let seriesR = max(0, seriesRemoteWins)
        // Baseline = snapshot cloud (seed), pas un max avec un vieux cache.
        let baseL = live?.baselineLocal ?? hist.localWins
        let baseR = live?.baselineRemote ?? hist.remoteWins
        let final = BlomixPvPH2HTotals(
            localWins: baseL + seriesL,
            remoteWins: baseR + seriesR
        )
        print("[H2H] series-end snapshot+Δ \(final.localWins)-\(final.remoteWins) (cloud \(baseL)-\(baseR) + série \(seriesL)-\(seriesR)) flush=\(flushPending)")
        let doFlush = flushPending
        let persistRemotes = remotes
        Task { @MainActor in
            self.clearLiveSeries(forRemoteIDs: persistRemotes)
            if doFlush {
                self.flushPendingEventsBestEffort()
            }
        }
        return final
    }

    /// Enregistre le résultat d’une manche. Fournir **tous** les IDs distants connus
    /// (`gamePlayerID`, `teamPlayerID`) pour que le classement Elo retrouve le cumul.
    /// - Parameter matchEventKey: clé stable optionnelle (ex. seed+index de manche) pour
    ///   idempotence cloud ; si omis → UUID (comportement historique).
    func recordMatchOutcome(
        localWon: Bool,
        remoteGamePlayerID: String,
        remoteTeamPlayerID: String? = nil,
        channel: String,
        matchEventKey: String? = nil,
        matchId: String? = nil
    ) {
        registerLifecycleIfNeeded()
        migrateCacheV1IfNeeded()

        let remoteIDs = Self.normalizedIDList([remoteGamePlayerID, remoteTeamPlayerID ?? ""])
        guard !remoteIDs.isEmpty else {
            print("[H2H] record skip — remote IDs vides")
            return
        }
        registerAliases(remoteIDs)

        let localIDs = resolvedLocalPlayerIDs()
        // IDs d’écriture cloud : priorité match-like (A:_…) pour coller à l’historique prod.
        guard let primaryLocal = Self.preferredCloudID(from: localIDs),
              let primaryRemote = Self.preferredCloudID(from: remoteIDs)
        else {
            print("[H2H] record skip — local ID manquant")
            return
        }

        guard let pair = Self.pairKey(localID: primaryLocal, remoteID: primaryRemote) else {
            print("[H2H] record skip — IDs manquants local=\(debugID(primaryLocal)) remote=\(debugID(primaryRemote))")
            return
        }

        // Affichage session = baseline + série. **Aucun** CloudKit ici (match / inter-manches).
        let displayed = applyLiveSeriesOutcome(localWon: localWon, remoteIDs: remoteIDs)
        noteSessionOutcome(
            remoteIDs: remoteIDs,
            localWon: localWon,
            totalsBefore: BlomixPvPH2HTotals(
                localWins: max(0, displayed.localWins - (localWon ? 1 : 0)),
                remoteWins: max(0, displayed.remoteWins - (localWon ? 0 : 1))
            )
        )
        print("[H2H] cache \(localWon ? "win" : "loss") → \(displayed.localWins)-\(displayed.remoteWins) (baseline+série) \(debugDumpLiveSeries(remoteIDs))")

        let trimmedMatchId = matchId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasSharedMatchId = !trimmedMatchId.isEmpty
        // Sans matchId (vieux chemin) : seul le vainqueur écrit. Avec matchId : les deux.
        guard hasSharedMatchId || localWon else { return }

        let winnerID = localWon ? primaryLocal : primaryRemote
        let loserID = localWon ? primaryRemote : primaryLocal
        let clientEventId = hasSharedMatchId
            ? Self.stableClientEventId(matchEventKey: "\(trimmedMatchId)|\(primaryLocal)", pairKey: pair, winnerID: primaryLocal)
            : Self.stableClientEventId(matchEventKey: matchEventKey, pairKey: pair, winnerID: primaryLocal)
        if loadPending().contains(where: { $0.clientEventId == clientEventId }) {
            print("[H2H] report already pending event=\(clientEventId.prefix(12))…")
            return
        }

        let event = PendingH2HEvent(
            clientEventId: clientEventId,
            pairKey: pair,
            winnerID: winnerID,
            loserID: loserID,
            channel: channel,
            createdAt: Date(),
            matchId: hasSharedMatchId ? trimmedMatchId : nil,
            reporterId: primaryLocal
        )
        enqueuePending(event)
        print("[H2H] \(localWon ? "win" : "loss") queued event=\(event.clientEventId.prefix(12))… matchId=\(hasSharedMatchId ? String(trimmedMatchId.prefix(16)) : "nil") (no flush in-match)")
    }

    /// Totaux en cache pour un ID distant (suit les alias).
    func cachedTotals(against remoteGamePlayerID: String) -> BlomixPvPH2HTotals? {
        cachedTotals(againstRemoteIDs: [remoteGamePlayerID])
    }

    /// Totaux en cache pour un ensemble d’IDs (game + team + alias + pont nom).
    func cachedTotals(againstRemoteIDs remoteIDs: [String], displayName: String? = nil) -> BlomixPvPH2HTotals? {
        migrateCacheV1IfNeeded()
        if let displayName {
            bridgeAliasesUsingDisplayName(displayName, eloIDs: remoteIDs)
        }
        let keys = expandedRemoteIDs(remoteIDs)
        guard !keys.isEmpty else { return nil }
        return pickCloudSnapshot(from: loadCacheV2(), keys: keys)
    }

    /// Une valeur : clé `A:_` si présente (écriture cloud), sinon la première. **Pas** de max.
    private func pickCloudSnapshot(
        from cache: [String: BlomixPvPH2HTotals],
        keys: some Sequence<String>
    ) -> BlomixPvPH2HTotals? {
        var preferred: BlomixPvPH2HTotals?
        var fallback: BlomixPvPH2HTotals?
        for key in keys {
            guard let t = cache[key], t.hasHistory else { continue }
            if key.hasPrefix("A:_") {
                preferred = t
            } else if fallback == nil {
                fallback = t
            }
        }
        return preferred ?? fallback
    }

    /// Rafraîchit depuis CloudKit (toutes combinaisons d’IDs plausibles). Ne throw pas vers l’UI.
    func refreshTotals(against remoteGamePlayerID: String) async -> BlomixPvPH2HTotals? {
        await refreshTotals(againstRemoteIDs: [remoteGamePlayerID], displayName: nil)
    }

    func refreshTotals(
        againstRemoteIDs remoteIDs: [String],
        displayName: String? = nil,
        flushPending: Bool = true
    ) async -> BlomixPvPH2HTotals? {
        migrateCacheV1IfNeeded()
        if let displayName {
            bridgeAliasesUsingDisplayName(displayName, eloIDs: remoteIDs)
        }
        registerAliases(remoteIDs)

        var remotes = augmentedRemoteIDs(remoteIDs, displayName: displayName)
        remotes = Self.normalizedIDList(remotes + [lastOpponentGameID, lastOpponentTeamID])
        guard !remotes.isEmpty else {
            print("[H2H] refresh skip — no remote IDs")
            return nil
        }

        let localIDs = resolvedLocalPlayerIDs()
        guard !localIDs.isEmpty else {
            print("[H2H] refresh skip — no local IDs")
            return nil
        }

        let previous = cachedTotals(againstRemoteIDs: remotes)

        if BlomixPublicCloudGate.shared.isBlocked {
            print("[H2H] refresh skip — CK gate \(BlomixPublicCloudGate.shared.retryRemainingSeconds)s")
            return previous
        }

        // Un flush, une lecture — pas de rafale (503 Public DB).
        if flushPending {
            await flushPendingUntilEmptyOrAttempts(maxAttempts: 1)
        }
        let pendingLeft = pendingLocalWins(localIDs: Set(localIDs), remoteIDs: Set(remotes))
        if pendingLeft > 0 {
            print("[H2H] pending still \(pendingLeft) — \(debugDumpPendingSummary())")
        }

        let cloudBundle = await fetchCloudSum(
            localIDs: localIDs,
            remotes: remotes,
            flushFirst: false
        )

        if cloudBundle.querySucceeded {
            let cloud = cloudBundle.sum
            let complete = cloudBundle.queryComplete && pendingLeft == 0
            if cloud.hasHistory {
                clearLiveSeries(forRemoteIDs: remotes)
                clearCommittedFloor(forRemoteIDs: remotes)
                replaceTotals(cloud, underRemoteIDs: remotes)
                NotificationCenter.default.post(name: .blomixH2HCacheDidChange, object: nil)
                forceCloseSessionFloor(remoteIDs: remotes, to: cloud)
                print("[H2H] reconcile CLOUD-JUDGE \(cloud.localWins)-\(cloud.remoteWins) complete=\(complete) pending=\(pendingLeft)")
                return cloud
            }
            print("[H2H] reconcile cloud empty complete=\(complete) keep snapshot \(previous.map { "\($0.localWins)-\($0.remoteWins)" } ?? "nil")")
            return previous
        }

        print("[H2H] refresh OFFLINE keep snapshot \(previous.map { "\($0.localWins)-\($0.remoteWins)" } ?? "nil")")
        return previous
    }

    // MARK: - Live series (baseline + deltas)

    private struct LiveSeriesContext: Codable, Equatable {
        var remoteKey: String
        var remoteIDs: [String]
        var baselineLocal: Int
        var baselineRemote: Int
        var seriesLocal: Int
        var seriesRemote: Int
        var isActive: Bool
        var graceUntil: Date?
        var updatedAt: Date

        var displayedTotals: BlomixPvPH2HTotals {
            BlomixPvPH2HTotals(
                localWins: baselineLocal + seriesLocal,
                remoteWins: baselineRemote + seriesRemote
            )
        }

        /// Série en cours ou grâce post-fin (Elo protégé).
        var protectsDisplay: Bool {
            if isActive { return true }
            if let g = graceUntil, g > Date() { return true }
            return false
        }
    }

    /// Incrémente la série live et met le cache = baseline + série.
    private func applyLiveSeriesOutcome(localWon: Bool, remoteIDs: [String]) -> BlomixPvPH2HTotals {
        let remotes = expandedRemoteIDs(remoteIDs)
        var ctx = liveSeries(forRemoteIDs: remoteIDs)
        if ctx == nil || ctx?.isActive == false {
            let base = historicalTotals(againstRemoteIDs: remotes)
            ctx = LiveSeriesContext(
                remoteKey: sessionStorageKey(forRemoteIDs: remoteIDs),
                remoteIDs: remotes,
                baselineLocal: base.localWins,
                baselineRemote: base.remoteWins,
                seriesLocal: 0,
                seriesRemote: 0,
                isActive: true,
                graceUntil: nil,
                updatedAt: Date()
            )
            print("[H2H] series baseline fallback snapshot \(base.localWins)-\(base.remoteWins)")
        }
        guard var live = ctx else {
            return cachedTotals(againstRemoteIDs: remotes) ?? .zero
        }
        live.isActive = true
        if localWon {
            live.seriesLocal += 1
        } else {
            live.seriesRemote += 1
        }
        live.updatedAt = Date()
        // Ne pas écrire baseline+Δ dans le cache ici : le lock ferait alors +série en double.
        let floorRemotes = Array(remotes.prefix(Self.maxExpandedRemoteIDs))
        var liveToSave = live
        liveToSave.remoteIDs = floorRemotes
        saveLiveSeries(liveToSave)
        return composeDisplayed(historical: historicalTotals(againstRemoteIDs: remotes), live: liveToSave)
    }

    private func liveSeries(forRemoteIDs remoteIDs: [String]) -> LiveSeriesContext? {
        let all = loadLiveSeriesMap()
        let keys = Set(expandedRemoteIDs(remoteIDs) + [sessionStorageKey(forRemoteIDs: remoteIDs)])
        for k in keys {
            if let c = all[k], c.protectsDisplay || c.isActive {
                return c
            }
        }
        // Scan global : l’Elo peut présenter un hex alors que la série était sous A:_…
        let expanded = Set(expandedRemoteIDs(remoteIDs))
        for (_, c) in all where c.protectsDisplay || c.isActive {
            let ctxIDs = Set(expandedRemoteIDs(c.remoteIDs) + [c.remoteKey])
            if !ctxIDs.isDisjoint(with: expanded) {
                return c
            }
        }
        for k in keys {
            if let c = all[k] { return c }
        }
        return nil
    }

    private func saveLiveSeries(_ ctx: LiveSeriesContext) {
        var all = loadLiveSeriesMap()
        var merged = ctx
        // Peu de clés d’indexation (plafond expansion) — pas de duplication ×82.
        let indexIDs = Array(Set(Self.normalizedIDList(ctx.remoteIDs) + expandedRemoteIDs(ctx.remoteIDs)))
            .prefix(Self.maxExpandedRemoteIDs)
        merged.remoteIDs = Array(indexIDs)
        all[merged.remoteKey] = merged
        for rid in merged.remoteIDs {
            all[rid] = merged
        }
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: Self.liveSeriesKey)
        }
    }

    private func clearLiveSeries(forRemoteIDs remoteIDs: [String]) {
        var all = loadLiveSeriesMap()
        if let ctx = liveSeries(forRemoteIDs: remoteIDs) {
            all.removeValue(forKey: ctx.remoteKey)
            for rid in ctx.remoteIDs { all.removeValue(forKey: rid) }
        }
        let keys = expandedRemoteIDs(remoteIDs) + [sessionStorageKey(forRemoteIDs: remoteIDs)]
        for k in keys { all.removeValue(forKey: k) }
        if all.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.liveSeriesKey)
        } else if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: Self.liveSeriesKey)
        }
        print("[H2H] live series cleared")
    }

    private func loadLiveSeriesMap() -> [String: LiveSeriesContext] {
        guard let data = UserDefaults.standard.data(forKey: Self.liveSeriesKey),
              let decoded = try? JSONDecoder().decode([String: LiveSeriesContext].self, from: data)
        else { return [:] }
        return decoded
    }

    private func debugDumpLiveSeries(_ remoteIDs: [String]) -> String {
        guard let l = liveSeries(forRemoteIDs: remoteIDs) else { return "live=nil" }
        return "live base \(l.baselineLocal)-\(l.baselineRemote) +s \(l.seriesLocal)-\(l.seriesRemote) active=\(l.isActive)"
    }

    // MARK: - Committed floor (durable until cloud catches up)

    private struct CommittedFloor: Codable, Equatable {
        var localWins: Int
        var remoteWins: Int
        var remoteIDs: [String]
        var updatedAt: Date

        var totals: BlomixPvPH2HTotals {
            BlomixPvPH2HTotals(localWins: localWins, remoteWins: remoteWins)
        }
    }

    private func commitDisplayFloor(_ totals: BlomixPvPH2HTotals, remoteIDs: [String]) {
        guard totals.hasHistory else { return }
        // Peu de clés : input normalisé + expansion plafonnée (jamais des dizaines).
        let remotes = Array(Set(Self.normalizedIDList(remoteIDs) + expandedRemoteIDs(remoteIDs)))
            .prefix(Self.maxExpandedRemoteIDs)
            .map { $0 }
        var all = loadCommittedFloors()
        let key = sessionStorageKey(forRemoteIDs: Array(remotes))
        let existing = committedFloor(forRemoteIDs: remotes)
        let merged = BlomixPvPH2HTotals(
            localWins: max(totals.localWins, existing?.localWins ?? 0),
            remoteWins: max(totals.remoteWins, existing?.remoteWins ?? 0)
        )
        let floor = CommittedFloor(
            localWins: merged.localWins,
            remoteWins: merged.remoteWins,
            remoteIDs: remotes,
            updatedAt: Date()
        )
        all[key] = floor
        for rid in remotes {
            all[rid] = floor
        }
        saveCommittedFloors(all)
        print("[H2H] committed floor \(merged.localWins)-\(merged.remoteWins) keys=\(remotes.count)")
    }

    private func committedFloor(forRemoteIDs remoteIDs: [String]) -> BlomixPvPH2HTotals? {
        let all = loadCommittedFloors()
        let now = Date()
        // Lookup O(clés connues) sans re-expand chaque floor via aliasRoot global.
        let probe = Set(Self.normalizedIDList(remoteIDs) + expandedRemoteIDs(remoteIDs) + [sessionStorageKey(forRemoteIDs: remoteIDs)])
        var best: CommittedFloor?
        for key in probe {
            guard let f = all[key] else { continue }
            guard now.timeIntervalSince(f.updatedAt) <= Self.committedFloorMaxAge else { continue }
            if let b = best {
                if f.localWins + f.remoteWins > b.localWins + b.remoteWins { best = f }
            } else {
                best = f
            }
        }
        return best?.totals
    }

    private func clearCommittedFloor(forRemoteIDs remoteIDs: [String]) {
        var all = loadCommittedFloors()
        let expanded = Set(expandedRemoteIDs(remoteIDs) + [sessionStorageKey(forRemoteIDs: remoteIDs)])
        for (k, f) in all {
            let fIDs = Set(expandedRemoteIDs(f.remoteIDs) + [k])
            if !fIDs.isDisjoint(with: expanded) || expanded.contains(k) {
                all.removeValue(forKey: k)
            }
        }
        saveCommittedFloors(all)
        print("[H2H] committed floor cleared")
    }

    private func loadCommittedFloors() -> [String: CommittedFloor] {
        guard let data = UserDefaults.standard.data(forKey: Self.committedFloorKey),
              let decoded = try? JSONDecoder().decode([String: CommittedFloor].self, from: data)
        else { return [:] }
        let now = Date()
        return decoded.filter { now.timeIntervalSince($0.value.updatedAt) <= Self.committedFloorMaxAge }
    }

    private func saveCommittedFloors(_ map: [String: CommittedFloor]) {
        if map.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.committedFloorKey)
            return
        }
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: Self.committedFloorKey)
        }
    }

    /// Flush pending jusqu’à vide ou épuisement des tentatives.
    func flushPendingUntilEmptyOrAttempts(maxAttempts: Int) async {
        for attempt in 1...max(1, maxAttempts) {
            await flushPendingEventsAsync()
            let left = loadPending().count
            if left == 0 {
                if attempt > 1 { print("[H2H] pending flush empty after attempt \(attempt)") }
                return
            }
            print("[H2H] pending flush attempt \(attempt)/\(maxAttempts) left=\(left)")
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
    }

    // MARK: - Cloud fetch helper (dédup events)

    private struct CloudSumBundle {
        var sum: BlomixPvPH2HTotals
        var anyHit: Bool
        var querySucceeded: Bool
        var pairKeyAttempted: Int
        var pairKeyFailed: Int
        var winnerIDAttempted: Int = 0
        var winnerIDFailed: Int = 0
        var queryComplete: Bool {
            let attempted = pairKeyAttempted + winnerIDAttempted
            let failed = pairKeyFailed + winnerIDFailed
            return attempted > 0 && failed == 0
        }
    }

    private struct H2HCloudEvent {
        var recordName: String
        var winnerID: String
        var loserID: String
        var pairKey: String
        var clientEventId: String
        var matchId: String
        var reporterId: String
    }

    private func fetchCloudSum(
        localIDs: [String],
        remotes: [String],
        flushFirst: Bool
    ) async -> CloudSumBundle {
        if flushFirst {
            await flushPendingEventsAsync()
        }

        var localSet = Set(localIDs)
        var remoteSet = Set(remotes)
        var unique: [String: H2HCloudEvent] = [:]
        var querySucceeded = false
        var pairKeyAttempted = 0
        var pairKeyFailed = 0

        if BlomixPublicCloudGate.shared.isBlocked {
            return CloudSumBundle(
                sum: .zero, anyHit: false, querySucceeded: false,
                pairKeyAttempted: 0, pairKeyFailed: 0
            )
        }

        // `pairKey` A:_×A:_ d’abord — le prefix lexico prenait souvent 3 clés `T:_` vides
        // alors que l’historique est sous `A:_local|A:_remote` (queryable en Production).
        let pairKeys = rankedPairKeys(localIDs: Array(localSet), remotes: Array(remoteSet))
        print("[H2H] pairKeys try \(pairKeys.map { String($0.prefix(44)) }.joined(separator: " | "))")
        for pair in pairKeys {
            pairKeyAttempted += 1
            do {
                let recs = try await fetchRecords(predicate: NSPredicate(format: "pairKey == %@", pair))
                querySucceeded = true
                mergeCloudRecords(recs, into: &unique)
                if !recs.isEmpty {
                    rememberPairKey(pair)
                    print("[H2H] cloud hit pair=\(String(pair.prefix(44)))… raw=\(recs.count)")
                    break
                } else {
                    print("[H2H] cloud empty pair=\(String(pair.prefix(44)))…")
                }
            } catch {
                pairKeyFailed += 1
                BlomixPublicCloudGate.shared.noteError(error)
                print("[H2H] pairKey query fail pair=\(String(pair.prefix(24)))…: \(error.localizedDescription)")
                if BlomixPublicCloudGate.shared.isBlocked { break }
            }
        }

        func isStrictDuo(_ ev: H2HCloudEvent, loc: Set<String>, rem: Set<String>) -> Bool {
            Self.eventInvolvesDuo(
                winnerID: ev.winnerID,
                loserID: ev.loserID,
                pairKey: ev.pairKey,
                localIDs: loc,
                remoteIDs: rem
            )
        }

        var duoEvents = unique.values.filter { isStrictDuo($0, loc: localSet, rem: remoteSet) }

        // Filet si la pairKey n’a rien donné pour CE duo (`loserID` non queryable).
        var winnerIDAttempted = 0
        var winnerIDFailed = 0
        if duoEvents.isEmpty, !BlomixPublicCloudGate.shared.isBlocked {
            let winnerIDs = Self.normalizedIDList([
                Self.preferredCloudID(from: Array(localSet)),
                Self.preferredCloudID(from: Array(remoteSet))
            ].compactMap { $0 })
            for wid in winnerIDs.prefix(2) {
                winnerIDAttempted += 1
                do {
                    let recs = try await fetchRecords(predicate: NSPredicate(format: "winnerID == %@", wid))
                    querySucceeded = true
                    mergeCloudRecords(recs, into: &unique)
                    print("[H2H] winnerID hit \(debugID(wid)) raw=\(recs.count)")
                } catch {
                    winnerIDFailed += 1
                    BlomixPublicCloudGate.shared.noteError(error)
                    print("[H2H] winnerID query fail \(debugID(wid)): \(error.localizedDescription)")
                    if BlomixPublicCloudGate.shared.isBlocked { break }
                }
            }
            duoEvents = unique.values.filter { isStrictDuo($0, loc: localSet, rem: remoteSet) }
        }

        // Enrichissement borné : IDs alternatifs sur des events déjà reconnus duo.
        for ev in duoEvents {
            rememberPairKey(ev.pairKey)
            if remoteSet.contains(ev.loserID) || localSet.contains(ev.winnerID) {
                localSet.insert(ev.winnerID)
                remoteSet.insert(ev.loserID)
            }
            if localSet.contains(ev.loserID) || remoteSet.contains(ev.winnerID) {
                remoteSet.insert(ev.winnerID)
                localSet.insert(ev.loserID)
            }
        }
        // Re-filtre avec sets enrichis (récupère d’éventuels events orphelins du même duo).
        duoEvents = unique.values.filter { isStrictDuo($0, loc: localSet, rem: remoteSet) }

        let learnedLocal = localSet.subtracting(Set(localIDs))
        let learnedRemote = remoteSet.subtracting(Set(remotes))
        if !learnedLocal.isEmpty {
            registerAliases(Array(learnedLocal) + localIDs)
            print("[H2H] learned local IDs \(learnedLocal.map(debugID).joined(separator: ","))")
        }
        if !learnedRemote.isEmpty {
            registerAliases(Array(learnedRemote) + remotes)
            print("[H2H] learned remote IDs \(learnedRemote.map(debugID).joined(separator: ","))")
        }

        let sum = tallyDuoEvents(duoEvents, localSet: localSet, remoteSet: remoteSet)
        if !duoEvents.isEmpty {
            print("[H2H] cloud events=\(duoEvents.count) matchIds=\(Set(duoEvents.map(\.matchId).filter { !$0.isEmpty }).count) pairsTried=\(pairKeyAttempted) winnerTried=\(winnerIDAttempted) fail=\(pairKeyFailed + winnerIDFailed) → \(sum.localWins)-\(sum.remoteWins)")
        } else {
            print("[H2H] cloud empty after pairs=\(pairKeyAttempted) winnerTried=\(winnerIDAttempted) fail=\(pairKeyFailed + winnerIDFailed)")
        }
        return CloudSumBundle(
            sum: sum,
            anyHit: sum.hasHistory,
            querySucceeded: querySucceeded,
            pairKeyAttempted: pairKeyAttempted,
            pairKeyFailed: pairKeyFailed,
            winnerIDAttempted: winnerIDAttempted,
            winnerIDFailed: winnerIDFailed
        )
    }

    /// 1 `matchId` = 1 point. Records sans matchId (pré-114) : 1 `clientEventId`.
    private func tallyDuoEvents(
        _ events: [H2HCloudEvent],
        localSet: Set<String>,
        remoteSet: Set<String>
    ) -> BlomixPvPH2HTotals {
        var grouped: [String: [H2HCloudEvent]] = [:]
        var legacy: [H2HCloudEvent] = []
        for ev in events {
            let mid = ev.matchId.trimmingCharacters(in: .whitespacesAndNewlines)
            if mid.isEmpty {
                legacy.append(ev)
            } else {
                grouped[mid, default: []].append(ev)
            }
        }
        var localWins = 0
        var remoteWins = 0
        func credit(_ winnerID: String) {
            if Self.isLocalWinner(winnerID: winnerID, localIDs: localSet, remoteIDs: remoteSet) {
                localWins += 1
            } else {
                remoteWins += 1
            }
        }
        for reports in grouped.values {
            credit(Self.resolvedWinnerID(reports: reports))
        }
        for ev in legacy {
            credit(ev.winnerID)
        }
        return BlomixPvPH2HTotals(localWins: localWins, remoteWins: remoteWins)
    }

    /// Accord des reports ; en conflit : majorité, puis winnerID lexico min (déterministe).
    private static func resolvedWinnerID(reports: [H2HCloudEvent]) -> String {
        var votes: [String: Int] = [:]
        for r in reports {
            let w = r.winnerID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !w.isEmpty else { continue }
            votes[w, default: 0] += 1
        }
        if let best = votes.max(by: {
            if $0.value != $1.value { return $0.value < $1.value }
            return $0.key > $1.key
        }) {
            return best.key
        }
        return reports.first?.winnerID ?? ""
    }

    private func mergeCloudRecords(_ records: [CKRecord], into unique: inout [String: H2HCloudEvent]) {
        for rec in records {
            let name = rec.recordID.recordName
            let winner = (rec["winnerID"] as? String) ?? ""
            let loser = (rec["loserID"] as? String) ?? ""
            let pair = (rec["pairKey"] as? String) ?? ""
            let cid = (rec["clientEventId"] as? String) ?? name
            let matchId = (rec["matchId"] as? String) ?? ""
            let reporterId = (rec["reporterId"] as? String) ?? ""
            let key = cid.isEmpty ? name : cid
            guard !winner.isEmpty else { continue }
            unique[key] = H2HCloudEvent(
                recordName: name,
                winnerID: winner,
                loserID: loser,
                pairKey: pair,
                clientEventId: cid,
                matchId: matchId,
                reporterId: reporterId
            )
        }
    }

    private static func eventInvolvesDuo(
        winnerID: String,
        loserID: String,
        pairKey: String,
        localIDs: Set<String>,
        remoteIDs: Set<String>
    ) -> Bool {
        let winLocal = localIDs.contains(winnerID)
        let winRemote = remoteIDs.contains(winnerID)
        let loseLocal = localIDs.contains(loserID)
        let loseRemote = remoteIDs.contains(loserID)
        if (winLocal && loseRemote) || (winRemote && loseLocal) { return true }
        // pairKey historique : les deux IDs du duo.
        let parts = pairKey.split(separator: "|").map(String.init)
        if parts.count == 2 {
            let a = parts[0], b = parts[1]
            let aL = localIDs.contains(a), aR = remoteIDs.contains(a)
            let bL = localIDs.contains(b), bR = remoteIDs.contains(b)
            if (aL && bR) || (aR && bL) { return true }
        }
        return false
    }

    private static func isLocalWinner(
        winnerID: String,
        localIDs: Set<String>,
        remoteIDs: Set<String>
    ) -> Bool {
        if localIDs.contains(winnerID) { return true }
        if remoteIDs.contains(winnerID) { return false }
        // Inconnu : ne pas attribuer au local par défaut.
        return false
    }

    private func fetchRecords(predicate: NSPredicate) async throws -> [CKRecord] {
        let query = CKQuery(recordType: Self.recordType, predicate: predicate)
        var all: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let (batch, next): ([CKRecord], CKQueryOperation.Cursor?) = try await withCheckedThrowingContinuation { cont in
                let op: CKQueryOperation
                if let cursor {
                    op = CKQueryOperation(cursor: cursor)
                } else {
                    op = CKQueryOperation(query: query)
                }
                op.qualityOfService = .utility
                op.resultsLimit = 100
                let box = H2HRecordPage()
                op.recordMatchedBlock = { _, result in
                    if case .success(let rec) = result {
                        box.append(rec)
                    }
                }
                op.queryResultBlock = { result in
                    switch result {
                    case .success(let c):
                        cont.resume(returning: (box.snapshot(), c))
                    case .failure(let err):
                        cont.resume(throwing: err)
                    }
                }
                publicDB.add(op)
            }
            all.append(contentsOf: batch)
            cursor = next
        } while cursor != nil

        return all
    }

    /// Accumulateur thread-safe : `recordMatchedBlock` n’est pas forcément sur le même thread que le completion.
    private final class H2HRecordPage: @unchecked Sendable {
        private let lock = NSLock()
        private var recs: [CKRecord] = []

        func append(_ rec: CKRecord) {
            lock.lock()
            recs.append(rec)
            lock.unlock()
        }

        func snapshot() -> [CKRecord] {
            lock.lock()
            defer { lock.unlock() }
            return recs
        }
    }

    /// Enregistre que plusieurs IDs désignent le même joueur (game ↔ team, Elo ↔ match).
    /// Ne replie **que** les IDs fournis (+ leurs racines directes), pas toute la map d’alias.
    func registerAliases(_ ids: [String]) {
        let clean = Self.normalizedIDList(ids)
        guard clean.count >= 2 else {
            // Même un seul ID : s’assurer qu’il se résout vers lui-même si déjà aliasé autrement — no-op.
            return
        }
        var map = loadAliases()
        let roots = Array(Set(clean.map { Self.aliasRoot($0, map: map) }))
        // Canonique = préférence match-like (A:_), sinon le plus petit lexico pour stabilité.
        let canonical = roots.max(by: { Self.idQueryPriority($0) < Self.idQueryPriority($1) })
            ?? roots.sorted()[0]
        // Uniquement le petit ensemble concerné — pas un scan global de la map (évite de fusionner 80+ IDs).
        for id in clean {
            map[id] = canonical
        }
        for r in roots where r != canonical {
            map[r] = canonical
        }
        // Clés qui pointaient **directement** vers une racine du groupe → canonique.
        for (k, v) in map where roots.contains(v) {
            map[k] = canonical
        }
        saveAliases(map)

        // Répliquer le cache sous le petit groupe (ids + canonique), pas expanded monstre.
        let group = Self.normalizedIDList(clean + [canonical])
        if let best = cachedTotals(againstRemoteIDs: group), best.hasHistory {
            replaceTotals(best, underRemoteIDs: group)
        }
    }

    func flushPendingEventsBestEffort() {
        Task { @MainActor in
            await flushPendingEventsAsync()
        }
    }

    /// Debug / diagnostic cache + pending + session floors (logs Xcode / Console).
    func debugDumpCacheSummary() -> String {
        migrateCacheV1IfNeeded()
        pruneEmptyCacheEntriesIfNeeded()
        let c = loadCacheV2().filter { $0.value.hasHistory }
        let parts = c.map { "\(debugID($0.key)):\($0.value.localWins)-\($0.value.remoteWins)" }
        let aliasCount = loadAliases().count
        let pend = debugDumpPendingSummary()
        let sess = debugDumpSessionSummary()
        return "entries=\(c.count) aliases=\(aliasCount) [\(parts.joined(separator: ", "))] localIDs=\(resolvedLocalPlayerIDs().map(debugID).joined(separator: ",")) \(pend) \(sess)"
    }

    /// Wins locales en attente d’upload CloudKit (ce qui « traîne » sur cet iPhone).
    func debugDumpPendingSummary() -> String {
        let pending = loadPending()
        if pending.isEmpty { return "pending=0" }
        let bits = pending.prefix(12).map { e in
            let age = Int(Date().timeIntervalSince(e.createdAt))
            return "\(e.clientEventId.prefix(8))… ch=\(e.channel) age=\(age)s pair=\(String(e.pairKey.prefix(28)))…"
        }
        let more = pending.count > 12 ? " +\(pending.count - 12) more" : ""
        return "pending=\(pending.count) [\(bits.joined(separator: "; "))]\(more)"
    }

    /// Nombre d’events vainqueur non encore uploadés (diagnostic).
    func pendingUploadCount() -> Int {
        loadPending().count
    }

    func debugDumpSessionSummary(forRemoteIDs remoteIDs: [String] = []) -> String {
        if remoteIDs.isEmpty {
            let all = loadSessionFloors().filter { $0.value.hasOpenSession }
            if all.isEmpty { return "sessionFloors=0" }
            let bits = all.prefix(6).map { "\(debugID($0.key)):\($0.value.floorLocal)-\($0.value.floorRemote)(d\($0.value.deltaLocal)/\($0.value.deltaRemote))" }
            return "sessionFloors=\(all.count) [\(bits.joined(separator: ", "))]"
        }
        guard let s = sessionFloorState(forRemoteIDs: remoteIDs) else { return "session=nil" }
        return "session conf=\(s.confirmedLocal)-\(s.confirmedRemote) Δ=\(s.deltaLocal)/\(s.deltaRemote) floor=\(s.floorLocal)-\(s.floorRemote)"
    }

    // MARK: - Session floor (garde-fou)

    /// État de session pour un adversaire : baseline confirmée + manches locales non encore « rattrapées » par le cloud.
    private struct SessionFloorState: Codable, Equatable {
        var confirmedLocal: Int
        var confirmedRemote: Int
        var deltaLocal: Int
        var deltaRemote: Int
        var updatedAt: Date

        var floorLocal: Int { confirmedLocal + deltaLocal }
        var floorRemote: Int { confirmedRemote + deltaRemote }
        var hasOpenSession: Bool { deltaLocal > 0 || deltaRemote > 0 }
    }

    private func noteSessionOutcome(
        remoteIDs: [String],
        localWon: Bool,
        totalsBefore: BlomixPvPH2HTotals
    ) {
        let key = sessionStorageKey(forRemoteIDs: remoteIDs)
        var all = loadSessionFloors()
        var state = all[key] ?? SessionFloorState(
            confirmedLocal: totalsBefore.localWins,
            confirmedRemote: totalsBefore.remoteWins,
            deltaLocal: 0,
            deltaRemote: 0,
            updatedAt: Date()
        )
        // Première manche de la « session ouverte » : baseline = total avant outcome.
        if !state.hasOpenSession {
            state.confirmedLocal = totalsBefore.localWins
            state.confirmedRemote = totalsBefore.remoteWins
            state.deltaLocal = 0
            state.deltaRemote = 0
        }
        if localWon {
            state.deltaLocal += 1
        } else {
            state.deltaRemote += 1
        }
        state.updatedAt = Date()
        all[key] = state
        // Répliquer sous les alias pour lookup Elo multi-ID.
        for rid in expandedRemoteIDs(remoteIDs) {
            all[rid] = state
        }
        saveSessionFloors(all)
        print("[H2H] session floor note \(localWon ? "W" : "L") → conf \(state.confirmedLocal)-\(state.confirmedRemote) Δ\(state.deltaLocal)/\(state.deltaRemote) floor \(state.floorLocal)-\(state.floorRemote)")
    }

    private func sessionFloorState(forRemoteIDs remoteIDs: [String]) -> SessionFloorState? {
        let all = loadSessionFloors()
        let keys = expandedRemoteIDs(remoteIDs)
        var best: SessionFloorState?
        for k in keys {
            guard let s = all[k] else { continue }
            if Date().timeIntervalSince(s.updatedAt) > Self.sessionFloorMaxAge {
                continue
            }
            if !s.hasOpenSession { continue }
            if let b = best {
                // Garde le plancher le plus haut (sécurité multi-clés).
                if s.floorLocal + s.floorRemote > b.floorLocal + b.floorRemote {
                    best = s
                }
            } else {
                best = s
            }
        }
        return best
    }

    /// Ferme le plancher après un fetch cloud OK (vérité partagée = cloud).
    private func forceCloseSessionFloor(remoteIDs: [String], to displayed: BlomixPvPH2HTotals) {
        var all = loadSessionFloors()
        let cleared = SessionFloorState(
            confirmedLocal: displayed.localWins,
            confirmedRemote: displayed.remoteWins,
            deltaLocal: 0,
            deltaRemote: 0,
            updatedAt: Date()
        )
        let key = sessionStorageKey(forRemoteIDs: remoteIDs)
        all[key] = cleared
        for rid in expandedRemoteIDs(remoteIDs) {
            all[rid] = cleared
        }
        saveSessionFloors(all)
        print("[H2H] session floor closed → conf \(cleared.confirmedLocal)-\(cleared.confirmedRemote) (cloud-truth)")
    }

    private func sessionStorageKey(forRemoteIDs remoteIDs: [String]) -> String {
        let expanded = expandedRemoteIDs(remoteIDs)
        if let pref = Self.preferredCloudID(from: expanded) { return pref }
        return expanded.sorted().first ?? "unknown"
    }

    private func loadSessionFloors() -> [String: SessionFloorState] {
        guard let data = UserDefaults.standard.data(forKey: Self.sessionFloorKey),
              let decoded = try? JSONDecoder().decode([String: SessionFloorState].self, from: data)
        else { return [:] }
        // Purge expirés.
        let now = Date()
        return decoded.filter { now.timeIntervalSince($0.value.updatedAt) <= Self.sessionFloorMaxAge }
    }

    private func saveSessionFloors(_ map: [String: SessionFloorState]) {
        if map.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.sessionFloorKey)
            return
        }
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: Self.sessionFloorKey)
        }
    }

    // MARK: - CloudKit

    private func flushPendingEventsAsync() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        let pending = loadPending()
        guard !pending.isEmpty else { return }

        var remaining: [PendingH2HEvent] = []
        for event in pending {
            do {
                try await saveEventToCloud(event)
                print("[H2H] uploaded \(event.clientEventId.prefix(8))…")
            } catch {
                print("[H2H] upload fail (kept pending): \(error.localizedDescription)")
                remaining.append(event)
            }
        }
        savePending(remaining)
    }

    private func saveEventToCloud(_ event: PendingH2HEvent) async throws {
        let recID = CKRecord.ID(recordName: "h2h_\(event.clientEventId)")
        let record = CKRecord(recordType: Self.recordType, recordID: recID)
        record["pairKey"] = event.pairKey as CKRecordValue
        record["winnerID"] = event.winnerID as CKRecordValue
        record["loserID"] = event.loserID as CKRecordValue
        record["channel"] = event.channel as CKRecordValue
        record["clientEventId"] = event.clientEventId as CKRecordValue
        record["createdAt"] = event.createdAt as CKRecordValue
        if let mid = event.matchId, !mid.isEmpty {
            record["matchId"] = mid as CKRecordValue
        }
        if let rid = event.reporterId, !rid.isEmpty {
            record["reporterId"] = rid as CKRecordValue
        }

        do {
            _ = try await publicDB.save(record)
            rememberPairKey(event.pairKey)
            BlomixPublicCloudGate.shared.noteSuccess()
        } catch {
            if isIdempotentCloudSuccess(error) {
                rememberPairKey(event.pairKey)
                return
            }
            BlomixPublicCloudGate.shared.noteError(error)
            throw error
        }
    }

    private func isIdempotentCloudSuccess(_ error: Error) -> Bool {
        if let ck = error as? CKError {
            switch ck.code {
            case .serverRecordChanged, .batchRequestFailed, .partialFailure:
                // Record déjà présent (re-flush / clientEventId stable) → succès.
                return true
            default:
                break
            }
        }
        let msg = error.localizedDescription.lowercased()
        return msg.contains("already exists")
            || msg.contains("duplicate")
            || msg.contains("unique")
            || msg.contains("server record changed")
    }

    // MARK: - Known pairKeys

    private func rememberPairKey(_ pairKey: String) {
        let p = pairKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard p.contains("|") else { return }
        var set = loadKnownPairKeys()
        guard set.insert(p).inserted else { return }
        saveKnownPairKeys(set)
    }

    private func loadKnownPairKeys() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: Self.knownPairKeysKey),
              let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(arr)
    }

    private func saveKnownPairKeys(_ set: Set<String>) {
        let arr = Array(set).sorted()
        if arr.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.knownPairKeysKey)
            return
        }
        if let data = try? JSONEncoder().encode(arr) {
            UserDefaults.standard.set(data, forKey: Self.knownPairKeysKey)
        }
    }

    /// pairKeys candidats pour ce duo (IDs live × connus × pending).
    private func candidatePairKeys(localIDs: [String], remotes: [String]) -> [String] {
        var keys = Set<String>()
        for local in localIDs {
            for remote in remotes {
                if let p = Self.pairKey(localID: local, remoteID: remote) {
                    keys.insert(p)
                }
            }
        }
        let localSet = Set(localIDs)
        let remoteSet = Set(remotes)
        for pk in loadKnownPairKeys() {
            let parts = pk.split(separator: "|").map(String.init)
            guard parts.count == 2 else { continue }
            let a = parts[0], b = parts[1]
            let touchesLocal = localSet.contains(a) || localSet.contains(b)
            let touchesRemote = remoteSet.contains(a) || remoteSet.contains(b)
            if touchesLocal && touchesRemote {
                keys.insert(pk)
            }
        }
        for event in loadPending() {
            let parts = event.pairKey.split(separator: "|").map(String.init)
            guard parts.count == 2 else { continue }
            let a = parts[0], b = parts[1]
            if (localSet.contains(a) || localSet.contains(b))
                && (remoteSet.contains(a) || remoteSet.contains(b)
                    || remoteSet.contains(event.loserID) || localSet.contains(event.winnerID)) {
                keys.insert(event.pairKey)
            }
        }
        return keys.sorted()
    }

    /// `A:_`×`A:_` (historique prod) avant les variantes `T:_` — plus de `sorted().prefix(3)` lexico.
    private func rankedPairKeys(localIDs: [String], remotes: [String]) -> [String] {
        var keys = Set(candidatePairKeys(localIDs: localIDs, remotes: remotes))
        if let loc = Self.preferredCloudID(from: localIDs),
           let rem = Self.preferredCloudID(from: remotes),
           let preferred = Self.pairKey(localID: loc, remoteID: rem) {
            keys.insert(preferred)
        }
        let ranked = keys.sorted { a, b in
            let sa = Self.pairKeyQueryScore(a)
            let sb = Self.pairKeyQueryScore(b)
            if sa != sb { return sa > sb }
            return a < b
        }
        return Array(ranked.prefix(3))
    }

    /// 2 × `A:_` = meilleur score. Les clés `T:_`×`T:_` passent après.
    private static func pairKeyQueryScore(_ pair: String) -> Int {
        let parts = pair.split(separator: "|").map(String.init)
        guard parts.count == 2 else { return 0 }
        var score = 0
        for part in parts {
            if part.hasPrefix("A:_") {
                score += 10
            } else if part.hasPrefix("T:_") || part.hasPrefix("G:") {
                score += 3
            } else if part.contains(":") {
                score += 1
            }
        }
        return score
    }

    // MARK: - Identity

    /// Tous les IDs locaux utiles pour pairKey / winnerID (game puis team).
    private func resolvedLocalPlayerIDs() -> [String] {
        var raw: [String] = []
        let live = GKLocalPlayer.local
        raw.append(live.gamePlayerID)
        raw.append(live.teamPlayerID)
        if let cached = BlomixEloManager.shared.cachedLocalGameIdentity()?.gamePlayerID {
            raw.append(cached)
        }
        return Self.normalizedIDList(raw)
    }

    /// Priorité de tentative query / écriture : IDs style match `A:_…` d’abord (historique cloud).
    private static func idQueryPriority(_ id: String) -> Int {
        if id.hasPrefix("A:_") || id.hasPrefix("G:") || id.hasPrefix("T:") { return 3 }
        if id.contains(":") { return 2 }
        return 1
    }

    /// ID préféré pour pairKey / winnerID / loserID (stable avec l’historique prod).
    private static func preferredCloudID(from ids: [String]) -> String? {
        let clean = normalizedIDList(ids)
        guard !clean.isEmpty else { return nil }
        return clean.max(by: {
            if idQueryPriority($0) != idQueryPriority($1) {
                return idQueryPriority($0) < idQueryPriority($1)
            }
            // À priorité égale : lexico plus petit (déterministe).
            return $0 > $1
        })
    }

    /// `clientEventId` cloud : stable si `matchEventKey` fourni (idempotence), sinon UUID.
    private static func stableClientEventId(
        matchEventKey: String?,
        pairKey: String,
        winnerID: String
    ) -> String {
        let raw = (matchEventKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return UUID().uuidString }
        let material = "\(pairKey)|\(winnerID)|\(raw)"
        // UUID-like déterministe (32 hex) — recordName `h2h_<id>` reste unique par manche.
        let digest = Self.fnv1a64(material)
        let hex = String(digest, radix: 16, uppercase: true)
        return "M" + hex.padding(toLength: 15, withPad: "0", startingAt: 0) + String(material.count, radix: 16)
    }

    private static func fnv1a64(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for b in string.utf8 {
            hash ^= UInt64(b)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    /// Nombre de wins locales encore en pending pour ce duo (après flush partiel).
    private func pendingLocalWins(localIDs: Set<String>, remoteIDs: Set<String>) -> Int {
        let pending = loadPending()
        guard !pending.isEmpty else { return 0 }
        var n = 0
        for event in pending {
            guard localIDs.contains(event.winnerID) else { continue }
            // loserID doit être l’adversaire (ou un de ses alias déjà dans remoteIDs).
            if remoteIDs.contains(event.loserID) {
                n += 1
                continue
            }
            // pairKey contient les deux IDs triés.
            let parts = event.pairKey.split(separator: "|").map(String.init)
            if parts.count == 2 {
                let a = parts[0], b = parts[1]
                let touchesLocal = localIDs.contains(a) || localIDs.contains(b)
                let touchesRemote = remoteIDs.contains(a) || remoteIDs.contains(b)
                if touchesLocal && touchesRemote { n += 1 }
            }
        }
        return n
    }

    private static func isUsablePlayerID(_ id: String) -> Bool {
        let t = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        if t == "GKPlayerIDUnknown" { return false }
        return true
    }

    private static func normalizedIDList(_ ids: [String]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for id in ids {
            let t = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isUsablePlayerID(t), seen.insert(t).inserted else { continue }
            out.append(t)
        }
        return out
    }

    /// Plafond strict : un adversaire = game + team + quelques alias, jamais des dizaines de clés.
    /// (Bug build ≤101 : scan global de la map d’alias → `keys=82` → freeze MainActor 20–25 s.)
    private static let maxExpandedRemoteIDs = 8

    /// IDs sous lesquels lire/écrire le cache pour un adversaire.
    /// **Direct seulement** : id fourni, racine d’alias, clés qui mappent *directement* vers la racine.
    /// Ne parcourt plus toute la map avec `aliasRoot` (O(n) × coût de chaîne → freeze UI).
    private func expandedRemoteIDs(_ remoteIDs: [String]) -> [String] {
        let map = loadAliases()
        var seen = Set<String>()
        var out: [String] = []
        func append(_ s: String) {
            guard Self.isUsablePlayerID(s), seen.insert(s).inserted else { return }
            out.append(s)
        }
        for id in Self.normalizedIDList(remoteIDs) {
            let root = Self.aliasRoot(id, map: map)
            append(id)
            append(root)
            // Alias directs uniquement (pas de fermeture transitive sur toute la map).
            for (k, v) in map where v == root || v == id || k == root {
                append(k)
                if out.count >= Self.maxExpandedRemoteIDs { return out }
            }
            if out.count >= Self.maxExpandedRemoteIDs { return out }
        }
        return out
    }

    /// IDs match + Elo + récents au même nom + dernier adversaire — une seule baseline par duo.
    private func augmentedRemoteIDs(_ remoteIDs: [String], displayName: String?) -> [String] {
        var ids = Self.normalizedIDList(remoteIDs)
        if let raw = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let lower = raw.lowercased()
            for recent in BlomixRecentOpponentsCache.shared.all() {
                if recent.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lower {
                    ids.append(recent.gamePlayerID)
                }
            }
            if let last = lastOpponentDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
               last.lowercased() == lower {
                ids.append(lastOpponentGameID)
                ids.append(lastOpponentTeamID)
            }
            bridgeAliasesUsingDisplayName(raw, eloIDs: ids)
        }
        registerAliases(ids)
        return expandedRemoteIDs(ids)
    }

    /// Pont de secours : même displayName qu’un adversaire récent (ID match `A:_…`).
    private func bridgeAliasesUsingDisplayName(_ displayName: String, eloIDs: [String]) {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let recent = BlomixRecentOpponentsCache.shared.all()
        let matches = recent.filter {
            $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(name) == .orderedSame
        }
        guard !matches.isEmpty else { return }
        var ids = eloIDs
        for m in matches {
            ids.append(m.gamePlayerID)
        }
        // Aussi : si le cache a une seule entrée avec historique et le nom matche via recent → déjà couvert.
        registerAliases(ids)
        print("[H2H] alias via displayName «\(name)» → \(Self.normalizedIDList(ids).map(debugID).joined(separator: ","))")
    }

    private func debugID(_ id: String) -> String {
        guard !id.isEmpty else { return "∅" }
        if id.count <= 14 { return id }
        return String(id.prefix(10)) + "…" + String(id.suffix(4))
    }

    private func describeCache(_ remoteID: String) -> String {
        if let t = cachedTotals(againstRemoteIDs: [remoteID]), t.hasHistory {
            return "\(t.localWins)-\(t.remoteWins)"
        }
        return "nil"
    }

    // MARK: - Cache v2 (remoteID → totals)

    private struct PendingH2HEvent: Codable, Equatable {
        var clientEventId: String
        var pairKey: String
        var winnerID: String
        var loserID: String
        var channel: String
        var createdAt: Date
        var matchId: String?
        var reporterId: String?
    }

    private func loadCacheV2() -> [String: BlomixPvPH2HTotals] {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKeyV2),
              let decoded = try? JSONDecoder().decode([String: BlomixPvPH2HTotals].self, from: data)
        else { return [:] }
        return decoded
    }

    private func saveCacheV2(_ cache: [String: BlomixPvPH2HTotals]) {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: Self.cacheKeyV2)
        }
    }

    /// Snapshot cloud : **même** total sous toutes les clés du duo (plus de max entre clés).
    private func replaceTotals(_ totals: BlomixPvPH2HTotals, underRemoteIDs remoteIDs: [String]) {
        var cache = loadCacheV2()
        var keys = Set(expandedRemoteIDs(remoteIDs) + Self.normalizedIDList([lastOpponentGameID, lastOpponentTeamID]))
        let aliases = loadAliases()
        let roots = Set(keys.map { Self.aliasRoot($0, map: aliases) })
        for (k, _) in cache where roots.contains(Self.aliasRoot(k, map: aliases)) {
            keys.insert(k)
            if keys.count > 16 { break }
        }
        if totals.hasHistory {
            for rid in keys {
                cache[rid] = totals
            }
        } else {
            for rid in keys {
                cache.removeValue(forKey: rid)
            }
        }
        cache = cache.filter { $0.value.hasHistory }
        saveCacheV2(cache)
    }

    private func clearTotals(underRemoteIDs remoteIDs: [String]) {
        replaceTotals(.zero, underRemoteIDs: remoteIDs)
    }

    private func pruneEmptyCacheEntriesIfNeeded() {
        guard !didPruneEmpty else { return }
        didPruneEmpty = true
        let cache = loadCacheV2()
        let pruned = cache.filter { $0.value.hasHistory }
        if pruned.count != cache.count {
            saveCacheV2(pruned)
            print("[H2H] pruned empty cache entries \(cache.count)→\(pruned.count)")
        }
    }

    /// Migre l’ancien cache pairKey → remoteID (POV local).
    private func migrateCacheV1IfNeeded() {
        guard !didMigrateCache else { return }
        didMigrateCache = true
        guard UserDefaults.standard.data(forKey: Self.cacheKeyV2) == nil,
              let data = UserDefaults.standard.data(forKey: Self.cacheKeyV1),
              let old = try? JSONDecoder().decode([String: BlomixPvPH2HTotals].self, from: data),
              !old.isEmpty
        else { return }

        let localIDs = Set(resolvedLocalPlayerIDs())
        var neu: [String: BlomixPvPH2HTotals] = [:]
        for (pair, totals) in old {
            let parts = pair.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2 else { continue }
            let a = parts[0], b = parts[1]
            let remote: String
            if localIDs.contains(a) {
                remote = b
            } else if localIDs.contains(b) {
                remote = a
            } else {
                continue
            }
            guard !remote.isEmpty else { continue }
            if let existing = neu[remote] {
                neu[remote] = existing.merging(totals)
            } else {
                neu[remote] = totals
            }
        }
        if !neu.isEmpty {
            saveCacheV2(neu)
            print("[H2H] migrated cache v1→v2 entries=\(neu.count)")
        }
    }

    // MARK: - Aliases

    private func loadAliases() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: Self.aliasKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded
    }

    private func saveAliases(_ map: [String: String]) {
        if map.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.aliasKey)
            return
        }
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: Self.aliasKey)
        }
    }

    private static func aliasRoot(_ id: String, map: [String: String]) -> String {
        var current = id
        var guardCounter = 0
        while let next = map[current], next != current, guardCounter < 16 {
            current = next
            guardCounter += 1
        }
        return current
    }

    // MARK: - Pending

    private func loadPending() -> [PendingH2HEvent] {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingKey),
              let decoded = try? JSONDecoder().decode([PendingH2HEvent].self, from: data)
        else { return [] }
        return decoded
    }

    private func savePending(_ events: [PendingH2HEvent]) {
        if events.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.pendingKey)
            return
        }
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: Self.pendingKey)
        }
    }

    private func enqueuePending(_ event: PendingH2HEvent) {
        var pending = loadPending()
        if pending.contains(where: { $0.clientEventId == event.clientEventId }) { return }
        pending.append(event)
        if pending.count > 100 {
            pending = Array(pending.suffix(100))
        }
        savePending(pending)
    }
}
