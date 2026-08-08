//
//  YouTubeURLTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct YouTubeURLTests {

    @Test func extractsIDFromStandardWatchURL() {
        #expect(YouTubeURL.videoID(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ")
    }

    @Test func extractsIDFromWatchURLWithExtraQueryParams() {
        #expect(YouTubeURL.videoID(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=30s&list=PL123") == "dQw4w9WgXcQ")
    }

    @Test func extractsIDFromShortLink() {
        #expect(YouTubeURL.videoID(from: "https://youtu.be/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
    }

    @Test func extractsIDFromShortLinkWithQuery() {
        #expect(YouTubeURL.videoID(from: "https://youtu.be/dQw4w9WgXcQ?si=abc123") == "dQw4w9WgXcQ")
    }

    @Test func extractsIDFromEmbedURL() {
        #expect(YouTubeURL.videoID(from: "https://www.youtube.com/embed/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
    }

    @Test func extractsIDFromShortsURL() {
        #expect(YouTubeURL.videoID(from: "https://www.youtube.com/shorts/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
    }

    @Test func extractsIDFromMobileHost() {
        #expect(YouTubeURL.videoID(from: "https://m.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ")
    }

    @Test func rejectsNonYouTubeHosts() {
        #expect(YouTubeURL.videoID(from: "https://vimeo.com/watch?v=dQw4w9WgXcQ") == nil)
    }

    @Test func rejectsMalformedOrTooShortIDs() {
        #expect(YouTubeURL.videoID(from: "https://youtu.be/short") == nil)
    }

    @Test func rejectsPlainText() {
        #expect(YouTubeURL.videoID(from: "not a url at all") == nil)
    }

    @Test func rejectsYouTubeHomepageWithNoVideo() {
        #expect(YouTubeURL.videoID(from: "https://www.youtube.com/") == nil)
    }

    @Test func isValidYouTubeURLMatchesVideoIDExtraction() {
        #expect(YouTubeURL.isValidYouTubeURL("https://youtu.be/dQw4w9WgXcQ"))
        #expect(!YouTubeURL.isValidYouTubeURL("https://vimeo.com/12345"))
    }
}
