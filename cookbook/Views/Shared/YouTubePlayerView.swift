//
//  YouTubePlayerView.swift
//  cookbook
//
//  Wraps Google's own YouTubeiOSPlayerHelper (MIT-licensed, free — no API
//  key or account needed to embed a specific known video, only YouTube's
//  standard embed player under the hood via a WKWebView). AVPlayer can't
//  play a YouTube URL directly — YouTube doesn't expose a direct stream
//  URL through any public/ToS-compliant means — this is the correct way
//  to embed one.
//
//  Callers should attach `.id(videoID)` at the call site so SwiftUI
//  recreates this view (and its makeUIView load call) when the selected
//  video changes, rather than this view needing its own update-diffing
//  logic to detect a changed id and re-trigger playback.
//

import SwiftUI
#if os(iOS)
import YouTubeiOSPlayerHelper

struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> YTPlayerView {
        let playerView = YTPlayerView()
        playerView.load(withVideoId: videoID, playerVars: ["playsinline": 1])
        return playerView
    }

    func updateUIView(_ uiView: YTPlayerView, context: Context) {}
}
#endif
