//
//  ImportReviewView.swift
//  cookbook
//
//  Shown after RecipeFileImportCoordinator.parseRecipes finishes and
//  before anything is saved — lets the user check that the parsed data
//  (title, chapter, author, ingredients, steps, notes) actually lines up
//  with the source file. Nothing is written to modelContext until
//  "Approve & Save" runs RecipeFileImportCoordinator.commit; "Abort" just
//  dismisses, and since nothing was persisted yet, that's a real no-op.
//

import SwiftUI
import SwiftData

// Only ever reached from ImportRecipesFileView, which is itself iOS/macOS
// -only (see its header comment) — DisclosureGroup below is unavailable on
// tvOS anyway, so this whole file follows the same platform split rather
// than needing its own tvOS stub (nothing on tvOS references this type).
#if os(iOS) || os(macOS)
struct ImportReviewView: View {
    let preview: RecipeFileImportPreview
    let cookbook: Cookbook
    let ownerID: String
    let importSession: RecipeImportSession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var saveOutcome: SaveOutcome?

    private enum SaveOutcome {
        case saved(count: Int)
        case failed(message: String)
    }

    private var existingChapterTitlesLowercased: Set<String> {
        Set(cookbook.sections.map { $0.title.lowercased() })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let saveOutcome {
                    outcomeView(saveOutcome)
                } else {
                    reviewList
                }
            }
            .navigationTitle("Review Import")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if saveOutcome == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abort", role: .destructive) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Approve & Save") { commit() }
                            .disabled(preview.drafts.isEmpty || importSession.phase != .idle)
                    }
                }
            }
        }
    }

    private var reviewList: some View {
        List {
            Section {
                Text("Importing into **\(cookbook.title)**. Review the \(preview.drafts.count) recipe\(preview.drafts.count == 1 ? "" : "s") below, then Approve & Save to add them, or Abort to discard the whole file — nothing is saved until you approve.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !preview.drafts.isEmpty {
                Section("Recipes to Import (\(preview.drafts.count))") {
                    ForEach(preview.drafts) { draft in
                        DisclosureGroup {
                            draftDetail(draft)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(draft.title)
                                    .font(.headline)
                                Text(summaryLine(for: draft))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !preview.failedChunks.isEmpty {
                Section("Couldn't Be Parsed (\(preview.failedChunks.count))") {
                    ForEach(preview.failedChunks, id: \.self) { snippet in
                        Text(snippet)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if importSession.phase == .saving {
                Section {
                    HStack {
                        ProgressView()
                        Text("Saving…")
                    }
                }
            }
        }
        .potluckHiddenScrollBackground()
        .background(Color.potluckCream)
    }

    private func chapterStatus(for draft: DraftRecipe) -> String? {
        guard let chapterName = draft.chapterName?.trimmingCharacters(in: .whitespacesAndNewlines), !chapterName.isEmpty else {
            return nil
        }
        return existingChapterTitlesLowercased.contains(chapterName.lowercased())
            ? chapterName
            : "\(chapterName) (new chapter)"
    }

    private func summaryLine(for draft: DraftRecipe) -> String {
        var parts: [String] = []
        if let chapterStatus = chapterStatus(for: draft) {
            parts.append(chapterStatus)
        }
        parts.append("\(draft.ingredients.count) ingredient\(draft.ingredients.count == 1 ? "" : "s")")
        parts.append("\(draft.steps.count) step\(draft.steps.count == 1 ? "" : "s")")
        if !draft.videoURLs.isEmpty {
            parts.append("\(draft.videoURLs.count) video\(draft.videoURLs.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    private func draftDetail(_ draft: DraftRecipe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            labeledLine("By", (draft.authorLineage?.isEmpty == false) ? draft.authorLineage! : "Anonymous")

            if !draft.ingredients.isEmpty {
                labeledBlock(
                    "Ingredients",
                    draft.ingredients.map { RecipeFileImportCoordinator.displayText(for: $0) }.joined(separator: "\n")
                )
            }
            if !draft.steps.isEmpty {
                labeledBlock(
                    "Steps",
                    draft.steps.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n")
                )
            }
            labeledBlock("Notes", draft.notes.isEmpty ? "No notes." : draft.notes)
            if !draft.videoURLs.isEmpty {
                labeledBlock("Videos", draft.videoURLs.joined(separator: "\n"))
            }
        }
        .font(.caption)
        .padding(.vertical, 4)
    }

    private func labeledLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("\(label):").foregroundStyle(.secondary)
            Text(value)
        }
    }

    private func labeledBlock(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }

    @ViewBuilder
    private func outcomeView(_ outcome: SaveOutcome) -> some View {
        VStack(spacing: 16) {
            Spacer()
            switch outcome {
            case .saved(let count):
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("\(count) recipe\(count == 1 ? "" : "s") saved to \(cookbook.title).")
                Text("You may close this window now.")
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                Text("Couldn't save: \(message)")
                Text("Nothing was imported.")
                    .foregroundStyle(.secondary)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding()
    }

    private func commit() {
        Task {
            importSession.phase = .saving
            // RecipeFileImportCoordinator.commit is synchronous, in-memory
            // SwiftData work with no per-item I/O — genuinely backgrounding
            // it isn't needed (and SwiftData's ModelContext shouldn't be
            // touched off its owning actor anyway). Without a real
            // suspension point, though, .saving and the eventual outcome
            // would both land in the same run-loop turn and the "Saving…"
            // row would never actually render — Task.yield() forces one.
            await Task.yield()
            let result = RecipeFileImportCoordinator.commit(preview.drafts, into: cookbook, ownerID: ownerID, modelContext: modelContext)
            importSession.phase = .idle
            switch result {
            case .success(let count):
                saveOutcome = .saved(count: count)
            case .failure(let error):
                saveOutcome = .failed(message: error.localizedDescription)
            }
        }
    }
}

#Preview {
    let cookbook = Cookbook(ownerID: "preview", title: "Family Favorites")
    return ImportReviewView(
        preview: RecipeFileImportPreview(
            drafts: [
                DraftRecipe(
                    title: "Sausage Balls",
                    chapterName: "Appetizers",
                    notes: "",
                    authorLineage: "Kathleen Hurd",
                    ingredients: [ParsedIngredientLine(name: "cheddar cheese", quantity: 10, unit: "oz")],
                    steps: ["Cut cheese into cubes."]
                )
            ],
            failedChunks: ["Name: Unreadable Recipe"]
        ),
        cookbook: cookbook,
        ownerID: "preview",
        importSession: RecipeImportSession()
    )
    .modelContainer(for: Recipe.self, inMemory: true)
}
#endif
