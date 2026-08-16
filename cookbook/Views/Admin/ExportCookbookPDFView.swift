//
//  ExportCookbookPDFView.swift
//  cookbook
//
//  Administrator's "Export Cookbook to PDF" action — pick one personal
//  cookbook, generate a text-only PDF (no photos, no Notes section) via
//  CookbookPDFExporter, and hand it to the system's own save/share sheet
//  through .fileExporter, matching the existing cookbook-backup export
//  flow in CookbooksHubView.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// FileDocument (and therefore .fileExporter) is unavailable on tvOS — no
// user-facing document/file system there — so this whole screen's real
// implementation is iOS/macOS-only; tvOS gets a minimal stub below with
// the same name/init so AdministratorView's call site never has to know.
#if os(iOS) || os(macOS)
struct ExportCookbookPDFView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountState.self) private var accountState
    @Query private var allCookbooks: [Cookbook]
    @Query private var allRecipes: [Recipe]

    @State private var selectedCookbookID: UUID?
    @State private var isExporting = false
    @State private var pdfDocument: PDFFileDocument?
    @State private var isPresentingExporter = false
    @State private var exportErrorMessage: String?
    @State private var isPresentingExportSuccess = false

    private var ownedCookbooks: [Cookbook] {
        allCookbooks.filter { $0.ownerID == accountState.currentOwnerID }
    }

    private var selectedCookbook: Cookbook? {
        ownedCookbooks.first { $0.id == selectedCookbookID }
    }

    private var exportFilename: String {
        guard let title = selectedCookbook?.title else { return "Cookbook.pdf" }
        let sanitizedTitle = title.replacingOccurrences(of: "/", with: "-")
        return "\(sanitizedTitle).pdf"
    }

    private var recipeCountForSelectedCookbook: Int {
        guard let selectedCookbookID else { return 0 }
        return allRecipes.filter { $0.cookbookID == selectedCookbookID }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Cookbook", selection: $selectedCookbookID) {
                        Text("Choose a Cookbook").tag(UUID?.none)
                        ForEach(ownedCookbooks) { cookbook in
                            Text(cookbook.title).tag(UUID?.some(cookbook.id))
                        }
                    }
                } footer: {
                    Text("Creates a PDF with one recipe per page — name, author, chapter, ingredients, and directions. Photos and notes aren't included.")
                }

                Section {
                    Button("Export Cookbook to PDF") {
                        exportSelectedCookbook()
                    }
                    .disabled(selectedCookbookID == nil || isExporting || recipeCountForSelectedCookbook == 0)
                }

                if selectedCookbookID != nil && recipeCountForSelectedCookbook == 0 {
                    Section {
                        Text("This cookbook has no recipes yet.")
                            .foregroundStyle(.secondary)
                    }
                }

                if isExporting {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Generating PDF…")
                        }
                    }
                }
            }
            .potluckHiddenScrollBackground()
            .background(Color.potluckCream)
            .navigationTitle("Export Cookbook to PDF")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Couldn't Export Cookbook", isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportErrorMessage ?? "")
            }
            .alert("Export Complete", isPresented: $isPresentingExportSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(exportFilename) was saved. You may close this window now.")
            }
        }
        .fileExporter(
            isPresented: $isPresentingExporter,
            document: pdfDocument,
            contentType: .pdf,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                isPresentingExportSuccess = true
            case .failure(let error):
                exportErrorMessage = error.localizedDescription
            }
            pdfDocument = nil
        }
    }

    private func exportSelectedCookbook() {
        guard let selectedCookbook else { return }
        let cookbookID = selectedCookbook.id
        let recipes = allRecipes.filter { $0.cookbookID == cookbookID }
        isExporting = true
        Task {
            // Yields at least one frame so the "Generating PDF…" row
            // actually renders — same fix as the recipe-import save flow
            // and RootTabView's standardization overlay, for the same
            // reason: this is fast synchronous work that would otherwise
            // set isExporting true and false within one run-loop turn.
            await Task.yield()
            let data = CookbookPDFExporter.generatePDF(for: selectedCookbook, recipes: recipes)
            pdfDocument = PDFFileDocument(data: data)
            isExporting = false
            isPresentingExporter = true
        }
    }
}

private struct PDFFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let fileData = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = fileData
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    ExportCookbookPDFView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
}
#else
struct ExportCookbookPDFView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Not Available on tvOS",
                systemImage: "tv.slash",
                description: Text("Exporting a cookbook to PDF isn't supported on this device — use your iPhone, iPad, or Mac instead.")
            )
            .navigationTitle("Export Cookbook to PDF")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
#endif
