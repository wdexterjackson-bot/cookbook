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
    @Environment(AccountState.self) private var accountState
    @State private var isPresentingImport = false
    @State private var isPresentingPublishCookbook = false
    @State private var isPresentingManageGroups = false
    @State private var isPresentingManageCommunityCookbooks = false
    @State private var isPresentingStandardizeRecipes = false
    @State private var isPresentingExportPDF = false
    #if os(iOS)
    @State private var isPresentingPhotoScan = false
    #endif
    #if !os(tvOS)
    @State private var isPresentingSamplePDF = false
    #endif
    /// "Manage Community Cookbooks" is only worth offering (and only ever
    /// lists anything once opened) if the user is an active admin of at
    /// least one group — a plain member has nothing to manage there.
    @State private var isAdminOfAnyCommunityCookbook = false

    private let groupsService: GroupsServicing = FirestoreGroupsService()

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
                    Label("Publish a Cookbook to a Community Cookbook", systemImage: "square.and.arrow.up.on.square")
                }
                #if os(iOS)
                // Both open the same Photo/Scan screen — it already offers
                // Take Photo and Choose Photo together (see
                // RecipePhotoScanView), so either entry point here reaches
                // the same capture-or-pick-then-OCR flow CreateHubView's
                // own "Photo / Scan" button uses.
                Button {
                    isPresentingPhotoScan = true
                } label: {
                    Label("Scan Recipe (Camera)", systemImage: "camera")
                }
                Button {
                    isPresentingPhotoScan = true
                } label: {
                    Label("Import Recipe from Picture", systemImage: "photo.on.rectangle")
                }
                #endif

                Section("Community Cookbooks") {
                    Button {
                        isPresentingManageGroups = true
                    } label: {
                        Label("Manage Groups", systemImage: "person.3")
                    }
                    if isAdminOfAnyCommunityCookbook {
                        Button {
                            isPresentingManageCommunityCookbooks = true
                        } label: {
                            Label("Manage Community Cookbooks", systemImage: "person.3.sequence")
                        }
                    }
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

                // Not available on tvOS — see SamplePDFPreviewView's header
                // comment for why.
                #if !os(tvOS)
                Section {
                    Button {
                        isPresentingSamplePDF = true
                    } label: {
                        Label("View Sample Import File (Sample.pdf)", systemImage: "doc.text.magnifyingglass")
                    }
                } footer: {
                    Text("If you'd like to see what a properly formatted import file looks like, you can view Sample.pdf.")
                }
                #endif
            }
            .potluckHiddenScrollBackground()
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
            .task {
                await loadAdminStatus()
            }
        }
        .sheet(isPresented: $isPresentingImport) {
            ImportRecipesFileView()
        }
        .sheet(isPresented: $isPresentingPublishCookbook) {
            PublishCookbookToFamilyCookbookView()
        }
        .sheet(isPresented: $isPresentingManageGroups) {
            ManageGroupsListView()
        }
        .sheet(isPresented: $isPresentingManageCommunityCookbooks) {
            ManageCommunityCookbooksListView()
        }
        .sheet(isPresented: $isPresentingStandardizeRecipes) {
            StandardizeRecipesView()
        }
        .sheet(isPresented: $isPresentingExportPDF) {
            ExportCookbookPDFView()
        }
        #if os(iOS)
        .sheet(isPresented: $isPresentingPhotoScan) {
            RecipePhotoScanView()
        }
        #endif
        #if !os(tvOS)
        .sheet(isPresented: $isPresentingSamplePDF) {
            SamplePDFPreviewView()
        }
        #endif
    }

    private func loadAdminStatus() async {
        guard let userID = accountState.currentUserID else {
            isAdminOfAnyCommunityCookbook = false
            return
        }
        let memberships = (try? await groupsService.fetchMemberships(forUser: userID)) ?? []
        isAdminOfAnyCommunityCookbook = memberships.contains { $0.status == .active && $0.role == .admin }
    }
}

#Preview {
    AdministratorView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
}
