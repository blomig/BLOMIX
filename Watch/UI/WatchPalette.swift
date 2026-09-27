//
//  WatchPalette.swift
//  Skin default figé (`color_skins.json` id default). Pas de JSON Watch.
//

import SwiftUI

enum WatchPalette {
    static let blue   = Color(hex: 0x00b3e9)
    static let red    = Color(hex: 0xf2009f)
    static let purple = Color(hex: 0xfda1ff)
    static let yellow = Color(hex: 0xffb200)
    static let green  = Color(hex: 0x008e34)
    static let orange = Color(hex: 0x00688b)
    static let priks  = Color(hex: 0x00024c)
    static let prikstext = Color(hex: 0xead400)
    static let emptyCell = Color(white: 0.16)
    static let board = Color.black
    static let highlight = Color.white.opacity(0.22)

    static func fill(for block: WatchBlockType) -> Color {
        switch block {
        case .empty:
            return emptyCell
        case .color(let name):
            return color(named: name)
        case .priks, .magix:
            return priks
        }
    }

    static func color(named name: String) -> Color {
        switch name {
        case "blue":   return blue
        case "red":    return red
        case "purple": return purple
        case "yellow": return yellow
        case "green":  return green
        case "orange": return orange
        default:       return red
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
