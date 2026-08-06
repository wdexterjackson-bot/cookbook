//
//  PublicGroupSearchView.swift
//  cookbook
//
//  Search + filter for publicly-searchable Family Cookbooks. Matches the
//  user's own example: searching "Team USA" could return hundreds of
//  results, narrowed further by Family/Group Name and Home Location.
//

import SwiftUI

struct PublicGroupSearchView: View {
    let groupsService: GroupsServicing

    @Environment(AccountState.self) private var accountState
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var locationFilter = ""
    @State private var results: [FamilyGroup] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var requestedGroupIDs: Set<String> = []

    var body: some View {
        NavigationStack {
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
                            Text(group.cookbookName)
                                .font(.headline)
                            Text("\(group.name) · \(group.locationText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
            .scrollContentBackground(.hidden)
            .background(Color.potluckCream)
            .navigationTitle("Find a Family Cookbook")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await search()
            }
        }
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestToJoin(_ group: FamilyGroup) async {
        guard let userID = accountState.currentUserID else { return }
        do {
            _ = try await groupsService.requestToJoin(groupID: group.id, requesterID: userID, note: nil)
            requestedGroupIDs.insert(group.id)
        } catch GroupsServiceError.alreadyMember {
            errorMessage = "You're already a member of this cookbook."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    let service = InMemoryGroupsService()
    return PublicGroupSearchView(groupsService: service)
        .environment(AccountState(authService: FakeAuthService()))
}
