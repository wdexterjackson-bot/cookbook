//
//  PublicationContentSnapshot+Recipe.swift
//  cookbook
//
//  Recipe (SwiftData, local-only) -> PublicationContentSnapshot (plain
//  Codable, what actually travels to Firestore). Kept out of both model
//  files on purpose — Publication.swift stays free of a SwiftData import,
//  matching this app's existing local/cloud model separation.
//

import Foundation

extension PublicationContentSnapshot {
    static func make(from recipe: Recipe, coverImageURL: String? = nil) -> PublicationContentSnapshot {
        PublicationContentSnapshot(
            title: recipe.title,
            summary: recipe.summary,
            yield: recipe.yield,
            totalTimeMinutes: recipe.totalTimeMinutes,
            ingredientSections: recipe.ingredientSections
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { section in
                    PublicationIngredientSection(
                        heading: section.heading,
                        ingredients: section.ingredients
                            .sorted { $0.sortOrder < $1.sortOrder }
                            .map { PublicationIngredient(displayText: $0.displayText, isOptional: $0.isOptional) }
                    )
                },
            stepSections: recipe.stepSections
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { section in
                    PublicationStepSection(
                        heading: section.heading,
                        steps: section.steps
                            .sorted { $0.sortOrder < $1.sortOrder }
                            .map(\.text)
                    )
                },
            notes: recipe.notes,
            tags: recipe.tags,
            coverImageURL: coverImageURL
        )
    }
}
