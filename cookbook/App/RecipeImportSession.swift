//
//  RecipeImportSession.swift
//  cookbook
//
//  Shared progress state for the bulk recipe import flow (ImportRecipesFileView
//  -> ImportReviewView) — owned by ImportRecipesFileView, which stays mounted
//  for the whole flow (ImportReviewView is presented as its nested sheet), so
//  a single .onAppear/.onDisappear pair there can span idle-timer prevention
//  across both screens without a flicker between them.
//

import Foundation

@Observable
final class RecipeImportSession {
    enum Phase: Equatable {
        case idle
        case extracting(page: Int, of: Int)
        case parsing(chunk: Int, of: Int)
        case saving
    }

    var phase: Phase = .idle
}
