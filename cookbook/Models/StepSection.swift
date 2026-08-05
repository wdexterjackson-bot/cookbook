//
//  StepSection.swift
//  cookbook
//

import Foundation
import SwiftData

@Model
final class StepSection {
    var id: UUID
    var heading: String?
    var sortOrder: Int

    @Relationship(deleteRule: .cascade, inverse: nil)
    var steps: [Step]

    init(heading: String? = nil, sortOrder: Int = 0) {
        self.id = UUID()
        self.heading = heading
        self.sortOrder = sortOrder
        self.steps = []
    }
}

@Model
final class Step {
    var id: UUID
    var text: String
    var sortOrder: Int

    init(text: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.text = text
        self.sortOrder = sortOrder
    }
}
