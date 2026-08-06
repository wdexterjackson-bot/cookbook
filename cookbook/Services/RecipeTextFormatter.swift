//
//  RecipeTextFormatter.swift
//  cookbook
//
//  The readable fallback for direct sharing (SHR-003): plain text so a
//  recipient without the app — or any share destination that can't render
//  a deep link — still gets the full recipe.
//

import Foundation

enum RecipeTextFormatter {
    static func plainText(for recipe: Recipe) -> String {
        var lines: [String] = [recipe.title]

        if let authorLineage = recipe.authorLineage, !authorLineage.isEmpty {
            lines.append("by \(authorLineage)")
        }

        if !recipe.summary.isEmpty {
            lines.append("")
            lines.append(recipe.summary)
        }

        var metaLine: [String] = []
        if !recipe.yield.isEmpty { metaLine.append("Yield: \(recipe.yield)") }
        if let total = recipe.totalTimeMinutes { metaLine.append("Total time: \(total) min") }
        if !metaLine.isEmpty {
            lines.append("")
            lines.append(metaLine.joined(separator: " · "))
        }

        appendIngredients(from: recipe, to: &lines)
        appendSteps(from: recipe, to: &lines)

        if !recipe.notes.isEmpty {
            lines.append("")
            lines.append("NOTES")
            lines.append(recipe.notes)
        }

        lines.append("")
        lines.append("Shared from the Family & Friends Cookbook app.")

        return lines.joined(separator: "\n")
    }

    private static func appendIngredients(from recipe: Recipe, to lines: inout [String]) {
        let sections = recipe.ingredientSections.sorted { $0.sortOrder < $1.sortOrder }
        guard !sections.isEmpty else { return }

        lines.append("")
        lines.append("INGREDIENTS")
        for section in sections {
            if let heading = section.heading, !heading.isEmpty {
                lines.append("")
                lines.append("\(heading):")
            }
            let ingredients = section.ingredients.sorted { $0.sortOrder < $1.sortOrder }
            for ingredient in ingredients {
                lines.append("- \(ingredient.displayText)")
            }
        }
    }

    private static func appendSteps(from recipe: Recipe, to lines: inout [String]) {
        let sections = recipe.stepSections.sorted { $0.sortOrder < $1.sortOrder }
        guard !sections.isEmpty else { return }

        lines.append("")
        lines.append("STEPS")
        var stepNumber = 1
        for section in sections {
            if let heading = section.heading, !heading.isEmpty {
                lines.append("")
                lines.append("\(heading):")
            }
            let steps = section.steps.sorted { $0.sortOrder < $1.sortOrder }
            for step in steps {
                lines.append("\(stepNumber). \(step.text)")
                stepNumber += 1
            }
        }
    }
}
