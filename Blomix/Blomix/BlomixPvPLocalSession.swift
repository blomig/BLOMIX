//
//  BlomixPvPLocalSession.swift
//  Blomix
//
//  PvP local (même lieu) via MultipeerConnectivity — Bluetooth + Wi‑Fi local, sans Internet.
//  Découverte, connexion 1v1, échange d’identité GC/Elo, puis relais binaire pour le protocole PvP.
//

import Foundation
import MultipeerConnectivity
@preconcurrency import GameKit

/// `MCPeerID` n’est pas `Sendable` — boîte pour traverser les callbacks Multipeer (Swift 6).
private struct BlomixMCPeerIDBox: @unchecked Sendable {
    let peer: MCPeerID
}

// MARK: - Identité échangée au handshake local

struct BlomixPvPLocalPeerIdentity: Codable, Equatable, Sendable {
    var gamePlayerID: String
    var displayName: String
    var eloRating: Int
    var completedMatchCount: Int
    var protocolVersion: Int
    var appBuild: Int
}

// MARK: - Session

/// Session Multipeer 1v1. Les deux appareils advertisent + browsent.
/// **Un seul** des deux invite (ordre déterministe sur `gamePlayerID`) pour éviter les invitations croisées
/// qui font échouer MCSession en « Connexion… » → notConnected.
@MainActor
final class BlomixPvPLocalSession: NSObject {

    /// Service Multipeer (1–15 car. minuscules / chiffres / tirets).
    static let serviceType = "blomix-pvp"

    enum Phase: Equatable {
        case idle
        case searching
        case connecting
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    /// Pair distant une fois l’identité reçue.
    private(set) var remoteIdentity: BlomixPvPLocalPeerIdentity?
    private(set) var remotePeerID: MCPeerID?

    var onPhaseChange: ((Phase) -> Void)?
    /// Pair découvert (pour liste UI si plusieurs).
    var onPeerDiscovered: ((MCPeerID, String) -> Void)?
    var onPeerLost: ((MCPeerID) -> Void)?
    /// Session prête (identité échangée) — lancer le coordinateur.
    var onReady: ((BlomixPvPLocalSession) -> Void)?
    var onData: ((Data) -> Void)?
    var onDisconnected: (() -> Void)?
    /// Transport Multipeer de nouveau live mid-match (après rebuild / re-invite).
    var onTransportRestored: (() -> Void)?

    private let myPeerID: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    /// peer → (displayName, gamePlayerID pour l’ordre d’invitation)
    private var discovered: [MCPeerID: (name: String, gamePlayerID: String)] = [:]
    private var didSendIdentity = false
    private var didReceiveIdentity = false
    /// Évite double invitation sortante.
    private var didSendInvite = false
    private var identityTimeout: Timer?
    private var searchTimeout: Timer?
    private var connectingGraceTimer: Timer?
    private var inviteRetryTimer: Timer?
    /// Debounce notConnected une fois ready (évite faux « joueur déconnecté »).
    private var disconnectNotifyTimer: Timer?
    /// Boucle de re-découverte / re-invite mid-match (Multipeer ne se reconnecte pas tout seul).
    private var midGameReconnectTimer: Timer?
    private var midGameReconnectTicks = 0
    /// gamePlayerID du pair (pour le retrouver après drop).
    private var preferredRemoteGamePlayerID: String?
    /// Évite de reconstruire la MCSession en boucle trop serrée.
    private var lastSessionRebuildAt: Date?
    /// Pendant un rebuild, ignorer les notConnected résiduels de l’ancienne session.
    private var isRebuildingSession = false

    private let localIdentity: BlomixPvPLocalPeerIdentity

    /// Identité locale (pour host-resolve Elo / logs).
    var localPeerIdentity: BlomixPvPLocalPeerIdentity { localIdentity }

    /// `true` si au moins un peer MC est connecté (plus fiable que l’égalité d’identité seule).
    var hasLiveTransport: Bool { !session.connectedPeers.isEmpty }

    /// Prépare une session à partir du cache GC + profil Elo local.
    static func makeIfGCCacheAvailable() -> BlomixPvPLocalSession? {
        guard let id = BlomixEloManager.shared.cachedLocalGameIdentity() else { return nil }
        let profile = BlomixEloManager.shared.cachedLocalProfileOrDefault()
        let build = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
        let identity = BlomixPvPLocalPeerIdentity(
            gamePlayerID: id.gamePlayerID,
            displayName: id.displayName,
            eloRating: profile.rating,
            completedMatchCount: profile.completedMatchCount,
            protocolVersion: BlomixPvPMatchCoordinator.protocolVersion,
            appBuild: build
        )
        return BlomixPvPLocalSession(localIdentity: identity)
    }

    private init(localIdentity: BlomixPvPLocalPeerIdentity) {
        self.localIdentity = localIdentity
        // MCPeerID doit être unique et stable pour la session : nom + suffixe court de l’ID GC
        // (évite collision si deux joueurs ont le même displayName).
        let shortName = String(localIdentity.displayName.prefix(28))
        let idSuffix = String(localIdentity.gamePlayerID.suffix(6))
        let peerLabel = (shortName.isEmpty ? "BLOMIX" : shortName) + "·" + idSuffix
        self.myPeerID = MCPeerID(displayName: String(peerLabel.prefix(63)))
        super.init()
        // `.optional` est nettement plus fiable en local que `.required` (échecs BT fréquents).
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .optional)
        session.delegate = self
    }

    // MARK: - Public API

    func startSearching(timeout: TimeInterval = 90) {
        stopDiscoveryTimersAndBrowsing()

        phase = .searching
        onPhaseChange?(.searching)
        didSendIdentity = false
        didReceiveIdentity = false
        didSendInvite = false
        remoteIdentity = nil
        remotePeerID = nil
        discovered.removeAll()

        // discoveryInfo : doit rester petit ; inclut gamePlayerID pour l’ordre d’invitation.
        let info: [String: String] = [
            "dn": String(localIdentity.displayName.prefix(24)),
            "gid": String(localIdentity.gamePlayerID.prefix(48)),
            "elo": "\(localIdentity.eloRating)"
        ]
        let adv = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: info, serviceType: Self.serviceType)
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv

        let br = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        br.delegate = self
        br.startBrowsingForPeers()
        browser = br

        BlomixPvPLog.event("local_search_start", [
            "peer": myPeerID.displayName,
            "gid": String(localIdentity.gamePlayerID.prefix(8))
        ])

        searchTimeout?.invalidate()
        searchTimeout = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .searching || self.phase == .connecting else { return }
                // Si on est encore en connecting sans ready, timeout aussi.
                self.fail(BlomixL10n.pvpLocalTimeout)
            }
        }
    }

    /// Invite un pair découvert (liste UI, auto, ou **reconnexion mid-match**).
    func invite(_ peer: MCPeerID) {
        guard phase == .searching || phase == .connecting || phase == .ready else { return }
        // Déjà connecté à ce pair (ou un pair live) : rien à faire.
        if !session.connectedPeers.isEmpty {
            if let live = session.connectedPeers.first {
                remotePeerID = live
            }
            return
        }
        if didSendInvite, phase != .ready {
            BlomixPvPLog.event("local_invite_skip_already_sent")
            return
        }
        didSendInvite = true
        if phase != .ready {
            phase = .connecting
            onPhaseChange?(.connecting)
        }
        ensureDiscoveryRunning()
        BlomixPvPLog.event("local_invite_send", [
            "to": peer.displayName,
            "ready": "\(phase == .ready)"
        ])
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 30)

        inviteRetryTimer?.invalidate()
        inviteRetryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.hasLiveTransport { return }
                self.didSendInvite = false
                BlomixPvPLog.event("local_invite_retry_window")
                if self.phase == .ready {
                    self.attemptMidGameReconnect()
                } else {
                    self.tryInviteBestPeer()
                }
            }
        }
    }

    /// Relance découverte + invite après un drop mid-match (à appeler depuis le coordinator).
    func attemptMidGameReconnect() {
        guard phase == .ready else { return }
        if hasLiveTransport {
            stopMidGameReconnectLoop()
            return
        }
        // Multipeer ne se reconnecte presque jamais sur une MCSession déjà « morte ».
        // Rebuild (avec throttle) + re-découverte + invite déterministe.
        rebuildSessionIfNeededForReconnect()
        ensureDiscoveryRunning()
        didSendInvite = false
        invitePreferredPeerIfPossible()
        startMidGameReconnectLoopIfNeeded()
    }

    /// Appelé par le coordinator en cas de silence applicatif (keepAlive jamais reçu)
    /// alors que Multipeer croit encore être connecté (« zombie »).
    func forceTransportReset(reason: String) {
        guard phase == .ready else { return }
        BlomixPvPLog.event("local_force_transport_reset", ["reason": reason])
        rebuildSessionIfNeededForReconnect(force: true)
        ensureDiscoveryRunning()
        didSendInvite = false
        invitePreferredPeerIfPossible()
        startMidGameReconnectLoopIfNeeded()
        scheduleDeferredDisconnectNotify()
    }

    private func invitePreferredPeerIfPossible() {
        guard phase == .ready || phase == .searching || phase == .connecting else { return }
        guard session.connectedPeers.isEmpty else { return }
        let preferred = preferredRemoteGamePlayerID
        if let preferred, !preferred.isEmpty {
            for (peer, meta) in discovered {
                let gid = meta.gamePlayerID
                let matchGID = gid == preferred
                    || gid.hasPrefix(String(preferred.prefix(8)))
                    || preferred.hasPrefix(String(gid.prefix(8)))
                guard matchGID else { continue }
                // Un seul inviteur déterministe pour éviter les invitations croisées.
                if shouldBeInviter(forRemoteGamePlayerID: preferred) {
                    invite(peer)
                } else {
                    BlomixPvPLog.event("local_midgame_wait_invite", ["from": peer.displayName])
                }
                return
            }
            BlomixPvPLog.event("local_midgame_peer_not_rediscovered_yet")
            return
        }
        tryInviteBestPeer()
    }

    private func startMidGameReconnectLoopIfNeeded() {
        guard midGameReconnectTimer == nil else { return }
        midGameReconnectTicks = 0
        BlomixPvPLog.event("local_midgame_reconnect_loop_start")
        let t = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .ready else {
                    self?.stopMidGameReconnectLoop()
                    return
                }
                if self.hasLiveTransport {
                    self.stopMidGameReconnectLoop()
                    return
                }
                self.midGameReconnectTicks += 1
                // Toutes les ~7.5 s, forcer un rebuild de session (MCSession zombie).
                if self.midGameReconnectTicks % 3 == 0 {
                    self.rebuildSessionIfNeededForReconnect(force: true)
                }
                self.didSendInvite = false
                self.ensureDiscoveryRunning()
                self.invitePreferredPeerIfPossible()
                // ~45 s de tentatives actives (aligne grace coordinator locale).
                if self.midGameReconnectTicks >= 18 {
                    BlomixPvPLog.event("local_midgame_reconnect_loop_exhausted")
                    self.stopMidGameReconnectLoop()
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        midGameReconnectTimer = t
    }

    private func stopMidGameReconnectLoop() {
        midGameReconnectTimer?.invalidate()
        midGameReconnectTimer = nil
        midGameReconnectTicks = 0
    }

    /// (Re)démarre advertiser + browser. Important : un stop sans `nil` (bug historique)
    /// laissait `ensureDiscoveryRunning` croire que la découverte tournait encore.
    private func ensureDiscoveryRunning() {
        let info: [String: String] = [
            "dn": String(localIdentity.displayName.prefix(24)),
            "gid": String(localIdentity.gamePlayerID.prefix(48)),
            "elo": "\(localIdentity.eloRating)"
        ]
        if advertiser == nil {
            let adv = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: info, serviceType: Self.serviceType)
            adv.delegate = self
            adv.startAdvertisingPeer()
            advertiser = adv
            BlomixPvPLog.event("local_advertiser_started")
        } else {
            // Relance idempotente si stoppé sans nil (après ready) ou après un hic Multipeer.
            advertiser?.startAdvertisingPeer()
        }
        if browser == nil {
            let br = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
            br.delegate = self
            br.startBrowsingForPeers()
            browser = br
            BlomixPvPLog.event("local_browser_started")
        } else {
            browser?.startBrowsingForPeers()
        }
    }

    /// Recrée la `MCSession` : après un `notConnected`, ré-inviter sur la même session échoue souvent.
    private func rebuildSessionIfNeededForReconnect(force: Bool = false) {
        guard phase == .ready else { return }
        if !force, hasLiveTransport { return }
        if let last = lastSessionRebuildAt, Date().timeIntervalSince(last) < 4.0, !force {
            return
        }
        // Force : throttle un peu moins strict mais pas en boucle serrée.
        if force, let last = lastSessionRebuildAt, Date().timeIntervalSince(last) < 2.0 {
            return
        }
        lastSessionRebuildAt = Date()
        isRebuildingSession = true
        BlomixPvPLog.event("local_session_rebuild", ["force": "\(force)"])
        // Couper l’ancienne session sans remonter un fail applicatif.
        session.delegate = nil
        session.disconnect()
        let newSession = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .optional)
        newSession.delegate = self
        session = newSession
        remotePeerID = nil
        didSendInvite = false
        // Identité déjà connue mid-match : pas de re-échange obligatoire.
        // On garde didSendIdentity / didReceiveIdentity / remoteIdentity.
        discovered.removeAll()
        // Laisse Multipeer digérer le teardown avant de ré-accepter / ré-inviter.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.isRebuildingSession = false
            self?.ensureDiscoveryRunning()
            self?.invitePreferredPeerIfPossible()
        }
    }

    /// Auto-invite : 1 pair → invite si on est l’inviteur déterministe ; N pairs → UI.
    func inviteSolePeerIfAny() {
        guard phase == .searching else { return }
        guard discovered.count == 1, let peer = discovered.keys.first else { return }
        guard shouldBeInviter(forRemoteGamePlayerID: discovered[peer]?.gamePlayerID ?? "") else {
            BlomixPvPLog.event("local_wait_for_invite", ["from": peer.displayName])
            // On reste en searching et on accepte l’invitation entrante.
            return
        }
        invite(peer)
    }

    var discoveredPeers: [(peer: MCPeerID, name: String)] {
        discovered.map { ($0.key, $0.value.name) }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    func send(_ data: Data) {
        // Multipeer peut reconnecter avec un autre handle MCPeerID : toujours
        // envoyer au premier peer live, et resynchroniser remotePeerID.
        let peers = session.connectedPeers
        guard !peers.isEmpty else {
            BlomixPvPLog.event("local_send_skip_no_peers")
            if phase == .ready { attemptMidGameReconnect() }
            return
        }
        let target: MCPeerID
        if let remotePeerID, peers.contains(remotePeerID) {
            target = remotePeerID
        } else {
            target = peers[0]
            remotePeerID = target
        }
        do {
            try session.send(data, toPeers: [target], with: .reliable)
        } catch {
            BlomixPvPLog.event("local_send_error", ["error": error.localizedDescription])
            if phase == .ready { attemptMidGameReconnect() }
        }
    }

    var isConnected: Bool { hasLiveTransport }

    func disconnect() {
        tearDown()
    }

    func tearDown() {
        stopDiscoveryTimersAndBrowsing()
        session.disconnect()
        phase = .idle
    }

    // MARK: - Invitation policy

    /// Un seul côté invite : celui dont `gamePlayerID` est lexicographiquement **plus petit**.
    private func shouldBeInviter(forRemoteGamePlayerID remoteGID: String) -> Bool {
        let local = localIdentity.gamePlayerID
        guard !remoteGID.isEmpty else {
            // Pas d’ID distant dans discoveryInfo → on invite quand même (mieux que rester bloqué).
            return true
        }
        return local < remoteGID
    }

    private func tryInviteBestPeer() {
        guard phase == .searching || phase == .connecting || phase == .ready else { return }
        guard !didSendInvite else { return }
        guard session.connectedPeers.isEmpty else { return }
        if discovered.count == 1, let peer = discovered.keys.first {
            if shouldBeInviter(forRemoteGamePlayerID: discovered[peer]?.gamePlayerID ?? "") {
                invite(peer)
            }
        }
    }

    // MARK: - Identity

    private func sendIdentityIfNeeded() {
        guard !didSendIdentity, let peer = remotePeerID else { return }
        guard session.connectedPeers.contains(peer) else { return }
        guard let data = try? JSONEncoder().encode(localIdentity) else { return }
        var payload = Data([0x01])
        payload.append(data)
        do {
            try session.send(payload, toPeers: [peer], with: .reliable)
            didSendIdentity = true
            BlomixPvPLog.event("local_identity_sent", ["to": peer.displayName])
        } catch {
            BlomixPvPLog.event("local_identity_send_fail", ["error": error.localizedDescription])
            // Réessaie une fois peu après (canal parfois pas prêt à l’instant connected).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, !self.didSendIdentity else { return }
                self.sendIdentityIfNeeded()
            }
        }
    }

    private func handleIncomingPayload(_ data: Data) {
        guard !data.isEmpty else { return }
        let kind = data[0]
        let body = data.dropFirst()
        if kind == 0x01 {
            guard let id = try? JSONDecoder().decode(BlomixPvPLocalPeerIdentity.self, from: Data(body)) else {
                fail(BlomixL10n.pvpLocalIdentityFailed)
                return
            }
            if id.protocolVersion != BlomixPvPMatchCoordinator.protocolVersion {
                fail(BlomixL10n.pvpProtocolMismatchMessage)
                return
            }
            remoteIdentity = id
            preferredRemoteGamePlayerID = id.gamePlayerID
            didReceiveIdentity = true
            BlomixPvPLog.event("local_identity_received", ["name": id.displayName, "elo": "\(id.eloRating)"])
            // Si on n’a pas encore envoyé (guest), envoyer maintenant.
            sendIdentityIfNeeded()
            maybeBecomeReady()
            return
        }
        if kind == 0x02 {
            onData?(Data(body))
        } else {
            onData?(data)
        }
    }

    func sendGameData(_ data: Data) {
        var payload = Data([0x02])
        payload.append(data)
        send(payload)
    }

    private func maybeBecomeReady() {
        guard didSendIdentity, didReceiveIdentity, remoteIdentity != nil else { return }
        guard phase != .ready else { return }
        identityTimeout?.invalidate()
        identityTimeout = nil
        searchTimeout?.invalidate()
        searchTimeout = nil
        connectingGraceTimer?.invalidate()
        connectingGraceTimer = nil
        inviteRetryTimer?.invalidate()
        inviteRetryTimer = nil
        // Garder advertiser + browser actifs pendant tout le match local :
        // 1) arrêter la découverte juste après ready provoque parfois un notConnected
        // 2) stop sans `nil` empêchait toute reconnexion (ensureDiscovery croyait tourner)
        // 3) Multipeer mid-match a besoin de re-découvrir pour se reconnecter
        phase = .ready
        preferredRemoteGamePlayerID = remoteIdentity?.gamePlayerID ?? preferredRemoteGamePlayerID
        onPhaseChange?(.ready)
        BlomixPvPLog.event("local_ready", ["remote": remoteIdentity?.displayName ?? "?"])
        onReady?(self)
    }

    private func fail(_ message: String) {
        guard phase != .failed(message) else { return }
        BlomixPvPLog.event("local_fail", ["msg": message])
        phase = .failed(message)
        onPhaseChange?(.failed(message))
        tearDown()
    }

    private func startIdentityExchange(with peer: MCPeerID) {
        remotePeerID = peer
        phase = .connecting
        onPhaseChange?(.connecting)
        connectingGraceTimer?.invalidate()
        connectingGraceTimer = nil
        // Léger délai : la session MC est parfois pas encore prête pour send à l’instant connected.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.sendIdentityIfNeeded()
        }
        identityTimeout?.invalidate()
        identityTimeout = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .connecting else { return }
                self.fail(BlomixL10n.pvpLocalIdentityFailed)
            }
        }
    }

    private func stopDiscoveryTimersAndBrowsing() {
        searchTimeout?.invalidate()
        searchTimeout = nil
        identityTimeout?.invalidate()
        identityTimeout = nil
        connectingGraceTimer?.invalidate()
        connectingGraceTimer = nil
        inviteRetryTimer?.invalidate()
        inviteRetryTimer = nil
        disconnectNotifyTimer?.invalidate()
        disconnectNotifyTimer = nil
        stopMidGameReconnectLoop()
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
    }

    /// Dès un notConnected mid-match : reconnexion active + notify coordinator seulement
    /// si toujours mort après une fenêtre de retry (pas un simple wait passif).
    private func scheduleDeferredDisconnectNotify() {
        // Toujours tenter de se reconnecter tout de suite (rebuild + discovery + invite).
        attemptMidGameReconnect()
        guard disconnectNotifyTimer == nil else { return }
        BlomixPvPLog.event("local_disconnect_debounce_start")
        // Laisse ~12 s de tentatives actives avant d’afficher « Reconnexion… » côté coordinator.
        // La grace mid-match locale continue ensuite (~45 s) pendant que la boucle invite tourne.
        let t = Timer(timeInterval: 12, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.disconnectNotifyTimer = nil
                if self.hasLiveTransport {
                    BlomixPvPLog.event("local_disconnect_debounce_cancelled_peer_back")
                    return
                }
                BlomixPvPLog.event("local_disconnect_debounce_fire")
                // Continuer les tentatives même après notification UI.
                self.attemptMidGameReconnect()
                self.onDisconnected?()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        disconnectNotifyTimer = t
    }

    private func noteTransportRestored(peer: MCPeerID) {
        remotePeerID = peer
        stopMidGameReconnectLoop()
        disconnectNotifyTimer?.invalidate()
        disconnectNotifyTimer = nil
        connectingGraceTimer?.invalidate()
        connectingGraceTimer = nil
        BlomixPvPLog.event("local_peer_reconnected", ["peer": peer.displayName])
        onTransportRestored?()
    }

    /// `.notConnected` pendant connecting : ne pas échouer tout de suite (souvent transitoire).
    private func handleNotConnectedWhileConnecting() {
        BlomixPvPLog.event("local_not_connected_grace")
        // Remet didSendInvite pour permettre un retry déterministe.
        didSendInvite = false
        didSendIdentity = false
        // Grace 3 s : si toujours pas connected, on retente l’invite (si inviteur).
        connectingGraceTimer?.invalidate()
        connectingGraceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.phase == .connecting else { return }
                if !self.session.connectedPeers.isEmpty {
                    if let peer = self.session.connectedPeers.first {
                        self.startIdentityExchange(with: peer)
                    }
                    return
                }
                // Retour en searching pour ré-inviter / attendre.
                self.phase = .searching
                self.onPhaseChange?(.searching)
                self.tryInviteBestPeer()
            }
        }
    }
}

// MARK: - MCSessionDelegate

extension BlomixPvPLocalSession: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let peerBox = BlomixMCPeerIDBox(peer: peerID)
        let name = peerID.displayName
        Task { @MainActor in
            switch state {
            case .connected:
                BlomixPvPLog.event("local_peer_connected", ["peer": name])
                self.connectingGraceTimer?.invalidate()
                self.connectingGraceTimer = nil
                // Reconnexion mid-match : identité déjà connue → transport restored.
                if self.phase == .ready {
                    self.noteTransportRestored(peer: peerBox.peer)
                } else {
                    self.disconnectNotifyTimer?.invalidate()
                    self.disconnectNotifyTimer = nil
                    self.startIdentityExchange(with: peerBox.peer)
                }
            case .connecting:
                BlomixPvPLog.event("local_peer_connecting", ["peer": name])
                if self.phase == .searching {
                    self.phase = .connecting
                    self.onPhaseChange?(.connecting)
                }
            case .notConnected:
                BlomixPvPLog.event("local_peer_not_connected", [
                    "peer": name,
                    "phase": "\(self.phase)",
                    "rebuilding": "\(self.isRebuildingSession)"
                ])
                if self.isRebuildingSession {
                    // Événement résiduel de l’ancienne session — ignorer.
                    break
                }
                if self.phase == .ready {
                    // Micro-coupure Multipeer fréquente : reconnect active, pas fail immédiat.
                    self.scheduleDeferredDisconnectNotify()
                } else if self.phase == .connecting {
                    // Ne plus fail immédiat : Multipeer envoie souvent notConnected
                    // quand les deux tentaient de se connecter — grace + retry.
                    self.handleNotConnectedWhileConnecting()
                }
                // searching : ignorer (pair perdu en découverte géré par lostPeer)
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let payload = data
        Task { @MainActor in
            self.handleIncomingPayload(payload)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - Advertiser

extension BlomixPvPLocalSession: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let name = peerID.displayName
        let peerBox = BlomixMCPeerIDBox(peer: peerID)
        let handlerBox = UncheckedInvitationHandler(invitationHandler)
        // Appel rapide sur le main : Multipeer est sensible au délai d’acceptation.
        DispatchQueue.main.async {
            let peer = peerBox.peer
            let accept: Bool
            if !self.session.connectedPeers.isEmpty {
                // Déjà un live peer : n’accepter que le même.
                accept = self.session.connectedPeers.contains(peer)
            } else {
                // searching / connecting / ready (reconnexion mid-match) : accepter.
                switch self.phase {
                case .searching, .connecting, .ready:
                    accept = true
                case .idle, .failed:
                    accept = false
                }
            }
            handlerBox.call(accept, accept ? self.session : nil)
            if accept {
                BlomixPvPLog.event("local_invite_accepted", [
                    "from": name,
                    "phase": "\(self.phase)"
                ])
                if self.phase != .ready {
                    self.phase = .connecting
                    self.onPhaseChange?(.connecting)
                }
            } else {
                BlomixPvPLog.event("local_invite_rejected", ["from": name])
            }
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.fail(message)
        }
    }
}

/// Wrapper pour passer `invitationHandler` Multipeer à travers des files (Swift 6).
private struct UncheckedInvitationHandler: @unchecked Sendable {
    private let handler: (Bool, MCSession?) -> Void
    init(_ handler: @escaping (Bool, MCSession?) -> Void) { self.handler = handler }
    func call(_ accept: Bool, _ session: MCSession?) { handler(accept, session) }
}

// MARK: - Browser

extension BlomixPvPLocalSession: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let peerBox = BlomixMCPeerIDBox(peer: peerID)
        let name = info?["dn"] ?? peerID.displayName
        let gid = info?["gid"] ?? ""
        Task { @MainActor in
            guard self.phase == .searching || self.phase == .connecting || self.phase == .ready else { return }
            self.discovered[peerBox.peer] = (name: name, gamePlayerID: gid)
            self.onPeerDiscovered?(peerBox.peer, name)
            BlomixPvPLog.event("local_peer_found", [
                "name": name,
                "gid": String(gid.prefix(8)),
                "count": "\(self.discovered.count)",
                "phase": "\(self.phase)"
            ])
            if self.phase == .ready {
                // Mid-match : pair re-vu → invite déterministe si besoin.
                self.invitePreferredPeerIfPossible()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    self?.inviteSolePeerIfAny()
                }
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let peerBox = BlomixMCPeerIDBox(peer: peerID)
        Task { @MainActor in
            self.discovered.removeValue(forKey: peerBox.peer)
            self.onPeerLost?(peerBox.peer)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.fail(message)
        }
    }
}
