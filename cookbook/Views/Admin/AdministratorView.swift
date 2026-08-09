//
//  AdministratorView.swift
//  cookbook
//
//  A general tools/data-management screen, open to any signed-in user
//  (not a locked-down admin role — the name is just what this screen is
//  called). Only Import exists today; the action-list shape is what makes
//  adding more actions later straightforward, not a promise of specific
//  future ones. See Recipe_Import_Format.md for the bulk-import file
//  format.
//

import SwiftUI
import SwiftData

struct AdministratorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingImport = false
    @State private var isPresentingPublishCookbook = false
    @State private var isPresentingStandardizeRecipes = false
    @State private var isPresentingExportPDF = false

    var body: some View {
        NavigationStack {
            List {
                Button {
                    isPresentingImport = true
                } label: {
                    Label("Import Recipes from File", systemImage: "square.and.arrow.down.on.square")
                }
                Button {
                    isPresentingPublishCookbook = true
                } label: {
                    Label("Publish a Cookbook to a Family Cookbook", systemImage: "square.and.arrow.up.on.square")
                }
                Button {
                    isPresentingStandardizeRecipes = true
                } label: {
                    Label("Standardize Recipes", systemImage: "wand.and.stars")
                }
                Button {
                    isPresentingExportPDF = true
                } label: {
                    Label("Export Cookbook to PDF", systemImage: "doc.richtext")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.potluckCream)
            .navigationTitle("Administrator")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $isPresentingImport) {
            ImportRecipesFileView()
        }
        .sheet(isPresented: $isPresentingPublishCookbook) {
            PublishCookbookToFamilyCookbookView()
        }
        .sheet(isPresented: $isPresentingStandardizeRecipes) {
            StandardizeRecipesView()
        }
        .sheet(isPresented: $isPresentingExportPDF) {
            ExportCookbookPDFView()
        }
    }
}

#Preview {
    AdministratorView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
}
