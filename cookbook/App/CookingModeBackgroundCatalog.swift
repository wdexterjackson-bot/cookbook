//
//  CookingModeBackgroundCatalog.swift
//  cookbook
//
//  The list of kitchen-scene background images Cooking Mode picks from —
//  shared by the video sheet (CookingModeVideoSheet) and the step pager
//  (CookingModeView), so there's one place to extend when more images are
//  imported later (10 per device idiom, per the "im2" source folder — not
//  yet imported; this catalog just needs its `imageNames` list extended
//  once that happens, nothing else changes). Each name is one imageset
//  containing iphone/ipad/tv-idiom renditions together (see
//  CookingModeBackground01.imageset's Contents.json) — Image(_:) resolves
//  the right one for whatever device this is actually running on
//  automatically, no manual idiom branching needed.
//

import Foundation

enum CookingModeBackgroundCatalog {
    static let imageNames = ["CookingModeBackground01", "CookingModeBackground06"]

    /// A random name, different from `excluding` whenever more than one
    /// name exists — used to rotate backgrounds (video sheet on each open,
    /// step pager on each step change) without repeating the one just
    /// shown.
    static func randomName(excluding: String?) -> String {
        guard imageNames.count > 1 else {
            return imageNames.first ?? "CookingModeBackground01"
        }
        let candidates: [String]
        if let excluding {
            candidates = imageNames.filter { $0 != excluding }
        } else {
            candidates = imageNames
        }
        return candidates.randomElement() ?? excluding ?? imageNames[0]
    }
}
