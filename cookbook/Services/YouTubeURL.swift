//
//  YouTubeURL.swift
//  cookbook
//
//  Pure URL parsing, deliberately kept out of any View so it's testable
//  without SwiftUI — same reasoning as RecipeSearch.swift. Recipe.videoURLs
//  stores whatever the user actually pasted (not just the extracted video
//  ID), so this is also what resolves a stored URL back into a playable
//  video ID at Cooking Mode playback time.
//

import Foundation

enum YouTubeURL {
    /// Recognizes youtube.com/watch?v=, youtu.be/, youtube.com/embed/, and
    /// youtube.com/shorts/ — with or without extra query params (playlist,
    /// timestamp, share-tracking, etc.).
    static func videoID(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed), let host = components.host?.lowercased() else {
            return nil
        }
        guard host.hasSuffix("youtube.com") || host.hasSuffix("youtu.be") else {
            return nil
        }

        let pathParts = components.path.split(separator: "/").map(String.init)

        if host.hasSuffix("youtu.be") {
            return validated(pathParts.first)
        }
        if let last = pathParts.last, pathParts.count >= 2, ["embed", "shorts"].contains(pathParts[pathParts.count - 2]) {
            return validated(last)
        }
        if let v = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return validated(v)
        }
        return nil
    }

    static func isValidYouTubeURL(_ urlString: String) -> Bool {
        videoID(from: urlString) != nil
    }

    /// Real YouTube video IDs are always exactly 11 URL-safe base64-ish
    /// characters — rejecting anything else here means a malformed/partial
    /// paste fails validation instead of silently producing a broken player.
    private static func validated(_ id: String?) -> String? {
        guard let id, id.count == 11,
              id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        else {
            return nil
        }
        return id
    }
}
