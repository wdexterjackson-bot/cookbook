//
//  MoreHubView.swift
//  cookbook
//
//  The new "More" tab — a small, deliberately visual landing spot for
//  everything that doesn't warrant its own persistent tab: Profile,
//  Messages, Administrator (moved here from inside AccountView's own
//  Profile screen — it no longer appears there, only here), Discover New
//  Cookbook Communities (public-group search, reusing the same enhanced
//  PublicGroupSearchView SearchHubView's "Public Cookbooks" scope uses),
//  and Discover (TheMealDB/Spoonacular browse — the same DiscoverView
//  already reachable from Create's "Search Online"). Icon-badge cards in a
//  grid, not a plain list of text rows, per the explicit design ask — same
//  rounded-card/shadow language every other Potluck screen already uses,
//  just arranged as tiles instead of a vertical stack.
//

import SwiftUI

private struct MoreMenuItem: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String
    var systemImage: String
    var tint: Color
}

struct MoreHubView: View {
    @State private var isPresentingProfile = false
    @State private var isPresentingMessages = false
    @State private var isPresentingAdministrator = false
    @State private var isPresentingCommunities = false
    @State private var isPresentingDiscover = false

    private let groupsService: GroupsServicing = FirestoreGroupsService()

    private let items: [MoreMenuItem] = [
        MoreMenuItem(title: "Profile", subtitle: "Account & purchases", systemImage: "person.crop.circle.fill", tint: .potluckTomato),
        MoreMenuItem(title: "Messages", subtitle: "Invitations & requests", systemImage: "tray.fill", tint: .potluckSage),
        MoreMenuItem(title: "Administrator", subtitle: "Bulk recipe import", systemImage: "wrench.and.screwdriver.fill", tint: .potluckSunflower),
        MoreMenuItem(title: "Discover New Cookbook Communities", subtitle: "Search & join public Family Cookbooks", systemImage: "person.3.fill", tint: .potluckTomato),
        MoreMenuItem(title: "Discover", subtitle: "Find recipes to import from the web", systemImage: "sparkle.magnifyingglass", tint: .potluckSage),
    ]

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items) { item in
                        Button {
                            select(item)
                        } label: {
                            moreCard(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Color.potluckCream)
            .navigationTitle("More")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .sheet(isPresented: $isPresentingProfile) {
            AccountView()
        }
        .sheet(isPresented: $isPresentingMessages) {
            MessagesView()
        }
        .sheet(isPresented: $isPresentingAdministrator) {
            AdministratorView()
        }
        .sheet(isPresented: $isPresentingCommunities) {
            PublicGroupSearchView(groupsService: groupsService)
        }
        .sheet(isPresented: $isPresentingDiscover) {
            DiscoverView()
        }
    }

    private func select(_ item: MoreMenuItem) {
        switch item.title {
        case "Profile": isPresentingProfile = true
        case "Messages": isPresentingMessages = true
        case "Administrator": isPresentingAdministrator = true
        case "Discover New Cookbook Communities": isPresentingCommunities = true
        case "Discover": isPresentingDiscover = true
        default: break
        }
    }

    private func moreCard(_ item: MoreMenuItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(item.tint.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: item.systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(item.tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.potluckSemiboldBody(16))
                    .foregroundStyle(Color.potluckDeepTeal)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
        .potluckCardShadow()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). \(item.subtitle)")
    }
}

#Preview {
    MoreHubView()
        .environment(AccountState(authService: FakeAuthService()))
        .environment(ActiveCookbookState())
}
