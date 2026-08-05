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

    init(title: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.title = title
        self.sortOrder = sortOrder
    }
}
