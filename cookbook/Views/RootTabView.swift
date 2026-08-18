//
//  RootTabView.swift
//  cookbook
//
//  5-tab navigation: Home / Cookbooks / Create / Search / More. The first
//  three are the original dashboard spec's tabs, kept exactly as they
//  were; Search and More replaced the old direct Messages/Profile tabs —
//  Messages and Profile (plus Administrator, moved here from inside
//  Profile) now live inside More's own hub instead, see MoreHubView. Create
//  isn't a persistent destination (it's "a centered, visually-elevated tab
//  button" per spec) — selecting it presents CreateHubView as a sheet and
//  immediately reverts the tab selection, so it never "sticks" as an
//  active tab the way a real destination would.
//

import SwiftUI
import SwiftData

private enum RootTab: Hashable {
    case home, cookbooks, create, search, more
}

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountState.self) private var accountState
    @Environment(ActiveCookbookState.self) private var activeCookbookState
    @Environment(PendingFileImportState.self) private var pendingFileImportState
    @State private var selectedTab: RootTab = .home
    @State private var previousTab: RootTab = .home
    @State private var isPresentingCreate = false
    @State private var bootstrapErrorMessage: String?
    @State private var isPresentingCloudCookbooksAvailable = false
    @State private var isPresentingCloudRestoreFromPrompt = false
    @State private var cloudCookbooksAvailableCount = 0
    @State private var cookbooksPendingStandardization: [Cookbook] = []
    @State private var isPresentingStandardizePrompt = false
    @State private var isStandardizing = false

    private let syncService: PersonalCookbookSyncServicing = FirestorePersonalCookbookSyncService()

    var body: some View {
        // Split from the rest of the modifier chain below — adding the
        // pending-file-import sheet as one more link on an already-long
        // chain pushed the type checker over its time budget on tvOS
        // (unable to resolve module dependency-style "too complex"
        // error), even though the two are logically unrelated. Two
        // separate view expressions type-check independently.
        tabViewContent
            .sheet(isPresented: isPresentingPendingFileImportBinding) {
                if let url = pendingFileImportState.url {
                    ImportRecipesFileView(initialFileURL: url)
                }
            }
    }

    private var isPresentingPendingFileImportBinding: Binding<Bool> {
        Binding(
            get: { pendingFileImportState.url != nil },
            set: { isPresented in if !isPresented { pendingFileImportState.url = nil } }
        )
    }

    private var tabViewContent: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(RootTab.home)

            CookbooksHubView()
                .tabItem {
                    Label("Cookbooks", systemImage: "book.closed")
                }
                .tag(RootTab.cookbooks)

            Color.clear
                .tabItem {
                    Image(systemName: "plus.circle.fill")
                    Text("Create")
                }
                .tag(RootTab.create)

            SearchHubView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(RootTab.search)

            MoreHubView()
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .tag(RootTab.more)
        }
        .tint(Color.potluckTomato)
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .create {
                isPresentingCreate = true
                // Deferred to the next run loop turn rather than set
                // synchronously alongside isPresentingCreate above — both
                // changing in the same update stacks two UIKit-transition-
                // triggering state changes (tab selection + sheet
                // presentation) into one transaction, which is the same
                // shape that caused a real SIGTRAP crash during tab-bar-item
                // layout (missing-environment assertion in
                // UIKitBarItemHost.initializeSize(), observed 2026-08-08
                // tapping Create then Cancel). Sequencing them avoids it,
                // same fix pattern as CookbooksHubView's restore flow.
                Task { @MainActor in
                    selectedTab = previousTab
                }
            } else {
                previousTab = newTab
            }
        }
        .sheet(isPresented: $isPresentingCreate) {
            CreateHubView()
        }
        .task(id: accountState.currentOwnerID) {
            bootstrapActiveCookbook()
        }
        .task(id: accountState.currentUserID) {
            await checkForCloudCookbooksAvailable()
        }
        .task(id: accountState.currentOwnerID) {
            await checkForRecipeStandardization()
        }
        .overlay {
            if isStandardizing {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Updating your recipes…")
                            .font(.subheadline)
                    }
                    .padding(24)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
                }
            }
        }
        .alert(
            "Update Recipe Amounts?",
            isPresented: $isPresentingStandardizePrompt
        ) {
            Button("Update Now") {
                Task { await standardizePendingCookbooks() }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Recipe amounts are moving to a new whole-number-plus-fraction format (like \"1 1/2\" instead of \"1.5\"). Update your recipes now, or skip for now — you'll be asked again next time, and you can always do this later from Administrator → Standardize Recipes.")
        }
        .alert("Couldn't Set Up Your Cookbook", isPresented: Binding(
            get: { bootstrapErrorMessage != nil },
            set: { if !$0 { bootstrapErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(bootstrapErrorMessage ?? "")
        }
        .alert(
            "Cookbooks Available",
            isPresented: $isPresentingCloudCookbooksAvailable
        ) {
            Button("Restore") {
                isPresentingCloudRestoreFromPrompt = true
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text(cloudCookbooksAvailableCount == 1
                ? "We found a cookbook synced from another device — restore it now?"
                : "We found \(cloudCookbooksAvailableCount) cookbooks synced from another device — restore them now?")
        }
        .sheet(isPresented: $isPresentingCloudRestoreFromPrompt) {
            RestoreFromCloudView { _ in }
        }
    }

    /// Activates the current owner's first Cookbook if one already exists
    /// and nothing is active yet (e.g. right after sign-in, or cookbooks
    /// restored/synced from another device) — deliberately does NOT
    /// create one anymore. A brand-new account has zero cookbooks until
    /// the user explicitly creates or restores one, via the Home
    /// dashboard's "Getting Started" card; CreateEditRecipeView's own
    /// save-time guard blocks adding a recipe with nowhere to file it.
    private func bootstrapActiveCookbook() {
        guard activeCookbookState.activeCookbookID == nil else { return }
        let ownerID = accountState.currentOwnerID
        let descriptor = FetchDescriptor<Cookbook>(
            predicate: #Predicate<Cookbook> { $0.ownerID == ownerID },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        do {
            if let firstCookbook = try modelContext.fetch(descriptor).first {
                activeCookbookState.setActive(firstCookbook.id)
            }
        } catch {
            bootstrapErrorMessage = error.localizedDescription
        }
    }

    /// Directly answers "the app looks broken/empty on a new device"
    /// (this feature's original motivation, see the sync plan) — rather
    /// than requiring the user to already know "Restore from Cloud" exists
    /// in the Cookbooks tab menu, proactively surface it once per cookbook
    /// id (DismissedCloudCookbookPrompts) so a genuinely new sync from
    /// another device still gets caught on a later launch without nagging
    /// about ones already seen.
    private func checkForCloudCookbooksAvailable() async {
        guard let userID = accountState.currentUserID else { return }
        let summaries = (try? await syncService.fetchSyncedCookbooks(forUser: userID)) ?? []
        guard !summaries.isEmpty else { return }

        let localIDs = Set(((try? modelContext.fetch(FetchDescriptor<Cookbook>())) ?? []).map(\.id))
        let newSummaries = summaries.filter { !localIDs.contains($0.id) && !DismissedCloudCookbookPrompts.hasBeenPrompted(for: $0.id) }
        guard !newSummaries.isEmpty else { return }

        DismissedCloudCookbookPrompts.markPrompted(newSummaries.map(\.id))
        cloudCookbooksAvailableCount = newSummaries.count
        isPresentingCloudCookbooksAvailable = true
    }

    /// Every personal cookbook this owner has that RecipeQuantityStandardizer
    /// hasn't touched yet — checked on every launch (RecipeStandardizationState
    /// has no permanent "skip"/dismiss, by design, so "Not Now" below just
    /// means "not this launch," matching the confirmed decision to keep
    /// reminding until it's actually done).
    private func checkForRecipeStandardization() async {
        let ownerID = accountState.currentOwnerID
        let descriptor = FetchDescriptor<Cookbook>(predicate: #Predicate<Cookbook> { $0.ownerID == ownerID })
        guard let ownedCookbooks = try? modelContext.fetch(descriptor) else { return }
        let pending = ownedCookbooks.filter { !RecipeStandardizationState.hasStandardized($0.id) }
        guard !pending.isEmpty else { return }
        cookbooksPendingStandardization = pending
        isPresentingStandardizePrompt = true
    }

    private func standardizePendingCookbooks() async {
        isStandardizing = true
        // Without a real suspension point, a fast run (a typical personal
        // cookbook's worth of recipes) would set isStandardizing true and
        // false in the same run-loop turn — Task.yield() forces the
        // "Updating your recipes…" overlay to actually render for at
        // least one frame, same fix as the recipe-import save flow.
        await Task.yield()
        for cookbook in cookbooksPendingStandardization {
            RecipeQuantityStandardizer.standardize(cookbook, modelContext: modelContext)
            RecipeStandardizationState.markStandardized(cookbook.id)
        }
        cookbooksPendingStandardization = []
        isStandardizing = false
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
        .environment(ActiveCookbookState())
        .environment(CookingSessionState())
        .environment(PendingFileImportState())
}
