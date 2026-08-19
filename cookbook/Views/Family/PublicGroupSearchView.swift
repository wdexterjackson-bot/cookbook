//
//  PublicGroupSearchView.swift
//  cookbook
//
//  Search + filter for publicly-searchable Family Cookbooks. Matches the
//  user's own example: searching "Team USA" could return hundreds of
//  results, narrowed further by Family/Group Name and Home Location. Each
//  result shows its total recipe count and total like count (summed
//  across all its Publications) so a browser can gauge how active/worth-
//  joining a community is before requesting to join.
//
//  PublicGroupSearchContent is the actual search UI/logic, with no
//  NavigationStack of its own — reused from three places: FamilyView's own
//  "Find a Family Cookbook" entry point and MoreHubView's "Discover New
//  Cookbook Communities" card both use it via PublicGroupSearchView (a
//  thin NavigationStack + Done-button wrapper, since both present it as a
//  sheet); SearchHubView embeds PublicGroupSearchContent directly inside
//  its own already-existing NavigationStack for the "Public Cookbooks"
//  search scope — nesting a second NavigationStack there would swallow
//  navigation the same way it does anywhere else in this app (see
//  RecipeListView's own history with that exact bug).
//

import SwiftUI

struct PublicGroupSearchView: View {
    let groupsService: GroupsServicing

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PublicGroupSearchContent(groupsService: groupsService)
                .navigationTitle("Discover Communities")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

struct PublicGroupSearchContent: View {
    let groupsService: GroupsServicing

    @Environment(AccountState.self) private var accountState

    private let entitlementService: EntitlementServicing = FirestoreEntitlementService()
    private let purchaseService: PurchaseServicing = StoreKitPurchaseService()
    private let claimWriter: PurchaseClaimSubmitting = FirestorePurchaseClaimWriter()
    private let publicationsService: PublicationsServicing = FirestorePublicationsService()
    @State private var gate = EntitlementGateCoordinator()

    @State private var searchText = ""
    @State private var locationFilter = ""
    @State private var results: [FamilyGroup] = []
    @State private var groupStats: [String: (recipeCount: Int, likeCount: Int)] = [:]
    /// A group can now hold several cookbooks — fetched alongside the
    /// stats below (same concurrent, best-effort pattern) since this
    /// screen's search box still finds groups by family/location, but
    /// showing at least one of a group's cookbook names is what makes a
    /// result recognizable to someone searching for it.
    @State private var groupCookbookNames: [String: [String]] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var requestedGroupIDs: Set<String> = []

    var body: some View {
        List {
            Section {
                TextField("Cookbook or Family Name", text: $searchText)
                    .onSubmit { Task { await search() } }
                TextField("Home Location", text: $locationFilter)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await search() } }
                Button("Search") {
                    Task { await search() }
                }
            }

            if results.isEmpty && !isLoading {
                ContentUnavailableView("No Public Cookbooks Found", systemImage: "magnifyingglass")
            } else {
                ForEach(results) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(cookbookNamesText(for: group))
                            .font(.headline)
                        Text("\(group.name) · \(group.locationText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        let stats = groupStats[group.id]
                        HStack(spacing: 12) {
                            Label("\(stats?.recipeCount ?? 0) recipes", systemImage: "book")
                            Label("\(stats?.likeCount ?? 0) likes", systemImage: "hand.thumbsup")
                        }
                        .font(.caption2)
                        .foregroundStyle(Color.potluckSage)
                        .redacted(reason: stats == nil ? .placeholder : [])

                        // "Request to Join" is the request-membership
                        // action for every public group — approval path
                        // (pending vs. instant) is decided server-side by
                        // the group's own approvalPolicy, not something
                        // this screen needs to branch on.
                        Button(requestedGroupIDs.contains(group.id) ? "Requested" : "Request to Join") {
                            Task { await requestToJoin(group) }
                        }
                        .disabled(requestedGroupIDs.contains(group.id))
                    }
                    .padding(.vertical, 4)
                }
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .potluckHiddenScrollBackground()
        .background(Color.potluckCream)
        .task {
            await search()
        }
        .entitlementGate(
            gate,
            userID: accountState.currentUserID ?? "",
            entitlementService: entitlementService,
            purchaseService: purchaseService,
            claimWriter: claimWriter
        )
    }

    private func search() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            results = try await groupsService.fetchPublicGroups(matching: PublicGroupSearchFilter(
                text: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : searchText,
                locationText: locationFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : locationFilter
            ))
            groupStats = [:]
            groupCookbookNames = [:]
            await loadStats(for: results)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetched concurrently, one call per result — search result sets are
    /// small, so this stays cheap without needing a denormalized counter
    /// on FamilyGroup itself.
    private func loadStats(for groups: [FamilyGroup]) async {
        await withTaskGroup(of: (String, Int, Int).self) { taskGroup in
            for familyGroup in groups {
                taskGroup.addTask {
                    let publications = (try? await publicationsService.fetchPublications(forGroup: familyGroup.id)) ?? []
                    let likeTotal = publications.reduce(0) { $0 + ($1.likeCount ?? 0) }
                    return (familyGroup.id, publications.count, likeTotal)
                }
            }
            for await (groupID, recipeCount, likeCount) in taskGroup {
                groupStats[groupID] = (recipeCount, likeCount)
            }
        }
        await withTaskGroup(of: (String, [String]).self) { taskGroup in
            for familyGroup in groups {
                taskGroup.addTask {
                    let cookbooks = (try? await groupsService.fetchGroupCookbooks(forGroup: familyGroup.id)) ?? []
                    return (familyGroup.id, cookbooks.map(\.cookbookName))
                }
            }
            for await (groupID, names) in taskGroup {
                groupCookbookNames[groupID] = names
            }
        }
    }

    private func cookbookNamesText(for group: FamilyGroup) -> String {
        let names = groupCookbookNames[group.id] ?? []
        return names.isEmpty ? group.name : names.joined(separator: ", ")
    }

    private func requestToJoin(_ group: FamilyGroup) async {
        guard let userID = accountState.currentUserID else { return }
        let entitlement = try? await entitlementService.fetchEntitlement(userID: userID)
        await gate.attempt(.groupJoin, outcome: EntitlementGate.forGroupJoin(entitlement, group: group)) {
            do {
                _ = try await groupsService.requestToJoin(groupID: group.id, requesterID: userID, note: nil)
                requestedGroupIDs.insert(group.id)
            } catch GroupsServiceError.alreadyMember {
                errorMessage = "You're already a member of this cookbook."
            } catch GroupsServiceError.joinRequestAlreadyPending {
                // Reached when this screen's local "Requested" flag never
                // saw the first request (e.g. a different screen instance
                // sent it) — resync the button instead of just showing a
                // dead-end error over a still-tappable "Request to Join".
                requestedGroupIDs.insert(group.id)
                errorMessage = "You already requested to join this cookbook."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    let service = InMemoryGroupsService()
    return PublicGroupSearchView(groupsService: service)
        .environment(AccountState(authService: FakeAuthService()))
}
