//
//  AppBackground.swift
//  cookbook
//
//  One background art choice per app launch, shared by the four tab root
//  screens (Home/Cookbooks/Search/More) — reuses the Cooking Mode
//  background image set rather than needing its own assets.
//  `static let` evaluates exactly once, the first time anything touches
//  it, and stays fixed for the rest of the process's lifetime, matching
//  "randomly choose a background at application launch."
//
//  iPad is a separate pool from iPhone/tvOS: it has its own set of 10
//  numbered backgrounds (01-10), each supplied as a portrait/landscape
//  pair rather than a single idiom-variant image, since asset catalogs
//  don't have an "orientation" axis the way they have "idiom" — the
//  right pair member is picked live at render time based on the current
//  frame size, not fixed at launch. iPhone/tvOS keep the original
//  single-image-per-idiom pool (only 01/06 have iPhone/tvOS art).
//

import Foundation

enum AppBackground {
    private static let assetNames = ["CookingModeBackground01", "CookingModeBackground06"]

    static let assetName: String = assetNames.randomElement() ?? assetNames[0]

    private static let ipadNumbers = 1...10

    private static let ipadNumber: Int = ipadNumbers.randomElement() ?? 1

    static func ipadAssetName(isLandscape: Bool) -> String {
        let padded = String(format: "%02d", ipadNumber)
        let orientation = isLandscape ? "Landscape" : "Portrait"
        return "CookingModeBackgroundIPad\(padded)\(orientation)"
    }
}
