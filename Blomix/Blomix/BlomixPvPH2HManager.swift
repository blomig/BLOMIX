//
//  BlomixPvPH2HManager.swift
//  Blomix
//
//  Historique tête-à-tête PvP (1 point = 1 manche gagnée) via CloudKit Public DB.
//
//  Isolation stricte : tout est best-effort / async. Un échec n’affecte que l’affichage
//  du total H2H — jamais le match, l’Elo, la série session ou la reconnexion.
//
//  Schéma CloudKit (Record Type `PvPH2HEvent`, Public DB) — à déployer en prod :
//    pairKey        String   Queryable
//    winnerID       String
//    loserID        String
//    channel        String   ("online" | "local")
//    clientEventId  String
//    createdAt      Date
//  recordName = "h2h_{clientEventId}" (créateur = vainqueur → WRITE OK).
//
//  Identité : GameKit expose parfois des chaînes différentes selon l’API
//  (`GKMatch` vs `GKLeaderboard.Entry`) pour le même joueur (`gamePlayerID` vs
//  `teamPlayerID`, formats `A:_…` vs hex). Le cache est multi-clés + alias ;
//  les queries cloud tentent les combinaisons d’IDs locaux/distants.
//
//  Modèle produit (v5.9 build 91+) — cumul H2H **sans freeze gameplay** :
//
//  1) **Baseline** au lancement série = **cache local only** (0 réseau).
//  2) **Pendant le match live** : **aucun** fetchCloudSum / flush multi / CloudKit H2H.
//  3) **Fin de série** : LOCK baseline+série + committed floor ; flush pending **léger**.
//  4) **Elo / hors partie** : seul endroit pour fetchCloudSum (agrégation cloud).
//  5) Uploads winner-only : 1 flush best-effort en fin de manche, pas une rafale.
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
    private var lastCloudReconcileAt: Date?
    private static let homeReconcileMinInterval: TimeInterval = 20
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
                self?.flushPendingEventsBestEffort()
                // Juge 1 duo hors écran Elo (sinon freeze serpent / scroll).
                self?.scheduleHomeReconcileAfterReturnToMenu()
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

    /// Snapshot filaire (2 ints) pour merge max au contact PvP. Lecture cache pure, 0 CloudKit.
    func wireSnapshot(
        remoteGamePlayerID: String,
        remoteTeamPlayerID: String? = nil
    ) -> (myWins: Int, theirWins: Int) {
        let remoteIDs = Self.normalizedIDList([remoteGamePlayerID, remoteTeamPlayerID ?? ""])
        let t = displayedTotalsPreferringLive(againstRemoteIDs: remoteIDs)
        return (t.localWins, t.remoteWins)
    }

    /// Merge max avec le snapshot du peer (event rare).
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

        let ours = displayedTotalsPreferringLive(againstRemoteIDs: remotes)
        let merged = BlomixPvPH2HTotals(
            localWins: max(ours.localWins, max(0, peerClaimsOurWins)),
            remoteWins: max(ours.remoteWins, max(0, peerOwnWins))
        )
        guard merged != ours else {
            print("[H2H] peer snapshot no-op \(ours.localWins)-\(ours.remoteWins)")
            return
        }

        // Série déjà en cours : on ne touche qu’à la baseline (garde les Δ série).
        if var live = liveSeries(forRemoteIDs: remotes),
           live.isActive,
           live.seriesLocal + live.seriesRemote > 0 {
            live.baselineLocal = max(live.baselineLocal, max(0, merged.localWins - live.seriesLocal))
            live.baselineRemote = max(live.baselineRemote, max(0, merged.remoteWins - live.seriesRemote))
            live.updatedAt = Date()
            saveLiveSeries(live)
            let disp = live.displayedTotals
            replaceTotals(disp, underRemoteIDs: remotes)
            commitDisplayFloor(disp, remoteIDs: remotes)
            print("[H2H] peer max-merge mid-series → base \(live.baselineLocal)-\(live.baselineRemote) disp \(disp.localWins)-\(disp.remoteWins)")
            return
        }

        replaceTotals(merged, underRemoteIDs: remotes)
        commitDisplayFloor(merged, remoteIDs: remotes)
        if var live = liveSeries(forRemoteIDs: remotes), live.isActive {
            live.baselineLocal = merged.localWins
            live.baselineRemote = merged.remoteWins
            live.updatedAt = Date()
            saveLiveSeries(live)
        } else if liveSeries(forRemoteIDs: remotes) == nil {
            let ctx = LiveSeriesContext(
                remoteKey: sessionStorageKey(forRemoteIDs: remotes),
                remoteIDs: remotes,
                baselineLocal: merged.localWins,
                baselineRemote: merged.remoteWins,
                seriesLocal: 0,
                seriesRemote: 0,
                isActive: true,
                graceUntil: nil,
                updatedAt: Date()
            )
            saveLiveSeries(ctx)
        }
        print("[H2H] peer max-merge \(ours.localWins)-\(ours.remoteWins) + peer claims us=\(peerClaimsOurWins) them=\(peerOwnWins) → \(merged.localWins)-\(merged.remoteWins)")
    }

    /// Une seule vérité d’affichage (récap, Duel, baseline série) : max(live, cache, plancher).
    /// Jamais de lecture CloudKit. Ne redescend pas sous un cumul déjà connu.
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

    /// Totaux à afficher : max(live protégé, cache, committed) — jamais le plus bas seul.
    private func displayedTotalsPreferringLive(againstRemoteIDs remoteIDs: [String]) -> BlomixPvPH2HTotals {
        let remotes = expandedRemoteIDs(remoteIDs)
        let cache = cachedTotals(againstRemoteIDs: remotes) ?? .zero
        let committed = committedFloor(forRemoteIDs: remotes) ?? .zero
        var best = BlomixPvPH2HTotals(
            localWins: max(cache.localWins, committed.localWins),
            remoteWins: max(cache.remoteWins, committed.remoteWins)
        )
        if let live = liveSeries(forRemoteIDs: remotes), live.protectsDisplay {
            let d = live.displayedTotals
            best = BlomixPvPH2HTotals(
                localWins: max(best.localWins, d.localWins),
                remoteWins: max(best.remoteWins, d.remoteWins)
            )
        }
        return best
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

    /// Lecture **légère** pour le tableau Elo : 1 decode cache/live/floor/alias, puis lookups.
    /// Alias **en mémoire uniquement** (pas d’écriture). 0 CloudKit.
    func precomputedLightTotals(idGroups: [[String]], displayNames: [String] = []) -> [String: BlomixPvPH2HTotals] {
        migrateCacheV1IfNeeded()
        let cache = loadCacheV2()
        let lives = loadLiveSeriesMap()
        let floors = loadCommittedFloors()
        let aliases = loadAliases()
        let lastKeys = Set(Self.normalizedIDList([lastOpponentGameID, lastOpponentTeamID]))
        let lastName = lastOpponentDisplayName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
            if !lastName.isEmpty, index < displayNames.count {
                let rowName = displayNames[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if !rowName.isEmpty, rowName.caseInsensitiveCompare(lastName) == .orderedSame {
                    keys.formUnion(lastKeys)
                }
            }
            var best = BlomixPvPH2HTotals.zero
            for k in keys {
                if let t = cache[k] { best = best.merging(t) }
                if let f = floors[k], f.totals.hasHistory { best = best.merging(f.totals) }
                if let live = lives[k], live.protectsDisplay {
                    best = best.merging(live.displayedTotals)
                }
            }
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
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
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
    func seedSeriesBaselineFromCache(
        remoteGamePlayerID: String,
        remoteTeamPlayerID: String? = nil,
        displayName: String? = nil
    ) {
        registerLifecycleIfNeeded()
        migrateCacheV1IfNeeded()
        let remoteIDs = Self.normalizedIDList([remoteGamePlayerID, remoteTeamPlayerID ?? ""])
        guard !remoteIDs.isEmpty else { return }
        if let name = displayName { bridgeAliasesUsingDisplayName(name, eloIDs: remoteIDs) }
        registerAliases(remoteIDs)

        if let live = liveSeries(forRemoteIDs: remoteIDs),
           live.isActive,
           live.seriesLocal + live.seriesRemote > 0 {
            return
        }

        let remotes = expandedRemoteIDs(remoteIDs)
        // Toujours repartir du max(cache, committed) — pas d’un live series « mort » avec anciens Δ.
        let base = displayedTotalsPreferringLive(againstRemoteIDs: remotes)
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
        print("[H2H] series baseline seed \(base.localWins)-\(base.remoteWins) (cache+committed max)")
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
        let remotes = expandedRemoteIDs(remoteIDs)
        let live = liveSeries(forRemoteIDs: remoteIDs)
        let known = displayedTotalsPreferringLive(againstRemoteIDs: remotes)
        let seriesL = max(0, seriesLocalWins)
        let seriesR = max(0, seriesRemoteWins)
        let liveDisp = live?.displayedTotals
        let final: BlomixPvPH2HTotals
        if let live, let liveDisp,
           known.localWins == liveDisp.localWins,
           known.remoteWins == liveDisp.remoteWins {
            // Cache / live déjà = baseline + Δ : ne pas rajouter la série.
            final = known
        } else {
            let hist = BlomixPvPH2HTotals(
                localWins: max(known.localWins, live?.baselineLocal ?? 0),
                remoteWins: max(known.remoteWins, live?.baselineRemote ?? 0)
            )
            final = BlomixPvPH2HTotals(
                localWins: hist.localWins + seriesL,
                remoteWins: hist.remoteWins + seriesR
            )
        }
        let baseline = BlomixPvPH2HTotals(
            localWins: max(0, final.localWins - seriesL),
            remoteWins: max(0, final.remoteWins - seriesR)
        )
        let indexIDs = Array(Set(Self.normalizedIDList([remoteGamePlayerID, remoteTeamPlayerID ?? ""]) + remotes))
            .prefix(Self.maxExpandedRemoteIDs)
            .map { $0 }
        let ctx = LiveSeriesContext(
            remoteKey: sessionStorageKey(forRemoteIDs: indexIDs),
            remoteIDs: indexIDs,
            baselineLocal: final.localWins,
            baselineRemote: final.remoteWins,
            seriesLocal: 0,
            seriesRemote: 0,
            isActive: false,
            graceUntil: Date().addingTimeInterval(Self.seriesGraceDuration),
            updatedAt: Date()
        )
        // Totaux **calculés en mémoire** tout de suite (UI récap).
        // Persistance UserDefaults **différée** pour ne pas bloquer le present.
        print("[H2H] series-end LOCK \(final.localWins)-\(final.remoteWins) (base \(baseline.localWins)-\(baseline.remoteWins) + série \(seriesL)-\(seriesR)) flush=\(flushPending) keys=\(indexIDs.count)")
        let persistFinal = final
        let persistCtx = ctx
        let doFlush = flushPending
        Task { @MainActor in
            self.saveLiveSeries(persistCtx)
            self.replaceTotals(persistFinal, underRemoteIDs: persistCtx.remoteIDs)
            self.commitDisplayFloor(persistFinal, remoteIDs: persistCtx.remoteIDs)
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
        matchEventKey: String? = nil
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

        guard localWon else { return }

        let clientEventId = Self.stableClientEventId(matchEventKey: matchEventKey, pairKey: pair, winnerID: primaryLocal)
        // Idempotence : déjà en pending.
        if loadPending().contains(where: { $0.clientEventId == clientEventId }) {
            print("[H2H] win already pending event=\(clientEventId.prefix(12))…")
            return
        }

        let event = PendingH2HEvent(
            clientEventId: clientEventId,
            pairKey: pair,
            winnerID: primaryLocal,
            loserID: primaryRemote,
            channel: channel,
            createdAt: Date()
        )
        enqueuePending(event)
        print("[H2H] win queued event=\(event.clientEventId.prefix(12))… (no flush in-match)")
        // Flush uniquement hors partie (didBecomeActive / fin de série / ouverture Elo).
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
        let cache = loadCacheV2()
        var best: BlomixPvPH2HTotals?
        for key in keys {
            guard let t = cache[key] else { continue }
            best = best.map { $0.merging(t) } ?? t
        }
        return best
    }

    /// Rafraîchit depuis CloudKit (toutes combinaisons d’IDs plausibles). Ne throw pas vers l’UI.
    func refreshTotals(against remoteGamePlayerID: String) async -> BlomixPvPH2HTotals? {
        await refreshTotals(againstRemoteIDs: [remoteGamePlayerID], displayName: nil)
    }

    func refreshTotals(
        againstRemoteIDs remoteIDs: [String],
        displayName: String? = nil
    ) async -> BlomixPvPH2HTotals? {
        migrateCacheV1IfNeeded()
        if let displayName {
            bridgeAliasesUsingDisplayName(displayName, eloIDs: remoteIDs)
        }
        registerAliases(remoteIDs)

        let remotes = expandedRemoteIDs(remoteIDs)
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
        let live = liveSeries(forRemoteIDs: remotes)
        let liveFloor = live.flatMap { $0.protectsDisplay ? $0.displayedTotals : nil }
        let committed = committedFloor(forRemoteIDs: remotes)
        // Plancher d’affichage = max(série live, cumul session verrouillé durable).
        let seriesFloor: BlomixPvPH2HTotals? = {
            switch (liveFloor, committed) {
            case let (l?, c?):
                return BlomixPvPH2HTotals(
                    localWins: max(l.localWins, c.localWins),
                    remoteWins: max(l.remoteWins, c.remoteWins)
                )
            case let (l?, nil): return l
            case let (nil, c?): return c
            default: return nil
            }
        }()

        // Flush agressif pour pousser les wins avant lecture vérité cloud.
        await flushPendingUntilEmptyOrAttempts(maxAttempts: 4)
        var pendingLeft = pendingLocalWins(localIDs: Set(localIDs), remoteIDs: Set(remotes))
        if pendingLeft > 0 {
            print("[H2H] pending still \(pendingLeft) — \(debugDumpPendingSummary())")
        }

        var cloudBundle = await fetchCloudSum(
            localIDs: localIDs,
            remotes: remotes,
            flushFirst: false
        )
        // Re-essai si cloud sous le plancher (uploads en vol).
        if let floor = seriesFloor, cloudBundle.querySucceeded {
            let c = cloudBundle.sum
            if c.localWins < floor.localWins || c.remoteWins < floor.remoteWins || pendingLeft > 0 {
                print("[H2H] cloud \(c.localWins)-\(c.remoteWins) < floor \(floor.localWins)-\(floor.remoteWins) — extra flush+query")
                try? await Task.sleep(nanoseconds: 500_000_000)
                await flushPendingUntilEmptyOrAttempts(maxAttempts: 3)
                cloudBundle = await fetchCloudSum(
                    localIDs: localIDs,
                    remotes: remotes,
                    flushFirst: false
                )
                pendingLeft = pendingLocalWins(localIDs: Set(localIDs), remoteIDs: Set(remotes))
            }
        }

        if cloudBundle.querySucceeded {
            let cloud = cloudBundle.sum
            let total: BlomixPvPH2HTotals
            if let floor = seriesFloor, floor.hasHistory {
                let cloudGames = cloud.localWins + cloud.remoteWins
                let floorGames = floor.localWins + floor.remoteWins
                // Query vide / autre pairKey : 1–0 vs 34–34. Ne pas effacer l’historique.
                let cloudLooksComplete = cloud.hasHistory && cloudGames + 2 >= floorGames
                if pendingLeft == 0, cloudLooksComplete {
                    // Juge : pending vides + cloud plausible → le cloud a raison (corrige un +1 fantôme).
                    total = cloud
                    clearLiveSeries(forRemoteIDs: remotes)
                    clearCommittedFloor(forRemoteIDs: remotes)
                    print("[H2H] reconcile CLOUD-JUDGE \(total.localWins)-\(total.remoteWins) (was floor \(floor.localWins)-\(floor.remoteWins))")
                } else {
                    // Uploads encore en vol, ou lecture partielle : ne pas redescendre.
                    total = BlomixPvPH2HTotals(
                        localWins: max(cloud.localWins, floor.localWins),
                        remoteWins: max(cloud.remoteWins, floor.remoteWins)
                    )
                    if cloud.localWins >= floor.localWins && cloud.remoteWins >= floor.remoteWins {
                        clearLiveSeries(forRemoteIDs: remotes)
                        clearCommittedFloor(forRemoteIDs: remotes)
                        print("[H2H] reconcile CLOUD+FLOOR synced \(total.localWins)-\(total.remoteWins) (floors cleared)")
                    } else {
                        print("[H2H] reconcile CLOUD+FLOOR floor \(floor.localWins)-\(floor.remoteWins) cloud \(cloud.localWins)-\(cloud.remoteWins) → \(total.localWins)-\(total.remoteWins) pending=\(pendingLeft)")
                    }
                }
            } else if let prev = previous, prev.hasHistory {
                // Pas de live/committed trouvé : quand même ne pas écraser 34–34 par un cloud 28–30.
                let cloudGames = cloud.localWins + cloud.remoteWins
                let prevGames = prev.localWins + prev.remoteWins
                let cloudLooksComplete = cloud.hasHistory && cloudGames + 2 >= prevGames
                if pendingLeft == 0, cloudLooksComplete {
                    total = cloud
                    print("[H2H] reconcile CLOUD-JUDGE (no floor) \(total.localWins)-\(total.remoteWins) prev \(prev.localWins)-\(prev.remoteWins)")
                } else {
                    total = BlomixPvPH2HTotals(
                        localWins: max(cloud.localWins, prev.localWins),
                        remoteWins: max(cloud.remoteWins, prev.remoteWins)
                    )
                    print("[H2H] reconcile CLOUD+CACHE prev \(prev.localWins)-\(prev.remoteWins) cloud \(cloud.localWins)-\(cloud.remoteWins) → \(total.localWins)-\(total.remoteWins)")
                }
            } else {
                total = cloud
                print("[H2H] reconcile CLOUD-TRUTH \(total.localWins)-\(total.remoteWins) prev \(previous.map { "\($0.localWins)-\($0.remoteWins)" } ?? "nil")")
            }
            if total.hasHistory {
                replaceTotals(total, underRemoteIDs: remotes)
                NotificationCenter.default.post(name: .blomixH2HCacheDidChange, object: nil)
            } else if seriesFloor == nil {
                clearTotals(underRemoteIDs: remotes)
            }
            forceCloseSessionFloor(remoteIDs: remotes, to: total)
            return total.hasHistory ? total : nil
        }

        // ── Offline : floor > cache ──
        if let floor = seriesFloor, floor.hasHistory {
            replaceTotals(floor, underRemoteIDs: remotes)
            print("[H2H] refresh OFFLINE floor \(floor.localWins)-\(floor.remoteWins)")
            return floor
        }
        if let previous, previous.hasHistory {
            print("[H2H] refresh OFFLINE keep cache \(previous.localWins)-\(previous.remoteWins)")
            return previous
        }
        if let floor = sessionFloorState(forRemoteIDs: remotes), floor.hasOpenSession {
            let total = BlomixPvPH2HTotals(localWins: floor.floorLocal, remoteWins: floor.floorRemote)
            replaceTotals(total, underRemoteIDs: remotes)
            print("[H2H] refresh OFFLINE legacy floor \(total.localWins)-\(total.remoteWins)")
            return total
        }

        print("[H2H] refresh empty remotes=\(remotes.prefix(3).map(debugID).joined(separator: ","))…")
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
        if ctx == nil || (ctx?.isActive == false && ctx?.protectsDisplay == false) {
            // Pas de baseline async encore : baseline = cache courant (ou 0).
            let base = cachedTotals(againstRemoteIDs: remotes) ?? .zero
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
            print("[H2H] series baseline fallback cache \(base.localWins)-\(base.remoteWins)")
        }
        guard var live = ctx else {
            return cachedTotals(againstRemoteIDs: remotes) ?? .zero
        }
        if !live.isActive, live.protectsDisplay {
            // Grâce encore ouverte + nouvelle manche : rouvre la série en gardant le total affiché comme baseline.
            let d = live.displayedTotals
            live.baselineLocal = d.localWins
            live.baselineRemote = d.remoteWins
            live.seriesLocal = 0
            live.seriesRemote = 0
            live.isActive = true
            live.graceUntil = nil
        }
        live.isActive = true
        if localWon {
            live.seriesLocal += 1
        } else {
            live.seriesRemote += 1
        }
        live.updatedAt = Date()
        let displayed = live.displayedTotals
        // Persistance **différée** : ne pas bloquer le MainActor pendant l’UI de fin de match
        // (viewDidLoad résultat / serpent / present). Les totaux live restent en mémoire via saveLiveSeries.
        let floorTotals = displayed
        let floorRemotes = Array(remotes.prefix(Self.maxExpandedRemoteIDs))
        var liveToSave = live
        liveToSave.remoteIDs = floorRemotes
        // Live series = petit write immédiat (nécessaire pour le HUD série).
        saveLiveSeries(liveToSave)
        // Cache + floor : après un vrai délai pour laisser l’UI s’afficher (pas seulement yield).
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self.replaceTotals(floorTotals, underRemoteIDs: floorRemotes)
            self.commitDisplayFloor(floorTotals, remoteIDs: floorRemotes)
        }
        return displayed
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
    }

    private struct H2HCloudEvent {
        var recordName: String
        var winnerID: String
        var loserID: String
        var pairKey: String
        var clientEventId: String
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
        var winnerQueryUseful = false

        // 1) Queries par winnerID (même ensemble d’events des deux côtés si index Queryable).
        let winnerIDs = Array(localSet.union(remoteSet)).sorted { Self.idQueryPriority($0) > Self.idQueryPriority($1) }
        for wid in winnerIDs {
            do {
                let recs = try await fetchRecords(predicate: NSPredicate(format: "winnerID == %@", wid))
                querySucceeded = true
                winnerQueryUseful = true
                mergeCloudRecords(recs, into: &unique)
            } catch {
                // Index absent ou erreur : on bascule sur pairKey (pas fatal).
                print("[H2H] winnerID query fail id=\(debugID(wid)): \(error.localizedDescription)")
            }
        }

        // 2) Queries pairKey (IDs live + known + pending) — couvre l’historique même sans index winnerID.
        let pairKeys = candidatePairKeys(localIDs: Array(localSet), remotes: Array(remoteSet))
        for pair in pairKeys {
            do {
                let recs = try await fetchRecords(predicate: NSPredicate(format: "pairKey == %@", pair))
                querySucceeded = true
                mergeCloudRecords(recs, into: &unique)
                if !recs.isEmpty {
                    rememberPairKey(pair)
                    print("[H2H] cloud hit pair=\(String(pair.prefix(36)))… raw=\(recs.count)")
                }
            } catch {
                print("[H2H] pairKey query fail pair=\(String(pair.prefix(24)))…: \(error.localizedDescription)")
            }
        }

        // 3) Filtrer strictement le duo (winnerID renvoie toutes les wins vs tout le monde).
        //    Puis enrichir les sets d’IDs seulement à partir d’events déjà duo-valides.
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

        var localWins = 0
        var remoteWins = 0
        for ev in duoEvents {
            if Self.isLocalWinner(winnerID: ev.winnerID, localIDs: localSet, remoteIDs: remoteSet) {
                localWins += 1
            } else if remoteSet.contains(ev.winnerID) {
                remoteWins += 1
            } else {
                // Winner inconnu mais event duo via pairKey : l’autre côté du pair.
                remoteWins += 1
            }
        }

        let sum = BlomixPvPH2HTotals(localWins: localWins, remoteWins: remoteWins)
        if !duoEvents.isEmpty {
            print("[H2H] cloud unique events=\(duoEvents.count) pairsTried=\(pairKeys.count) winnerQ=\(winnerQueryUseful) → \(localWins)-\(remoteWins)")
        }
        return CloudSumBundle(sum: sum, anyHit: sum.hasHistory, querySucceeded: querySucceeded)
    }

    private func mergeCloudRecords(_ records: [CKRecord], into unique: inout [String: H2HCloudEvent]) {
        for rec in records {
            let name = rec.recordID.recordName
            let winner = (rec["winnerID"] as? String) ?? ""
            let loser = (rec["loserID"] as? String) ?? ""
            let pair = (rec["pairKey"] as? String) ?? ""
            let cid = (rec["clientEventId"] as? String) ?? name
            let key = cid.isEmpty ? name : cid
            guard !winner.isEmpty else { continue }
            unique[key] = H2HCloudEvent(
                recordName: name,
                winnerID: winner,
                loserID: loser,
                pairKey: pair,
                clientEventId: cid
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
                op.qualityOfService = .userInitiated
                op.resultsLimit = 200
                var page: [CKRecord] = []
                op.recordMatchedBlock = { _, result in
                    if case .success(let rec) = result {
                        page.append(rec)
                    }
                }
                op.queryResultBlock = { result in
                    switch result {
                    case .success(let c):
                        cont.resume(returning: (page, c))
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

        do {
            _ = try await publicDB.save(record)
            rememberPairKey(event.pairKey)
        } catch {
            if isIdempotentCloudSuccess(error) {
                rememberPairKey(event.pairKey)
                return
            }
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

    /// Écrit le total **tel quel** sous toutes les clés (réconciliation cloud-first).
    private func replaceTotals(_ totals: BlomixPvPH2HTotals, underRemoteIDs remoteIDs: [String]) {
        var cache = loadCacheV2()
        let keys = expandedRemoteIDs(remoteIDs)
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
