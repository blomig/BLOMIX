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

    private let barHeight: CGFloat = 28
    /// Bande de l’heure (horloge à droite, score à gauche, même ligne).
    /// Un peu plus que la rangée d’heure pour décaler grille + barre bas.
    private let topBand: CGFloat = 26

    init(snapshot: WatchZenRunState?, onExitToHome: @escaping () -> Void) {
        self.onExitToHome = onExitToHome
        _engine = StateObject(wrappedValue: WatchZenEngine(snapshot: snapshot))
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
                    .padding(.leading, 8)
                    .padding(.top, 6)
            }
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        .background(WatchPalette.board)
        .overlay { gameOverOverlay }
        .onChange(of: engine.isGameOver) { _, over in
            guard over else { return }
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
            guard delta > 0 else { return }
            withAnimation(.easeOut(duration: 0.15)) { scoreFlash = delta }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                if scoreFlash == delta {
                    withAnimation(.easeOut(duration: 0.2)) { scoreFlash = 0 }
                }
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
            Text("\(engine.score)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: engine.score)
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
        guard !engine.isGameOver else { return }
        engine.flushTransientAim()
        WatchZenStore.save(engine.exportRunState())
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
