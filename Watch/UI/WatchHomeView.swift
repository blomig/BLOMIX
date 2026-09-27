//
//  WatchHomeView.swift
//

import SwiftUI

struct WatchHomeView: View {
    @State private var isPlaying = false
    @State private var resumeSaved = false
    @State private var showNewGameConfirm = false

    private var best: Int { WatchZenStore.bestScore }
    private var hasMidRun: Bool { WatchZenStore.hasMidRun }

    var body: some View {
        if isPlaying {
            WatchPlayView(
                snapshot: resumeSaved ? WatchZenStore.load() : nil,
                onExitToHome: { isPlaying = false }
            )
        } else {
            homeContent
        }
    }

    private var homeContent: some View {
        VStack(spacing: 10) {
            Text("BLOMIX")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Button {
                resumeSaved = hasMidRun
                isPlaying = true
            } label: {
                Text(hasMidRun ? WatchL10n.continueGame : WatchL10n.playZen)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            if hasMidRun {
                Button {
                    showNewGameConfirm = true
                } label: {
                    Text(WatchL10n.newGame)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if best > 0 {
                Text("\(WatchL10n.bestScore) \(best)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .overlay { newGameOverlay }
    }

    @ViewBuilder
    private var newGameOverlay: some View {
        if showNewGameConfirm {
            ZStack {
                Color.black.opacity(0.78)
                VStack(spacing: 8) {
                    Text(WatchL10n.abandonTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Button(WatchL10n.abandonYes) {
                        WatchZenStore.clearRun()
                        showNewGameConfirm = false
                        resumeSaved = false
                        isPlaying = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    Button(WatchL10n.abandonNo) { showNewGameConfirm = false }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(.horizontal, 8)
            }
        }
    }
}
