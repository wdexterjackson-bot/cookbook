//
//  CookbookSection.swift
//  cookbook
//
//  A chapter within one Cookbook. Named CookbookSection, deliberately not
//  "Section" — that would shadow SwiftUI.Section everywhere in the app,
//  the same collision a bare "Group" model caused in Phase 2 milestone 2B.
//

import Foundation
import SwiftData

@Model
final class CookbookSection {
    var id: UUID
    var title: String
    var sortOrder: Int
    /// CookbookSectionIconCatalog.assetName — nil until either a default
    /// match is assigned (CookbookConfigurationView, on adding a chapter
    /// whose title matches a manifest category) or the user picks one
    /// explicitly. Optional so existing chapters predating this field
    /// decode/migrate fine with no icon shown.
    var iconAssetName: String?

    init(title: String, sortOrder: Int = 0, iconAssetName: String? = nil) {
        self.id = UUID()
        self.title = title
        self.sortOrder = sortOrder
        self.iconAssetName = iconAssetName
    }
}
