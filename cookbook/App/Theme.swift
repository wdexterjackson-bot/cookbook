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
    /// A denim/steel blue — deliberately darker than a standard system
    /// blue but lighter than navy. Used for the Getting Started row
    /// buttons only; every other button on Home still uses potluckTomato.
    static let potluckDenimBlue = Color(hex: "2F6690")
}

extension Font {
    /// Bold, rounded geometric headlines — Poppins ExtraBold throughout,
    /// per the sketch's type direction.
    ///
    /// `relativeTo:` matters here, not just cosmetically: `.custom(_,
    /// size:)` without it is a *fixed* point size that ignores the user's
    /// Dynamic Type setting entirely — a real accessibility gap (PRD
    /// A11Y-001) discovered in a 2026-08-08 review, since every call site
    /// across the app passes a literal size to these four functions.
    /// `.custom(_, size:, relativeTo:)` scales that size against the given
    /// text style the same way system fonts do.
    static func potluckHeadline(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .title2) -> Font {
        .custom("Poppins-ExtraBold", size: size, relativeTo: textStyle)
    }

    static func potluckSemiboldBody(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        .custom("Poppins-SemiBold", size: size, relativeTo: textStyle)
    }

    static func potluckBody(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        .custom("Poppins-Regular", size: size, relativeTo: textStyle)
    }

    /// Playful script accent ("yum!"-style stickers) — Sketch C repurposes
    /// the same script family Sketch A used for lineage notes, but here
    /// it's decorative, not an attribution signal.
    static func potluckScript(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        .custom("Snell Roundhand", size: size, relativeTo: textStyle)
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

    /// `.potluckHiddenScrollBackground()` itself is unavailable on tvOS
    /// (a List/Form there has no equivalent concept of a swappable
    /// background material) — every screen in this app calls it to let its
    /// own `Color.potluckCream`/`potluckHubBackground()` show through
    /// instead of the system's default List/Form chrome, so this one
    /// wrapper is what makes that a no-op on tvOS instead of a build error
    /// at every one of those call sites.
    @ViewBuilder
    func potluckHiddenScrollBackground() -> some View {
        #if os(tvOS)
        self
        #else
        self.scrollContentBackground(.hidden)
        #endif
    }

    /// The cream base every tab root already used, plus this launch's
    /// AppBackground art at 35% opacity filling the screen behind it.
    ///
    /// iPad has portrait/landscape-matched art (each pair rendered at the
    /// device's exact aspect ratio), so `.fill` + `.clipped()` covers the
    /// full screen with no cropping in practice; the GeometryReader reads
    /// the live frame size on every layout pass, so rotating the device
    /// swaps the image immediately rather than freezing whatever was
    /// picked at launch. iPhone/tvOS have only one image per pick (no
    /// orientation pairs), so they keep `.fit` — the whole image shows
    /// rather than being cropped/zoomed to cover the frame, and any
    /// letterboxing just reveals the same cream color underneath.
    func potluckHubBackground() -> some View {
        background {
            GeometryReader { geometry in
                ZStack {
                    Color.potluckCream
                    #if os(iOS)
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        Image(AppBackground.ipadAssetName(isLandscape: geometry.size.width > geometry.size.height))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .opacity(0.35)
                            .accessibilityHidden(true)
                    } else {
                        Image(AppBackground.assetName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .opacity(0.35)
                            .accessibilityHidden(true)
                    }
                    #else
                    Image(AppBackground.assetName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .opacity(0.35)
                        .accessibilityHidden(true)
                    #endif
                }
            }
            .ignoresSafeArea()
        }
    }
}
