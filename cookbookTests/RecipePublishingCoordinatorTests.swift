//
//  RecipePublishingCoordinatorTests.swift
//  cookbookTests
//
//  Photo upload is Annual Pro Membership-exclusive — these cover the gate
//  itself, and the "never strip an already-shared photo on a lapsed
//  republish" behavior, which the coordinator's own header comment
//  documents as mirroring PersonalCookbookSyncCoordinator's precedent.
//

import Foundation
import Testing
@testable import cookbook

struct RecipePublishingCoordinatorTests {

    private func makeRecipe(title: String = "Skillet Cornbread", withLocalPhoto: Bool = false) -> Recipe {
        let recipe = Recipe(ownerID: "alice", title: title)
        if withLocalPhoto {
            recipe.heroPhotoFilename = try? PhotoStore.save(Data("fake-photo-bytes".utf8))
        }
        return recipe
    }

    private func makeGroup(id: String = "group-1") -> FamilyGroup {
        FamilyGroup(
            id: id, slug: id, name: "Jackson", description: "", type: "Family",
            locationText: "Baltimore, MD", structuredRegion: nil, coverImageURL: nil,
            visibility: .publicGroup, createdByUserID: "alice", createdByDisplayName: "Alice",
            createdAt: .now, status: .active, allowsMemberInvites: false,
            approvalPolicy: .anyAdministrator, isMFB: nil
        )
    }

    private func makeCookbook(id: String = "cookbook-1", groupID: String = "group-1") -> GroupCookbook {
        GroupCookbook(
            id: id, groupID: groupID, cookbookName: "Family Favorites", createdByUserID: "alice",
            createdByDisplayName: "Alice", createdAt: .now, coverImageURL: nil, allowsMemberPublishing: true
        )
    }

    @Test func annualProMemberUploadsThePhoto() async throws {
        let recipe = makeRecipe(withLocalPhoto: true)
        let group = makeGroup()
        let cookbook = makeCookbook()
        let photoService = FakeRecipePhotoUploadService()
        let publicationsService = InMemoryPublicationsService()

        let succeeded = try await RecipePublishingCoordinator.publish(
            recipe, to: group, cookbook: cookbook, ownerUserID: "alice",
            isActiveAnnualProMember: true,
            publicationsService: publicationsService, photoUploadService: photoService
        )

        #expect(succeeded == true)
        #expect(photoService.uploadedData.count == 1)
        let compositeID = Publication.compositeID(groupID: group.id, cookbookID: cookbook.id, sourceRecipeID: recipe.id.uuidString, ownerUserID: "alice")
        let publication = try #require(await publicationsService.fetchPublication(id: compositeID))
        #expect(publication.content.coverImageURL != nil)
    }

    @Test func nonAnnualMemberPublishesWithoutUploadingAPhoto() async throws {
        let recipe = makeRecipe(withLocalPhoto: true)
        let group = makeGroup()
        let cookbook = makeCookbook()
        let photoService = FakeRecipePhotoUploadService()
        let publicationsService = InMemoryPublicationsService()

        let succeeded = try await RecipePublishingCoordinator.publish(
            recipe, to: group, cookbook: cookbook, ownerUserID: "alice",
            isActiveAnnualProMember: false,
            publicationsService: publicationsService, photoUploadService: photoService
        )

        #expect(succeeded == true)
        #expect(photoService.uploadedData.isEmpty)
        let compositeID = Publication.compositeID(groupID: group.id, cookbookID: cookbook.id, sourceRecipeID: recipe.id.uuidString, ownerUserID: "alice")
        let publication = try #require(await publicationsService.fetchPublication(id: compositeID))
        #expect(publication.content.coverImageURL == nil)
    }

    @Test func republishingAfterLapsingPreservesTheAlreadySharedPhoto() async throws {
        let recipe = makeRecipe(withLocalPhoto: true)
        let group = makeGroup()
        let cookbook = makeCookbook()
        let photoService = FakeRecipePhotoUploadService()
        let publicationsService = InMemoryPublicationsService()
        let compositeID = Publication.compositeID(groupID: group.id, cookbookID: cookbook.id, sourceRecipeID: recipe.id.uuidString, ownerUserID: "alice")

        // First publish while still an active Annual Pro Member.
        try await RecipePublishingCoordinator.publish(
            recipe, to: group, cookbook: cookbook, ownerUserID: "alice",
            isActiveAnnualProMember: true,
            publicationsService: publicationsService, photoUploadService: photoService
        )
        let originalURL = try #require(await publicationsService.fetchPublication(id: compositeID)?.content.coverImageURL)

        // Membership has since lapsed; republish (e.g. an edited title).
        recipe.title = "Skillet Cornbread (Updated)"
        let succeeded = try await RecipePublishingCoordinator.publish(
            recipe, to: group, cookbook: cookbook, ownerUserID: "alice",
            isActiveAnnualProMember: false,
            publicationsService: publicationsService, photoUploadService: photoService
        )

        #expect(succeeded == true)
        #expect(photoService.uploadedData.count == 1) // no second upload attempted
        let republished = try #require(await publicationsService.fetchPublication(id: compositeID))
        #expect(republished.content.coverImageURL == originalURL)
        #expect(republished.content.title == "Skillet Cornbread (Updated)")
    }

    @Test func noLocalPhotoPublishesNormallyRegardlessOfMembership() async throws {
        let recipe = makeRecipe(withLocalPhoto: false)
        let group = makeGroup()
        let cookbook = makeCookbook()
        let photoService = FakeRecipePhotoUploadService()
        let publicationsService = InMemoryPublicationsService()

        let succeeded = try await RecipePublishingCoordinator.publish(
            recipe, to: group, cookbook: cookbook, ownerUserID: "alice",
            isActiveAnnualProMember: true,
            publicationsService: publicationsService, photoUploadService: photoService
        )

        #expect(succeeded == true)
        #expect(photoService.uploadedData.isEmpty)
    }
}
