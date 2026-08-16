//
//  FoundationModelsPrepSummaryService.swift
//  cookbook
//
//  Uses Apple's on-device FoundationModels framework, same as
//  FoundationModelsLineImportService — runs fully on-device, no network
//  call, no API key. Unlike line-import (which extracts structured fields
//  via @Generable), this asks for a short freeform paragraph, since a
//  prep summary is naturally prose ("Preheat the oven to 350°F. You'll
//  need a 9x13 pan and a stand mixer.") rather than structured data.
//
//  Known gap: on-device model *inference* may not actually execute inside
//  the iOS Simulator (it typically needs the real Neural Engine) — reviewed
//  against the SDK's public interface but not proven to produce a real
//  model response in this environment, same caveat as line-import.
//

import Foundation
// FoundationModels (Apple Intelligence) has no tvOS build — Apple TV
// hardware doesn't run on-device models at all, unlike the Simulator-vs-
// Neural-Engine inference gap noted below, which is a availability detail
// on platforms that DO ship the framework. isAvailable is simply always
// false here so RecipePrepSummaryServicing's existing "no summary section
// shown at all" fallback (see CookingModePrepReviewView's header comment)
// covers tvOS for free, with no call-site changes.
#if os(iOS)
import FoundationModels
#endif

#if os(iOS)
final class FoundationModelsPrepSummaryService: RecipePrepSummaryServicing {
    var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    func generateSummary(for input: RecipePrepSummaryInput) async throws -> String {
        guard isAvailable else {
            throw RecipePrepSummaryError.unavailable
        }
        guard !input.ingredientLines.isEmpty || !input.stepLines.isEmpty else {
            throw RecipePrepSummaryError.emptyInput
        }

        let session = LanguageModelSession {
            """
            You help a home cook get ready to start cooking, before they
            begin following the numbered steps. Given a recipe's
            ingredients and steps, write a short prep summary covering
            only what's useful to know or do *before* starting:

            - Any equipment the steps imply but don't explicitly call out
              up front — pan sizes/counts (e.g. "two 8x10 pans"), a mixer,
              blender, food processor, thermometer, etc.
            - Whether the oven needs preheating, and to what temperature,
              if that's not the very first step already.
            - Any ingredients that need advance prep before step 1 (e.g.
              softened butter, room-temperature eggs, thawed dough) if the
              steps imply this without stating it directly.

            Keep it brief — 1-3 short sentences, plain prose, no headers
            or bullet points. If there's genuinely nothing beyond what the
            steps already state plainly, say so briefly rather than
            padding with restated instructions. Never invent equipment or
            temperatures the recipe doesn't support — only surface what
            the ingredients/steps actually imply.
            """
        }

        let ingredientsText = input.ingredientLines.joined(separator: "\n")
        let stepsText = input.stepLines.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n")
        let prompt = """
        Recipe: \(input.title)

        Ingredients:
        \(ingredientsText)

        Steps:
        \(stepsText)
        """

        do {
            let response = try await session.respond(to: prompt)
            let summary = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !summary.isEmpty else {
                throw RecipePrepSummaryError.generationFailed
            }
            return summary
        } catch let error as RecipePrepSummaryError {
            throw error
        } catch {
            throw RecipePrepSummaryError.generationFailed
        }
    }
}
#else
final class FoundationModelsPrepSummaryService: RecipePrepSummaryServicing {
    var isAvailable: Bool { false }

    func generateSummary(for input: RecipePrepSummaryInput) async throws -> String {
        throw RecipePrepSummaryError.unavailable
    }
}
#endif
