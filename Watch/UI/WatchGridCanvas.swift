//
//  WatchGridCanvas.swift
//  64 cases + cellules identifiées (slide compactage). Hit-test dans la Vue.
//

import SwiftUI

struct WatchGridCanvas: View {
    let cells: [WatchLiveCell]
    let highlightedColumn: Int?
    let aimedBombCell: WatchGridAddress?
    let incomingPreview: [WatchBlockType]?
    let magixFX: WatchMagixFX?
    let previewBlock: WatchBlockType
    let isBombMode: Bool
    let isInteractive: Bool
    let onHighlightColumn: (Int?) -> Void
    let onAimBomb: (WatchGridAddress?) -> Void
    let onDrop: (Int) -> Void
    let onPlaceBomb: () -> Void
    let onCancel: () -> Void

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / CGFloat(WatchGridLayout.columnCount)
            let gutter: CGFloat = 1
            let inner = cell - gutter

            ZStack {
                WatchPalette.board

                ForEach(0..<WatchGridLayout.rowCount, id: \.self) { row in
                    ForEach(0..<WatchGridLayout.columnCount, id: \.self) { col in
                        RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                            .fill(WatchPalette.emptyCell)
                            .frame(width: inner, height: inner)
                            .position(
                                x: CGFloat(col) * cell + cell / 2,
                                y: CGFloat(row) * cell + cell / 2
                            )
                    }
                }

                ForEach(cells) { item in
                    WatchBlockTile(block: item.block)
                        .frame(width: inner, height: inner)
                        .position(
                            x: CGFloat(item.col) * cell + cell / 2,
                            y: CGFloat(item.row) * cell + cell / 2
                        )
                        .transition(.opacity)
                }
                .animation(
                    .easeOut(duration: WatchZenRules.lineRiseAnimationDuration),
                    value: cells
                )

                if let magixFX {
                    magixOverlay(fx: magixFX, cell: cell, inner: inner)
                }

                if let incomingPreview, incomingPreview.count == WatchGridLayout.columnCount {
                    let bottom = WatchGridLayout.bottomRowIndex
                    ForEach(0..<WatchGridLayout.columnCount, id: \.self) { col in
                        WatchBlockTile(block: incomingPreview[col])
                            .frame(width: inner, height: inner / 2)
                            .opacity(0.85)
                            .position(
                                x: CGFloat(col) * cell + cell / 2,
                                y: CGFloat(bottom) * cell + cell * 0.75
                            )
                    }
                    .allowsHitTesting(false)
                }

                if isBombMode, let aimedBombCell {
                    ForEach(WatchZenRules.bombAffectedCells(center: aimedBombCell), id: \.self) { addr in
                        RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                            .fill(WatchPalette.orange.opacity(0.22))
                            .overlay {
                                RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                                    .stroke(WatchPalette.orange, lineWidth: 1.2)
                            }
                            .frame(width: inner, height: inner)
                            .position(
                                x: CGFloat(addr.col) * cell + cell / 2,
                                y: CGFloat(addr.row) * cell + cell / 2
                            )
                    }
                    .allowsHitTesting(false)
                }

                if let highlightedColumn, !isBombMode {
                    columnAimOverlay(
                        column: highlightedColumn,
                        cell: cell,
                        inner: inner,
                        side: side
                    )
                    .allowsHitTesting(false)
                    .transaction { $0.animation = nil }
                }
            }
            .frame(width: side, height: side)
            .clipped() // la ligne monte depuis le bord bas
            .contentShape(Rectangle())
            .gesture(gridGesture(side: side, cell: cell))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func gridGesture(side: CGFloat, cell: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isInteractive else { return }
                let addr = address(at: value.location, side: side, cell: cell)
                if isBombMode {
                    onAimBomb(addr)
                } else {
                    onHighlightColumn(addr?.col)
                }
            }
            .onEnded { value in
                guard isInteractive else { return }
                let addr = address(at: value.location, side: side, cell: cell)
                if isBombMode {
                    if addr != nil {
                        onAimBomb(addr)
                        onPlaceBomb()
                    } else {
                        onCancel()
                    }
                } else if let addr {
                    onDrop(addr.col)
                } else {
                    onCancel()
                }
            }
    }

    @ViewBuilder
    private func columnAimOverlay(column: Int, cell: CGFloat, inner: CGFloat, side: CGFloat) -> some View {
        let landing = landingRow(in: column)
        let x = CGFloat(column) * cell + cell / 2
        let refused = landing == nil
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill((refused ? Color.red : Color.white).opacity(0.16))
                .overlay {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(refused ? Color.red.opacity(0.85) : WatchPalette.yellow, lineWidth: 1.5)
                }
                .frame(width: cell, height: side)
                .position(x: x, y: side / 2)

            if let landing, !previewBlock.isEmpty {
                WatchBlockTile(block: previewBlock)
                    .opacity(0.58)
                    .frame(width: inner, height: inner)
                    .overlay {
                        RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                            .stroke(Color.white.opacity(0.9), lineWidth: 1)
                    }
                    .position(
                        x: x,
                        y: CGFloat(landing) * cell + cell / 2
                    )
            }
        }
    }

    private func landingRow(in column: Int) -> Int? {
        let occupied = Set(cells.filter { $0.col == column }.compactMap { cell -> Int? in
            guard cell.row >= 0, cell.row < WatchGridLayout.rowCount else { return nil }
            return cell.row
        })
        for row in WatchGridLayout.topRowIndex..<WatchGridLayout.rowCount {
            if !occupied.contains(row) { return row }
        }
        return nil
    }

    @ViewBuilder
    private func magixOverlay(fx: WatchMagixFX, cell: CGFloat, inner: CGFloat) -> some View {
        let tint = fx.paintColor.map { WatchPalette.color(named: $0).opacity(0.45) }
            ?? Color.white.opacity(0.35)
        ZStack {
            ForEach(fx.highlight, id: \.self) { addr in
                RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                    .fill(tint)
                    .overlay {
                        RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                            .stroke(Color.white.opacity(0.85), lineWidth: 1)
                    }
                    .frame(width: inner, height: inner)
                    .position(
                        x: CGFloat(addr.col) * cell + cell / 2,
                        y: CGFloat(addr.row) * cell + cell / 2
                    )
            }
            Text(fx.name)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(WatchPalette.prikstext)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(WatchPalette.priks.opacity(0.86), in: Capsule())
                .position(
                    x: CGFloat(fx.landing.col) * cell + cell / 2,
                    y: max(10, CGFloat(fx.landing.row) * cell - 6)
                )
        }
        .allowsHitTesting(false)
    }

    private func address(at point: CGPoint, side: CGFloat, cell: CGFloat) -> WatchGridAddress? {
        guard point.x >= 0, point.y >= 0, point.x < side, point.y < side else { return nil }
        let col = min(max(Int(point.x / cell), 0), WatchGridLayout.columnCount - 1)
        let row = min(max(Int(point.y / cell), 0), WatchGridLayout.rowCount - 1)
        return WatchGridAddress(row: row, col: col)
    }
}

struct WatchBlockTile: View {
    let block: WatchBlockType

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                    .fill(WatchPalette.fill(for: block))
                if let mark = WatchBlockTile.mark(for: block) {
                    Text(mark)
                        .font(.system(size: max(8, side * 0.62), weight: .heavy, design: .rounded))
                        .foregroundStyle(WatchPalette.prikstext)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
            }
        }
    }

    private static func mark(for block: WatchBlockType) -> String? {
        switch block {
        case .priks(let hits): return "\(hits)"
        case .magix(let kind): return kind.glyph
        default: return nil
        }
    }
}
