//
//  PublicationsServicing.swift
//  cookbook
//

import Foundation

enum PublicationsServiceError: Error, Equatable {
    case publicationNotFound
    case notAuthorized
}

protocol PublicationsServicing {
    /// Publishing the same `sourceRecipeID` to the same `groupID` again
    /// updates the existing Publication in place — an explicit "Publish
    /// update," never silent propagation (LIN-001) — rather than creating
    /// a duplicate.
    func publish(_ content: PublicationContentSnapshot, sourceRecipeID: String, to groupID: String, ownerUserID: String) async throws -> Publication
    func unpublish(_ publicationID: String, actingUserID: String) async throws
    func fetchPublications(forGroup groupID: String) async throws -> [Publication]
    func fetchPublication(id: String) async throws -> Publication?
}
