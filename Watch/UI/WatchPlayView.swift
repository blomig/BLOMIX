//
//  WatchPlayView.swift
//  Score overlay dans la bande de l’heure. Grille un peu plus grande.
//

import SwiftUI

struct WatchPlayView: View {
    var onExitToHome: () -> Void

    @StateObject private var engine: WatchZenEngine
    @Environment(\.scenePhase) private var scenePhase
    @State private var showNewRecord = false
    @State private var scoreFlash = 0
    /// Chiffre affiché. Il défile avec les paillettes, il ne saute pas avec `engine.score`.
    @State private var shownScore: Int
    @State private var scoreRoll: WatchScoreRoll?
    @State private var scoreRollTask: Task<Void, Never>?
    @State private var scoreRollToken = 0

    private let barHeight: CGFloat = 28
    /// Bande de l’heure (horloge à droite, score à gauche, même ligne).
    /// Un peu plus que la rangée d’heure pour décaler grille + barre bas.
    private let topBand: CGFloat = 26

    init(snapshot: WatchZenRunState?, onExitToHome: @escaping () -> Void) {
        self.onExitToHome = onExitToHome
        _engine = StateObject(wrappedValue: WatchZenEngine(snapshot: snapshot))
        _shownScore = State(initialValue: snapshot?.score ?? 0)
    }

    var body: some View {
        GeometryReader { geo in
            let gridSide = min(geo.size.width, max(0, geo.size.height - barHeight - topBand))
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                Color.clear.frame(height: topBand)
                WatchGridCanvas(
                    cells: engine.liveCells,
                    highlightedColumn: engine.highlightedColumn,
                    aimedBombCell: engine.aimedBombCell,
                    incomingPreview: engine.incomingPreview,
                    magixFX: engine.magixFX,
                    previewBlock: engine.p0,
                    isBombMode: engine.isBombMode,
                    isInteractive: !engine.isGameOver && !engine.isProcessing,
                    onHighlightColumn: { engine.setHighlightedColumn($0) },
                    onAimBomb: { engine.updateBombAim($0) },
                    onDrop: { engine.drop(column: $0) },
                    onPlaceBomb: { engine.placeBombAtAimedCell() },
                    onCancel: { engine.cancelGesture() }
                )
                .frame(width: gridSide, height: gridSide)
                .frame(maxWidth: .infinity)
                .anchorPreference(key: WatchPlayAnchorKey.self, value: .bounds) { ["grid": $0] }

                WatchBottomBar(
                    p0: engine.p0,
                    p1: engine.p1,
                    p2: engine.p2,
                    bombCount: engine.bombCount,
                    isBombMode: engine.isBombMode,
                    bombEnabled: engine.bombButtonEnabled,
                    onHome: saveAndGoHome,
                    onBomb: { engine.toggleBombMode() },
                    onCycleMagix: { engine.debugCycleP0Magix() }
                )
                .frame(height: barHeight)
                    Spacer(minLength: 0)
                }
                scoreOverlay
                    .anchorPreference(key: WatchPlayAnchorKey.self, value: .bounds) { ["score": $0] }
                    .padding(.leading, 8)
                    .padding(.top, 6)
            }
            .overlayPreferenceValue(WatchPlayAnchorKey.self) { anchors in
                WatchChainSparkleLayer(
                    request: engine.chainSparkle,
                    grid: anchors["grid"].map { geo[$0] },
                    score: anchors["score"].map { geo[$0] },
                    onFlight: { points, first, last in
                        beginChainRoll(points: points, first: first, last: last)
                    }
                )
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        .background(WatchPalette.board)
        .overlay { gameOverOverlay }
        .onChange(of: engine.isGameOver) { _, over in
            guard over else { return }
            scoreRoll = nil
            scoreRollTask?.cancel()
            shownScore = engine.score
            let previousBest = WatchZenStore.bestScore
            let isWatchPB = engine.score > previousBest && engine.score > 0
            showNewRecord = isWatchPB
            WatchZenStore.recordScore(engine.score)
            WatchZenStore.clearRun()
            if isWatchPB {
                WatchZenScoreBridge.shared.enqueueZenPersonalBest(engine.score)
            }
        }
        .onChange(of: engine.score) { old, new in
            let delta = new - old
            guard delta > 0 else {
                scoreRoll = nil
                scoreRollTask?.cancel()
                shownScore = new
                return
            }
            let chain = engine.consumeChainSparklePoints(upTo: delta)
            let immediate = delta - chain
            if immediate > 0 {
                applyImmediateScore(immediate)
                flashScore(immediate)
            }
        }
        .onChange(of: engine.isProcessing) { _, processing in
            if !processing { persistMidRun() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { persistMidRun() }
        }
    }

    private var scoreOverlay: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(shownScore)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .animation(nil, value: shownScore)
            if scoreFlash > 0 {
                Text("+\(scoreFlash)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(WatchPalette.yellow)
                    .transition(.opacity)
            }
        }
        .accessibilityLabel(WatchL10n.scoreA11y)
    }

    private func saveAndGoHome() {
        persistMidRun()
        onExitToHome()
    }

    private func persistMidRun() {
        guard !engine.isGameOver, !engine.isProcessing else { return }
        engine.flushTransientAim()
        WatchZenStore.save(engine.exportRunState())
    }

    /// Points hors chaîne (Brix, bombe, colonne) : tout de suite, y compris au milieu d’un défilement.
    private func applyImmediateScore(_ points: Int) {
        guard points > 0 else { return }
        shownScore += points
        guard var roll = scoreRoll else { return }
        roll.to += points
        if Date() < roll.start {
            roll.from += points
        } else {
            roll.from = shownScore
            roll.start = Date()
        }
        scoreRoll = roll
    }

    /// Le chiffre part à la première paillette et s’arrête juste après la dernière.
    private func beginChainRoll(points: Int, first: Double, last: Double) {
        guard points > 0 else { return }
        let now = Date()
        let start = now.addingTimeInterval(max(0, first))
        let end = now.addingTimeInterval(
            max(last, first) + WatchZenRules.chainSparkleRollPad
        )
        let earliestEnd = start.addingTimeInterval(WatchZenRules.chainSparkleRollMin)
        if var roll = scoreRoll, roll.end > now {
            roll.to += points
            roll.end = max(roll.end, end, earliestEnd)
            if now >= roll.start {
                roll.from = shownScore
                roll.start = now
            }
            scoreRoll = roll
        } else {
            scoreRoll = WatchScoreRoll(
                from: shownScore,
                to: shownScore + points,
                start: start,
                end: max(end, earliestEnd)
            )
        }
        ensureScoreRollLoop()
        flashScore(points)
    }

    private func ensureScoreRollLoop() {
        scoreRollToken += 1
        let token = scoreRollToken
        scoreRollTask?.cancel()
        scoreRollTask = Task { @MainActor in
            while !Task.isCancelled {
                guard let roll = scoreRoll else { return }
                let now = Date()
                if now < roll.start {
                    let wait = roll.start.timeIntervalSince(now)
                    try? await Task.sleep(nanoseconds: UInt64(max(0, wait) * 1_000_000_000))
                    if Task.isCancelled { return }
                    continue
                }
                let span = max(0.05, roll.end.timeIntervalSince(roll.start))
                let t = min(1, now.timeIntervalSince(roll.start) / span)
                shownScore = roll.from + Int((Double(roll.to - roll.from) * t).rounded())
                if t >= 1 {
                    shownScore = roll.to
                    if scoreRoll?.to == roll.to, scoreRoll?.end == roll.end {
                        scoreRoll = nil
                        return
                    }
                    continue
                }
                try? await Task.sleep(nanoseconds: 33_000_000)
                if Task.isCancelled { return }
            }
            if scoreRollToken == token {
                scoreRollTask = nil
            }
        }
    }

    private func flashScore(_ delta: Int) {
        guard delta > 0 else { return }
        withAnimation(.easeOut(duration: 0.15)) { scoreFlash = delta }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            if scoreFlash == delta {
                withAnimation(.easeOut(duration: 0.2)) { scoreFlash = 0 }
            }
        }
    }

    @ViewBuilder
    private var gameOverOverlay: some View {
        if engine.isGameOver {
            ZStack {
                Color.black.opacity(0.78)
                VStack(spacing: 6) {
                    Text(WatchL10n.gameOver)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("\(engine.score)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    if showNewRecord {
                        Text(WatchL10n.newRecord)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(WatchPalette.yellow)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onExitToHome() }
        }
    }
}

private struct WatchScoreRoll {
    var from: Int
    var to: Int
    var start: Date
    var end: Date
}

private struct WatchPlayAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(
        value: inout [String: Anchor<CGRect>],
        nextValue: () -> [String: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Paillettes de la couleur de la chaîne, vers le score. Canvas seulement pendant le vol.
private struct WatchChainSparkleLayer: View {
    let request: WatchChainSparkleRequest?
    let grid: CGRect?
    let score: CGRect?
    let onFlight: (Int, Double, Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dots: [WatchFlyingDot] = []
    @State private var seenToken = 0

    var body: some View {
        Group {
            if dots.isEmpty {
                Color.clear
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    Canvas { context, _ in
                        draw(dots, at: timeline.date, in: &context)
                    }
                }
            }
        }
        .onChange(of: request?.token) { _, _ in launchIfReady() }
        .onChange(of: grid) { _, _ in launchIfReady() }
        .onChange(of: score) { _, _ in launchIfReady() }
    }

    private func launchIfReady() {
        guard let request, request.token != seenToken, request.points > 0 else { return }
        guard let grid, grid.width > 1, let score, score.width > 1 else { return }
        seenToken = request.token
        guard !reduceMotion else {
            onFlight(request.points, 0, 0.28)
            return
        }

        let cell = grid.width / CGFloat(WatchGridLayout.columnCount)
        let perCell = max(1, min(3, 24 / max(request.cells.count, 1)))
        let speed = max(48, (grid.height * 0.5) / 0.25)
        let born = Date()
        var first = Double.greatestFiniteMagnitude
        var last = 0.0
        var spawned: [WatchFlyingDot] = []
        for (index, item) in request.cells.enumerated() {
            let delay = WatchZenRules.chainClearDelay(index: index)
            let origin = CGPoint(
                x: grid.minX + (CGFloat(item.col) + 0.5) * cell,
                y: grid.minY + (CGFloat(item.row) + 0.5) * cell
            )
            let color = WatchPalette.color(named: item.colorName)
            for _ in 0..<perCell {
                let spread = cell * 0.28
                let from = CGPoint(
                    x: origin.x + CGFloat.random(in: -spread ... spread),
                    y: origin.y + CGFloat.random(in: -spread ... spread)
                )
                let to = CGPoint(
                    x: score.midX + CGFloat.random(in: -7 ... 7),
                    y: score.midY + CGFloat.random(in: -3 ... 3)
                )
                let distance = hypot(to.x - from.x, to.y - from.y)
                let duration = max(
                    WatchZenRules.chainSparkleFlightMin,
                    Double(distance / speed)
                )
                let dotDelay = delay + Double.random(in: 0 ... 0.03)
                first = min(first, dotDelay + duration)
                last = max(last, dotDelay + duration)
                spawned.append(WatchFlyingDot(
                    batch: request.token,
                    color: color,
                    from: from,
                    to: to,
                    delay: dotDelay,
                    duration: duration,
                    radius: CGFloat.random(in: 1.4 ... 2.2),
                    born: born
                ))
            }
        }
        guard !spawned.isEmpty else {
            onFlight(request.points, 0, WatchZenRules.chainSparkleRollMin)
            return
        }
        dots.append(contentsOf: spawned)
        onFlight(request.points, first, last)
        let batch = request.token
        let life = last + 0.05
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, life) * 1_000_000_000))
            dots.removeAll { $0.batch == batch }
        }
    }

    private func draw(_ dots: [WatchFlyingDot], at date: Date, in context: inout GraphicsContext) {
        for dot in dots {
            let local = date.timeIntervalSince(dot.born) - dot.delay
            guard local >= 0 else { continue }
            let t = min(1, local / dot.duration)
            guard t < 1 else { continue }
            let eased = t * t
            let point = CGPoint(
                x: dot.from.x + (dot.to.x - dot.from.x) * eased,
                y: dot.from.y + (dot.to.y - dot.from.y) * eased
            )
            let alpha = min(1, local / 0.05)
            var dotContext = context
            dotContext.opacity = alpha
            let side = dot.radius * 2
            let rect = CGRect(x: point.x - dot.radius, y: point.y - dot.radius, width: side, height: side)
            dotContext.fill(Path(ellipseIn: rect), with: .color(dot.color))
        }
    }
}

private struct WatchFlyingDot: Identifiable {
    let id = UUID()
    var batch: Int
    var color: Color
    var from: CGPoint
    var to: CGPoint
    var delay: Double
    var duration: Double
    var radius: CGFloat
    var born: Date
}
