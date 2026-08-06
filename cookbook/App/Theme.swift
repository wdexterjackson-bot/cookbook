//
//  Theme.swift
//  cookbook
//
//  Sketch C "Potluck" design tokens — colors, type, corner radius, and
//  card shadow, all in one place so the next pass (retrofitting existing
//  screens to this visual language) has a single source to pull from
//  instead of scattered literals. Reuses Color(hex:) from Color+Hex.swift.
//
//  Font sourcing: Poppins isn't a system font — real .ttf files (OFL
//  license) are bundled under Resources/Fonts and registered in
//  Info.plist's UIAppFonts. Snell Roundhand (the script accent) IS
//  already an Apple system font (confirmed via `system_profiler
//  SPFontsDataType` — /System/Library/Fonts/Supplemental/SnellRoundhand.ttc),
//  so it needs no bundling.
//

import SwiftUI

extension Color {
    static let potluckTomato = Color(hex: "D6472B")
    static let potluckSunflower = Color(hex: "F2A93B")
    static let potluckSage = Color(hex: "6E9463")
    static let potluckCream = Color(hex: "FFF8EA")
    static let potluckDeepTeal = Color(hex: "1E3A3A")
}

extension Font {
    /// Bold, rounded geometric headlines — Poppins ExtraBold throughout,
    /// per the sketch's type direction.
    static func potluckHeadline(_ size: CGFloat) -> Font {
        .custom("Poppins-ExtraBold", size: size)
    }

    static func potluckSemiboldBody(_ size: CGFloat) -> Font {
        .custom("Poppins-SemiBold", size: size)
    }

    static func potluckBody(_ size: CGFloat) -> Font {
        .custom("Poppins-Regular", size: size)
    }

    /// Playful script accent ("yum!"-style stickers) — Sketch C repurposes
    /// the same script family Sketch A used for lineage notes, but here
    /// it's decorative, not an attribution signal.
    static func potluckScript(_ size: CGFloat) -> Font {
        .custom("Snell Roundhand", size: size)
    }
}

enum PotluckMetrics {
    /// Noticeably rounder than the app's prior corner radius (10pt) —
    /// Sketch C's cards read distinctly more playful/rounded than
    /// Sketches A/B.
    static let cardCornerRadius: CGFloat = 20
    static let pillCornerRadius: CGFloat = 999
}

private struct PotluckCardShadow: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: Color.potluckDeepTeal.opacity(0.18), radius: 12, x: 0, y: 6)
    }
}

extension View {
    /// Heavier lift than the app's existing subtle shadows — matches
    /// Sketch C's "cards carry more shadow lift" direction.
    func potluckCardShadow() -> some View {
        modifier(PotluckCardShadow())
    }
}
