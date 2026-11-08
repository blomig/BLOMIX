//
//  WatchBottomBar.swift
//  40 mm : Home à gauche · file P2 P1 P0 au centre · bombe à droite (comme iPhone).
//  Bombe armée : le slot P0 montre la bombe, la file visible décale d’un cran.
//  p0 / p1 / p2 réels ne bougent pas.
//

import SwiftUI

struct WatchBottomBar: View {
    let p0: WatchBlockType
    let p1: WatchBlockType
    let p2: WatchBlockType
    let bombCount: Int
    let isBombMode: Bool
    let bombEnabled: Bool
    let onHome: () -> Void
    let onBomb: () -> Void
    var onCycleMagix: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onHome) {
                Image(systemName: "house.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(WatchL10n.homeA11y)

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                if isBombMode {
                    // Même décalage visuel que l’iPhone : la bombe passe devant P0.
                    miniBlock(p1, size: 11)
                    miniBlock(p0, size: 11)
                    bombSlot(size: 16)
                } else {
                    miniBlock(p2, size: 11)
                    miniBlock(p1, size: 11)
                    miniBlock(p0, size: 16, breathes: true)
                }
            }
            .frame(height: 28)
            .onLongPressGesture(minimumDuration: 0.55, perform: onCycleMagix)

            Spacer(minLength: 0)

            Button(action: onBomb) {
                ZStack {
                    Circle()
                        .fill(bombFill)
                        .frame(width: 22, height: 22)
                    Text("\(bombCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(bombEnabled ? .white : .white.opacity(0.35))
                }
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!bombEnabled)
            .accessibilityLabel(WatchL10n.bombA11y)
        }
        .frame(height: 28)
    }

    private var bombFill: Color {
        if isBombMode { return WatchPalette.orange }
        if bombEnabled { return Color.white.opacity(0.22) }
        return Color.white.opacity(0.10)
    }

    @ViewBuilder
    private func miniBlock(_ block: WatchBlockType, size: CGFloat, breathes: Bool = false) -> some View {
        if breathes {
            blockFace(block, size: size).modifier(WatchNextDropBreath())
        } else {
            blockFace(block, size: size)
        }
    }

    private func blockFace(_ block: WatchBlockType, size: CGFloat) -> some View {
        WatchBlockTile(block: block)
            .frame(width: size, height: size)
    }

    /// Slot qui part au prochain tap : la bombe, qui respire comme P0.
    private func bombSlot(size: CGFloat) -> some View {
        WatchQueueBombFace()
            .frame(width: size, height: size)
            .modifier(WatchNextDropBreath())
    }
}

/// Disque statique noir / rouge / jaune. Pas de shader, pas de particules.
private struct WatchQueueBombFace: View {
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                .black,
                                WatchPalette.red,
                                WatchPalette.yellow,
                                WatchPalette.red,
                                .black,
                            ],
                            center: .center
                        )
                    )
                Circle()
                    .strokeBorder(Color.black, lineWidth: max(1.2, side * 0.14))
            }
            .frame(width: side, height: side)
        }
    }
}

/// Respiration du bloc qui part au prochain tap (P0 seulement).
private struct WatchNextDropBreath: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lifted = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1 : (lifted ? 1.14 : 1))
            .task(id: reduceMotion) {
                guard !reduceMotion else {
                    lifted = false
                    return
                }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    lifted = true
                }
            }
    }
}
