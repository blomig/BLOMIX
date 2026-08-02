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

/// Session Multipeer 1v1. Les deux appareils advertisent + browsent ; connexion puis échange d’identité.
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

    private let myPeerID: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private var discovered: [MCPeerID: String] = [:] // peer → display name from discoveryInfo
    private var didSendIdentity = false
    private var didReceiveIdentity = false
    private var identityTimeout: Timer?
    private var searchTimeout: Timer?

    private let localIdentity: BlomixPvPLocalPeerIdentity

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
        // MCPeerID displayName max ~63 ; on garde un label lisible.
        let shortName = String(localIdentity.displayName.prefix(40))
        self.myPeerID = MCPeerID(displayName: shortName.isEmpty ? "BLOMIX" : shortName)
        super.init()
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
    }

    deinit {
        // tearDown doit être appelé depuis MainActor avant release.
    }

    // MARK: - Public API

    func startSearching(timeout: TimeInterval = 60) {
        // Reset découverte sans casser le MCSession sous-jacent.
        searchTimeout?.invalidate()
        searchTimeout = nil
        identityTimeout?.invalidate()
        identityTimeout = nil
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil

        phase = .searching
        onPhaseChange?(.searching)
        didSendIdentity = false
        didReceiveIdentity = false
        remoteIdentity = nil
        remotePeerID = nil
        discovered.removeAll()

        let info: [String: String] = [
            "dn": String(localIdentity.displayName.prefix(32)),
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

        searchTimeout?.invalidate()
        searchTimeout = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .searching else { return }
                self.fail(BlomixL10n.pvpLocalTimeout)
            }
        }
    }

    /// Invite un pair découvert (liste UI).
    func invite(_ peer: MCPeerID) {
        guard phase == .searching || phase == .connecting else { return }
        phase = .connecting
        onPhaseChange?(.connecting)
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 20)
    }

    /// Auto-invite s’il n’y a qu’un pair découvert.
    func inviteSolePeerIfAny() {
        guard phase == .searching, discovered.count == 1, let peer = discovered.keys.first else { return }
        invite(peer)
    }

    var discoveredPeers: [(peer: MCPeerID, name: String)] {
        discovered.map { ($0.key, $0.value) }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    func send(_ data: Data) {
        guard let peer = remotePeerID, session.connectedPeers.contains(peer) else { return }
        do {
            try session.send(data, toPeers: [peer], with: .reliable)
        } catch {
            BlomixPvPLog.event("local_send_error", ["error": error.localizedDescription])
        }
    }

    var isConnected: Bool {
        guard let peer = remotePeerID else { return false }
        return session.connectedPeers.contains(peer)
    }

    func disconnect() {
        tearDown()
    }

    func tearDown() {
        searchTimeout?.invalidate()
        searchTimeout = nil
        identityTimeout?.invalidate()
        identityTimeout = nil
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        session.disconnect()
        phase = .idle
    }

    // MARK: - Identity

    private func sendIdentityIfNeeded() {
        guard !didSendIdentity, let peer = remotePeerID else { return }
        guard let data = try? JSONEncoder().encode(localIdentity) else { return }
        // Préfixe pour distinguer identité vs trafic jeu.
        var payload = Data([0x01])
        payload.append(data)
        do {
            try session.send(payload, toPeers: [peer], with: .reliable)
            didSendIdentity = true
            BlomixPvPLog.event("local_identity_sent", ["to": peer.displayName])
        } catch {
            BlomixPvPLog.event("local_identity_send_fail", ["error": error.localizedDescription])
        }
    }

    private func handleIncomingPayload(_ data: Data) {
        guard !data.isEmpty else { return }
        let kind = data[0]
        let body = data.dropFirst()
        if kind == 0x01 {
            // Identité
            guard let id = try? JSONDecoder().decode(BlomixPvPLocalPeerIdentity.self, from: Data(body)) else {
                fail(BlomixL10n.pvpLocalIdentityFailed)
                return
            }
            if id.protocolVersion != BlomixPvPMatchCoordinator.protocolVersion {
                fail(BlomixL10n.pvpProtocolMismatchMessage)
                return
            }
            remoteIdentity = id
            didReceiveIdentity = true
            BlomixPvPLog.event("local_identity_received", ["name": id.displayName, "elo": "\(id.eloRating)"])
            maybeBecomeReady()
            return
        }
        // Trafic jeu (0x02 ou raw sans préfixe pour robustesse après ready)
        if kind == 0x02 {
            onData?(Data(body))
        } else {
            // Compat : paquet sans préfixe = jeu
            onData?(data)
        }
    }

    /// Envoi pour le coordinateur PvP (préfixe jeu).
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
        // Arrête la découverte pour ne pas inviter d’autres pairs.
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        phase = .ready
        onPhaseChange?(.ready)
        onReady?(self)
    }

    private func fail(_ message: String) {
        phase = .failed(message)
        onPhaseChange?(.failed(message))
        tearDown()
    }

    private func startIdentityExchange(with peer: MCPeerID) {
        remotePeerID = peer
        phase = .connecting
        onPhaseChange?(.connecting)
        sendIdentityIfNeeded()
        identityTimeout?.invalidate()
        identityTimeout = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .connecting else { return }
                self.fail(BlomixL10n.pvpLocalIdentityFailed)
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
                self.startIdentityExchange(with: peerBox.peer)
            case .connecting:
                self.phase = .connecting
                self.onPhaseChange?(.connecting)
            case .notConnected:
                BlomixPvPLog.event("local_peer_not_connected", ["peer": name])
                if self.phase == .ready || self.didReceiveIdentity {
                    self.onDisconnected?()
                } else if self.phase == .connecting {
                    self.fail(BlomixL10n.pvpLocalConnectionFailed)
                }
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
        let peerBox = BlomixMCPeerIDBox(peer: peerID)
        let name = peerID.displayName
        // Handler non-Sendable : appel depuis le main via une boîte nonchecked.
        let handlerBox = UncheckedInvitationHandler(invitationHandler)
        Task { @MainActor in
            let accept = (self.phase == .searching || self.phase == .connecting) && self.session.connectedPeers.isEmpty
            handlerBox.call(accept, accept ? self.session : nil)
            if accept {
                BlomixPvPLog.event("local_invite_accepted", ["from": name])
            }
            _ = peerBox
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.fail(message)
        }
    }
}

/// Wrapper pour passer `invitationHandler` Multipeer à travers MainActor (Swift 6).
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
        Task { @MainActor in
            guard self.phase == .searching else { return }
            self.discovered[peerBox.peer] = name
            self.onPeerDiscovered?(peerBox.peer, name)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.inviteSolePeerIfAny()
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
