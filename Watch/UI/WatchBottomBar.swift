//
//  WatchBottomBar.swift
//  40 mm : Home à gauche · file P2 P1 P0 au centre · bombe à droite (comme iPhone).
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
                miniBlock(p2, size: 11)
                miniBlock(p1, size: 11)
                miniBlock(p0, size: 16)
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

    private func miniBlock(_ block: WatchBlockType, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1.4, style: .continuous)
            .fill(WatchPalette.fill(for: block))
            .overlay {
                switch block {
                case .priks(let hits):
                    Text("\(hits)")
                        .font(.system(size: size * 0.72, weight: .heavy, design: .rounded))
                        .foregroundStyle(WatchPalette.prikstext)
                case .magix(let kind):
                    Text(kind.glyph)
                        .font(.system(size: size * 0.72, weight: .heavy, design: .rounded))
                        .foregroundStyle(WatchPalette.prikstext)
                default:
                    EmptyView()
                }
            }
            .frame(width: size, height: size)
    }
}
