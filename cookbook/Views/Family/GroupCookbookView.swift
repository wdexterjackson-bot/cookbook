//
//  GroupCookbookView.swift
//  cookbook
//
//  Read-only browse of a Family Cookbook's published recipes. Publishing a
//  personal recipe INTO a Family Cookbook is a deliberately deferred
//  follow-up (confirmed scope decision) — a brand-new cookbook shows an
//  honest empty state here rather than silently looking broken.
//

import SwiftUI

struct GroupCookbookView: View {
    let group: FamilyGroup
    let membership: Membership
    let groupsService: GroupsServicing

    @Environment(\.dismiss) private var dismiss
    @State private var publications: [Publication] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let publicationsService: PublicationsServicing = FirestorePublicationsService()

    var body: some View {
        List {
            Section {
                LabeledContent("Family/Group", value: group.name)
                LabeledContent("Location", value: group.locationText)
                LabeledContent("Your Role", value: membership.role.rawValue.capitalized)
                LabeledContent("Visibility", value: group.visibility == .publicGroup ? "Public" : "Private")
            }

            Section("Recipes") {
                if publications.isEmpty && !isLoading {
                    Text("No recipes have been published to this cookbook yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(publications) { publication in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(publication.content.title)
                                .font(.headline)
                            if !publication.content.summary.isEmpty {
                                Text(publication.content.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Button("Leave Family Cookbook", role: .destructive) {
                    Task { await leave() }
                }
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle(group.cookbookName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadPublications()
        }
    }

    private func loadPublications() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            publications = try await publicationsService.fetchPublications(forGroup: group.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func leave() async {
        do {
            try await groupsService.leaveGroup(groupID: group.id, userID: membership.userID)
            dismiss()
        } catch GroupsServiceError.lastAdminCannotLeaveOrBeDemoted {
            errorMessage = "You're the last admin of this cookbook — promote someone else first."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
